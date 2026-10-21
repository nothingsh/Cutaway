---
description: From download to your app’s layers in 3D in about ten minutes.
---

<script setup>
import { useData } from 'vitepress'

const { theme } = useData()
const cutaway = theme.value.cutaway
</script>

# Getting started

From download to your app’s layers in 3D. You need a Mac with macOS 14 or later and an iOS app you can build in Xcode.

<div class="facts">
  <Badge type="info" text="About 10 minutes" />
  <Badge type="info" :text="`Cutaway ${cutaway.version} · CutawayServer 1.2`" />
</div>

<div class="steps">

## Install Cutaway

Download the disk image, open it and drag Cutaway to Applications.

<a class="cta" :href="cutaway.download">Download Cutaway {{ cutaway.version }}</a><a class="aside-link" :href="cutaway.releases">All releases and checksums</a>

::: info macOS says it can’t verify the developer?
Cutaway’s builds are not notarized by Apple. The first time you open it, open **System Settings › Privacy & Security** and choose **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```
:::

To find out about newer releases later, choose **Cutaway › Check for Updates…** at any time.

## Add CutawayServer to your app

CutawayServer is the small iOS SDK that answers Cutaway from inside your app. Add it with Swift Package Manager:

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
// …and add the product "CutawayServer" to your app target's dependencies.
```

:::

Then start it once when the app launches:

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

`start()` can be called from any thread, and calling it again does nothing.

::: tip Only in Debug builds
CutawayServer is compiled into builds that define `DEBUG`, and is an empty function everywhere else. Building a configuration named Staging or QA? See [Debug and Release builds](/integrate/builds).
:::

## Run your app and connect

Run the app in the Simulator, or on an iPhone or iPad connected to your Mac with a cable. Open Cutaway: your app appears in the list within a few seconds. Choose it.

<Shot name="guide-applist" alt="The app list with one app in the Simulator, ready to be chosen." />

The layer tree arrives first, then a screenshot of every layer. Drag in the preview to turn it in 3D, or press <kbd>⌘1</kbd> for 2D.

</div>

## Your app isn’t in the list?

Check these, in order:

- **The build includes the server.** The configuration defines `DEBUG`, or the package’s `ReleaseEnabled` trait is on. See [Debug and Release builds](/integrate/builds).
- **The server is started.** `CutawayServer.start()` runs at launch, and the app is in the foreground: the server listens once the app becomes active.
- **On a device:** it is connected with a cable, unlocked, and trusts this Mac.
- **The list shows the app with two versions:** one side is too old for the other. Update the older one; see [Versions and compatibility](/protocol/versions).

More answers are in [FAQ and troubleshooting](/resources/faq).

## Next

<NextSteps :items="[
  { title: 'The layer list', text: 'Read a row, filter, focus on a subtree.', link: '/guide/hierarchy' },
  { title: 'The preview', text: 'Turn, zoom and spread the layers.', link: '/guide/preview' },
  { title: 'Attributes', text: 'Edit a value in the running app.', link: '/guide/attributes' }
]" />
