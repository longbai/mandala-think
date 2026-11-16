# MandalaThink

使用 Xcode 16 或更新版本打开 [mandala-think.xcodeproj](mandala-think.xcodeproj)，选择 `mandala-think` scheme 和 iPhone 或 iPad 模拟器，按 Run。项目的最低系统版本是 iOS / iPadOS 17。安装到真机时，在 Signing & Capabilities 中选择开发团队。工程使用开发用 Bundle ID `org.mandalathink.app`。

在首页工具栏的地球菜单中可切换简体中文、日本語、한국어、English，或跟随系统。项目中的文字和资源使用其原始语言。Apple 的文件选择器和提醒事项由系统语言控制。

- 首页的项目列表按最近打开的顺序排列，左滑可以删除项目。在「文件」中的 MandalaThink → Recently Deleted 可以找回本机项目。外部项目使用原文件位置提供的废纸篓。
- 每格只编辑一段正文，九宫格预览优先取正文首条非空行，正文为空时显示第一条行动的名称。此前测试构建保存的项目可以直接打开，升级时保留已编辑的文字。行动与文字显示在同一正文区。资源区直接提供照片图库、相机和添加文件入口。
- 点击已有格可以查看详情，点击格内的展开按钮可进入下一层。点击空位会进入编辑器，键入有效内容才会生成格子，输入停顿后自动保存。
- 系统「文件」可打开 `.mprj` 编辑包，或导入 `.mandalaprj` 和旧版 `.mandala`。分享、备份和旧版导出在九宫格工具菜单中。
- 行动先保存在格子里。从格子详情选择「添加到提醒事项」，在列表中确认后才写入 Apple 提醒事项。
- 日常编辑、包内附件和行动结构见 [格式规范](../../docs/mandala-format-v1.md)。首版验收和后续顺序见 [开发计划](../../docs/mandala-app-v1-plan.md)。
- 独立浏览器阅读器的静态入口为 [apps/web-reader/dist/index.html](../web-reader/dist/index.html)，支持浏览旧版 `.mandala`。

在 `apps/apple` 下用 `swift test --package-path MandalaCore` 运行格式测试。旧格式测试使用仓库自带的 [sample.mandala](MandalaCore/Tests/MandalaCoreTests/Fixtures/sample.mandala)，其中有三个格子、两级子格和一张图片。界面测试可在 Xcode 中使用 Product → Test 运行。旧格式界面测试需要先将同一个样本放进测试设备的 App Documents 目录，再用 `TEST_RUNNER_MANDALA_TEST_LEGACY_FIXTURE=1 xcodebuild … test` 启用。图库测试先用 `simctl addmedia` 将测试图片加入 iPhone 模拟器，再用 `TEST_RUNNER_MANDALA_TEST_PHOTO_FIXTURE=1 xcodebuild … test` 启用。

iPhone 15（iOS 27.2.1）已通过四语界面、空位不落盘、首次编辑自动保存、项目重开、系统文件选择器导入 `memology.mandala` 与两层导航测试。导入生成 283 份格子 YAML。原版 MandalArt 真机回导、iPad 真机、iCloud Drive 双真机同步与冲突、Apple 提醒事项真机创建和回链仍需验收。浏览器版可以继续独立使用。macOS CLI 和 Agent Skill 安排在原生首版验收之后。

解析层在仓库内固定了 Yams 6.1.0 和 ZIPFoundation 0.9.20，构建时不下载这两个依赖。项目为 Yams 增加受限 YAML 入口，并让 ZIPFoundation 公开中央目录记录数来校验完整枚举。两个上游的许可保留在 `MandalaCore/Vendor`。 [Yams 6.1.0](https://github.com/jpsim/Yams/releases/tag/6.1.0) · [ZIPFoundation 0.9.20](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.20)
