---
description: Read the Auto Layout constraints of the selected view, see which ones are not in effect, and find the other end of each.
---

# Constraints

The Layout section of the attributes ends with the Auto Layout constraints that refer to the selected view. This page shows how to read them and follow them to the other end.

## Read a constraint

Each constraint is written as the app reports it:

```text
self.leading = Safe Area of UIView.leading + 16
```

`self` is the selected view. The other end is a chip with its icon and name; it can be another view or a layout guide (Safe Area, Layout Margins, Readable Content, Keyboard). The priority is shown when it is below 1000, and the identifier when there is one.

- Constraints that are **not in effect** are dimmed and marked.
- The constraints **UIKit generates** itself are folded into one row, such as “4 from UIKit”.

Earlier in the Layout section, the Auto Layout row says whether the view’s layout is ambiguous, near its hugging, compression resistance and intrinsic size.

<Shot name="guide-constraints-list" alt="The Constraints list of a view, one constraint pointed at, and its other end marked in the preview." />

## Find the other end

- **Point** at a constraint to mark its other end in the preview.
- **Click** the other end’s chip to select that view.
- **View › Show Constraint Ends** (<kbd>⇧⌘K</kbd>) marks the other end of every constraint at once. It is also in the borders menu below the preview, as **Constraint Ends**.

## Next

<NextSteps :items="[
  { title: 'Measuring', text: 'Check the distances the constraints produce.', link: '/guide/measuring' },
  { title: 'Attributes', text: 'Change a frame or an inset in the running app.', link: '/guide/attributes' }
]" />
