#!/usr/bin/env bash
# Fixture for scripts/install-git-hooks.sh, both directions: the default writes the hooks path into
# the brain's own config and leaves the user's config alone; --global writes the user's config;
# --check accepts either, and refuses an unset path and a local path that points elsewhere (git
# itself lets the local value win). Sandbox only: GIT_CONFIG_GLOBAL is a temp file.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/install-git-hooks.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
# GIT_CONFIG_GLOBAL is a path handed to the native git as DATA in an env var: native() (OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export GIT_CONFIG_GLOBAL="$(native "$TMP/gitconfig")" GIT_CONFIG_NOSYSTEM=1
: > "$TMP/gitconfig"
B="$TMP/brain"; O="$TMP/other"
git init -q "$B"; git init -q "$O"
glob() { git config --global --get core.hooksPath; }
loc() { git -C "$1" config --local --get core.hooksPath; }

( cd "$B" && bash "$S" --check >/dev/null ) && fail "--check passes with no hooks path" || pass "--check refuses an unset hooks path"

out=$(cd "$B" && bash "$S")
[ -n "$(loc "$B")" ] && pass "default writes the brain's own config" || fail "no local hooks path: $out"
[ -z "$(glob)" ] && pass "default leaves the user's config alone" || fail "default wrote the global config: $(glob)"
( cd "$B" && bash "$S" --check >/dev/null ) && pass "--check accepts a local hooks path" || fail "--check refuses the local path"
( cd "$O" && bash "$S" --check >/dev/null ) && fail "--check passes in a repo without hooks" || pass "another repo stays without the hooks"

git -C "$B" config --local core.hooksPath "$TMP/elsewhere"
( cd "$B" && bash "$S" --check >/dev/null ) && fail "--check passes a local path that points elsewhere" \
  || pass "--check refuses a local path that points elsewhere"
git -C "$B" config --local --unset core.hooksPath

out=$(cd "$O" && bash "$S" --global)
[ -n "$(glob)" ] && pass "--global writes the user's config" || fail "no global hooks path: $out"
[ -z "$(loc "$O")" ] && pass "--global leaves the repo's config alone" || fail "--global wrote a local path"
( cd "$B" && bash "$S" --check >/dev/null ) && pass "--check accepts a global hooks path" || fail "--check refuses the global path"

out=$(cd "$TMP" && bash "$S" 2>&1); rc=$?
[ "$rc" = 1 ] && pass "default outside a repo refuses and names --global" || fail "outside a repo: rc=$rc $out"

if [ "$FAIL" = 0 ]; then echo "test-install-git-hooks: all checks passed"; else echo "test-install-git-hooks: FAILED"; exit 1; fi
