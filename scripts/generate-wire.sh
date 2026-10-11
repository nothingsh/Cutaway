#!/bin/bash
# Generates the Swift code for the wire schema into <output-dir>.
# Usage: generate-wire.sh <output-dir>
#
# The checked-in copy lives in CutawayKit/Sources/CutawayWire/Generated.
# scripts/check.sh generates into a temporary directory and compares the two.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
out="${1:?usage: generate-wire.sh <output-dir>}"
mkdir -p "$out"
out="$(cd "$out" && pwd)" # resolve before changing directory

cd "$repo_root"
[[ -f Protocol/schema/cutaway.fbs ]] || {
  echo "generate-wire: Protocol/ is empty; run: git submodule update --init" >&2
  exit 1
}
flatc="$(Protocol/scripts/get-flatc.sh "$repo_root/.tools")"

# Remove earlier output first, so that a file the schema no longer produces does not linger.
find "$out" -mindepth 1 -maxdepth 1 -name '*_generated.swift' -delete

# --swift-implementation-only makes every generated type internal, which is what keeps
# FlatBuffers types inside CutawayWire.
"$flatc" --swift --gen-object-api --swift-implementation-only -o "$out" Protocol/schema/cutaway.fbs

# The same flag writes "@_implementationOnly import". In a module built without library
# evolution the compiler warns at every use of a FlatBuffers type (309 places), and rejects them
# under its stricter check. The types are already internal, so the supported spelling is
# "internal import". Other files in CutawayWire must then import FlatBuffers the same way:
# a bare "import FlatBuffers" next to this one is an error.
for file in "$out"/*_generated.swift; do
  sed -i '' 's/^@_implementationOnly import /internal import /' "$file"
  if grep -q '@_implementationOnly' "$file" || ! grep -q '^internal import FlatBuffers$' "$file"; then
    echo "generate-wire: could not rewrite the imports in $file; flatc's output has changed shape" >&2
    exit 1
  fi
done

echo "generate-wire: wrote $(find "$out" -name '*_generated.swift' | wc -l | tr -d ' ') file(s) to $out"
