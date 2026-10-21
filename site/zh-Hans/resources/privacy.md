---
description: Cutaway 与 CutawayServer 连接什么、存储什么，以及从不做什么。
---

# 隐私与安全 {#privacy-and-security}

Cutaway 只在你的 Mac 和你的 App 之间。它没有账户，没有统计，没有崩溃报告，也从不联系自己的服务器。

## Cutaway 连接什么 {#what-cutaway-connects-to}

- **这台 Mac 上的模拟器。** Cutaway 每两秒尝试一次 `127.0.0.1` 上的端口 48160 至 48167，模拟器里的 CutawayServer 在那里监听。
- **经 USB 连接的设备。** 它经系统的 `usbmuxd`，在每台经 USB 连接的设备上尝试同样的端口。不经过 Wi-Fi 或互联网。
- **只连接回答的 App。** 回答握手的 App 才会列出。只要 App 还在列表里，Cutaway 就为它保持一个连接；已经有客户端的 App 它不去打扰。
- **你要求时连接 GitHub。** **Cutaway › 检查更新…** 经 HTTPS 向 GitHub 要 Cutaway 的版本列表。它不发送你的 Mac 的任何信息，而且只在你选择它时运行：没有自动检查。

Cutaway 不建立其他任何网络连接。

## Cutaway 存储什么 {#what-cutaway-stores}

- **偏好设置**存在 `UserDefaults` 里，最近的存档在系统的最近使用的文稿列表里。
- 你关联的**项目文件夹**（见[源代码](/zh-Hans/guide/source)）按 App 的 bundle ID 记住。Cutaway 只读取它们：源文件、asset catalog 和 String Catalog。它从不写入项目文件夹，也不把它发送到任何地方。
- **存档**是你自己存储的文件。里面是你检查过的内容：图层树、截图、属性和约束。分享存档时，像分享你的 App 的截图一样斟酌。

## 为什么 Cutaway 没有沙盒、没有公证 {#why-cutaway-isn-t-sandboxed-or-notarized}

Cutaway 没有沙盒，因为它经 USB 连接设备所用的套接字在沙盒之外。这也是它在 Mac App Store 之外、在 [GitHub Releases](https://github.com/nothingsh/Cutaway/releases) 上分发的原因。

它的构建没有经过 Apple 公证，所以第一次打开时 macOS 会提示无法验证开发者。打开**系统设置 › 隐私与安全性**，选择**仍要打开**；或者运行：

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

Cutaway 以 GPL-3.0 开源：你可以读每一行代码，也可以自己构建。每个版本都列出了其文件的 SHA-256 校验和。

## 你的 App 里的 CutawayServer {#cutawayserver-in-your-app}

- **只用回环地址。** 服务端只在 `127.0.0.1` 上监听 TCP，从不在其他网络接口上监听。在设备上，Mac 经 USB 连接到达它。
- **同一时间一个客户端。** 第一个客户端连着时，第二个会被拒绝。
- **保活。** 约 25 秒没有回答的对端会被断开，服务端随即可以接受下一个客户端。
- **不进入 Release 构建。** 默认情况下，服务端只编译进定义了 `DEBUG` 的构建。其他任何构建里只有一个空的 `start()`，没有监听的代码。见 [Debug 与 Release 构建](/zh-Hans/integrate/builds)。
- **你选择隐藏的内容。** 你的 App 可以把敏感的视图（例如卡号）排除在所有截图之外。见[定制 Cutaway 显示的内容](/zh-Hans/integrate/customizing)。
- **错误的输入不会让 App 崩溃。** 格式错误的数据和极端的请求都以错误回答。

截取时会动到你的 App 的哪些地方、又怎样复原，见[在设备上的行为](/zh-Hans/integrate/on-device)。
