---
description: What changed in each release of Cutaway, with links to the downloads.
---

# Release notes

Every release is on [GitHub Releases](https://github.com/nothingsh/Cutaway/releases), with the disk image, a zip and their SHA-256 checksums. Which Cutaway works with which CutawayServer is in [Versions and compatibility](/protocol/versions).

## 1.2.0 <Badge type="tip" text="Current" />

Cutaway 1.2.0 speaks protocol 1.2. It works with apps that include CutawayServer 1.0 or 1.1; the features marked below need [CutawayServer 1.2.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.2.0).

[Cutaway 1.2.0 on GitHub](https://github.com/nothingsh/Cutaway/releases/tag/v1.2.0) <Badge type="info" text="the links work once 1.2.0 is released" />

**Environment** (needs CutawayServer 1.2)

- Override the app’s appearance, text size (XS to AX5), layout direction and size classes from the **Environment** button in the toolbar or **View › Environment**. <kbd>⇧⌘A</kbd> toggles light and dark.
- After a change, Cutaway waits for the app to redraw and refreshes the whole tree. **Reset** gives the app its own environment back, and so does closing the inspection.
- Archives remember the overrides and name them under the window’s title.

**Your source code**

- **File › Link Project Folder…** connects an app to its Xcode project; **Settings › Projects** lists the folders. Cutaway only reads them.
- **Open in Xcode** (<kbd>⌥⌘O</kbd>) jumps from the app’s own classes to their declarations, in Swift or Objective-C.
- Colors are named after the asset catalog’s color sets they match, and text shows the string catalog key it came from.
- **Edit › Copy LLDB Command** copies a command that prints the selected object, or stops when its frame changes.

**Attributes**

- Dynamic colors show their light and dark values side by side.
- An Accessibility section; text styles, drawn and truncated lines, images, index paths and item counts in one row each.
- Values that refer to other views, such as a stack view’s arranged subviews, are chips you can point at and click.

**Your app’s own details** (needs CutawayServer 1.2)

- An App section with the attribute groups your app adds, editable like any other.
- Colors your app registers are shown by name.
- Views your app marks start collapsed in the list, and views it excludes are hatched instead of captured.
- Virtual nodes: parts of the interface a view draws itself, such as the bars of a chart, appear in the tree with their own icon and a dashed outline.

**Also**

- Hold <kbd>⌥</kbd> over a row of the layer list to measure to that layer.
- A layer with a thousand attributes shows them at once, and screenshots arrive faster: about 1.4 s instead of 3.8 s for 5,000 layers.

## 1.1.0

[Cutaway 1.1.0 on GitHub](https://github.com/nothingsh/Cutaway/releases/tag/v1.1.0) · [CutawayServer 1.1.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.1.0)

Cutaway 1.1.0 speaks protocol 1.1. It works with apps that include CutawayServer 1.0, and shows everything below with CutawayServer 1.1.0.

- **Attributes** in one list of five sections by purpose: Content, Appearance, Layout, Behavior and Object. Related attributes share one row; values show their units, checkboxes, segmented controls, insets as a box and colors with their system names. A value with no effect is faded, with the reason in its tooltip.
- A value outside the limits the app reports is never sent: the field stays open and says why.
- A filter for the attributes, section headers that stay in view, and a row of the layer’s ancestors.
- The other end of a constraint is a chip. Point at a constraint to mark its other end in the preview, or turn on **Show Constraint Ends** (<kbd>⇧⌘K</kbd>).
- **Hierarchy:** each layer has an icon for its kind, filled for the app’s own classes; guides show nesting; the ancestors of the top row stay pinned; **Select Parent Layer** (<kbd>⌘↑</kbd>) and **Select First Child Layer** (<kbd>⌘↓</kbd>).
- **Preview:** a tag beside the selected layer; borders off, plain or by kind, optionally only for the app’s own classes.
- The app list groups simulators and USB devices and takes the arrow keys and Return.
- An appearance setting: system, light or dark.

## 1.0.0

[Cutaway 1.0.0 on GitHub](https://github.com/nothingsh/Cutaway/releases/tag/v1.0.0) · [CutawayServer 1.0.0](https://github.com/nothingsh/CutawayServer/releases/tag/1.0.0)

The first public release, speaking protocol 1.0.

- The layer tree of every window, with view controllers’ root views and the member variables that hold each layer marked.
- A screenshot of every layer, flat in 2D or spread apart in 3D, with every position, size, rotation and scale as on the device, including 3D transforms.
- Measuring between two layers with <kbd>⌥</kbd>, in 2D and in 3D.
- Editable attributes, applied in the running app at once, with <kbd>⌘Z</kbd> to undo.
- The Auto Layout constraints that refer to a view, with the ones not in effect marked.
- Search, focus on a subtree, expand to a depth, refresh a subtree alone.
- `.cutaway` archives that open on any Mac without the device, and PNG export of a layer’s screenshot.
- Finds apps in simulators and on USB devices by itself, reconnects when an app comes back, and follows the app into the background and back.
- In English, Simplified Chinese, Traditional Chinese, Japanese and Korean.
- **Check for Updates…** asks GitHub whether a newer release is out.
