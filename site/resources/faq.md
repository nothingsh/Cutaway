---
description: Answers to common questions about connecting, what Cutaway shows, builds and archives.
---

# FAQ and troubleshooting

Answers to the questions people ask most. If yours isn’t here, search the site (<kbd>⌘K</kbd>) or [open an issue](https://github.com/nothingsh/Cutaway/issues).

## Connecting

### My app doesn’t appear in the list.

Check these, in order:

- **The build includes CutawayServer.** It is compiled into Debug builds only, unless the package’s `ReleaseEnabled` trait is on. See [Debug and Release builds](/integrate/builds).
- **The server is started.** `CutawayServer.start()` runs at launch, and the app is in the foreground: the server starts listening once the app becomes active.
- **On a device:** it is connected with a cable, unlocked, and trusts this Mac.
- **The ports are free.** The server takes the first free port from 48160 to 48167. If all eight are taken, it doesn’t listen, and tries again the next time the app becomes active.

### The list shows my app with two versions.

Cutaway and the app’s CutawayServer speak protocol versions it can’t bridge: their major versions differ. The list shows both versions; update the older side. See [Versions and compatibility](/protocol/versions).

### Can I inspect an app over Wi-Fi?

Not yet. Cutaway reaches simulators over the loopback address and devices over the USB cable. Wi-Fi connections, authenticated and encrypted, are on the [roadmap](/resources/roadmap).

### Can two Macs inspect the same app at once?

No. CutawayServer serves one client at a time and turns a second one away while the first is connected. When a connection goes quiet for about 25 seconds, the server drops it and accepts the next.

### The app went to the background, or I lost the connection.

When the app goes to the background, Cutaway says so and continues when it returns. If the connection is lost, the last picture stays on screen, and Cutaway reconnects when the same app is found again. See [Connecting to apps](/guide/connecting).

### Does Cutaway need the network?

No. It talks to simulators over the loopback address and to devices over USB, and never contacts a server of its own. The only exception is **Check for Updates…**, which you choose. See [Privacy and security](/resources/privacy).

## What you see

### Why is a blur, video or Metal view blank?

That content is composited by the system’s render server, outside the app’s process, so CutawayServer can’t render it from the layer tree. See [Limitations](/integrate/limitations).

### Why is a bar title white in the screenshot but black on screen?

On iOS 26, text and icons in navigation bars, toolbars and tab bars are drawn in a plain color, often white, and a filter on a parent layer gives them their on-screen color when the render server composites the screen. Screenshots show each layer’s own content, before that filter. Attributes such as `textColor` still show the color the app set.

### The preview shows an old picture.

Cutaway shows what the app looked like when it was asked. Press <kbd>⌘R</kbd> to ask again for the whole tree and every screenshot, or <kbd>⇧⌘R</kbd> for the selected subtree only. See [The preview](/guide/preview).

### I changed the environment, but some layers still look the old way.

After an override, Cutaway waits half a second for the app to redraw, then refreshes. An app that changes its look later than that needs one more <kbd>⌘R</kbd>. See [Environment](/guide/environment).

### Why isn’t an attribute I expect in the list?

Cutaway has no list of its own: it shows what the app’s CutawayServer sends, so what appears depends on the server’s version. Your app can add its own attributes; see [Customizing what Cutaway shows](/integrate/customizing).

## Builds and safety

### Will CutawayServer end up in my App Store build?

Not by default. Unless you enable the `ReleaseEnabled` trait, a build without `DEBUG` contains only an empty `start()`: no server, no networking code. See [Debug and Release builds](/integrate/builds).

### Can other devices on the network connect to my app?

No. CutawayServer listens on `127.0.0.1` only. On a device, the Mac reaches it through the USB connection.

### Does inspecting change my app?

Only the edits you make, and the layout they cause. Capturing restores everything it touches before the main thread moves on, and reading attributes doesn’t trigger layout. See [Behavior on the device](/integrate/on-device).

### macOS says it can’t verify the developer.

Cutaway’s builds are not notarized by Apple. Open **System Settings › Privacy & Security** and choose **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

## Archives

### Can I look at an app without the device?

Yes. Save an archive while the app is connected (<kbd>⌘S</kbd>) and open it anywhere, on any Mac: the tree, screenshots, attributes and constraints are all there. Everything works except editing. See [Archives and export](/guide/archives).

### Can I replay an archive as if it were a running app?

For development, yes: `scripts/replay.sh <file.cutaway>` in the Cutaway repository serves an archive as an app in a simulator, for a running Cutaway to connect to. See [Contributing](/resources/contributing).
