#!/bin/bash
# Makes git run the hooks in scripts/git-hooks for this clone and its worktrees. Run it once
# after cloning; the hooks themselves change with the repository.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
git -C "$repo_root" config core.hooksPath scripts/git-hooks
echo "git runs the hooks in scripts/git-hooks"
