#!/bin/bash
# Sets up a fresh clone for development: the protocol submodule, the pinned tools, the git hooks
# and the Xcode project. Run it again at any time; it redoes only what is missing. It changes
# nothing outside this clone: what has to be installed system-wide it names, and stops.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

xcode="/Applications/Xcode.app/Contents/Developer"
# The XcodeGen version the project is generated with.
xcodegen_version="2.46.0"

step() { printf '\n== %s\n' "$1"; }
fail() {
  echo "setup: $1" >&2
  exit 1
}

step "system tools"
missing=0
if [[ -d "$xcode" ]]; then
  DEVELOPER_DIR="$xcode" xcodebuild -version | sed -n 1p
else
  echo "Xcode is not at /Applications/Xcode.app; install it from the App Store or developer.apple.com"
  missing=1
fi
if command -v xcodegen >/dev/null && [[ "$(xcodegen --version 2>&1)" == "Version: $xcodegen_version" ]]; then
  echo "XcodeGen $xcodegen_version"
else
  echo "XcodeGen $xcodegen_version is required (found: $(xcodegen --version 2>&1 || echo none));" \
    "see https://github.com/yonaskolb/XcodeGen/releases/tag/$xcodegen_version"
  missing=1
fi
if command -v jq >/dev/null; then
  jq --version
else
  echo "jq is required by scripts/check.sh; install it, for example: brew install jq"
  missing=1
fi
((missing == 0)) || fail "install what is named above, then run ./setup.sh again"

step "Metal toolchain"
if DEVELOPER_DIR="$xcode" xcrun metal --version >/dev/null 2>&1; then
  echo "installed"
else
  echo "downloading the Metal toolchain (Xcode's component, a few hundred MB)"
  DEVELOPER_DIR="$xcode" xcodebuild -downloadComponent MetalToolchain ||
    fail "could not download the Metal toolchain"
fi

step "protocol submodule"
git submodule update --init
# Protocol/ is pinned at a released tag; a shallow clone hides the tags, so fetch them to name it.
git -C Protocol describe --tags --exact-match >/dev/null 2>&1 ||
  git -C Protocol fetch --quiet --tags --unshallow 2>/dev/null ||
  git -C Protocol fetch --quiet --tags
echo "Protocol/ at $(git -C Protocol describe --tags --exact-match 2>/dev/null || git -C Protocol rev-parse --short HEAD)"

step "pinned tools"
Protocol/scripts/get-flatc.sh "$repo_root/.tools" || fail "could not install flatc"
scripts/get-format-tools.sh swiftformat || fail "could not install SwiftFormat"
scripts/get-format-tools.sh swiftlint || fail "could not install SwiftLint"

step "git hooks"
scripts/install-git-hooks.sh

step "Swift packages"
DEVELOPER_DIR="$xcode" swift package --package-path CutawayKit resolve ||
  fail "could not resolve CutawayKit's packages"

step "Xcode project"
xcodegen generate --spec project.yml --quiet || fail "xcodegen could not generate the project"
echo "generated Cutaway.xcodeproj from project.yml"

printf '\nsetup: done. Open Cutaway.xcodeproj; scripts/check.sh builds and tests everything.\n'
