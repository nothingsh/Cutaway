# Contributing to Cutaway

Thanks for helping. This page says how to build and check the code, where changes go and how they
are reviewed. How the three repositories fit together, and how to use Cutaway, is on the
[website](https://nothingsh.github.io/Cutaway/resources/contributing); its source is in `site/`.

## Development

Cutaway is written in Swift 6 with AppKit and Metal. The code is a local Swift package,
`CutawayKit`, with the app target doing nothing but assembling it:

| Target | Content |
|---|---|
| `CutawayWire` | Frames, the protocol's messages as value types, and the archive format |
| `CutawayTransport` | Finding apps, `usbmuxd`, sessions and requests |
| `CutawayModel` | The layer tree, screenshots and attributes, and the state the windows share |
| `CutawayProjects` | Linked project folders and their index: declarations, color sets, strings |
| `CutawayScene` | Where every layer is drawn, in what order, and hit testing; pure Swift |
| `CutawayRender` | Drawing the scene with Metal |
| `CutawayUI` | Windows, the list, the preview, the inspector, settings |
| `CutawayTestSupport` | A mock server that replays the protocol's fixtures, synthetic trees, a fake `usbmuxd` |

The wire format is defined in [CutawayProtocol](https://github.com/nothingsh/CutawayProtocol),
checked out at `Protocol/` as a submodule; the Swift code for it is generated from the schema and
checked in. Nothing is shared with [CutawayServer](https://github.com/nothingsh/CutawayServer) but the protocol.

After cloning, run `./setup.sh` once. It checks for Xcode, XcodeGen and jq, downloads Xcode's
Metal toolchain if it is missing, checks out the protocol submodule, installs the pinned tools
(flatc, SwiftFormat, SwiftLint) into `.tools/`, sets up the git hooks, resolves CutawayKit's Swift
packages and generates `Cutaway.xcodeproj` from `project.yml`. Running it again is harmless.

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

## Branches

- `main` holds released versions only. Every release is a tag on `main`.
- Work happens on `dev-<next version>`, for example `dev-1.1.0`. There is one such branch at a
  time: the `dev-*` branch in the branch list.
- Open pull requests against that `dev-*` branch. Pull requests into `main` are closed
  automatically.
- When a version is ready, the maintainer rebases the `dev-*` branch onto `main`, tags the release
  and starts the next `dev-*` branch from `main`. A pull request still open at that point needs to
  be retargeted to the new branch.

## Issues and planning

- Report bugs and suggest features with the issue templates.
- Each version is a milestone. An issue in a milestone is planned for that version; an issue
  without one is not scheduled yet.
- Features that need new messages or fields also need a change to the
  [Cutaway protocol](https://github.com/nothingsh/CutawayProtocol). The `protocol` label marks
  them; the change is proposed in that repository first.
- For anything larger than a small fix, comment on the issue before you start, so the approach
  can be agreed first.

## Pull requests

- Branch from the current `dev-*` branch and keep one change per pull request. Link the issue it
  closes, e.g. "Closes #12".
- Use a [Conventional Commits](https://www.conventionalcommits.org/) prefix in the title, e.g.
  `feat: ...`, `fix: ...`, `docs: ...`.
- The `check` workflow must pass, and the maintainer reviews every change.
- History is linear: pull requests are merged by squash or rebase. To pick up new commits on the
  `dev-*` branch, rebase onto it rather than merging it in.
- Do not consult the source code of other view-inspection tools while working on this one.
