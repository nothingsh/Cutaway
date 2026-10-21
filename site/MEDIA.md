# The website's screenshots and videos

The pages name every image and video they need. Until a file exists, the page shows a labelled
placeholder; `scripts/site.sh check` lists what is still missing. This file says how to make them
so that they look alike. It is not part of the site.

Every language of the site uses the same files, taken with Cutaway in English: a translated page
translates only the alt text.

## How to take them

- **The app inspected:** Wikipedia in the Simulator for everything except the two `integrate-…`
  shots, which need CutawayDemo's Extensions page (the only app using the extension interface).
- **Simulator:** iPhone 17 Pro, iOS 26.
- **Cutaway:** the inspector window 1440 × 900 points, Settings at their defaults, the system's
  accent color. Make each shot in **Light** and **Dark** (Settings › General › Appearance), with
  the same state.
- **Capture:** a window without its shadow: `screencapture -o -l <window number>`, or ⌘⇧4,
  Space, then ⌥-click the window. Crop to what the alt text describes when the whole window is
  not needed.
- **Put it in place:** `scripts/site-media.sh shot <name> <light.png> <dark.png>` scales both to
  at most 1600 pixels wide and writes `public/media/<name>-light.png` and `-dark.png`.

Videos are 5 to 10 seconds, recorded with ⌘⇧5 (Record Selected Portion) in Light, of the region
that shows the movement, without the pointer jumping. Put each in place with
`scripts/site-media.sh video <name> <recording.mov>`: it writes an H.264 `public/media/<name>.mp4`
and a poster `<name>.jpg`. The page loops it silently, or shows the poster and controls to a
viewer who asked for reduced motion.

The product picture on the home page and in the README is `public/media/home-overview-*.png`
(the same as `Resources/readme/overview-*.png`). When it is redone for a new interface, run
`swift scripts/site-images.swift` afterwards to redraw the social preview.

## Screenshots

| Name | Page | What it shows |
|---|---|---|
| `guide-applist` | Getting started, Connecting | The app list with one app in the Simulator, ready to be chosen |
| `guide-hierarchy-rows` | The layer list | Part of the layer list: pinned ancestors at the top, rows with view controllers and member variables, and a dimmed hidden row |
| `guide-preview-3d` | The preview | The preview in 3D with a wide layer spacing, the layers spread apart and turned to the side |
| `guide-measuring-2d` | Measuring | Measuring in 2D: the selected layer and the layer under the pointer, with the distances between their edges in points |
| `guide-measuring-3d` | Measuring | Measuring in 3D: the distances drawn on the selected layer's level while the preview is turned |
| `guide-attributes-panel` | Attributes | The attributes of a label: the Content and Appearance sections, a color field being edited, and a faded value with no effect |
| `guide-attributes-colors` | Attributes | Color rows: a registered color name, a split light and dark swatch with the current half underlined, and its tooltip |
| `guide-constraints-list` | Constraints | The Constraints list of a view, one constraint pointed at, and its other end marked in the preview |
| `guide-environment-popover` | Environment | The Environment popover: Appearance set to Dark, the text size slider, layout direction and size classes, each with its current value |
| `guide-source-open` | Source code | The Object section with an Open in Xcode button beside an app class, and the File menu's Open in Xcode item |
| `guide-archives-window` | Archives and export | An archive window, marked Archive in the toolbar with the date it was saved, next to the File menu |
| `guide-settings-general` | Settings | The General page of Settings: the Language and Appearance pop-up menus |
| `guide-settings-preview` | Settings | The Preview page of Settings: the default mode, layer spacing, hidden layers and borders |
| `integrate-app-section` | Customizing (CutawayDemo) | The inspector of the sales chart: the App section with the Chart group, an editable bar color showing the registered name brandBlue |
| `integrate-virtual-nodes` | Customizing (CutawayDemo) | The sales chart: the bars North, South and East as virtual nodes in the layer list, and their dashed outlines in the preview |

`guide-attributes-colors` needs a registered color name, which Wikipedia does not have: take it in
CutawayDemo, or leave the name out of the shot and the alt text.

## Videos (home page)

| Name | What it shows |
|---|---|
| `home-3d` | Turning the 3D preview, then widening the layer spacing |
| `home-measure` | Holding ⌥ over neighbouring layers, then over a row in the list |
| `home-edit` | Dragging opacity and picking a color, then ⌘Z |
| `home-constraints` | Pointing at constraints; their other ends light up in the preview |
| `home-environment` | Switching to Dark, then to a larger text size |
| `home-archive` | Saving an archive, then opening it in its own window |
