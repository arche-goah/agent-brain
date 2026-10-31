#!/usr/bin/env bash
# install-git-hooks.sh — point core.hooksPath at the core's hooks (pre-commit checks, shared-memory
# state trailer). Default: the repo of the working directory only (the brain); --global: every repo
# of this user. Idempotent.
#
# Usage: bash core/scripts/install-git-hooks.sh [--global] [--check]
#   (none)    set it in the brain's own .git/config
#   --global  set it in the user's git config, so other repos (suites, the shared memory) run the
#             hooks too. Opt-in: it overrides the hooks of every repo of this user, including
#             another tool's (husky, pre-commit). Fresh-brain trial 2026-10-21: a repo-local
#             pre-commit hook in an unrelated repo was skipped; the core owners decided on local.
#   --check   say whether the hooks are installed, locally or globally; exit 1 if not
# A hooksPath that points somewhere else is reported, never overwritten without being named:
# an instance may carry its own hooks dir on purpose.
set -u
hooks=$(cd "$(dirname "${BASH_SOURCE[0]}")/../helpers/git-hooks" && pwd)
# Git Bash: pwd gives /c/..., git config may hold C:/... for the same folder — compare (and
# write) the mixed long form (8.3 names expanded); everywhere else cygpath does not exist and the path stays.
norm() { [ -z "$1" ] || cygpath -ml "$1" 2>/dev/null || printf '%s' "$1"; }
hooks=$(norm "$hooks")
scope=--local
[ "${1:-}" = "--global" ] && { scope=--global; shift; }
glob=$(norm "$(git config --global --get core.hooksPath 2>/dev/null || true)")
loc=$(norm "$(git config --local --get core.hooksPath 2>/dev/null || true)")
if [ "${1:-}" = "--check" ]; then
  # A local value wins over the global one in git itself, so it decides here too.
  if [ "$loc" = "$hooks" ] || { [ -z "$loc" ] && [ "$glob" = "$hooks" ]; }; then
    echo "git hooks: core hooks installed"; exit 0
  fi
  echo "git hooks: core.hooksPath is '${loc:-${glob:-unset}}', not the core's hooks — run: bash core/scripts/install-git-hooks.sh"
  exit 1
fi
if [ "$scope" = --local ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "install-git-hooks: not inside a git repo — run it from the brain's root, or pass --global"
  exit 1
fi
if [ "$scope" = --global ]; then cur=$glob; else cur=$loc; fi
if [ -n "$cur" ] && [ "$cur" != "$hooks" ]; then
  echo "install-git-hooks: replacing ${scope#--} core.hooksPath '$cur'"
fi
git config "$scope" core.hooksPath "$hooks"
chmod +x "$hooks"/* 2>/dev/null || true
echo "install-git-hooks: ${scope#--} core.hooksPath = $hooks"
