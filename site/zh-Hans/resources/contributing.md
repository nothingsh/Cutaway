---
description: Cutaway 背后的三个仓库、怎样构建它们，以及在哪里报告问题、提交修改。
---

# 参与贡献 {#contributing}

Cutaway 公开开发，分在三个仓库里，它们不共享代码，只共享一个带版本的协议。

<PartsDiagram />

| 仓库 | 是什么 | 许可证 | 怎样贡献 |
|---|---|---|---|
| [Cutaway](https://github.com/nothingsh/Cutaway) | macOS App，用 Swift、AppKit 和 Metal 编写 | GPL-3.0 | [CONTRIBUTING.md](https://github.com/nothingsh/Cutaway/blob/main/CONTRIBUTING.md) |
| [CutawayServer](https://github.com/nothingsh/CutawayServer) | 嵌入被检查的 App 的 iOS SDK | MIT | [CONTRIBUTING.md](https://github.com/nothingsh/CutawayServer/blob/main/CONTRIBUTING.md) |
| [Cutaway Protocol](https://github.com/nothingsh/CutawayProtocol) | 线上协议：规范、FlatBuffers schema 和夹具 | MIT | [CONTRIBUTING.md](https://github.com/nothingsh/CutawayProtocol/blob/main/CONTRIBUTING.md) |

两端都把协议仓库的一个 tag 钉为 git submodule，并从它的 schema 生成代码。需要新消息或新字段的功能从修改协议开始；这类 issue 带 `protocol` 标签。

## 报告问题或建议功能 {#report-a-bug-or-suggest-a-feature}

使用问题所属仓库的 issue 模板。如果分不清，就在 [Cutaway](https://github.com/nothingsh/Cutaway/issues/new/choose) 提交：需要时会移过去。这次检查的一份存档（<kbd>⌘S</kbd>）往往比描述更能说明问题；如果 App 的内容可以分享，请附上一份。

## 构建 Cutaway {#build-cutaway}

Cutaway 用 Swift 6、AppKit 和 Metal 编写。代码是一个本地的 Swift 包 `CutawayKit`；App target 只负责把它组装起来。

| Target | 内容 |
|---|---|
| `CutawayWire` | 帧、作为值类型的协议消息，以及存档格式 |
| `CutawayTransport` | 发现 App、`usbmuxd`、会话和请求 |
| `CutawayModel` | 图层树、截图和属性，以及各窗口共享的状态 |
| `CutawayProjects` | 关联的项目文件夹及其索引：类型声明、颜色集、字符串 |
| `CutawayScene` | 每个图层画在哪里、按什么顺序，以及点选；纯 Swift |
| `CutawayRender` | 用 Metal 绘制场景 |
| `CutawayUI` | 窗口、列表、预览、检查器、设置 |
| `CutawayTestSupport` | 回放协议夹具的模拟服务端、合成的图层树、一个假的 `usbmuxd` |

克隆之后运行一次 `./setup.sh`。它检查 Xcode、XcodeGen 和 jq，缺少 Xcode 的 Metal 工具链时下载它，检出协议的 submodule，把钉住版本的工具（flatc、SwiftFormat、SwiftLint）装进 `.tools/`，设好 git 钩子，解析 CutawayKit 的 Swift 包，并从 `project.yml` 生成 `Cutaway.xcodeproj`。再运行一次也无妨。

| 任务 | 命令 |
|---|---|
| 按 CI 的方式构建和测试 | `scripts/check.sh` |
| 格式化，然后 lint | `scripts/format.sh` |
| 把存档当作模拟器里的一个 App 提供出来，供运行中的 Cutaway 连接 | `scripts/replay.sh <file.cutaway>` |
| 把每种操作重复一百轮，打印内存曲线 | `scripts/soak.sh` |

- 不靠肉眼判断。场景层由单元测试覆盖；绘制层在屏幕外渲染，与基准图比对。
- 测试从不需要设备。连接在这台 Mac 上对着回放协议夹具的模拟服务端测试。

完整的命令列表、分支模型以及拉取请求怎样审阅，见 [CONTRIBUTING.md](https://github.com/nothingsh/Cutaway/blob/main/CONTRIBUTING.md)。CutawayServer 和协议在各自的仓库里说明自己的构建。

## 提交修改 {#send-a-change}

- 从当前的 `dev-*` 分支开分支，并向它提交拉取请求；向 `main` 提交的拉取请求会被自动关闭。
- 一个拉取请求只做一件事，链接它关闭的 issue，标题使用 [Conventional Commits](https://www.conventionalcommits.org/) 的前缀。
- 比小修复更大的改动，开工之前先在 issue 里留言，先把做法商定下来。

## 改进本站 {#improve-this-website}

本站的源文件在 Cutaway 仓库的 [`site/`](https://github.com/nothingsh/Cutaway/tree/main/site) 里，用 Markdown 编写，以 VitePress 构建。每一页底部都有**在 GitHub 上编辑此页**的链接。
