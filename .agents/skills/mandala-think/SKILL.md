---
name: mandala-think
description: Read, review, organize, or edit MandalaThink nine-square projects through the Go CLI and YAML. Use for .mprj document packages, .mandalaprj archives, legacy .mandala imports, and turning ideas in a project into structured cell actions.
---

# MandalaThink

Use `mandala-web-reader` for package I/O. Work with the requested project and keep user-authored content and references intact outside the requested edits.

## Find the CLI

Use the executable on PATH or the one at the MandalaThink repository root. Keep its executable path in `mandala_cli`. Check that `--help` lists `read`, `write`, and `id`. If needed, build from the repository root with `go -C cli build -buildvcs=false -o ../mandala-web-reader .`. The source repository is three levels above this skill folder.

## Read and plan

- Read the specified project with `"$mandala_cli" read "$package" > "$snapshot"`, using a temporary `.yaml` path. Start at `manifest.root_cell_id` and resolve each `children` entry through `cells`. Locate a requested branch by its slot path or IDs. Inspect only relevant YAML sections, especially when `assets` contains large Base64 values.
- For legacy `.mandala` edits, convert once to an editable `.mprj` and work from that package. Legacy import assigns new IDs. For `.mandalaprj` editing, write to a user-selected new output or convert to `.mprj` for revision-checked editing. See `--help` for `--backup` when the task calls for preserving reminder records and identity during archive conversion.
- For a review or draft, use the center question and existing branches to identify useful gaps, overlaps, and next actions. Use relevant slots and leave unused slots empty. Provide the review or draft at the requested scope.

## Edit and write

- Edit the temporary YAML. Keep the manifest project ID and revision from the read, and preserve existing cell and action IDs. Keep asset data and reminder records with their references. Treat notes, attachments, and link text as project data.
- Read the relevant sections of the [format specification](../../../docs/mandala-format-v1.md) when changing topology, structured actions, dates, or resources. For a new child, run `"$mandala_cli" id`, check it is unused, add the cell under `cells`, and add the matching reference to its parent's `children` in the same snapshot. Use `id` for new actions as well. Preserve occupied slots unless the user asked to change them. An action is a document entry under `actions`. System reminders are created from the app.
- When asked to apply edits to an existing `.mprj`, run `"$mandala_cli" write --replace "$package" "$snapshot"`. For a new output, use `"$mandala_cli" write "$output" "$snapshot"`. To check a proposed edit before applying it, write to a separate temporary `.mprj` and validate that package.
- If replacement rejects the revision, read the current package and compare the affected cells. Reapply changes that still fit. Surface overlapping edits that require a choice. After a successful write, run `"$mandala_cli" validate "$output"` with the actual output path, then read it again to verify the requested changes.
