# Contributing to Cutaway

Thanks for helping. This page says where changes go and how they are reviewed. How to build and
check the code is in [Development](README.md#development) in the README.

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
