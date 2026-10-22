---
description: The three repositories behind Cutaway, how to build them, and where to report bugs and send changes.
---

# Contributing

Cutaway is built in the open, in three repositories that share no code, only a versioned protocol.

<PartsDiagram />

| Repository | What it is | License | How to contribute |
|---|---|---|---|
| [Cutaway](https://github.com/nothingsh/Cutaway) | The macOS app, in Swift with AppKit and Metal | GPL-3.0 | [CONTRIBUTING.md](https://github.com/nothingsh/Cutaway/blob/main/CONTRIBUTING.md) |
| [CutawayServer](https://github.com/nothingsh/CutawayServer) | The iOS SDK embedded in the app being inspected | MIT | [CONTRIBUTING.md](https://github.com/nothingsh/CutawayServer/blob/main/CONTRIBUTING.md) |
| [Cutaway Protocol](https://github.com/nothingsh/CutawayProtocol) | The wire protocol: specification, FlatBuffers schema and fixtures | MIT | [CONTRIBUTING.md](https://github.com/nothingsh/CutawayProtocol/blob/main/CONTRIBUTING.md) |

Both ends pin a tag of the protocol repository as a git submodule and generate their code from its schema. A feature that needs new messages or fields starts with a change to the protocol; the `protocol` label marks those issues.

## Report a bug or suggest a feature

Use the issue templates of the repository the problem belongs to. If you can’t tell, open it in [Cutaway](https://github.com/nothingsh/Cutaway/issues/new/choose): it will be moved if needed. An archive of the inspection (<kbd>⌘S</kbd>) often shows the problem better than a description; attach one if the app’s content can be shared.

## Build Cutaway

Cutaway is written in Swift 6 with AppKit and Metal. The code is a local Swift package, `CutawayKit`; the app target does nothing but assemble it.

| Target | Content |
|---|---|
| `CutawayWire` | Frames, the protocol’s messages as value types, and the archive format |
| `CutawayTransport` | Finding apps, `usbmuxd`, sessions and requests |
| `CutawayModel` | The layer tree, screenshots and attributes, and the state the windows share |
| `CutawayProjects` | Linked project folders and their index: declarations, color sets, strings |
| `CutawayScene` | Where every layer is drawn, in what order, and hit testing; pure Swift |
| `CutawayRender` | Drawing the scene with Metal |
| `CutawayUI` | Windows, the list, the preview, the inspector, settings |
| `CutawayTestSupport` | A mock server that replays the protocol’s fixtures, synthetic trees, a fake `usbmuxd` |

After cloning, run `./setup.sh` once. It checks for Xcode, XcodeGen and jq, downloads Xcode’s Metal toolchain if it is missing, checks out the protocol submodule, installs the pinned tools (flatc, SwiftFormat, SwiftLint) into `.tools/`, sets up the git hooks, resolves CutawayKit’s Swift packages and generates `Cutaway.xcodeproj` from `project.yml`. Running it again is harmless.

| Task | Command |
|---|---|
| Build and test the way CI does | `scripts/check.sh` |
| Format, then lint | `scripts/format.sh` |
| Serve an archive as an app in a simulator, for a running Cutaway | `scripts/replay.sh <file.cutaway>` |
| Repeat every operation for a hundred rounds and print the memory curve | `scripts/soak.sh` |

- Nothing is judged by eye. The scene layer is covered by unit tests; the drawing layer renders off screen and is compared with reference images.
- Tests never need a device. Connections are tested against a mock server replaying the protocol’s fixtures, on this Mac.

The full list of commands, the branch model and how pull requests are reviewed are in [CONTRIBUTING.md](https://github.com/nothingsh/Cutaway/blob/main/CONTRIBUTING.md). CutawayServer and the protocol describe their own builds in their repositories.

## Send a change

- Branch from the current `dev-*` branch and open the pull request against it; pull requests into `main` are closed automatically.
- Keep one change per pull request, link the issue it closes, and use a [Conventional Commits](https://www.conventionalcommits.org/) prefix in the title.
- For anything larger than a small fix, comment on the issue before you start, so the approach can be agreed first.

## Improve this website

The website’s source is in [`site/`](https://github.com/nothingsh/Cutaway/tree/main/site) in the Cutaway repository, written in Markdown and built with VitePress. Every page has an **Edit this page on GitHub** link at the bottom.
