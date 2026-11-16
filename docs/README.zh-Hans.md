# MandalaThink

[English](../README.md) · 简体中文 · [日本語](README.ja.md) · [한국어](README.ko.md)

MandalaThink 是一款面向 iPhone 和 iPad 的九宫格思考工具。用 3×3 梳理当前主题，用 9×9 同时查看下一层。每格可记录文字、照片、附件和行动，也可用颜色标记。界面支持简体中文、英文、日文和韩文。

### 特性

- **调用系统提醒事项。** 格子里的行动可添加到 Apple 提醒事项，提醒中的来源链接可直接返回对应格子。
- **通过 iCloud 云盘同步。** iCloud 云盘可用时，新建和导入的项目默认保存到 `iCloud 云盘/MandalaThink`。可为单个项目选择「仅此设备」。Mac 上可在 Finder 找到同一份 `.mprj`，并用 CLI 编辑。
- **无自建服务器。** 项目保存在设备本地或你的 iCloud 云盘。网页阅读器在浏览器内解析文件。
- **兼容旧版 MandalArt。** 支持导入和导出 `.mandala` 文件，并逐层浏览九宫格。

## Mandala 思考法

在九宫格中央写下问题、目标或主题，在周围八格记录相关想法。要深入某个想法，就把它作为下一张九宫格的中心。例如，围绕「准备一次分享」列出听众、材料和时间，再展开「材料」整理案例、图片和参考资料。[MandalArt 九宫格介绍](https://www.atpress.ne.jp/news/11958)

## 使用

1. **新建或打开项目。** 点「新建」填写项目名和中心主题。点「打开」可打开 `.mprj` 编辑包，或导入 `.mandalaprj` 分享包与旧版 `.mandala`。
2. **编辑和展开格子。** 点空格开始编辑，输入后自动保存，正文首条非空行用于预览。点已有格子查看详情，点右上角按钮进入下一层。
3. **切换画布。** 从画布上方切换 3×3 和 9×9。9×9 默认显示整张画布，支持双指缩放、拖动和「回到全览」。
4. **添加媒体和行动。** 在编辑器里从相册、相机或文件添加媒体。在格子详情中把行动送入 Apple 提醒事项，可通过提醒中的来源链接返回项目。
5. **分享或备份。** 从画布工具菜单导出 `.mandalaprj` 分享包或旧版 `.mandala`。项目结构见[格式规范](mandala-format-v1.md)。

### 浏览器阅读器

运行 `mandala serve`，打开 [http://127.0.0.1:8080](http://127.0.0.1:8080)，选择或拖入旧版 `.mandala` 文件。可用 [sample.mandala](../MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala) 试读。文件由浏览器在本地解析。用 `--listen 127.0.0.1:8081` 可切换端口。

### 文档 CLI

在 macOS 上可用 `mandala` 创建、读取和校验项目，通过 YAML 编辑内容，也可在文档包和分享包之间转换。

```sh
./mandala create --title "笔记" --center "有哪些值得探索的问题？" --output Notes.mprj
./mandala export --project Notes.mprj --output notes.yaml
# 编辑 notes.yaml，再把改动写回同一份项目。
./mandala apply --project Notes.mprj --input notes.yaml
./mandala validate --project Notes.mprj
./mandala export --project Notes.mprj --output Notes.mandalaprj
./mandala import --input OldNotes.mandala --output ImportedNotes.mprj
```

在 Mac 上可以用 `--name "笔记"` 代替 `--project Notes.mprj`，按名称查找 iCloud 项目。`--output -` 将 YAML 写到标准输出，`--input -` 从标准输入读取 YAML。`apply` 写回前校验项目 ID 和修订号。

将公开的 [MandalaThink Skill](../skills/mandala-think/SKILL.md) 目录 `skills/mandala-think` 复制到 Agent 的 skills 目录，并将 Go CLI 加入 PATH。在 Codex 中调用 `$mandala-think` 后直接说项目名，例如「读取旅行计划」。在 Mac 上，Skill 默认在「iCloud 云盘 → MandalaThink」中查找。

## 编译与测试

### iPhone 和 iPad

用 Xcode 打开根目录下的 [mandala-think.xcodeproj](../mandala-think.xcodeproj)，选择 `mandala-think` scheme 和 iPhone 或 iPad 模拟器，点击 Run。最低支持 iOS／iPadOS 17。真机运行时，在 **Signing & Capabilities** 选择开发团队。默认 Bundle ID 为 `org.mandalathink.app`，签名描述文件须授权 iCloud Documents 容器 `iCloud.org.mandalathink.app`。使用其他团队时，请使用该团队自己的 App ID 和容器，并更新 entitlements、Info.plist 和 ProjectDisk。

在仓库根目录运行格式测试：

```sh
swift test --package-path MandalaCore
```

在 Xcode 通过 **Product → Test** 运行界面测试。旧格式导入测试需要把 `sample.mandala` 放入测试设备的 App Documents 目录，并在运行 `xcodebuild test` 时设置 `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1`。图库测试需要通过 `simctl addmedia` 添加测试图片，并设置 `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1`。

### 浏览器阅读器

用 Go 1.22 或更新版本，在仓库根目录运行：

```sh
go -C cli build -buildvcs=false -o ../mandala .
```

可执行文件内嵌 [cli/dist](../cli/dist) 中的 HTML、CSS 和 JavaScript，可以单独拷贝运行。

### 文档 CLI

用上面的 Go 编译命令即可生成同一个程序，既能启动网页阅读器，也支持文档命令。macOS 和 Linux 支持原子写入。
