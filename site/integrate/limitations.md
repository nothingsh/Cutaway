---
description: What CutawayServer cannot capture or find, and why.
---

# Limitations

These come from how iOS draws, and from what an app can see of itself.

## Blurs, video and Metal are blank

Content composited by the system’s render server, outside the app’s process, is not in the images: blur effects, Metal and video layers, and the like. CutawayServer renders each layer from the layer tree inside the app, and that content is not there. The layers themselves are in the hierarchy, with their attributes; only their pictures are empty.

## Bar text is white in the images

Filters applied by the render server are not in the images either. On iOS 26, text and icons in navigation bars, toolbars and tab bars are drawn in a plain color, often white, and a filter on a parent layer gives them their on-screen color when the render server composites the screen. Images show each layer’s own content, before that filter.

Attributes such as `textColor` still show the color the app set.

## Colors are in sRGB

Colors are sent in sRGB, so wide-gamut (Display P3) colors are clipped to the nearest sRGB color.

## Member variable names

Cutaway marks the member variable that holds a layer or view, such as `HomeViewController.titleLabel`. The server finds these names by comparing addresses in the owner’s memory, without calling any getter, so:

- references held by default (safe) `unowned` properties are **not** found;
- references held in collections, such as arrays, are **not** found;
- `weak`, `unowned(unsafe)`, `lazy` properties and properties of generic classes **are** found.

## Environment overrides

[Overriding the environment](/guide/environment) has limits of its own:

- Before iOS 17, only the appearance (light or dark) can be overridden; Cutaway offers only what the app’s server can override on that device.
- Text size changes only content that takes its font from the trait environment, such as labels with `adjustsFontForContentSizeCategory`.
- An override a view controller or view sets itself, such as its own `overrideUserInterfaceStyle`, still wins under UIKit’s rules, and the interface below it does not change.

## One client at a time

The server serves one Cutaway at a time. A second one is turned away while the first is connected; it can connect once the first disconnects.

## Next

<NextSteps :items="[
  { title: 'FAQ and troubleshooting', text: 'More answers to “why is this blank?”', link: '/resources/faq' },
  { title: 'Behavior on the device', text: 'What capturing touches and restores.', link: '/integrate/on-device' }
]" />
