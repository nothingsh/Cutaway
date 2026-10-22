---
description: 关于连接、Cutaway 显示的内容、构建和存档的常见问题。
---

# 常见问题与故障排除 {#faq-and-troubleshooting}

这里回答最常被问到的问题。如果没有你要找的，可以搜索本站（<kbd>⌘K</kbd>），或者[提交 issue](https://github.com/nothingsh/Cutaway/issues)。

## 连接 {#connecting}

### 我的 App 没有出现在列表里。 {#my-app-doesn-t-appear-in-the-list}

按顺序检查这几项：

- **构建里包含 CutawayServer。** 它只编译进 Debug 构建，除非打开了包的 `ReleaseEnabled` trait。见 [Debug 与 Release 构建](/zh-Hans/integrate/builds)。
- **服务端已经开启。** `CutawayServer.start()` 在启动时运行，并且 App 在前台：App 变为活跃后，服务端才开始监听。
- **在设备上：** 设备用线缆连接、已解锁，并且信任这台 Mac。
- **端口空闲。** 服务端占用 48160 至 48167 中第一个空闲的端口。如果八个都被占用，它不监听，等 App 下次变为活跃时再试。

### 列表里我的 App 带着两个版本。 {#the-list-shows-my-app-with-two-versions}

Cutaway 与 App 里的 CutawayServer 使用的协议版本无法衔接：它们的主版本不同。列表会显示两个版本；更新较旧的一边。见[版本与兼容](/zh-Hans/protocol/versions)。

### 能经 Wi-Fi 检查 App 吗？ {#can-i-inspect-an-app-over-wi-fi}

还不能。Cutaway 经回环地址连接模拟器，经 USB 线缆连接设备。经过认证并加密的 Wi-Fi 连接在[路线图](/zh-Hans/resources/roadmap)上。

### 两台 Mac 能同时检查同一个 App 吗？ {#can-two-macs-inspect-the-same-app-at-once}

不能。CutawayServer 同一时间只服务一个客户端，第一个连着时会拒绝第二个。一个连接安静约 25 秒后，服务端断开它，接受下一个。

### App 进入了后台，或者连接断了。 {#the-app-went-to-the-background-or-i-lost-the-connection}

App 进入后台时，Cutaway 会说明，等它回来后继续。如果连接断了，最后的画面留在屏幕上，再次找到同一个 App 时 Cutaway 会重新连接。见[连接 App](/zh-Hans/guide/connecting)。

### Cutaway 需要网络吗？ {#does-cutaway-need-the-network}

不需要。它经回环地址与模拟器通信，经 USB 与设备通信，从不联系自己的服务器。唯一的例外是**检查更新…**，由你自己选择。见[隐私与安全](/zh-Hans/resources/privacy)。

## 看到的内容 {#what-you-see}

### 为什么模糊效果、视频或 Metal 视图是空白的？ {#why-is-a-blur-video-or-metal-view-blank}

这些内容由系统的渲染服务在 App 的进程之外合成，所以 CutawayServer 无法从图层树把它画出来。见[限制](/zh-Hans/integrate/limitations)。

### 为什么栏的标题在截图里是白色，在屏幕上是黑色？ {#why-is-a-bar-title-white-in-the-screenshot-but-black-on-screen}

在 iOS 26 上，导航栏、工具栏和标签栏里的文字与图标以一种单一的颜色绘制（常常是白色），由父图层上的滤镜在渲染服务合成屏幕时给出它们在屏幕上的颜色。截图显示的是每个图层自己的内容，在那个滤镜之前。`textColor` 等属性显示的仍是 App 设置的颜色。

### 预览显示的是旧画面。 {#the-preview-shows-an-old-picture}

Cutaway 显示的是请求时 App 的样子。按 <kbd>⌘R</kbd> 重新请求整棵树和每一张截图，或按 <kbd>⇧⌘R</kbd> 只请求所选的子树。见[刷新](/zh-Hans/guide/preview#refresh)。

### 我改了环境，但有些图层还是原来的样子。 {#i-changed-the-environment-but-some-layers-still-look-the-old-way}

改写之后，Cutaway 等半秒让 App 重画，然后刷新。比这更晚才改变外观的 App，需要再按一次 <kbd>⌘R</kbd>。见[环境](/zh-Hans/guide/environment)。

### 为什么列表里没有我想要的属性？ {#why-isn-t-an-attribute-i-expect-in-the-list}

Cutaway 自己没有属性清单：它显示的是 App 里的 CutawayServer 发来的内容，所以出现哪些属性取决于服务端的版本。你的 App 可以加上自己的属性；见[定制 Cutaway 显示的内容](/zh-Hans/integrate/customizing)。

## 构建与安全 {#builds-and-safety}

### CutawayServer 会进入我的 App Store 构建吗？ {#will-cutawayserver-end-up-in-my-app-store-build}

默认不会。除非你打开 `ReleaseEnabled` trait，没有 `DEBUG` 的构建里只有一个空的 `start()`：没有服务端，也没有网络代码。见 [Debug 与 Release 构建](/zh-Hans/integrate/builds)。

### 网络上的其他设备能连接我的 App 吗？ {#can-other-devices-on-the-network-connect-to-my-app}

不能。CutawayServer 只监听 `127.0.0.1`。在设备上，Mac 经 USB 连接到达它。

### 检查会改变我的 App 吗？ {#does-inspecting-change-my-app}

只有你做的编辑，以及它们引起的布局。截取时动过的一切都会在主线程继续之前复原，读取属性也不会触发布局。见[在设备上的行为](/zh-Hans/integrate/on-device)。

### macOS 提示无法验证开发者。 {#macos-says-it-can-t-verify-the-developer}

Cutaway 的构建没有经过 Apple 公证。打开**系统设置 › 隐私与安全性**，选择**仍要打开**；或者运行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

## 存档 {#archives}

### 不连设备能看 App 吗？ {#can-i-look-at-an-app-without-the-device}

能。在 App 连着时存储一份存档（<kbd>⌘S</kbd>），在任何地方、任何一台 Mac 上打开：图层树、截图、属性和约束都在。除了需要 App 的操作（修改属性或环境、刷新、存储），一切照常可用。见[存档与导出](/zh-Hans/guide/archives)。

### 能把存档当作运行中的 App 来回放吗？ {#can-i-replay-an-archive-as-if-it-were-a-running-app}

开发时可以：Cutaway 仓库里的 `scripts/replay.sh <file.cutaway>` 把存档当作模拟器里的一个 App 提供出来，供运行中的 Cutaway 连接。见[参与贡献](/zh-Hans/resources/contributing)。
