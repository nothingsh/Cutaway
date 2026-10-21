---
description: Add CutawayServer to your iOS app with Swift Package Manager and start it at launch.
---

# Installation

CutawayServer is the iOS SDK you add to your app during development. When Cutaway connects, it captures the layers, images and attributes Cutaway asks for and sends them back. It works in the Simulator and on devices connected to the Mac over USB.

<div class="facts">
  <Badge type="info" text="iOS 13 or later" />
  <Badge type="info" text="Swift Package Manager" />
  <Badge type="info" text="MIT license" />
</div>

## Requirements

- iOS 13 or later. A build made with Xcode 27 runs on iOS 15 and later: see the note below.
- Xcode 16.3 or later, Swift 6.1 or later.
- Swift Package Manager. Other package managers are not supported.

::: details Why iOS 15 with Xcode 27?
Every module is type-checked against the iOS SDK with an iOS 13 deployment target, so the package uses nothing newer without an availability check. Xcode 27’s build system, however, does not support deployment targets below iOS 15 and raises the package’s to 15.0, so a build made with Xcode 27 runs on iOS 15 and later. The package has never been run on iOS 13 or 14.
:::

## Add the package

::: code-group

```text [In Xcode]
File › Add Package Dependencies…, enter

  https://github.com/nothingsh/CutawayServer

and add the CutawayServer library to your app target.
```

```swift [In Package.swift]
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
]
// …and add the product "CutawayServer" to your target's dependencies.
```

:::

The package is pure Swift and has no third-party dependencies.

## Start the server

Call `start()` once when the app launches:

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

`start()` can be called from any thread; calling it again has no effect.

## What happens at launch

- The server starts listening once the app becomes active, on the loopback address `127.0.0.1` only, on the first free port from 48160 to 48167.
- Cutaway, running on the Mac, finds the app by itself: in a simulator over the loopback address, on a device through the USB connection. Within a few seconds the app appears in Cutaway’s list.
- Nothing is captured until Cutaway asks. While no one is connected, the server only listens.

[Behavior on the device](/integrate/on-device) has the details: ports, reconnection, and what capturing touches.

::: tip Only in Debug builds
By default the server is compiled only into builds that define `DEBUG`. In every other build `start()` is an empty function. If your development configurations have other names, read [Debug and Release builds](/integrate/builds) before you wonder why the app isn’t in the list.
:::

## Next

<NextSteps :items="[
  { title: 'Debug and Release builds', text: 'Which builds contain the server, and how to opt in.', link: '/integrate/builds' },
  { title: 'Customizing what Cutaway shows', text: 'Your own attributes, virtual nodes and color names.', link: '/integrate/customizing' },
  { title: 'Getting started', text: 'Install Cutaway and inspect your app.', link: '/guide/getting-started' }
]" />
