#!/bin/bash
# Formats the code with the pinned SwiftFormat, then lints it with the pinned SwiftLint.
# scripts/check.sh runs both without changing anything.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

swiftformat="$(scripts/get-format-tools.sh swiftformat)"
swiftlint="$(scripts/get-format-tools.sh swiftlint)"

"$swiftformat" --cache ignore .
# SwiftLint loads SourceKit from Xcode; the global developer directory has none.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$swiftlint" lint --strict --quiet --no-cache
