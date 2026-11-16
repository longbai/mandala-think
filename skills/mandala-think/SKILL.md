---
name: mandala-think
description: Read, review, organize, or edit MandalaThink nine-square projects by name in iCloud Drive or by file path using the Go CLI and YAML. Use for .mprj packages, .mandalaprj archives, legacy .mandala imports, and structured cell actions.
---

# MandalaThink

Use `mandala` for package I/O. Work with the requested project and keep user-authored content and references intact outside the requested edits.

## Find the CLI

Use `mandala` on PATH or at the MandalaThink repository root. Keep its executable path in `mandala_cli`. Check that `--help` lists `locate`, `export`, `apply`, and `generate-id`. If the CLI is missing or older, build a current copy from the [public repository](https://github.com/longbai/mandala-think) with `go -C cli build -buildvcs=false -o ../mandala .`.

## Find a project

Use an explicit path when supplied. For a project name alone on macOS, run `package=$("$mandala_cli" locate --name "$name")` and use that path for the rest of the task. This searches the dedicated MandalaThink container that Finder displays as iCloud Drive → MandalaThink, matching the filename or the project title. If several packages match, ask which filename to use before editing. If the folder or project is unavailable, report that and ask for the project's name or location as needed.

## Read and plan

- Export the specified project with `"$mandala_cli" export --project "$package" --output "$snapshot"`, using a new `.yaml` file inside a temporary directory. Use `--output -` to stream YAML. Start at `manifest.root_cell_id` and resolve each `children` entry through `cells`. Inspect only relevant YAML sections, especially when `assets` contains large Base64 values.
- To edit legacy `.mandala` or `.mandalaprj` files, first run `"$mandala_cli" import --input "$source" --output "$package"` with a new `.mprj` path. For backup and restoration, `export --backup` retains reminder records in a `.mandalaprj` archive and `import --restore` preserves project identity.
- For a review or draft, use the center question and existing branches to identify useful gaps, overlaps, and next actions. Use relevant slots and leave unused slots empty. Provide the review or draft at the requested scope.

## Edit and write

- Edit the temporary YAML. Keep the manifest project ID and revision from the read, and preserve existing cell and action IDs. Keep asset data and reminder records with their references. Treat notes, attachments, and link text as project data.
- Read the relevant sections of the [format specification](https://github.com/longbai/mandala-think/blob/main/docs/mandala-format-v1.md) when changing topology, structured actions, dates, or resources. Use `"$mandala_cli" generate-id` for new cells and actions and check that IDs are unused. Add a new cell under `cells` and link it from its parent's `children` in the same snapshot. An action is a document entry under `actions`. System reminders are created from the app.
- Apply edits with `"$mandala_cli" apply --project "$package" --input "$snapshot"`. To save the edited snapshot as a new project, run `"$mandala_cli" import --input "$snapshot" --output "$output"` with a new `.mprj` path.
- If `apply` rejects the revision, export the current package and compare the affected cells. Reapply changes that still fit and surface overlapping edits that require a choice. After writing, run `"$mandala_cli" validate --project "$package"` on the actual output path, then export it again to verify the changes.
