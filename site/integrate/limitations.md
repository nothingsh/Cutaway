---
description: What CutawayServer cannot capture or find, and why.
---

# Limitations

These come from how iOS draws, and from what an app can see of itself.

## What only the system draws

CutawayServer 1.3 takes the picture of a window, and of a subtree with blurs, Liquid Glass or color filters, from what the app composited, so these show in 2D and on collapsed layers. A layer’s own image is still rendered from the layer tree inside the app, without them, and that is what 3D shows of expanded layers. The status bar does not belong to the app and is in no image.

An effect that samples what lies behind it, such as glass, can look different in a picture of its subtree. While an excluded view shows, or when a window is translucent, the server draws the layers instead. Video and Metal content can still be blank. With a server older than 1.3 every image is drawn from the layers.

## Bar text can be white in a layer’s own image

On iOS 26, text and icons in navigation bars, toolbars and tab bars are drawn in a plain color, often white, and a filter on a parent layer gives them their on-screen color when the render server composites the screen. A layer’s own image shows its content before that filter. The picture of the window and of a collapsed bar has the right color.

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
