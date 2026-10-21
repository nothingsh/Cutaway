<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-client-dark.svg">
    <img src="cutaway-client-light.svg" alt="Cutaway — 逐层检查 iOS 界面。" width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](../../LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

[English](../../README.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*本文为译文；如与[英文 README](../../README.md) 有出入，以英文版为准。*

Cutaway 是一个用来查看正在运行的 iOS App 界面内部的 macOS App。把
[CutawayServer](https://github.com/nothingsh/CutawayServer) 添加到你的 App，在模拟器中或通过 USB
连接的设备上运行它，Cutaway 就会把它列出来。选中它，Cutaway 便会显示 App 的图层树、每个图层的截图
（可以平铺为 2D，也可以在 3D 中分开展示），以及你所选图层的属性和 Auto Layout 约束。你对属性所做的
编辑会应用到正在运行的 App。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="overview-dark.png">
    <img src="overview-light.png" alt="Cutaway 以 3D 检视一个 App：图层树、分层展开并带测量的预览，以及所选图层的属性。" width="850">
  </picture>
</p>

<a id="features"></a>
## 功能

- **看清界面是如何构建的。** 每个窗口的图层树，标出视图控制器，以及持有各个视图的成员变量。 [图层列表](https://nothingsh.github.io/Cutaway/zh-Hans/guide/hierarchy)
- **在 3D 中拆开来看。** 每个图层的截图，平铺为 2D 或在 3D 中分开展示；可以旋转、缩放、改变层间距。 [预览](https://nothingsh.github.io/Cutaway/zh-Hans/guide/preview)
- **测距。** 按住 ⌥ 并指向另一个图层（在预览或列表中），就能看到以点为单位的距离。 [测距](https://nothingsh.github.io/Cutaway/zh-Hans/guide/measuring)
- **在运行中修改。** 编辑属性，修改会立即应用到正在运行的 App；⌘Z 可以撤销。 [属性](https://nothingsh.github.io/Cutaway/zh-Hans/guide/attributes)
- **跟随约束。** 视图的每一条 Auto Layout 约束，标出未生效的，以及它们的另一端。 [约束](https://nothingsh.github.io/Cutaway/zh-Hans/guide/constraints)
- **试试深色模式和更大的文字。** 改写 App 的外观、文字大小、布局方向和尺寸类别。 [环境](https://nothingsh.github.io/Cutaway/zh-Hans/guide/environment)
- **跳到你的代码。** 在 Xcode 中打开类，看到 asset 和 String Catalog 里的名字，拷贝 LLDB 命令。 [源码](https://nothingsh.github.io/Cutaway/zh-Hans/guide/source)
- **保留你的发现。** 存档一次检查，在任何一台 Mac 上无需设备即可打开；把图层导出为 PNG。 [存档与导出](https://nothingsh.github.io/Cutaway/zh-Hans/guide/archives)

Cutaway 只与这台 Mac 上和通过 USB 线缆连接的 App 通信：没有统计分析，也没有崩溃报告。
界面提供英文、简体中文、繁体中文、日文和韩文。

<a id="requirements"></a>
## 要求

- macOS 14 或更高版本，Mac 需配备支持 Metal 的 GPU（所有能运行 macOS 14 的 Mac 都满足）。
- 一个集成了 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的 App，运行在 iOS
  模拟器中，或运行在通过 USB 连接到 Mac 的 iPhone 或 iPad 上。

<a id="installation"></a>
## 安装

从 [Releases](https://github.com/nothingsh/Cutaway/releases) 页面下载 `Cutaway-<版本号>.dmg`，打开后把 Cutaway 拖到“应用程序”。
Cutaway 是开源项目，它的构建没有经过 Apple 公证，所以第一次打开时 macOS 会提示无法验证开发者。
打开**系统设置 › 隐私与安全性**，选择**仍要打开**；或者运行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 检查更新…**会告诉你有没有更新的版本。

## 快速开始

1. 把 [CutawayServer](https://github.com/nothingsh/CutawayServer) 添加到你的 iOS App，并在启动时调用一次 `CutawayServer.start()`。它只会编译进
   Debug 构建。
2. 在模拟器中运行你的 App，或在用线缆连接到 Mac 的设备上运行。
3. 打开 Cutaway。几秒钟内你的 App 就会出现在列表中。选中它。

[入门指南](https://nothingsh.github.io/Cutaway/zh-Hans/guide/getting-started)给出了每一步、UIKit 和 SwiftUI 的代码，以及 App 没有出现时要检查什么。

<a id="documentation"></a>
## 文档

其余内容都在 [Cutaway 网站](https://nothingsh.github.io/Cutaway/zh-Hans/)上：

- [指南](https://nothingsh.github.io/Cutaway/zh-Hans/guide/getting-started)：按任务讲解 Cutaway 的用法，以及所有[键盘快捷键](https://nothingsh.github.io/Cutaway/zh-Hans/guide/shortcuts)。
- [集成](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/)：把 CutawayServer 添加到你的 App、Debug 与 Release 构建，以及显示 App 自己的信息。
- [协议](https://nothingsh.github.io/Cutaway/zh-Hans/protocol/)：Cutaway 与 CutawayServer 如何通信，以及哪些版本可以搭配使用。
- [常见问题与排障](https://nothingsh.github.io/Cutaway/zh-Hans/resources/faq)、[隐私与安全](https://nothingsh.github.io/Cutaway/zh-Hans/resources/privacy)、[性能](https://nothingsh.github.io/Cutaway/zh-Hans/resources/performance)、[版本记录](https://nothingsh.github.io/Cutaway/zh-Hans/resources/releases)、[路线图](https://nothingsh.github.io/Cutaway/zh-Hans/resources/roadmap)。

<a id="development"></a>
## 开发

如何构建和测试 Cutaway、修改如何审阅，见 [CONTRIBUTING.md](../../CONTRIBUTING.md)。
网站的[参与贡献](https://nothingsh.github.io/Cutaway/zh-Hans/resources/contributing)一页说明三个仓库如何配合。

## 许可证

Cutaway 是自由软件，以 GNU General Public License v3.0 发布；见 [LICENSE](../../LICENSE)。它使用
[FlatBuffers](https://github.com/google/flatbuffers)（Apache License 2.0）、
[DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)（MIT）和
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)（MIT）构建；它们的许可证在
“关于”面板和 [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements) 中。[Cutaway 协议](https://github.com/nothingsh/CutawayProtocol) 采用 MIT 许可证。
