#!/usr/bin/env bash
# install-git-hooks.sh — point git's global core.hooksPath at the core's hooks (pre-commit checks,
# shared-memory state trailer). One path for every brain; idempotent.
#
# Usage: bash core/scripts/install-git-hooks.sh [--check]
#   --check   say whether the hooks are installed; exit 1 if not (session start, preflight)
# A hooksPath that points somewhere else is reported, never overwritten without being named:
# an instance may carry its own hooks dir on purpose.
set -u
hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers/git-hooks" && pwd)
cur=$(git config --global --get core.hooksPath 2>/dev/null || true)
if [ "${1:-}" = "--check" ]; then
  if [ "$cur" = "$hooks" ]; then echo "git hooks: core hooks installed"; exit 0; fi
  echo "git hooks: global core.hooksPath is '${cur:-unset}', not the core's hooks — run: bash core/scripts/install-git-hooks.sh"
  exit 1
fi
if [ -n "$cur" ] && [ "$cur" != "$hooks" ]; then
  echo "install-git-hooks: replacing global core.hooksPath '$cur'"
fi
git config --global core.hooksPath "$hooks"
chmod +x "$hooks"/* 2>/dev/null || true
echo "install-git-hooks: core.hooksPath = $hooks"
