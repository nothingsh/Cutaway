---
description: Measure the distances between two layers by holding Option, in the preview or in the layer list, in 2D and in 3D.
---

# Measuring

Measure the space between two layers without a ruler: select one, hold <kbd>⌥</kbd> and point at the other.

## Measure in the preview

1. Select a layer: click it in the preview or in the layer list.
2. Hold <kbd>⌥</kbd> and point at another layer in the preview.

Cutaway outlines both layers and draws the distances between them, each with its value in points:

- where the two are apart, horizontally or vertically, the gap between their facing edges;
- where they overlap or one is inside the other, the distance between edges on the same side: left to left, right to right, top to top, bottom to bottom.

Distances of 0 are left out. Zooming and panning redraw the measurement; the values stay the same.

Let go of <kbd>⌥</kbd> and the measurement disappears.

<Shot name="guide-measuring-2d" alt="Measuring in 2D: the selected layer and the layer under the pointer, with the distances between their edges in points." />

## Measure in 3D

Measuring works the same way in 3D, with the same values as in 2D. The distances are drawn on the selected layer’s level and the other layer’s outline on its own level. When the two are on different levels, a dashed copy of the other outline appears on the selected layer’s level, joined to it at the corners, so you can see which edges are compared. Turn the preview, zoom or change the layer spacing, and the measurement follows.

<Shot name="guide-measuring-3d" alt="Measuring in 3D: the distances drawn on the selected layer’s level while the preview is turned." />

## Measure from the layer list

Some layers are hard to point at in the preview: a container covered by its subviews, a layer hidden behind others in 3D, a very small one. Point at its row instead:

1. Select a layer.
2. Hold <kbd>⌥</kbd> and point at another row in the layer list, including the pinned rows at the top.

The preview draws the distances between the selected layer and that row’s layer. Nothing is drawn when you point at the selected row itself, or at a layer that isn’t drawn in the preview (collapsed inside another, hidden, or outside the focused subtree). The measurement disappears when you let go of <kbd>⌥</kbd> or the pointer leaves the list.

<kbd>⌥</kbd>-clicking a row’s disclosure triangle still expands or collapses it with everything inside.

## Next

<NextSteps :items="[
  { title: 'Constraints', text: 'See the rules behind the distances.', link: '/guide/constraints' },
  { title: 'Attributes', text: 'Change a frame or an inset and measure again.', link: '/guide/attributes' }
]" />
