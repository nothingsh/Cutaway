#!/bin/bash
# Installs a pinned formatting or lint tool (scripts/format-tools.txt) and prints its path.
# Usage: get-format-tools.sh swiftformat|swiftlint [destination-dir]   (default: <repo>/.tools)
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

fail() {
  echo "get-format-tools: $1" >&2
  exit 1
}

name="${1:-}"
[[ -n "$name" ]] || fail "usage: get-format-tools.sh swiftformat|swiftlint [destination-dir]"
read -r version repository asset expected_sha < <(
  awk -v n="$name" '$1 == n { print $2, $3, $4, $5 }' "$script_dir/format-tools.txt"
) || fail "no entry for $name in scripts/format-tools.txt"
[[ -n "$expected_sha" ]] || fail "the entry for $name in scripts/format-tools.txt is incomplete"

# The version is part of the path, so that a binary of another version is never picked up.
dest="${2:-$repo_root/.tools}/$name-$version"
tool="$dest/$name"

# Prints the version the tool reports.
reported_version() {
  case "$name" in
    swiftlint) "$1" version ;;
    *) "$1" --version ;;
  esac
}

if [[ -x "$tool" ]] && [[ "$(reported_version "$tool")" == "$version" ]]; then
  echo "$tool"
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

url="https://github.com/$repository/releases/download/$version/$asset"
curl --fail --location --silent --show-error -o "$work/asset.zip" "$url" ||
  fail "download failed: $url"

actual_sha="$(shasum -a 256 "$work/asset.zip" | awk '{ print $1 }')"
[[ "$actual_sha" == "$expected_sha" ]] ||
  fail "checksum mismatch for $asset: expected $expected_sha, got $actual_sha"

unzip -q "$work/asset.zip" -d "$work/unpacked"
[[ -f "$work/unpacked/$name" ]] || fail "$asset does not contain $name"

mkdir -p "$dest"
mv "$work/unpacked/$name" "$tool"
chmod +x "$tool"

actual_version="$(reported_version "$tool")"
[[ "$actual_version" == "$version" ]] || {
  rm -f "$tool"
  fail "installed $name reports '$actual_version', expected '$version'"
}

echo "$tool"
