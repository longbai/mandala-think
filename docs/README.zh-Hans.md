# MandalaThink

[English](../README.md) · 简体中文 · [日本語](README.ja.md) · [한국어](README.ko.md)

MandalaThink 是一款面向 iPhone 和 iPad 的九宫格思考工具。用 3×3 梳理当前主题，用 9×9 同时查看下一层。每格可记录文字、照片、附件和行动，也可用颜色标记。界面支持简体中文、英文、日文和韩文。

## Mandala 思考法

在九宫格中央写下问题、目标或主题，在周围八格记录相关想法。要深入某个想法，就把它作为下一张九宫格的中心。例如，围绕「准备一次分享」列出听众、材料和时间，再展开「材料」整理案例、图片和参考资料。[MandalArt 九宫格介绍](https://www.atpress.ne.jp/news/11958)

## 使用

1. **新建或打开项目。** 点「新建」填写项目名和中心主题。点「打开」可打开 `.mprj` 编辑包，或导入 `.mandalaprj` 分享包与旧版 `.mandala`。
2. **编辑和展开格子。** 点空格开始编辑，输入后自动保存，正文首条非空行用于预览。点已有格子查看详情，点右上角按钮进入下一层。
3. **切换画布。** 从画布上方切换 3×3 和 9×9。9×9 默认显示整张画布，支持双指缩放、拖动和「回到全览」。
4. **添加媒体和行动。** 在编辑器里从相册、相机或文件添加媒体。在格子详情中把行动送入 Apple 提醒事项，可通过提醒中的来源链接返回项目。
5. **分享或备份。** 从画布工具菜单导出 `.mandalaprj` 分享包或旧版 `.mandala`。项目结构见[格式规范](mandala-format-v1.md)。

### 浏览器阅读器

运行 `mandala-web-reader`，打开 [http://127.0.0.1:8080](http://127.0.0.1:8080)，选择或拖入旧版 `.mandala` 文件。可用 [sample.mandala](../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala) 试读。文件由浏览器在本地解析。用 `-listen 127.0.0.1:8081` 可切换端口。

## 编译与测试

### iPhone 和 iPad

用 Xcode 打开根目录下的 [mandala-think.xcodeproj](../mandala-think.xcodeproj)，选择 `mandala-think` scheme 和 iPhone 或 iPad 模拟器，点击 Run。最低支持 iOS／iPadOS 17。真机运行时，在 **Signing & Capabilities** 选择开发团队，默认 Bundle ID 为 `org.mandalathink.app`。

在仓库根目录运行格式测试：

```sh
swift test --package-path MandalaCore
```

在 Xcode 通过 **Product → Test** 运行界面测试。旧格式导入测试需要把 `sample.mandala` 放入测试设备的 App Documents 目录，并在运行 `xcodebuild test` 时设置 `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1`。图库测试需要通过 `simctl addmedia` 添加测试图片，并设置 `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1`。

### 浏览器阅读器

用 Go 1.22 或更新版本，在仓库根目录运行：

```sh
go -C apps/web-reader build -buildvcs=false -o ../../mandala-web-reader .
```

可执行文件内嵌 [apps/web-reader/dist](../apps/web-reader/dist) 中的 HTML、CSS 和 JavaScript，可以单独拷贝运行。
