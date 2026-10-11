#!/bin/bash
# Run by Xcode before it builds the app (project.yml): the pinned SwiftLint's findings show in
# the editor and the issue navigator. A warning does not stop the build; an error does, as
# SwiftLint itself decides. It downloads nothing: without the pinned SwiftLint it says so and
# lints nothing.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(awk '$1 == "swiftlint" { print $2 }' scripts/format-tools.txt)"
swiftlint=".tools/swiftlint-$version/swiftlint"
if [[ ! -x "$swiftlint" ]]; then
  echo "warning: SwiftLint $version is not installed; run: scripts/get-format-tools.sh swiftlint"
  exit 0
fi
"$swiftlint" lint --quiet
