# MandalaThink

English · [简体中文](docs/README.zh-Hans.md) · [日本語](docs/README.ja.md) · [한국어](docs/README.ko.md)

MandalaThink is a nine-square thinking tool for iPhone and iPad. Use the 3×3 view to work on a topic and the 9×9 view to see its branches together. Cells can hold notes, photos, attachments, and actions, with optional color labels. The app supports English, Simplified Chinese, Japanese, and Korean.

## Mandala thinking

Write a question, goal, or topic in the center of a 3×3 grid. Use the eight surrounding cells to capture related ideas. To explore one of those ideas, make it the center of another grid. For example, start with “Prepare a talk,” then explore “Materials” in a separate grid with cells for examples, images, and references. [MandalArt introduction](https://www.atpress.ne.jp/news/11958)

## Use

1. **Create or open a project.** Tap New and enter the project name and central topic. Tap Open to open an editable `.mprj` package or import a `.mandalaprj` share or a legacy `.mandala` file.
2. **Edit and expand cells.** Tap an empty cell to edit it. The app saves as you type and uses the first nonblank line as the text preview. Tap a filled cell for its details, or use its upper-right button to open the next level.
3. **Switch views.** The controls above the board switch between 3×3 and 9×9. The 9×9 view starts fitted to the screen. Pinch to zoom, drag to pan, and tap Fit Board to reset.
4. **Add media and actions.** Add media from Photos, the camera, or Files. Send an action to Apple Reminders from the cell details. The reminder's source link opens the project again.
5. **Share or back up.** Use the board menu to export a `.mandalaprj` archive or a legacy `.mandala` file. See the [file format specification](docs/mandala-format-v1.md) for the package layout.

### Browser reader

Run `mandala-web-reader` and open [http://127.0.0.1:8080](http://127.0.0.1:8080). Select or drop a legacy `.mandala` file, such as [sample.mandala](MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala). The browser reads the file locally. Use `-listen 127.0.0.1:8081` to choose another port.

## Build and test

### iPhone and iPad

Open [mandala-think.xcodeproj](mandala-think.xcodeproj) from the repository root. Select the `mandala-think` scheme and an iPhone or iPad simulator, then click Run. The app requires iOS or iPadOS 17 or later. For a physical device, select your development team under **Signing & Capabilities**. The default bundle ID is `org.mandalathink.app`.

Run the format tests from the repository root:

```sh
swift test --package-path MandalaCore
```

Run UI tests with **Product → Test** in Xcode. For the legacy import tests, copy `sample.mandala` to the app's Documents directory on the test device and set `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1` when running `xcodebuild test`. The Photos test requires an image added with `simctl addmedia` and `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1`.

### Browser reader

With Go 1.22 or later, run this from the repository root:

```sh
go -C cli build -buildvcs=false -o ../mandala-web-reader .
```

The executable embeds the HTML, CSS, and JavaScript from [cli/dist](cli/dist). You can copy and run the executable by itself.
