#!/usr/bin/env bash
# covers: core-branch
# Fixture for scripts/core-branch.sh: a fresh clone + branch with the public identity, a stacked base, and the refusals
# (existing folder, missing identity, bad repo). Local bare repo only (CORE_BRANCH_URL), no network, no gh.
# Usage: bash scripts/test-core-branch.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/core-branch.sh"
. "$(dirname "$0")/git-sandbox.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

git init -q --bare -b main "$T/up.git"
git clone -q "$T/up.git" "$T/seed" 2>/dev/null
git -C "$T/seed" commit -q --allow-empty -m base
git -C "$T/seed" push -q origin HEAD:main
git -C "$T/seed" checkout -q -b fix/x
git -C "$T/seed" commit -q --allow-empty -m stacked
git -C "$T/seed" push -q origin fix/x

export CORE_BRANCH_URL="$T/up.git" CORE_BRANCH_NAME=bot CORE_BRANCH_EMAIL=1+bot@users.noreply.github.com
out="$(bash "$S" feat/new --repo o/core --into "$T/w" 2>&1)"; rc=$?
dir="$(printf '%s\n' "$out" | tail -1)"
[ "$rc" = 0 ] && [ -d "$dir/.git" ] && ok "fresh clone created (rc 0, path on the last line)" || bad "create: rc=$rc '$out'"
[ "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)" = feat/new ] && ok "on the new branch" || bad "branch"
[ "$(git -C "$dir" config --local user.email)" = 1+bot@users.noreply.github.com ] && ok "public identity set locally" || bad "identity"
case "$dir" in */w/core-feat-new) ok "folder named repo-branch";; *) bad "folder name: $dir";; esac

out="$(bash "$S" feat/new --repo o/core --into "$T/w" 2>&1)"; rc=$?
[ "$rc" = 2 ] && case "$out" in *exists*) true;; *) false;; esac && ok "an existing folder is refused, never switched" || bad "existing: rc=$rc '$out'"

out="$(bash "$S" feat/stack --repo o/core --base fix/x --into "$T/w" 2>&1)"; rc=$?
dir2="$(printf '%s\n' "$out" | tail -1)"
[ "$rc" = 0 ] && [ "$(git -C "$dir2" log -1 --format=%s 2>/dev/null)" = stacked ] && ok "a stacked base starts from that branch" || bad "stacked: rc=$rc '$out'"

out="$(bash "$S" feat/y --repo nonsense --into "$T/w" 2>&1)"; rc=$?
[ "$rc" = 2 ] && ok "a repo without owner/name is refused" || bad "bad repo: rc=$rc"

out="$(CORE_BRANCH_NAME= CORE_BRANCH_EMAIL= PATH="/usr/bin:/bin" bash "$S" feat/z --repo o/core --into "$T/w" 2>&1)"; rc=$?
[ "$rc" = 2 ] && [ ! -e "$T/w/core-feat-z" ] && ok "no identity (no env, no gh) is refused before any clone" || bad "identity missing: rc=$rc '$out'"

[ "$fail" -eq 0 ] && echo "core-branch: all checks passed" || echo "core-branch: FAILED"
exit "$fail"
