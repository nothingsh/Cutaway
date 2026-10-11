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

**看清界面是如何构建的**

- 每个窗口的图层树，并标出视图控制器的根视图，以及持有各个图层或视图的成员变量，因此可以从图层追溯到
  代码。
- 每个图层的截图，可以平铺为 2D，也可以在 3D 中分开展示。用鼠标或触控板旋转、缩放和平移；改变层间距；
  显示被隐藏的图层。
- 每个位置、尺寸、旋转和缩放都与设备屏幕上一致，包括 3D 变换。
- 测量：按住 ⌥ 并指向另一个图层，就能看到它与所选图层之间的距离，2D 和 3D 下都可以。

**处理细节**

- 所选图层和视图的属性，按 App 报告的分组显示。可编辑的属性带有控件：文本、可拖动的数字、开关、
  颜色选择器、枚举的弹出式菜单。改动会立即应用到正在运行的 App，⌘Z 可以撤销。
- 引用所选视图的 Auto Layout 约束，标出其中未生效的，并在预览中标出每条约束的另一端。点击另一端
  即可跳转过去。
- 搜索图层树、聚焦于某个子树、展开到指定层级、单独刷新某个子树。

**留住你的发现**

- 把一次检查存储为 `.cutaway` 存档，之后在任何一台 Mac 上都能打开，无需设备：图层树、截图、属性和
  约束都在，视图也和你当时看到的一样。
- 把某个图层的截图导出为 PNG，可以只含该图层本身，也可以包含其子图层。

**为日常使用而设计**

- 自动发现 App：包括这台 Mac 上的模拟器中的，以及通过 USB 连接的设备上的。
- 先显示图层树，截图随到随显；大型图层树依然响应迅速。
- App 回来时自动重新连接。跟随 App 的状态：当它进入后台时，Cutaway 会告知你，并在它回到前台后
  继续。
- 提供英文、简体中文、繁体中文、日文和韩文。
- 只与这台 Mac 上的 App 以及 USB 线缆另一端的 App 通信。没有分析统计，没有崩溃报告。

<a id="requirements"></a>
## 要求

- macOS 14 或更高版本，Mac 需配备支持 Metal 的 GPU（所有能运行 macOS 14 的 Mac 都满足）。
- 一个集成了 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的 App，运行在 iOS
  模拟器中，或运行在通过 USB 连接到 Mac 的 iPhone 或 iPad 上。

Cutaway 没有启用沙盒，因为它用来通过 USB 访问设备的套接字在沙盒之外。这也是它不经 Mac App Store、
而在其外分发的原因。

<a id="installation"></a>
## 安装

从 [Releases](https://github.com/nothingsh/Cutaway/releases) 页面下载 `Cutaway-<版本号>.dmg`，打开后把 Cutaway 拖到“应用程序”。
Cutaway 是开源项目，它的构建没有经过 Apple 公证，所以第一次打开时 macOS 会提示无法验证开发者。
打开**系统设置 › 隐私与安全性**，选择**仍要打开**；或者运行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › 检查更新…**会告诉你有没有更新的版本。你也可以从源码构建 Cutaway；见[开发](#development)。

## 快速开始

1. 把 [CutawayServer](https://github.com/nothingsh/CutawayServer) 添加到你的 iOS App，并在启动时调用一次 `CutawayServer.start()`。服务器的
   [README](https://github.com/nothingsh/CutawayServer#readme) 给出了 UIKit 和 SwiftUI 各自所需的
   两行代码。它只会编译进 Debug 构建。
2. 在模拟器中运行你的 App，或在用线缆连接到 Mac 的设备上运行。
3. 打开 Cutaway。几秒钟内你的 App 就会出现在列表中。选中它。

## 使用 Cutaway

### 图层列表

边栏以树的形式列出每个窗口的图层。每一行显示图层的类、它所支撑的视图、以它为根视图的视图控制器，
以及持有它的成员变量，例如 `HomeViewController.titleLabel`。变暗的行表示该图层已隐藏或完全透明。

- **过滤**：用顶部的输入框过滤图层树，标题或类名包含该文本的行会连同其祖先一起保留。
- **聚焦**于某个图层（⌥⌘↓）只显示它的子树，列表和预览都是如此；列表上方的路径可以带你回到外层。
- **展开**到选定的层级或全部展开，用过滤框旁边的菜单（全部展开和全部折叠为 ⌥⌘→ 和 ⌥⌘←）。
  首次检查一个 App 时，图层树会展开到屏幕上的视图控制器。
- **连按**某一行可以展开或折叠它。在预览中连按某个图层效果相同。

### 预览

预览会把每个可见图层连同其截图绘制在它在屏幕上的位置：图层树到达时先绘制，随后每张截图到达时再
绘制。

- **2D 或 3D**（⌘1、⌘2）在工具栏中切换。3D 模式下图层按深度分开；在列表中折叠某一行会把它的子树
  折回一层。
- **旋转**：在 3D 中拖动；**平移**：滚动，或在 2D 中拖动；**缩放**：捏合，或按住 ⌘ 滚动滚轮，以指针
  为中心。**重置视图**（⌘0）回到初始状态。
- 3D 中的**层间距**由预览下方的滑块控制，范围 0 到 200 点。
- **显示隐藏的图层**（⇧⌘H）会把隐藏或透明的图层也画出来，使用独有的样式。**显示边框**（⇧⌘B）为
  每个图层描边。这两个开关在预览下方也有。
- **测量**：选中一个图层后，按住 ⌥ 并指向另一个图层。两者之间的距离会连同以点为单位的数值一起画
  出来，2D 和 3D 下都可以。
- 点击图层即可选中它，列表和属性会跟着切换。指针下方的图层会高亮显示。

### 属性

右侧的检查器按 App 报告的分组显示所选图层及其视图的属性，例如 `layer`、`view` 和 `label`。Cutaway
自己没有属性清单：显示的就是 [CutawayServer](https://github.com/nothingsh/CutawayServer) 发来的内容，因此 App 所用版本的服务器知道什么，它就显示
什么。

- App 标记为可编辑的属性带有控件：文本框、可拖动的数字框、开关、带不透明度的颜色选择器、枚举的弹出式
  菜单，以及点、尺寸、矩形、边距和变换的逐分量输入框。
- 改动在你确认时立即发送，拖动时则持续发送。App 会回应该图层的属性，因此随另一个属性变化的属性
  （例如随视图 alpha 变化的图层不透明度）也会更新。
- ⌘Z 撤销上一次改动，⇧⌘Z 重做，在检查持续期间一直有效。
- 被 App 拒绝的改动会在该行给出说明，并恢复原来的值。

改动之后，Cutaway 会刷新可能受到影响的图层的截图。

### 约束

属性下方按 App 报告的形式列出视图的 Auto Layout 约束：
`self.leading = Safe Area of UIView.leading + 16`，优先级低于 1000 时会显示优先级，有标识符时会显示
标识符。未生效的约束会变暗并标出；UIKit 生成的约束折叠为一行。点击约束的另一端即可选中那个视图。
在预览中，所选视图各条约束的另一端都会标出。

### 刷新

Cutaway 显示的是 App 在被询问那一刻的样子。**刷新**（⌘R）会重新请求整棵图层树和每张截图，同时保留
你的选择、展开状态和相机。**刷新所选子树**（⇧⌘R，也在该行的快捷菜单中）只请求那个图层的子树。如果
App 进入后台，Cutaway 会等待；如果连接断开，最后的画面会保留，再次找到同一个 App 时 Cutaway 会重新
连接。

### 存档

**存储存档…**（⌘S）会把图层树、图标，以及每个图层（包括隐藏的）的截图、属性和约束收进一个
`.cutaway` 文件，连同窗口当时的样子。该文件可以用**打开…**（⌘O）打开，也可以从访达打开，或拖到
Cutaway 的图标上打开，它会在自己的窗口中显示，除编辑之外的一切功能都与在线时相同。可以同时打开
多个存档，与一个在线检查并列。

**导出图层截图…**（⇧⌘E）和**导出含子图层的截图…**（⌥⇧⌘E）会把所选图层的图像以设备的缩放比例
写成 PNG，保留透明度，不含该图层自身的变换和不透明度。

### 设置

**设置…**（⌘,）有两页。**通用**选择语言：跟随系统，或五种语言之一。**预览**选择新的检查如何开始：
2D 还是 3D、层间距，以及是否显示隐藏的图层和边框。已打开的窗口保持原样。

### 键盘快捷键

| 操作 | 按键 |
|---|---|
| 打开存档 | ⌘O |
| 存储存档 | ⌘S |
| 导出所选图层的截图：仅本图层 / 含子图层 | ⇧⌘E / ⌥⇧⌘E |
| 撤销 / 重做改动 | ⌘Z / ⇧⌘Z |
| 过滤图层列表 | ⌘F |
| 刷新全部 / 所选子树 | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| 放大 / 缩小 / 重置视图 | ⌘= / ⌘- / ⌘0 |
| 显示隐藏的图层 / 显示边框 | ⇧⌘H / ⇧⌘B |
| 聚焦于所选图层 / 显示全部图层 | ⌥⌘↓ / ⌥⌘↑ |
| 全部展开 / 全部折叠 | ⌥⌘→ / ⌥⌘← |
| 显示或隐藏边栏 / 检查器 | ⌃⌘S / ⌥⌘I |
| 显示 App 列表 | ⇧⌘0 |
| 设置 | ⌘, |

## 性能

大型界面也应当感觉即时。Cutaway 围绕这一点设计，其测试套件在每次运行时都要求它达到下表中的数字。
这些数字是在 Debug 构建中，针对一棵生成的、形状接近真实 App 的 10,000 个图层的树（窗口、容器、一个
导航栏和一长列单元格，每个单元格带图标、标签和分隔线）测得的：

| 操作 | 限制 |
|---|---|
| 图层树到达 → 列表显示在屏幕上 | 2 s |
| 布置场景 | 1 s |
| 相机移动后的新一帧 | 16 ms |
| 绘制一帧 | 16 ms |
| 选中一行 → 预览和检查器跟随 | 100 ms |
| 搜索列表 | 200 ms |
| 全部展开 / 全部折叠 | 1 s |
| 打开该树的存档 → 列表显示在屏幕上 | 2 s |

它是这样做到的：

- **截图保持压缩状态。** 模型只保留收到的压缩字节。它们在主线程之外解压、上传到 GPU，然后像素就被
  释放。
- **预览只在变化时绘制。** 没有任何东西在动时，不会提交任何一帧。
- **读取与绘制步调一致。** 截图到达的速度快于使用速度时，Cutaway 停止从连接读取，由 TCP 告诉 App
  等待。内存中不会堆积任何东西。
- **不会累积任何东西。** 测试套件在 5,000 个图层上把每个操作重复十次，并检查没有遗留任何截图、纹理、
  请求或窗口；更长时间的持续运行（`scripts/soak.sh`）会打印一百轮的内存曲线。
- **错误的数据不会让它崩溃。** 每一帧在解码前都会校验，而且每次运行都会用经过变异、截断和拼接的帧
  对解析器做模糊测试。

## Mac 上的行为

- 每两秒，Cutaway 会尝试 `127.0.0.1` 上的 48160 到 48167 端口（[CutawayServer](https://github.com/nothingsh/CutawayServer) 在模拟器中监听这些
  端口），并通过系统的 `usbmuxd` 尝试每台 USB 连接的设备上的相同端口。回应握手的 App 会被列出。
- 每个 App 一条连接，在 App 列在列表中期间一直保持。已经有客户端的 App 不会被打扰。
- 10 秒内收不到任何字节的请求会被放弃；App 发送[协议](https://github.com/nothingsh/CutawayProtocol)禁止的内容时，连接会被关闭。
- Cutaway 不建立其他任何网络连接，只有你选择**检查更新…**时例外：这时它向 GitHub 取本仓库的发布列表，不发送任何关于你的 Mac 的信息。
- 偏好设置保存在 `UserDefaults` 中；最近的存档在系统的最近使用文稿列表中。

## 路线图

以下是 1.0 之后计划的方向，与 [CutawayServer](https://github.com/nothingsh/CutawayServer) 共享。顺序和范围可能会变。

- **协议 1.0。** 冻结 [Cutaway 协议](https://github.com/nothingsh/CutawayProtocol)，使之后的功能只在其上增加。
- **交互分析。** 显示手势识别器和 target–action 对；启用和停用手势；在对象上调用方法。
- **面向宿主 App 的扩展 API。** 自定义属性、虚拟子节点，以及诸如默认折叠的类、颜色别名和从图像中
  排除的视图等配置。
- **大型层级。** 只采集可见图层的快速模式；对超大图像分块传输。
- **更多连接方式和平台。** 经过认证和加密的 Wi-Fi 连接；tvOS 和 visionOS。
- **SwiftUI。** 与图层树并列的 SwiftUI 视图语义层级。

## 常见问题

**我的 App 没有出现在列表中。**
检查构建是否包含 [CutawayServer](https://github.com/nothingsh/CutawayServer)（它只编译进 Debug 构建）并调用了 `CutawayServer.start()`，App 是否
在前台，以及在真机上，设备是否用线缆连接并信任这台 Mac。服务器使用 48160 到 48167 中第一个空闲的
端口；协议版本 Cutaway 无法使用的 App 也会显示在列表中，并同时标出两个版本号。

**Cutaway 需要网络吗？**
不需要。它通过回环地址与模拟器通信，通过 USB 与设备通信。它从不联系自己的任何服务器。

**为什么模糊、视频或 Metal 视图是空白的？**
这些内容由系统的渲染服务器在 App 进程之外合成，因此 [CutawayServer](https://github.com/nothingsh/CutawayServer) 无法从图层树渲染出来。

**没有设备时能查看 App 吗？**
在设备连接时存储一份存档，然后在任何地方打开它。开发时，测试支持库还可以回放存档，就像它是模拟器中
的一个 App 一样（`scripts/replay.sh`）。

**检查会改变我的 App 吗？**
只有你所做的编辑会。采集会恢复它改动过的一切，读取属性也不会触发布局；见 [CutawayServer](https://github.com/nothingsh/CutawayServer) 的 README。

<a id="development"></a>
## 开发

Cutaway 用 Swift 6 编写，基于 AppKit 和 Metal。代码是一个本地 Swift 包 `CutawayKit`，App target
只负责把它组装起来：

| Target | 内容 |
|---|---|
| `CutawayWire` | 帧、以值类型表示的协议消息，以及存档格式 |
| `CutawayTransport` | 发现 App、`usbmuxd`、会话和请求 |
| `CutawayModel` | 图层树、截图和属性，以及各窗口共享的状态 |
| `CutawayScene` | 每个图层画在哪里、按什么顺序，以及命中测试；纯 Swift |
| `CutawayRender` | 用 Metal 绘制场景 |
| `CutawayUI` | 窗口、列表、预览、检查器、设置 |
| `CutawayTestSupport` | 回放协议夹具的模拟服务器、合成的图层树、假的 `usbmuxd` |

线路格式在 [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol) 中定义，以 submodule
形式检出到 `Protocol/`；它的 Swift 代码由 schema 生成并已入库。除协议之外，与 [CutawayServer](https://github.com/nothingsh/CutawayServer) 不共享
任何东西。

克隆后运行一次 `./setup.sh`。它会检出协议的 submodule、检查 Xcode、XcodeGen 和 jq、把锁定版本的
工具安装到 `.tools/`、设置 git hooks，并从 `project.yml` 生成 `Cutaway.xcodeproj`。重复运行也无妨。

| 任务 | 命令 |
|---|---|
| 按 CI 的方式构建并测试（只依赖代码） | `scripts/check.sh` |
| 只测试包 | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| 格式化，然后 lint | `scripts/format.sh` |
| 为正在运行的 Cutaway 把存档当作模拟器中的 App 提供 | `scripts/replay.sh <file.cutaway>` |
| 把每个操作重复一百轮并打印内存曲线 | `scripts/soak.sh` |

- 没有任何东西靠肉眼判断。场景层由单元测试覆盖；绘制层离屏渲染，并与 `Baselines/` 中的基准图比对。
- 测试从不需要设备。连接是在这台 Mac 上，针对回放协议夹具的模拟服务器测试的。

## 许可证

Cutaway 是自由软件，以 GNU General Public License v3.0 发布；见 [LICENSE](../../LICENSE)。它使用
[FlatBuffers](https://github.com/google/flatbuffers)（Apache License 2.0）、
[DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit)（MIT）和
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine)（MIT）构建；它们的许可证在
“关于”面板和 [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](../../CutawayKit/Sources/CutawayUI/Resources/Acknowledgements) 中。[Cutaway 协议](https://github.com/nothingsh/CutawayProtocol) 采用 MIT 许可证。
