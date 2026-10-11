<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/readme/cutaway-client-dark.svg">
    <img src="Resources/readme/cutaway-client-light.svg" alt="Cutaway — Inspect iOS interfaces, layer by layer." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.0+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%2014+-blue)](#requirements)
[![License](https://img.shields.io/badge/License-GPL--3.0-lightgrey)](LICENSE)
[![check](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml/badge.svg)](https://github.com/nothingsh/Cutaway/actions/workflows/check.yml)

**English** | [简体中文](Resources/readme/README.zh-Hans.md) | [繁體中文](Resources/readme/README.zh-Hant.md) | [日本語](Resources/readme/README.ja.md) | [한국어](Resources/readme/README.ko.md) | [Español](Resources/readme/README.es.md) | [Français](Resources/readme/README.fr.md) | [Deutsch](Resources/readme/README.de.md)

Cutaway is a macOS app for looking inside the interface of a running iOS app. Add
[CutawayServer](https://github.com/nothingsh/CutawayServer) to your app, run it in the Simulator or
on a device connected over USB, and Cutaway lists it. Choose it, and Cutaway shows the app's layer
tree, a screenshot of every layer laid out in 2D or spread apart in 3D, and the attributes and Auto
Layout constraints of whichever layer you select. Edits you make to attributes are applied to the
running app.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/readme/overview-dark.png">
    <img src="Resources/readme/overview-light.png" alt="Cutaway inspecting an app in 3D: the layer tree, the layers spread apart with measurements, and the attributes of the selected layer." width="850">
  </picture>
</p>

## Features

**See how the interface is built**

- The layer tree of every window, with the root views of view controllers and the member
  variables that hold each layer or view marked, so a layer can be traced back to the code.
- A screenshot of every layer, flat in 2D or spread apart in 3D. Turn, zoom and pan with the
  mouse or trackpad; change the spacing between layers; show the layers that are hidden.
- Every position, size, rotation and scale as on the device's screen, including 3D transforms.
- Measure: hold ⌥ and point at another layer to see the distances between it and the selected
  one, in 2D and in 3D.

**Work with the details**

- The attributes of the selected layer and view, grouped as the app reports them. Editable
  attributes have controls: text, numbers you can drag, switches, color pickers, pop-ups for
  enumerations. Changes are applied in the running app at once, and ⌘Z undoes them.
- The Auto Layout constraints that refer to the selected view, with the ones that are not in
  effect marked, and the other end of each constraint marked in the preview. Click the other end
  to go to it.
- Search the tree, focus on a subtree, expand to a given depth, refresh a subtree alone.

**Keep what you found**

- Save an inspection as a `.cutaway` archive and open it later, on any Mac, with no device:
  the tree, screenshots, attributes and constraints are all there, with the view you had.
- Export the screenshot of a layer, alone or with its sublayers, as a PNG.

**Built for everyday use**

- Finds apps by itself: in simulators on this Mac and on devices connected over USB.
- Shows the tree first and the screenshots as they arrive; large trees stay responsive.
- Reconnects when an app comes back. Keeps up with the app's state: when it goes to the
  background, Cutaway says so and continues when it returns.
- In English, Simplified Chinese, Traditional Chinese, Japanese and Korean.
- Talks only to apps on this Mac and over the USB cable. No analytics, no crash reports.

## Requirements

- macOS 14 or later, on a Mac with a GPU that supports Metal (every Mac that runs macOS 14).
- An app that includes [CutawayServer](https://github.com/nothingsh/CutawayServer), running in
  the iOS Simulator or on an iPhone or iPad connected to the Mac over USB.

Cutaway is not sandboxed, because the socket it uses to reach devices over USB is outside the
sandbox. That is also why it is distributed outside the Mac App Store.

## Installation

Download `Cutaway-<version>.dmg` from the [Releases](https://github.com/nothingsh/Cutaway/releases) page, open it and drag
Cutaway to Applications. Cutaway is open source and its builds are not notarized by Apple, so the
first time you open it macOS says it cannot verify the developer. Open **System Settings › Privacy
& Security** and choose **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Cutaway.app
```

**Cutaway › Check for Updates…** tells you when a newer release is out. You can also build Cutaway
from source; see [Development](#development).

## Quick Start

1. Add [CutawayServer](https://github.com/nothingsh/CutawayServer) to your iOS app and call `CutawayServer.start()` once at launch. The
   server's [README](https://github.com/nothingsh/CutawayServer#readme) has the two lines for
   UIKit and SwiftUI. It is compiled only into Debug builds.
2. Run your app in the Simulator, or on a device connected to the Mac with a cable.
3. Open Cutaway. Your app appears in the list within a few seconds. Choose it.

## Using Cutaway

### The layer list

The sidebar lists the layers of every window as a tree. A row shows the layer's class, the view
it backs, the view controller whose root view it is, and the member variable that holds it, such
as `HomeViewController.titleLabel`. Dimmed rows are hidden or fully transparent.

- **Filter** the tree with the field at the top: rows whose title or class contains the text
  stay, with their ancestors.
- **Focus** on a layer (⌥⌘↓) to show only its subtree, in the list and in the preview; the path
  above the list leads back out.
- **Expand** to a chosen depth, or everything, from the menu next to the filter (⌥⌘→ and ⌥⌘←
  for all). When an app is first inspected, the tree opens down to the view controller on screen.
- **Double-click** a row to expand or collapse it. Double-clicking a layer in the preview does the
  same.

### The preview

The preview draws every visible layer at its place on the screen, with its screenshot, as the
tree arrives and then as each screenshot arrives.

- **2D or 3D** (⌘1, ⌘2) from the toolbar. In 3D the layers are spread apart along their depth;
  collapsing a row in the list folds its subtree back into one.
- **Turn** by dragging in 3D; **pan** by scrolling or, in 2D, by dragging; **zoom** by pinching or
  with ⌘ and the scroll wheel, around the pointer. **Reset View** (⌘0) goes back to the start.
- **Layer spacing** in 3D is the slider below the preview, from 0 to 200 points.
- **Show Hidden Layers** (⇧⌘H) also draws the layers that are hidden or transparent, in their own
  style. **Show Borders** (⇧⌘B) outlines every layer. Both switches are below the preview too.
- **Measure**: with a layer selected, hold ⌥ and point at another layer. The distances between
  the two are drawn with their values in points, in 2D and in 3D.
- Click a layer to select it; the list and the attributes follow. The layer under the pointer is
  highlighted.

### Attributes

The inspector on the right shows the attributes of the selected layer and its view in the
groups the app reports, such as `layer`, `view` and `label`. Cutaway has no list of its own: what
appears is what [CutawayServer](https://github.com/nothingsh/CutawayServer) sends, so it shows whatever the app's version of the server knows.

- Attributes the app marks editable have controls: a text field, a number field you can drag, a
  switch, a color picker with opacity, a pop-up for enumerations, and fields per component for
  points, sizes, rectangles, insets and transforms.
- A change is sent as soon as you commit it, or continuously while you drag. The app answers
  with the layer's attributes, so an attribute that changes with another (such as a layer's
  opacity with its view's alpha) is updated too.
- ⌘Z undoes the last change and ⇧⌘Z redoes it, for as long as the inspection lasts.
- A change the app rejects is explained in the row, and the previous value comes back.

After a change, Cutaway refreshes the screenshots of the layers it could have affected.

### Constraints

Below the attributes, a view's Auto Layout constraints are listed as the app reports them:
`self.leading = Safe Area of UIView.leading + 16`, with the priority when it is below 1000 and the
identifier when there is one. Constraints that are not in effect are dimmed and marked; the ones
UIKit generates are folded into one row. Click the other end of a constraint to select that view.
In the preview, the other ends of the selected view's constraints are marked.

### Refreshing

Cutaway shows what the app looked like when it was asked. **Refresh** (⌘R) asks again for the
whole tree and every screenshot, keeping your selection, expansion and camera. **Refresh Selected
Subtree** (⇧⌘R, also in the row's context menu) asks only for that layer's subtree. If the app
goes to the background, Cutaway waits; if the connection is lost, the last picture stays and
Cutaway reconnects when the same app is found again.

### Archives

**Save Archive…** (⌘S) collects the tree, the icon, and the screenshots, attributes and
constraints of every layer, hidden ones included, into one `.cutaway` file, along with how the
window looked. The file opens with **Open…** (⌘O), from Finder, or by dropping it on Cutaway's
icon, in its own window, and everything works as it did online except editing. Several archives
can be open at once, next to a live inspection.

**Export Layer Screenshot…** (⇧⌘E) and **Export Screenshot with Sublayers…** (⌥⇧⌘E) write the
selected layer's image as a PNG at the device's scale, with transparency, and without the layer's
own transform or opacity.

### Settings

**Settings…** (⌘,) has two pages. **General** chooses the language: the system's, or one of the
five. **Preview** chooses how a new inspection starts: 2D or 3D, the layer spacing, and whether
hidden layers and borders are shown. Windows already open keep their look.

### Keyboard shortcuts

| Action | Keys |
|---|---|
| Open an archive | ⌘O |
| Save an archive | ⌘S |
| Export the selected layer's screenshot, alone / with sublayers | ⇧⌘E / ⌥⇧⌘E |
| Undo / redo a change | ⌘Z / ⇧⌘Z |
| Filter the layer list | ⌘F |
| Refresh everything / the selected subtree | ⌘R / ⇧⌘R |
| 2D / 3D | ⌘1 / ⌘2 |
| Zoom in / zoom out / reset the view | ⌘= / ⌘- / ⌘0 |
| Show hidden layers / show borders | ⇧⌘H / ⇧⌘B |
| Focus on the selected layer / show all layers | ⌥⌘↓ / ⌥⌘↑ |
| Expand all / collapse all | ⌥⌘→ / ⌥⌘← |
| Show or hide the sidebar / the inspector | ⌃⌘S / ⌥⌘I |
| Show the app list | ⇧⌘0 |
| Settings | ⌘, |

## Performance

A large interface should still feel immediate. Cutaway is designed around that, and its test suite
holds it to the numbers below on every run. They are measured against a generated, app-shaped tree
of 10,000 layers (windows, containers, a navigation bar and a long list of cells, each with an
icon, labels and a separator), in a Debug build:

| Operation | Limit |
|---|---|
| The tree arrives → the list is on screen | 2 s |
| Laying out the scene | 1 s |
| A new frame after the camera moves | 16 ms |
| Drawing one frame | 16 ms |
| Selecting a row → the preview and the inspector follow | 100 ms |
| Searching the list | 200 ms |
| Expand all / collapse all | 1 s |
| Opening an archive of the tree → the list is on screen | 2 s |

How it gets there:

- **Screenshots stay compressed.** The model keeps only the compressed bytes it received. They
  are decompressed off the main thread, uploaded to the GPU, and the pixels are let go.
- **The preview draws only on change.** No frame is submitted while nothing moves.
- **Reading keeps pace with drawing.** When screenshots arrive faster than they are used, Cutaway
  stops reading from the connection, and TCP tells the app to wait. Nothing piles up in memory.
- **Nothing accumulates.** The suite repeats every operation ten times over 5,000 layers and
  checks that no screenshot, texture, request or window is left behind; a longer soak run
  (`scripts/soak.sh`) prints the memory curve over a hundred rounds.
- **Bad data does not crash it.** Every frame is validated before it is decoded, and the parsers
  are fuzzed with mutated, truncated and spliced frames on every run.

## Behavior on the Mac

- Every two seconds, Cutaway tries ports 48160 to 48167 on `127.0.0.1`, where [CutawayServer](https://github.com/nothingsh/CutawayServer)
  listens in simulators, and the same ports on each device connected over USB, through the
  system's `usbmuxd`. An app that answers the handshake is listed.
- One connection per app, kept for as long as the app is listed. An app that already has a client
  is left alone.
- A request that gets no byte for 10 seconds is given up; the connection is closed when the app
  sends something the [protocol](https://github.com/nothingsh/CutawayProtocol) forbids.
- Cutaway makes no other network connection, except when you choose **Check for Updates…**: then
  it asks GitHub for this repository's list of releases, and sends nothing about your Mac.
- Preferences are in `UserDefaults`; recent archives are in the system's recent-documents list.

## Roadmap

These are the directions planned after 1.0, shared with [CutawayServer](https://github.com/nothingsh/CutawayServer). Order and scope may change.

- **Protocol 1.0.** Freeze the [Cutaway protocol](https://github.com/nothingsh/CutawayProtocol), so later features only add to it.
- **Interaction analysis.** Show gesture recognizers and target–action pairs; enable and disable
  gestures; call methods on objects.
- **Extension API for host apps.** Custom attributes, virtual child nodes, and configuration such
  as classes collapsed by default, color aliases and views excluded from images.
- **Large hierarchies.** A fast mode that captures only visible layers; chunked transfer for very
  large images.
- **More connections and platforms.** Wi-Fi connections, authenticated and encrypted; tvOS and
  visionOS.
- **SwiftUI.** A semantic hierarchy of SwiftUI views alongside the layer tree.

## FAQ

**My app does not appear in the list.**
Check that the build includes [CutawayServer](https://github.com/nothingsh/CutawayServer) (it is compiled into Debug builds only) and calls
`CutawayServer.start()`, that the app is in the foreground, and, on a device, that the device is
connected with a cable and trusts this Mac. The server takes the first free port of 48160 to
48167; the list shows an app whose protocol version Cutaway cannot speak, with both versions.

**Does Cutaway need the network?**
No. It talks to simulators over the loopback address and to devices over USB. It never contacts
a server of its own.

**Why is a blur, video or Metal view blank?**
That content is composited by the system's render server, outside the app's process, so
[CutawayServer](https://github.com/nothingsh/CutawayServer) cannot render it from the layer tree.

**Can I look at an app without the device?**
Save an archive while the device is connected and open it anywhere. For development, the test
support library can also replay an archive as if it were an app in a simulator
(`scripts/replay.sh`).

**Does inspecting change my app?**
Only the edits you make. Capturing restores everything it touches, and reading attributes does
not trigger layout; see [CutawayServer's README](https://github.com/nothingsh/CutawayServer#readme).

## Development

Cutaway is written in Swift 6 with AppKit and Metal. The code is a local Swift package,
`CutawayKit`, with the app target doing nothing but assembling it:

| Target | Content |
|---|---|
| `CutawayWire` | Frames, the protocol's messages as value types, and the archive format |
| `CutawayTransport` | Finding apps, `usbmuxd`, sessions and requests |
| `CutawayModel` | The layer tree, screenshots and attributes, and the state the windows share |
| `CutawayScene` | Where every layer is drawn, in what order, and hit testing; pure Swift |
| `CutawayRender` | Drawing the scene with Metal |
| `CutawayUI` | Windows, the list, the preview, the inspector, settings |
| `CutawayTestSupport` | A mock server that replays the protocol's fixtures, synthetic trees, a fake `usbmuxd` |

The wire format is defined in [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol),
checked out at `Protocol/` as a submodule; the Swift code for it is generated from the schema and
checked in. Nothing is shared with [CutawayServer](https://github.com/nothingsh/CutawayServer) but the protocol.

After cloning, run `./setup.sh` once. It checks out the protocol submodule, checks for Xcode,
XcodeGen and jq, installs the pinned tools into `.tools/`, sets up the git hooks and generates
`Cutaway.xcodeproj` from `project.yml`. Running it again is harmless.

| Task | Command |
|---|---|
| Build and test the way CI does (needs only the code) | `scripts/check.sh` |
| Test the package alone | `cd CutawayKit && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' -testLanguage en` |
| Format, then lint | `scripts/format.sh` |
| Serve an archive as an app in a simulator, for a running Cutaway | `scripts/replay.sh <file.cutaway>` |
| Repeat every operation for a hundred rounds and print the memory curve | `scripts/soak.sh` |

- Nothing is judged by eye. The scene layer is covered by unit tests; the drawing layer renders
  off screen and is compared with the reference images in `Baselines/`.
- Tests never need a device. Connections are tested against the mock server replaying the
  protocol's fixtures, on this Mac.

## License

Cutaway is free software, released under the GNU General Public License v3.0; see
[LICENSE](LICENSE). It is built with [FlatBuffers](https://github.com/google/flatbuffers) (Apache
License 2.0), [DeclarativeAppKit](https://github.com/nothingsh/DeclarativeAppKit) (MIT) and
[DeclarativeCombine](https://github.com/nothingsh/DeclarativeCombine) (MIT); their licenses are in
the About panel and in [`CutawayKit/Sources/CutawayUI/Resources/Acknowledgements`](CutawayKit/Sources/CutawayUI/Resources/Acknowledgements). The [Cutaway protocol](https://github.com/nothingsh/CutawayProtocol) is under the
MIT License.
