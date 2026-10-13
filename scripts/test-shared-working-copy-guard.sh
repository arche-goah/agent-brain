#!/usr/bin/env bash
# covers: shared-working-copy-guard
#
# Effect proof for helpers/shared-working-copy-guard.cjs in BOTH directions: what it
# must refuse in a shared working copy, what it must wave through (by-path forms, a
# private worktree, a single session, the marker), and the owner check on an open
# rebase. The process list is replaced by the fixture seam SHARED_COPY_FIXTURE_SESSIONS
# (one entry per session), so the logic runs the same on every platform.
#
# Usage: bash scripts/test-shared-working-copy-guard.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
HELPER=$(resolve helpers/shared-working-copy-guard.cjs) || { echo "  --  helper not in this layout"; exit 0; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# OS-3: every path that reaches node as DATA (the JSON command and cwd, CLAUDE_PROJECT_DIR)
# is stated natively — Git Bash `/tmp/...` does not resolve for a native process, and the
# guard would skip the call (fail-open) exactly where a must-block case has to block.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
REPO="$TMP/shared"
git init -q "$REPO"
git -C "$REPO" -c user.name=fixture -c user.email=f@x config commit.gpgsign false
printf 'a\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" -c user.name=fixture -c user.email=f@x commit -q -m init
mkdir -p "$TMP/.claude-state"

# A private worktree: the scratchpad shape the harness uses (claude-<uid>/<project>/<session-uuid>/…)
PRIV="$TMP/claude-501/-proj/0f0e0d0c-0b0a-4908-8706-050403020100/scratchpad/wt"
mkdir -p "$(dirname "$PRIV")"
git -C "$REPO" worktree add -q "$PRIV" -b fixture-private
# The Windows shape: `%TEMP%\claude\<project>\<session-uuid>\…`, no uid (measured 2026-10-13).
PRIVW="$TMP/claude/-proj/0f0e0d0c-0b0a-4908-8706-050403020101/scratchpad/wt"
mkdir -p "$(dirname "$PRIVW")"
git -C "$REPO" worktree add -q "$PRIVW" -b fixture-private-win
# Negative control: a look-alike directory name is no scratchpad.
LOOK="$TMP/claudette/-proj/0f0e0d0c-0b0a-4908-8706-050403020102/scratchpad/wt"
mkdir -p "$(dirname "$LOOK")"
git -C "$REPO" worktree add -q "$LOOK" -b fixture-lookalike
TMP_N=$(native "$TMP"); REPO_N=$(native "$REPO"); PRIV_N=$(native "$PRIV")
PRIVW_N=$(native "$PRIVW"); LOOK_N=$(native "$LOOK")

# $1 name, $2 sessions fixture ("cwd1;cwd2" or ""), $3 command, $4 block|allow, [$5 session id]
probe() {
  local out rc sid="${5:-sess-A}"
  out=$(printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$sid" "$REPO_N" "$3" \
        | SHARED_COPY_FIXTURE_SESSIONS="$2" CLAUDE_PROJECT_DIR="$TMP_N" node "$HELPER" 2>&1)
  rc=$?
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    [ "$4" = "block" ] && ok "$1 blocks" || bad "$1 blocked what it should allow: $out"
  else
    [ "$4" = "allow" ] && ok "$1 allows (rc=$rc)" || bad "$1 did NOT block (rc=$rc): $out"
  fi
}

TWO="$REPO_N;$TMP_N/other"
ONE="$REPO_N"

echo "shared working copy, two sessions:"
probe "commit without pathspec"      "$TWO" "git -C $REPO_N commit -m \\\"x\\\""                    block
probe "commit -a"                    "$TWO" "git -C $REPO_N commit -a -m x"                         block
probe "commit --amend"               "$TWO" "git -C $REPO_N commit --amend --no-edit"              block
probe "commit by path"               "$TWO" "git -C $REPO_N commit a.txt -m x"                     allow
probe "commit by path after --"      "$TWO" "git -C $REPO_N commit -m x -- a.txt"                  allow
probe "commit -F file by path"       "$TWO" "git -C $REPO_N commit -F $TMP_N/msg a.txt"              allow
probe "add -A"                       "$TWO" "git -C $REPO_N add -A"                                 block
probe "add ."                        "$TWO" "git -C $REPO_N add ."                                  block
probe "add by path"                  "$TWO" "git -C $REPO_N add a.txt b.txt"                        allow
probe "stash"                        "$TWO" "git -C $REPO_N stash"                                  block
probe "reset --hard"                 "$TWO" "git -C $REPO_N reset --hard HEAD~1"                    block
probe "reset --soft"                 "$TWO" "git -C $REPO_N reset --soft HEAD~1"                    allow
probe "checkout branch"              "$TWO" "git -C $REPO_N checkout fixture-private"              block
probe "checkout -b"                  "$TWO" "git -C $REPO_N checkout -b new"                        block
probe "checkout -- path"             "$TWO" "git -C $REPO_N checkout -- a.txt"                      allow
probe "switch"                       "$TWO" "git -C $REPO_N switch main"                            block
probe "rebase"                       "$TWO" "git -C $REPO_N rebase origin/main"                     block
probe "merge"                        "$TWO" "git -C $REPO_N merge topic"                            block
probe "merge --ff-only"              "$TWO" "git -C $REPO_N merge --ff-only origin/main"            allow
probe "pull"                         "$TWO" "git -C $REPO_N pull"                                   block
probe "pull --rebase"                "$TWO" "git -C $REPO_N pull --rebase"                          block
probe "pull --ff-only"               "$TWO" "git -C $REPO_N pull --ff-only origin main"             allow
probe "push --force"                 "$TWO" "git -C $REPO_N push --force origin main"               block
probe "push --force-with-lease"      "$TWO" "git -C $REPO_N push --force-with-lease"                block
probe "push plain"                   "$TWO" "git -C $REPO_N push origin main"                       allow
probe "status / log / diff"          "$TWO" "git -C $REPO_N status --short; git -C $REPO_N log -1"    allow
probe "marker opens"                 "$TWO" "git -C $REPO_N commit -m x  # MECHANISM-OK: fixture"   allow
probe "mention in grep, not a call"  "$TWO" "grep -n 'git commit --amend' README.md"             allow
probe "private worktree, commit"     "$TWO" "git -C $PRIV_N commit -m x"                            allow
probe "private worktree, rebase"     "$TWO" "git -C $PRIV_N rebase origin/main"                     allow
probe "private worktree, windows shape" "$TWO" "git -C $PRIVW_N commit -m x"                        allow
probe "look-alike dir is no scratchpad" "$TWO" "git -C $LOOK_N commit -m x"                         block
probe "two sessions, not this repo"  "$TMP_N/x;$TMP_N/y" "git -C $REPO_N commit -m x"                   block
probe "count without cwd (windows)"  "-;-"  "git -C $REPO_N commit -m x"                            block

echo "single session:"
probe "commit without pathspec"      "$ONE" "git -C $REPO_N commit -m x"                            allow
probe "amend"                        "$ONE" "git -C $REPO_N commit --amend --no-edit"              allow
probe "rebase"                       "$ONE" "git -C $REPO_N rebase origin/main"                     allow
probe "no process list at all"       ""     "git -C $REPO_N commit -m x"                            allow

echo "open operation, owner check:"
GD="$(git -C "$REPO" rev-parse --git-dir)"
case "$GD" in /*) ;; *) GD="$REPO/$GD";; esac
# a rebase this session starts (single session lets it through) records the owner
probe "rebase start records owner"   "$ONE" "git -C $REPO_N rebase origin/main"                     allow sess-A
[ "$(cat "$GD/claude-op-owner" 2>/dev/null)" = "sess-A" ] && ok "owner file = sess-A" || bad "owner file not written: $(cat "$GD/claude-op-owner" 2>/dev/null)"
mkdir -p "$GD/rebase-merge"
probe "foreign rebase open: add"     "$TWO" "git -C $REPO_N add a.txt"                              block sess-B
probe "foreign rebase open: commit"  "$TWO" "git -C $REPO_N commit a.txt -m x"                      block sess-B
probe "foreign rebase open: continue" "$TWO" "git -C $REPO_N rebase --continue"                     block sess-B
probe "foreign rebase open: status"  "$TWO" "git -C $REPO_N status"                                 allow sess-B
probe "own rebase open: continue"    "$TWO" "git -C $REPO_N rebase --continue"                      allow sess-A
probe "own rebase open: add"         "$TWO" "git -C $REPO_N add a.txt"                              allow sess-A
probe "foreign rebase, marker"       "$TWO" "git -C $REPO_N rebase --abort  # MECHANISM-OK: fixture" allow sess-B
probe "foreign rebase, one session"  "$ONE" "git -C $REPO_N rebase --continue"                      allow sess-B
rmdir "$GD/rebase-merge"
probe "no operation: write passes"   "$TWO" "git -C $REPO_N add a.txt"                              allow sess-B
[ -e "$GD/claude-op-owner" ] && bad "owner file not cleared after the operation ended" || ok "owner file cleared"

echo "fail-open:"
probe "not a git repo"               "$TWO" "git -C $TMP_N/nowhere commit -m x"                     allow
probe "broken json"                  "$TWO" ""                                                     allow

exit $fail
