#!/bin/bash
# The build-and-test entry point: the pinned tools, the generated code, formatting, SwiftLint,
# the package tests and the app's build and tests. It is what GitHub Actions runs
# (.github/workflows/check.yml) and what a contributor runs.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

step() { printf '\n== %s\n' "$1"; }
fail() {
  echo "check: FAILED: $1" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# Where the logs of the two test runs go. A caller can name a directory of its own and read the
# passed tests from them.
logs="${CHECK_LOG_DIR:-$work}"

# The Xcode to build with: /Applications/Xcode.app unless DEVELOPER_DIR names another one, as a
# runner may. The global developer directory can be CommandLineTools, which cannot build the app.
xcode="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR="$xcode"

step "toolchain"
[[ -d "$xcode" ]] || fail "Xcode is not at $xcode; set DEVELOPER_DIR"
# Not "head -1": head exits after the first line, xcodebuild may then die of SIGPIPE writing
# the second, and under pipefail the script stops there.
xcodebuild -version | sed -n 1p
if ! xcrun metal --version >/dev/null 2>&1; then
  # Since Xcode 26 the Metal compiler is a separate component; the shaders need it.
  echo "downloading the Metal toolchain"
  xcodebuild -downloadComponent MetalToolchain >"$work/metal.log" 2>&1 || {
    tail -20 "$work/metal.log"
    fail "the Metal Toolchain is missing and could not be downloaded"
  }
fi
xcrun metal --version | sed -n 1p
command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
echo "xcodegen $(xcodegen --version 2>&1)"
command -v jq >/dev/null || fail "jq is not installed (brew install jq)"

step "protocol submodule"
[[ -f Protocol/PROTOCOL_VERSION ]] ||
  fail "Protocol/ is empty; run: git submodule update --init"
echo "protocol $(tr -d '[:space:]' <Protocol/PROTOCOL_VERSION) at $(git -C Protocol describe --tags --always)"

step "generated code"
flatc="$(Protocol/scripts/get-flatc.sh "$repo_root/.tools")" ||
  fail "could not install the pinned flatc"
"$flatc" --version
generated="CutawayKit/Sources/CutawayWire/Generated"
scripts/generate-wire.sh "$work/generated" >/dev/null ||
  fail "could not generate the wire code"
diff -r "$work/generated" "$generated" ||
  fail "$generated is out of date or was edited by hand; run: scripts/generate-wire.sh $generated"
echo "generated code matches the schema"

step "pinned FlatBuffers runtime"
flatbuffers_version="$(tr -d '[:space:]' <Protocol/FLATBUFFERS_VERSION)"
resolved_version="$(jq -r '.pins[] | select(.identity == "flatbuffers") | .state.version' CutawayKit/Package.resolved)"
[[ "$resolved_version" == "$flatbuffers_version" ]] ||
  fail "CutawayKit/Package.resolved pins FlatBuffers at '$resolved_version', but Protocol/FLATBUFFERS_VERSION is $flatbuffers_version"
echo "FlatBuffers $resolved_version"

step "formatting"
# Generated code is neither formatted nor linted: it must stay what flatc writes.
grep -qF "$generated" .swiftformat || fail ".swiftformat no longer excludes $generated"
grep -qxF "  - $generated" .swiftlint.yml || fail ".swiftlint.yml no longer excludes $generated"
swiftformat="$(scripts/get-format-tools.sh swiftformat "$repo_root/.tools")" ||
  fail "could not install the pinned SwiftFormat"
echo "swiftformat $("$swiftformat" --version)"
"$swiftformat" --lint --cache ignore . >"$work/format.log" 2>&1 || {
  grep -E "error:" "$work/format.log" || tail -20 "$work/format.log"
  fail "the code is not formatted; run: scripts/format.sh"
}
echo "the code is formatted"

step "lint"
swiftlint="$(scripts/get-format-tools.sh swiftlint "$repo_root/.tools")" ||
  fail "could not install the pinned SwiftLint"
echo "swiftlint $("$swiftlint" version)"
# SwiftLint loads SourceKit from the Xcode DEVELOPER_DIR names.
"$swiftlint" lint --strict --quiet --no-cache ||
  fail "SwiftLint found violations"
echo "no SwiftLint violations"

step "package tests"
# A CI runner sets CUTAWAY_CI=1 (.github/workflows/check.yml): the tests timed against the
# developer's Mac, and those a virtual GPU or a loaded machine upsets, are skipped there
# (TestRunner in CutawayTestSupport). xcodebuild passes a TEST_RUNNER_ variable to the tests,
# the app's included, without the prefix.
if [[ -n "${CUTAWAY_CI:-}" ]]; then
  export TEST_RUNNER_CUTAWAY_CI="$CUTAWAY_CI"
fi
# Through xcodebuild, not "swift test": SwiftPM compiles the string catalog only from Xcode 27
# (Swift 6.4) on; Xcode 26 copies it as it is and every text comes out as its key. Xcode's
# build system compiles it with either. The tests expect English (C-LOC-01).
(cd CutawayKit && xcodebuild test -scheme CutawayKit-Package -destination 'platform=macOS' \
  -derivedDataPath ../DerivedData -testLanguage en) >"$logs/package-tests.log" 2>&1 || {
  grep -E " error: |^Test Case .* failed" "$logs/package-tests.log" || true
  tail -40 "$logs/package-tests.log"
  fail "xcodebuild test (CutawayKit-Package)"
}
grep -E "^Test Case .* (failed|skipped)|Test skipped" "$logs/package-tests.log" || true
# The times C-SCALE-01 records.
grep -E "^C-SCALE-01 " "$logs/package-tests.log" || true
grep -E "Executed [0-9]+ tests" "$logs/package-tests.log" | tail -1
grep -q "^Test Case .* passed" "$logs/package-tests.log" || fail "no package test ran"

step "project"
[[ -z "$(git ls-files -- '*.xcodeproj/*')" ]] ||
  fail "an .xcodeproj is checked in; the project is generated from project.yml"
xcodegen generate --spec project.yml --quiet || fail "xcodegen could not generate the project"
echo "generated Cutaway.xcodeproj from project.yml"

step "app build and app tests"
# A module left in the built products by an earlier build can be found before the one this
# build makes, so the products are built afresh.
rm -rf DerivedData/Build/Products
xcodebuild test -project Cutaway.xcodeproj -scheme Cutaway \
  -destination 'platform=macOS' -derivedDataPath DerivedData >"$logs/app-tests.log" 2>&1 || {
  grep -E " error: |^Test Case .* failed" "$logs/app-tests.log" || true
  tail -40 "$logs/app-tests.log"
  fail "xcodebuild test"
}
# One line per test, so that a skipped test (and why) shows up in the log.
grep -E "^Test Case .* (passed|failed|skipped)|Test skipped" "$logs/app-tests.log" || true
grep -q "^Test Case .* passed" "$logs/app-tests.log" || fail "no app test ran"

printf '\ncheck: OK (the code builds, is formatted and passes its tests)\n'
