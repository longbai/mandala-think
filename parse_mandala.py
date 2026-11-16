#!/usr/bin/env python3
"""Export MandalArt .mandala cell trees and original media without dependencies."""

import argparse
import json
import plistlib
import re
import shutil
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from xml.parsers.expat import ExpatError
from zipfile import BadZipFile, ZipFile
from zlib import error as ZlibError


CELL_PATH = r"[0-9]+[.]cell(?:/Children/[0-9]+[.]cell)*"
CELL_DIRECTORY = re.compile(rf"(?P<cell>{CELL_PATH})/(?:[.]DS_Store)?")
CELL_CONTENT = re.compile(
    rf"(?P<cell>{CELL_PATH})/Contents/(?P<name>Content[.][A-Za-z0-9]+)"
)
PREVIEW_INFO = "Representing/RepresentingInfo.plist"
DEFAULT_PREVIEW = "Representing/Representing.png"
PREVIEW_PATH = re.compile(r"Representing/[A-Za-z0-9_-]+[.][A-Za-z0-9]+")


def read_preview(archive, names):
    """Find the preview advertised in the plist, if present."""
    if PREVIEW_INFO not in names:
        return DEFAULT_PREVIEW if DEFAULT_PREVIEW in names else None

    metadata = plistlib.loads(archive.read(PREVIEW_INFO))
    entry = metadata.get("representingEntry") if isinstance(metadata, dict) else None
    if not isinstance(entry, str) or not PREVIEW_PATH.fullmatch(entry):
        raise ValueError(f"Invalid representingEntry in {PREVIEW_INFO}")
    if entry not in names:
        raise ValueError(f"Preview entry is missing: {entry}")
    return entry


def read_document(archive):
    """Return the cell tree and a list of archive members to copy."""
    names = [member.filename for member in archive.infolist() if not member.is_dir()]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate file paths in the archive")

    file_names = set(names)
    preview = read_preview(archive, file_names)
    assets = [name for name in (preview, PREVIEW_INFO) if name in file_names]
    unparsed = []
    cells = {}
    for name in archive.namelist():
        directory = CELL_DIRECTORY.fullmatch(name)
        if directory:
            # Some empty cells survive in ZIP only as a .DS_Store entry.
            cells.setdefault(tuple(directory["cell"].split("/Children/")), {})
            continue

        match = CELL_CONTENT.fullmatch(name)
        if match:
            cell_path = tuple(match["cell"].split("/Children/"))
            cells.setdefault(cell_path, {})[match["name"]] = name
        elif name.rsplit("/", 1)[-1] not in ("", ".DS_Store") and name not in assets:
            unparsed.append(name)

    paths = {
        path[:depth]
        for path in cells
        for depth in range(1, len(path) + 1)
    }
    roots = [path for path in paths if len(path) == 1]
    if len(roots) != 1:
        raise ValueError(f"Expected one root .cell directory, found {len(roots)}")

    nodes = {}
    for path in sorted(paths, key=lambda path: tuple(cell_id(part) for part in path)):
        members = cells.get(path, {})
        text_path = members.get("Content.txt")
        attachments = [members[name] for name in sorted(members) if name != "Content.txt"]
        assets.extend(attachments)
        nodes[path] = {
            "id": cell_id(path[-1]),
            "path": "/Children/".join(path),
            "text": archive.read(text_path).decode("utf-8") if text_path else None,
            "attachments": attachments,
            "children": [],
        }
        if len(path) > 1:
            nodes[path[:-1]]["children"].append(nodes[path])

    document = {
        "preview": preview,
        "preview_metadata": PREVIEW_INFO if PREVIEW_INFO in file_names else None,
        "root": nodes[roots[0]],
        "unparsed_entries": sorted(unparsed),
    }
    return document, assets, len(nodes)


def cell_id(directory):
    return int(directory.removesuffix(".cell"))


def export(source, destination):
    with ZipFile(source) as archive:
        document, assets, cell_count = read_document(archive)
        document["source"] = source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() or destination.is_symlink():
            raise FileExistsError(f"Output already exists: {destination}")

        with TemporaryDirectory(prefix=".mandala-", dir=destination.parent) as temp:
            staging = Path(temp) / "export"
            staging.mkdir()
            for member in assets:
                path = staging / member
                path.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(member) as input_file, path.open("xb") as output_file:
                    shutil.copyfileobj(input_file, output_file)
            with (staging / "tree.json").open("w", encoding="utf-8") as output:
                json.dump(document, output, ensure_ascii=False, indent=2)
                output.write("\n")
            staging.rename(destination)
    return cell_count, len(document["unparsed_entries"])


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog="Each input gets its own folder with tree.json and the original assets.",
    )
    parser.add_argument("files", nargs="+", type=Path, help="input .mandala files")
    parser.add_argument("-o", "--output", required=True, type=Path, help="output directory")
    args = parser.parse_args()

    failed = False
    for source in args.files:
        destination = args.output / source.stem
        try:
            cells, unparsed = export(source, destination)
        except (
            OSError, BadZipFile, ValueError, RuntimeError, plistlib.InvalidFileException,
            ExpatError, ZlibError,
        ) as exc:
            print(f"{source}: {exc}", file=sys.stderr)
            failed = True
            continue
        print(f"{source.name}: {cells} cells -> {destination}")
        if unparsed:
            print(f"  {unparsed} unparsed files listed in tree.json", file=sys.stderr)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
