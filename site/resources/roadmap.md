---
description: The directions planned for Cutaway and CutawayServer after 1.2.
---

# Roadmap

These are the directions planned after 1.2, shared by Cutaway and CutawayServer. Order and scope may change.

- **Interaction analysis.** Show gesture recognizers and target–action pairs; enable and disable gestures; call methods on objects.
- **Large hierarchies.** A fast mode that captures only visible layers; chunked transfer for very large images.
- **More connections and platforms.** Wi-Fi connections, authenticated and encrypted; tvOS and visionOS.
- **SwiftUI.** A semantic hierarchy of SwiftUI views alongside the layer tree.

Features that need new messages or fields also need a change to the [protocol](/protocol/), which only grows by appending, so older apps keep working with newer releases (see [Versions and compatibility](/protocol/versions)).

## Done in 1.2

The extension API for host apps, planned after 1.0, shipped in 1.2: [custom attributes, virtual nodes, views collapsed by default, color names and views excluded from images](/integrate/customizing). Overriding the app’s environment and linking your source code also came in 1.2; see the [release notes](/resources/releases).

## Ask for something

Suggest a feature or report a bug with the issue templates in the repository it belongs to:

- [Cutaway](https://github.com/nothingsh/Cutaway/issues), the Mac app;
- [CutawayServer](https://github.com/nothingsh/CutawayServer/issues), the iOS SDK;
- [Cutaway Protocol](https://github.com/nothingsh/CutawayProtocol/issues), for new messages or fields.

Each version is a GitHub milestone: an issue in a milestone is planned for that version, and one without is not scheduled yet.
