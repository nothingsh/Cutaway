---
description: 用 Swift Package Manager 把 CutawayServer 加进你的 iOS App，并在启动时开启它。
---

# 安装 {#installation}

CutawayServer 是开发期间加进你的 App 的 iOS SDK。Cutaway 连上之后，它截取 Cutaway 要的图层、图像和属性，再发回去。它在模拟器里和经 USB 连接 Mac 的设备上都能工作。

<div class="facts">
  <Badge type="info" text="iOS 13 或更新版本" />
  <Badge type="info" text="Swift Package Manager" />
  <Badge type="info" text="MIT 许可证" />
</div>

## 要求 {#requirements}

- iOS 13 或更新版本。用 Xcode 27 构建的产物在 iOS 15 及更新版本上运行，见下面的说明。
- Xcode 16.3 或更新版本，Swift 6.1 或更新版本。
- Swift Package Manager。不支持其他包管理器。

::: details 为什么用 Xcode 27 时是 iOS 15？
每个模块都按 iOS 13 的部署目标对照 iOS SDK 做类型检查，所以这个包没有在可用性检查之外用到更新的东西。但 Xcode 27 的构建系统不支持低于 iOS 15 的部署目标，会把包的部署目标提到 15.0，所以用 Xcode 27 构建的产物在 iOS 15 及更新版本上运行。这个包从没有在 iOS 13 或 14 上运行过。
:::

## 加入这个包 {#add-the-package}

::: code-group

```text [在 Xcode 中]
File › Add Package Dependencies…，输入

  https://github.com/nothingsh/CutawayServer

然后把 CutawayServer 库加到你的 App target。
```

```swift [在 Package.swift 中]
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
]
// …and add the product "CutawayServer" to your target's dependencies.
```

:::

这个包是纯 Swift 的，没有第三方依赖。

## 开启服务端 {#start-the-server}

在 App 启动时调用一次 `start()`：

::: code-group

```swift [UIKit]
import CutawayServer

func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
) -> Bool {
    CutawayServer.start()
    return true
}
```

```swift [SwiftUI]
import CutawayServer

@main
struct MyApp: App {
    init() {
        CutawayServer.start()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

:::

`start()` 可以在任何线程调用；再次调用不起作用。

## 启动时发生什么 {#what-happens-at-launch}

- App 变为活跃后，服务端开始监听，只在回环地址 `127.0.0.1` 上，用 48160 至 48167 中第一个空闲的端口。
- Mac 上运行的 Cutaway 自己找到这个 App：模拟器里经回环地址，设备上经 USB 连接。几秒钟内，App 就出现在 Cutaway 的列表里。
- Cutaway 不要，就什么也不截取。没有人连接时，服务端只是监听。

细节见[在设备上的行为](/zh-Hans/integrate/on-device)：端口、重新连接，以及截取时会动到什么。

::: tip 只在 Debug 构建里
默认情况下，服务端只编译进定义了 `DEBUG` 的构建。在其他构建里，`start()` 是一个空函数。如果你的开发配置用的是别的名字，在奇怪 App 为什么不在列表里之前，先读[Debug 与 Release 构建](/zh-Hans/integrate/builds)。
:::

## 接下来 {#next}

<NextSteps :items="[
  { title: 'Debug 与 Release 构建', text: '哪些构建里有服务端，以及怎样主动打开。', link: '/zh-Hans/integrate/builds' },
  { title: '定制 Cutaway 显示的内容', text: '你自己的属性、虚拟节点和颜色名。', link: '/zh-Hans/integrate/customizing' },
  { title: '开始使用', text: '安装 Cutaway，检查你的 App。', link: '/zh-Hans/guide/getting-started' }
]" />
