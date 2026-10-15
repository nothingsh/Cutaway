#!/bin/bash
# Serves an archive (.cutaway) as an app in a simulator, for a running Cutaway to inspect
# without a device: MockServer on the first free port of 48160 to 48167, until Ctrl-C
# (C-MOCK-04). For trying a large app's archive on this Mac. Archives of real apps stay out of
# the repository.
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo "usage: scripts/replay.sh <archive.cutaway>" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
package="$repo_root/CutawayKit"
swift build --package-path "$package" --build-tests
# Run the bundle itself: `swift test` holds back a test's output until the test ends.
bin="$(swift build --package-path "$package" --show-bin-path)"
CUTAWAY_REPLAY_ARCHIVE="$archive" xcrun xctest \
  -XCTest CutawayTestSupportTests.ArchiveReplayServiceTests/test_C_MOCK_04_serveTheArchiveNamedInTheEnvironment \
  "$bin/CutawayTestSupportTests.xctest"
