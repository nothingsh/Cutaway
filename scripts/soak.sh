#!/bin/bash
# Rounds of every operation over 5,000 layers, many more than the test suite runs (C-SCALE-02):
# 100 by default, or CUTAWAY_SOAK_ROUNDS. Prints the process's memory (phys_footprint) after
# every 10th round, and at the end how the last compares with the 10th against 1.1 times. The
# objects, files and requests left behind are checked as in the test suite; the memory is for
# reading, not a pass or a fail. Keeps the display awake: an asleep one stops the windows
# drawing.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rounds="${CUTAWAY_SOAK_ROUNDS:-100}"
if ! [[ "$rounds" =~ ^[0-9]+$ ]] || ((rounds < 1)); then
  echo "usage: CUTAWAY_SOAK_ROUNDS=<rounds> scripts/soak.sh" >&2
  exit 2
fi

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
package="$repo_root/CutawayKit"
swift build --package-path "$package" --build-tests
# Run the bundle itself: `swift test` holds back a test's output until the test ends.
bin="$(swift build --package-path "$package" --show-bin-path)"
CUTAWAY_SOAK_ROUNDS="$rounds" caffeinate -du xcrun xctest \
  -XCTest CutawayUITests.SoakTests/test_C_SCALE_02_roundsOfEveryOperationLeaveNothingBehind \
  "$bin/CutawayUITests.xctest"
