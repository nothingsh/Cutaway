#!/bin/bash
# Installs the pinned Node.js (scripts/node-version.txt) and prints the path of its bin directory.
# Node is used only to build the website in site/, never the app.
# Usage: get-node.sh [destination-dir]   (default: <repo>/.tools)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
pins="$script_dir/node-version.txt"

fail() {
  echo "get-node: $1" >&2
  exit 1
}

version="$(awk '$1 == "version" { print $2 }' "$pins")"
[[ -n "$version" ]] || fail "no version in scripts/node-version.txt"
read -r asset expected_sha < <(awk -v a="$(uname -m)" '$1 == a { print $2, $3 }' "$pins") ||
  fail "no archive for $(uname -m) in scripts/node-version.txt"

# The version is part of the path, so that a Node of another version is never picked up.
dest="${1:-$repo_root/.tools}/node-$version"
bin="$dest/bin"

if [[ -x "$bin/node" ]] && [[ "$("$bin/node" --version)" == "v$version" ]]; then
  echo "$bin"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

url="https://nodejs.org/dist/v$version/$asset"
curl --fail --location --silent --show-error -o "$work/node.tar.gz" "$url" ||
  fail "download failed: $url"

actual_sha="$(shasum -a 256 "$work/node.tar.gz" | awk '{ print $1 }')"
[[ "$actual_sha" == "$expected_sha" ]] ||
  fail "checksum mismatch for $asset: expected $expected_sha, got $actual_sha"

tar -xzf "$work/node.tar.gz" -C "$work"
unpacked="$work/${asset%.tar.gz}"
[[ -x "$unpacked/bin/node" ]] || fail "$asset does not contain bin/node"

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$unpacked" "$dest"

actual_version="$("$bin/node" --version)"
[[ "$actual_version" == "v$version" ]] || {
  rm -rf "$dest"
  fail "installed node reports '$actual_version', expected 'v$version'"
}

echo "$bin"
