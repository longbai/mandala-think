# MandalaThink

English · [简体中文](docs/README.zh-Hans.md) · [日本語](docs/README.ja.md) · [한국어](docs/README.ko.md)

MandalaThink is a nine-square thinking tool for iPhone and iPad. Use the 3×3 view to work on a topic and the 9×9 view to see its branches together. Cells can hold notes, photos, attachments, and actions, with optional color labels. The app supports English, Simplified Chinese, Japanese, and Korean.

### Features

- **Apple Reminders.** Send cell actions to the system Reminders app. Each reminder includes a link back to its source cell in MandalaThink.
- **iCloud Drive sync.** New and imported projects default to `iCloud Drive/MandalaThink` when iCloud Drive is available. Choose **On This Device** to keep an individual project local. On Mac, find the same `.mprj` in Finder and edit it with the CLI.
- **No MandalaThink backend.** Projects stay on your device or in your iCloud Drive. The browser reader processes files locally in the browser.
- **Legacy MandalArt compatibility.** Import and export `.mandala` files and browse their nested grids.

## Mandala thinking

Write a question, goal, or topic in the center of a 3×3 grid. Use the eight surrounding cells to capture related ideas. To explore one of those ideas, make it the center of another grid. For example, start with “Prepare a talk,” then explore “Materials” in a separate grid with cells for examples, images, and references. [MandalArt introduction](https://www.atpress.ne.jp/news/11958)

## Use

1. **Create or open a project.** Tap New and enter the project name and central topic. Tap Open to open an editable `.mprj` package or import a `.mandalaprj` share or a legacy `.mandala` file.
2. **Edit and expand cells.** Tap an empty cell to edit it. The app saves as you type and uses the first nonblank line as the text preview. Tap a filled cell for its details, or use its upper-right button to open the next level.
3. **Switch views.** The controls above the board switch between 3×3 and 9×9. The 9×9 view starts fitted to the screen. Pinch to zoom, drag to pan, and tap Fit Board to reset.
4. **Add media and actions.** Add media from Photos, the camera, or Files. Send an action to Apple Reminders from the cell details. The reminder's source link opens the project again.
5. **Share or back up.** Use the board menu to export a `.mandalaprj` archive or a legacy `.mandala` file. See the [file format specification](docs/mandala-format-v1.md) for the package layout.

### Browser reader

Run `mandala serve` and open [http://127.0.0.1:8080](http://127.0.0.1:8080). Select or drop a legacy `.mandala` file, such as [sample.mandala](MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala). The browser reads the file locally. Use `--listen 127.0.0.1:8081` to choose another port.

### Document CLI

On macOS, use `mandala` to create and validate projects, edit a YAML snapshot, or convert between document formats.

```sh
./mandala create --title "Notes" --center "What should I explore?" --output Notes.mprj
./mandala export --project Notes.mprj --output notes.yaml
# Edit notes.yaml, then apply the edits to the original project.
./mandala apply --project Notes.mprj --input notes.yaml
./mandala validate --project Notes.mprj
./mandala export --project Notes.mprj --output Notes.mandalaprj
./mandala import --input OldNotes.mandala --output ImportedNotes.mprj
```

On Mac, use `--name "Notes"` in place of `--project Notes.mprj` to select an iCloud project by name. Use `--output -` to export YAML to stdout and `--input -` to read YAML from stdin. `apply` checks the project ID and revision before writing.

Install the public [MandalaThink skill](skills/mandala-think/SKILL.md) by copying the `skills/mandala-think` directory into your agent’s skills directory. Add the Go CLI to your PATH. In Codex, invoke `$mandala-think` with a project name, such as “Read Trip Planning.” On Mac the skill searches iCloud Drive → MandalaThink by default.

## Build and test

### iPhone and iPad

Open [mandala-think.xcodeproj](mandala-think.xcodeproj) from the repository root. Select the `mandala-think` scheme and an iPhone or iPad simulator, then click Run. The app requires iOS or iPadOS 17 or later. For a physical device, select your development team under **Signing & Capabilities**. The default bundle ID is `org.mandalathink.app`. The signing profile must authorize the iCloud Documents container `iCloud.org.mandalathink.app`. If you build under a different team, use its own App ID and container, and update the entitlements, Info.plist, and ProjectDisk accordingly.

Run the format tests from the repository root:

```sh
swift test --package-path MandalaCore
```

Run UI tests with **Product → Test** in Xcode. For the legacy import tests, copy `sample.mandala` to the app's Documents directory on the test device and set `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1` when running `xcodebuild test`. The Photos test requires an image added with `simctl addmedia` and `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1`.

### Browser reader

With Go 1.22 or later, run this from the repository root:

```sh
go -C cli build -buildvcs=false -o ../mandala .
```

The executable embeds the HTML, CSS, and JavaScript from [cli/dist](cli/dist). You can copy and run the executable by itself.

### Document CLI

With Go 1.22 or later, build the program using the command above. The same executable runs the reader and the document commands. Atomic document writes are supported on macOS and Linux.
