#!/bin/bash
# Builds a release of Cutaway: the checks of C-DIST-01, a Release build signed ad hoc (no
# Developer ID, no notarisation), a DMG and a zip of the app, their checksums, and a check of
# what was built. The release workflow (.github/workflows/release.yml) runs it on each v* tag
# and attaches the files to a draft release.
#
# Usage: scripts/release.sh [--checks-only] [--tag <tag>]
#   --checks-only  stop after the checks; nothing is built
#   --tag <tag>    the tag being released: it must be v<version>, point at HEAD and come with a
#                  clean working tree
# The files go to build/release/<version>/.
set -euo pipefail
# Digits are ASCII digits, whatever the language of the Mac.
export LC_ALL=C

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step() { printf '\n== %s\n' "$1"; }
fail() {
  echo "release: $1" >&2
  exit 1
}

checks_only=no
tag=""
while (($#)); do
  case "$1" in
    --checks-only) checks_only=yes ;;
    --tag)
      [[ $# -ge 2 ]] || fail "--tag needs a tag"
      tag="$2"
      shift
      ;;
    *) fail "usage: scripts/release.sh [--checks-only] [--tag <tag>]" ;;
  esac
  shift
done

# The value of a base setting in the project.yml text on stdin: the one place the version and
# the build are written (C-DIST-01).
setting() {
  sed -nE "s/^    $1: \"?([^\"]*)\"?\$/\\1/p" | head -1
}

# The same forms as AppVersion.isValid(version:) and isValid(build:).
valid_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-beta\.[1-9][0-9]*)?$ ]]
}
valid_build() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

step "checks"
version="$(setting MARKETING_VERSION <project.yml)"
build="$(setting CURRENT_PROJECT_VERSION <project.yml)"
valid_version "$version" || fail "the version '$version' in project.yml is not major.minor.patch or major.minor.patch-beta.N"
valid_build "$build" || fail "the build '$build' in project.yml is not a positive integer"
echo "version $version, build $build"

if [[ -n "$tag" ]]; then
  [[ "$tag" == "v$version" ]] || fail "the tag $tag is not v$version, the version in project.yml"
  tagged="$(git rev-parse --verify --quiet "$tag^{commit}")" || fail "there is no tag $tag"
  [[ "$tagged" == "$(git rev-parse HEAD)" ]] || fail "the tag $tag does not point at HEAD"
  [[ -z "$(git status --porcelain)" ]] || fail "the working tree has changes"
  echo "tag $tag at HEAD"
fi

# Each release's build is larger than that of every release before it (C-DIST-01).
while IFS= read -r other; do
  [[ -n "$other" && "$other" != "$tag" && "$other" != "v$version" ]] || continue
  other_build="$(git show "$other:project.yml" 2>/dev/null | setting CURRENT_PROJECT_VERSION)"
  valid_build "$other_build" || continue
  ((build > other_build)) || fail "the build $build is not larger than $other_build, the build of $other"
done < <(git tag --list 'v*')
echo "the build is larger than every earlier release's"

[[ "$checks_only" == no ]] || exit 0

# The Xcode to build with: /Applications/Xcode.app unless DEVELOPER_DIR names another one.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
out="build/release/$version"
derived="build/DerivedData"
rm -rf "$out"
mkdir -p "$out"
work="$(mktemp -d)"
cleanup() {
  [[ -z "${mounted:-}" ]] || hdiutil detach -quiet "$mounted" || true
  rm -rf "$work"
}
trap cleanup EXIT

step "build"
command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
xcodegen generate --spec project.yml --quiet || fail "xcodegen could not generate the project"
# The build products of an earlier release are not reused.
rm -rf "$derived/Build/Products"
xcodebuild build -project Cutaway.xcodeproj -scheme Cutaway -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" >"$out/build.log" 2>&1 || {
  grep -E " error: " "$out/build.log" || tail -40 "$out/build.log"
  fail "xcodebuild build -configuration Release"
}
app="$derived/Build/Products/Release/Cutaway.app"
[[ -d "$app" ]] || fail "the build made no Cutaway.app"
echo "built $app"

step "package"
zip="$out/Cutaway-$version.zip"
dmg="$out/Cutaway-$version.dmg"
ditto -c -k --keepParent "$app" "$zip"
# The disk image holds the app and a link to Applications, to drag it to.
mkdir "$work/image"
ditto "$app" "$work/image/Cutaway.app"
ln -s /Applications "$work/image/Applications"
hdiutil create -quiet -volname "Cutaway $version" -srcfolder "$work/image" -format UDZO -ov "$dmg" ||
  fail "hdiutil could not make the disk image"
(cd "$out" && shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" >SHA256SUMS)
echo "packaged the disk image and the zip"

step "self-check"
# Each check reads the app as a user gets it: from the zip and from the disk image.
plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist"
}
check_app() {
  local copy="$1" from="$2"
  codesign --verify --strict --deep "$copy" || fail "the app in $from does not pass codesign --verify --strict"
  # Read whole before grep: "grep -q" stops reading early, and under pipefail the writer's
  # SIGPIPE would count as a failure.
  local details entitlements
  details="$(codesign -d --verbose=2 "$copy" 2>&1)"
  grep -qE '^CodeDirectory .*flags=.*runtime' <<<"$details" ||
    fail "the app in $from is not signed for the hardened runtime"
  entitlements="$(codesign -d --entitlements - --xml "$copy" 2>/dev/null)"
  ! grep -q get-task-allow <<<"$entitlements" || fail "the app in $from can be attached to (get-task-allow)"
  [[ "$(plist_value "$copy" CFBundleShortVersionString)" == "$version" ]] ||
    fail "the app in $from is not version $version"
  [[ "$(plist_value "$copy" CFBundleVersion)" == "$build" ]] || fail "the app in $from is not build $build"
  echo "$from: signed ad hoc for the hardened runtime, version $version, build $build"
}
mkdir "$work/unzipped"
ditto -x -k "$zip" "$work/unzipped"
check_app "$work/unzipped/Cutaway.app" "the zip"
mkdir "$work/mount"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$work/mount" "$dmg" || fail "the disk image does not mount"
mounted="$work/mount"
check_app "$mounted/Cutaway.app" "the disk image"
[[ "$(readlink "$mounted/Applications")" == /Applications ]] || fail "the disk image has no link to Applications"
[[ "$(ls -A "$mounted" | grep -v '^\.' | sort | tr '\n' ' ')" == "Applications Cutaway.app " ]] ||
  fail "the disk image holds more than the app and the link"
(cd "$out" && shasum -a 256 -c SHA256SUMS >/dev/null) || fail "SHA256SUMS does not match the files"

printf '\nrelease: Cutaway %s (build %s) in %s\n' "$version" "$build" "$out"
cat "$out/SHA256SUMS"
