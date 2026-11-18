#!/usr/bin/env bash
# test-pre-commit-hook-env.sh - the pre-commit hook's lint step runs without git's hook variables: a fixture that commits
# into its own temp repo must not write into the repository being committed (Windows instance, 2026-11-18: three
# foreign commits, MERGE_HEAD lost, core.bare = true in the committing repo's config). The measured shape is a LINKED
# worktree: git sets GIT_DIR for its hooks, and GIT_DIR wins over `git -C <dir>`.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK:-$HERE/../helpers/git-hooks/pre-commit}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }   # OS-3
fail=0; ok() { echo "  OK   $1"; }; bad() { echo "  FAIL $1"; fail=1; }
g() { git -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$T/hooks/helpers/git-hooks"; cp "$HOOK" "$T/hooks/helpers/git-hooks/pre-commit"; chmod +x "$T/hooks/helpers/git-hooks/pre-commit"
R="$T/repo"; mkdir -p "$R/scripts" "$R/.github/workflows"
g init -q "$R"; : > "$R/.github/workflows/ci.yml"
# the "lint": a fixture that builds its own repo and commits there, as the real suites do. Its path is written in, not
# passed by the environment; its own commit runs no hooks (no recursion into this hook whatever the result).
IN="$(native "$T/inner")"
printf '%s\n' "git init -q \"$IN\"" \
  "git -C \"$IN\" -c core.hooksPath=/nonexistent -c user.email=t@t -c user.name=t commit -q --allow-empty -m inner" \
  "git init -q --bare \"$IN/bare.git\"" "exit 0" > "$R/scripts/ci-lint-local.sh"
g -C "$R" add -A; g -C "$R" commit -q -m base
WT="$T/wt"; git -C "$R" worktree add -q -b side "$WT" >/dev/null 2>&1
: > "$WT/x"; g -C "$WT" add x
g -C "$WT" -c core.hooksPath="$(native "$T/hooks/helpers/git-hooks")" commit -q -m outer >/dev/null 2>&1
n=$(git -C "$WT" rev-list --count base..HEAD 2>/dev/null || git -C "$WT" rev-list --count HEAD~1..HEAD)
msg=$(git -C "$WT" log -1 --format=%s 2>/dev/null)
bare=$(git -C "$R" config --get core.bare)
[ "$msg" = outer ] && ok "the committing worktree's HEAD is its own commit ('$msg')" || bad "foreign commit on the committing branch: HEAD '$msg'"
[ "$bare" = false ] && ok "core.bare of the committing repo stays false" || bad "core.bare is '$bare'"
[ $fail -eq 0 ] && echo "pre-commit-hook-env: all cases pass" || { echo "pre-commit-hook-env: FAILURES"; exit 1; }
