#!/usr/bin/env bash
# Fixture for helpers/git-hooks/pre-push: real pushes into bare remotes with core.hooksPath set to a
# copy of the hook inside a sandbox brain (<brain>/core/helpers/git-hooks), the way a brain mounts it.
# Blocks: delete, rewrite (force, a moved tag), main of a repo that is neither the brain, nor the
# shared memory, nor listed; a new branch carrying commits of a local main that is ahead of the
# remote main (named in the block). Passes: fast-forward, new branch, new tag, main of the brain, of the
# shared memory, of a listed repo and of a remote under the system temp, the PUSH_GUARD_OK marker. Negative control: without the hook
# the rewrite goes through. Sandbox only (GIT_CONFIG_GLOBAL), nothing reaches a real remote.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d)
# The hook frees main for a remote under the system temp (a fixture's bare repo), so the remotes that
# must stay GUARDED live outside it. Which root is "the temp" is named for the hook (PUSH_TEMP_ROOTS = $TMP only):
# $HOME is no safe outside - portability-smoke runs every suite with HOME under mktemp (merge train 2.1.6).
export PUSH_TEMP_ROOTS="$TMP"
REM=$(mktemp -d)   # a sibling of $TMP, not under it: guarded
trap 'rm -rf "$TMP" "$REM"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

B="$TMP/brain"; HOOKS="$B/core/helpers/git-hooks"; mkdir -p "$HOOKS" "$B/.claude/rules"
cp "$HERE/../helpers/git-hooks/pre-push" "$HOOKS/pre-push"; chmod +x "$HOOKS/pre-push"
export GIT_CONFIG_GLOBAL="$(native "$TMP/gitconfig")" GIT_CONFIG_NOSYSTEM=1
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[init]\n\tdefaultBranch = main\n[core]\n\thooksPath = %s\n' \
  "$(native "$HOOKS")" > "$GIT_CONFIG_GLOBAL"
LIST="$B/.claude/rules/push-targets.json"

repo() { # $1 name -> bare remote $REM/o/$1.git (outside the temp roots), clone at $2
  git init -q --bare "$REM/o/$1.git"; git clone -q "$REM/o/$1.git" "$2" 2>/dev/null
}
mkdir -p "$REM/o"
W="$TMP/work"; repo widget "$W"
c() { echo "$2" > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm "$2"; }
try() { # $1 label  $2 expect ok|blocked  $3 repo  $4.. push args
  local label=$1 want=$2 r=$3; shift 3
  if git -C "$r" push -q origin "$@" 2>"$TMP/err"; then got=ok; else got=blocked; fi
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label (expected $want, got $got: $(tr '\n' ' ' < "$TMP/err"))"; fi
}

# --- main: only the brain, the shared memory and listed repos -----------------------------------
c "$W" one; try "main of an unlisted repo is blocked (no list)" blocked "$W" main
printf '{"main_ok": ["o/widget"]}\n' > "$LIST"
try "main of a listed repo passes" ok "$W" main
c "$W" two; try "fast-forward of a listed main passes" ok "$W" main
printf '{"main_ok": ["o/other"]}\n' > "$LIST"
c "$W" three; try "main of a repo the list does not name is blocked" blocked "$W" main
# --- a new branch says what it carries (2026-11-12: six commits of a local main rode along) -----
try "a new branch from a main that is ahead is blocked" blocked "$W" main:refs/heads/feat/y
grep -q 'three' "$TMP/err" && pass "  ... and the block names the riding commit" || fail "  ... riding commit not named: $(tr '\n' ' ' < "$TMP/err")"
# Windows review 2026-11-17: a backslash in a riding subject is text - `\c` cut the message before `way out:`
c "$W" 'path C:\core\x'
try "a riding subject with a backslash is blocked" blocked "$W" main:refs/heads/feat/bs
grep -aq 'way out:' "$TMP/err" && grep -aqF 'C:\core\x' "$TMP/err" && pass "  ... and the block keeps the subject and its way out" \
  || fail "  ... message cut by the backslash: $(tr '\n' ' ' < "$TMP/err")"
PUSH_GUARD_OK="fixture" try "the marker lets that new branch through" ok "$W" main:refs/heads/feat/y
git -C "$W" checkout -qb feat/own origin/main; c "$W" own-1
try "a new branch with only its own commit passes" ok "$W" feat/own
git -C "$W" checkout -qb feat/two origin/main; c "$W" two-1; c "$W" two-2
try "a new branch with two own commits passes" ok "$W" feat/two
grep -q 'sends 2 commits' "$TMP/err" && grep -q 'two-1' "$TMP/err" && pass "  ... and lists what it sends" \
  || fail "  ... list missing: $(tr '\n' ' ' < "$TMP/err")"
git -C "$W" checkout -qb feat/one origin/main; c "$W" one-1
try "a new branch with one own commit passes" ok "$W" feat/one
grep -q 'sends' "$TMP/err" && fail "  ... a one-commit branch printed a list" || pass "  ... and prints no list"
git -C "$W" checkout -q main; git -C "$W" reset -q --hard origin/main
rm -f "$LIST"
git -C "$B" init -q; git -C "$B" remote add origin "$REM/o/brain.git"; git init -q --bare "$REM/o/brain.git"
c "$B" b1; try "main of the brain itself passes" ok "$B" main
S="$TMP/shared"; repo shared "$S"; echo '{}' > "$S/parties.json"; git -C "$S" add parties.json; c "$S" s1
try "main of the shared memory (parties.json) passes" ok "$S" main

# --- a fixture's throwaway remote under the system temp: main is free, rewrite and delete are not ----
F="$TMP/fixture"; git init -q --bare "$TMP/f.git"; git clone -q "$TMP/f.git" "$F" 2>/dev/null
c "$F" f1; try "main of a remote under the system temp passes" ok "$F" main
git -C "$F" remote set-url origin "file://$(native "$TMP/f.git")"
c "$F" f2; try "the same remote as a file:// URL passes" ok "$F" main
n=$(native "$TMP/f.git"); git -C "$F" remote set-url origin "file:///${n#/}"   # Windows: file:///C:/...
c "$F" f3; try "the same remote as a file:/// URL passes" ok "$F" main
git -C "$F" commit -q --amend -m f2-rewritten
try "a rewrite of a temp remote's main is still blocked" blocked "$F" +main
try "a side branch on a temp remote passes" ok "$F" HEAD:refs/heads/side
try "deleting a branch on a temp remote is still blocked" blocked "$F" :side
git -C "$F" remote set-url origin "$REM/o/widget.git"
try "main of a remote outside the temp roots stays blocked" blocked "$F" HEAD:refs/heads/main

# --- delete and rewrite: every repo ---------------------------------------------------------------
git -C "$W" checkout -qb feat/x; c "$W" four
try "a new branch passes" ok "$W" feat/x
git -C "$W" reset -q --hard HEAD~1; c "$W" four-b
try "a rewrite (force) is blocked" blocked "$W" +feat/x
PUSH_GUARD_OK="fixture" try "the marker lets one rewrite through" ok "$W" +feat/x
try "deleting a remote branch is blocked" blocked "$W" :feat/x
git -C "$W" tag v1; try "a new tag passes" ok "$W" v1
git -C "$W" tag -f v1 HEAD~1 >/dev/null; try "moving a published tag is blocked" blocked "$W" +v1
git -C "$B" reset -q --hard HEAD 2>/dev/null; git -C "$B" commit -q --amend -m b1-rewritten
try "a rewrite of the brain's main is blocked too" blocked "$B" +main

# NEGATIVE CONTROL: without the hook the same rewrite goes through, so the blocks above are the hook's.
git -C "$W" reset -q --hard HEAD~1; c "$W" four-c
if git -C "$W" -c core.hooksPath=/dev/null push -q origin +feat/x 2>/dev/null; then
  pass "negative control: without the hook the rewrite passes"
else
  fail "negative control: the push failed without the hook too"
fi

[ $FAIL -eq 0 ] && echo "test-pre-push: all passed" || echo "test-pre-push: FAILED"
exit $FAIL
