#!/bin/bash
# Tests the checks of scripts/release.sh (C-DIST-01) in throwaway git repositories: which
# versions, builds and tags it refuses and which it lets through. Nothing is built.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The repositories ignore the user's and the system's git configuration: no hooks, no signing.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

failures=0
passed=0

# write_project <version> <build>: project.yml with the two settings, as the real one has them.
write_project() {
  cat >"$repo/project.yml" <<EOF
name: Cutaway
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "$1"
    CURRENT_PROJECT_VERSION: "$2"
EOF
}

# new_repo <version> <build>: a repository with release.sh and that project.yml committed.
new_repo() {
  repo="$(mktemp -d "$work/repo.XXXXXX")"
  git -C "$repo" init -q
  mkdir "$repo/scripts"
  cp "$repo_root/scripts/release.sh" "$repo/scripts/"
  write_project "$1" "$2"
  commit "first"
}

commit() {
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "$1"
}

# expect pass|fail <description> <text the failure must say> [release.sh arguments...]
expect() {
  local outcome="$1" description="$2" says="$3" status=0
  shift 3
  (cd "$repo" && scripts/release.sh --checks-only "$@") >"$work/out" 2>&1 || status=$?
  if [[ "$outcome" == pass && "$status" -eq 0 ]] ||
    [[ "$outcome" == fail && "$status" -ne 0 ]] && grep -qF -- "$says" "$work/out"
  then
    passed=$((passed + 1))
    return
  fi
  failures=$((failures + 1))
  echo "FAILED: $description (expected to $outcome)"
  sed 's/^/    /' "$work/out"
}

# Versions and builds: the examples of AppVersionTests (C-DIST-01), the same rule on both sides.
for version in 1.0.0 0.1.0 1.0.0-beta.1 10.20.30-beta.12; do
  new_repo "$version" 1
  expect pass "version $version" ""
done
for version in 1.0 1.0.0.0 01.0.0 1.00.0 1.0.0-beta 1.0.0-beta.0 1.0.0-beta.01 1.0.0-rc.1 v1.0.0 "" "١.٠.٠"; do
  new_repo "$version" 1
  expect fail "version '$version'" "is not major.minor.patch"
done
for build in 1 42 1000; do
  new_repo 1.0.0 "$build"
  expect pass "build $build" ""
done
for build in 0 01 1.2 -1 +1 "" "١"; do
  new_repo 1.0.0 "$build"
  expect fail "build '$build'" "is not a positive integer"
done

# The tag being released.
new_repo 1.0.0-beta.1 1
expect fail "a tag that does not exist" "there is no tag v1.0.0-beta.1" --tag v1.0.0-beta.1
git -C "$repo" tag v1.0.0-beta.1
expect pass "the tag of the version at HEAD" "" --tag v1.0.0-beta.1
expect fail "a tag that is not v and the version" "is not v1.0.0-beta.1" --tag v1.0.0-beta.2
expect fail "a tag without a v" "is not v1.0.0-beta.1" --tag 1.0.0-beta.1
echo "change" >"$repo/notes.txt"
expect fail "changes in the working tree" "the working tree has changes" --tag v1.0.0-beta.1
commit "later"
expect fail "a tag that is not HEAD" "does not point at HEAD" --tag v1.0.0-beta.1

# The build against the builds of the releases before (C-DIST-01).
new_repo 1.0.0-beta.1 1
expect pass "the first release" ""
git -C "$repo" tag v1.0.0-beta.1
write_project 1.0.0-beta.2 1
commit "same build"
expect fail "a build equal to the last release's" "is not larger than 1, the build of v1.0.0-beta.1"
write_project 1.0.0-beta.2 2
commit "next build"
git -C "$repo" tag v1.0.0-beta.2
expect pass "a larger build" "" --tag v1.0.0-beta.2
write_project 1.0.0 9
commit "a build ahead"
git -C "$repo" tag v1.0.0
write_project 1.0.1 3
commit "a build behind"
expect fail "a build smaller than an earlier release's" "is not larger than 9, the build of v1.0.0"
write_project 1.0.1 10
commit "a build past them all"
expect pass "a build larger than every earlier release's" ""

if ((failures > 0)); then
  echo "test-release: $failures of $((failures + passed)) checks FAILED" >&2
  exit 1
fi
echo "test-release: all $passed checks of release.sh behave as expected"
