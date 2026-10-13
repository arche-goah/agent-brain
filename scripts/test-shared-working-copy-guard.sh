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

# $1 name, $2 sessions fixture ("cwd1;cwd2" or ""), $3 command, $4 block|allow, [$5 session id]
probe() {
  local out rc sid="${5:-sess-A}"
  out=$(printf '{"tool_name":"Bash","session_id":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$sid" "$REPO" "$3" \
        | SHARED_COPY_FIXTURE_SESSIONS="$2" CLAUDE_PROJECT_DIR="$TMP" node "$HELPER" 2>&1)
  rc=$?
  if printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    [ "$4" = "block" ] && ok "$1 blocks" || bad "$1 blocked what it should allow: $out"
  else
    [ "$4" = "allow" ] && ok "$1 allows (rc=$rc)" || bad "$1 did NOT block (rc=$rc): $out"
  fi
}

TWO="$REPO;$TMP/other"
ONE="$REPO"

echo "shared working copy, two sessions:"
probe "commit without pathspec"      "$TWO" "git -C $REPO commit -m \\\"x\\\""                    block
probe "commit -a"                    "$TWO" "git -C $REPO commit -a -m x"                         block
probe "commit --amend"               "$TWO" "git -C $REPO commit --amend --no-edit"              block
probe "commit by path"               "$TWO" "git -C $REPO commit a.txt -m x"                     allow
probe "commit by path after --"      "$TWO" "git -C $REPO commit -m x -- a.txt"                  allow
probe "commit -F file by path"       "$TWO" "git -C $REPO commit -F $TMP/msg a.txt"              allow
probe "add -A"                       "$TWO" "git -C $REPO add -A"                                 block
probe "add ."                        "$TWO" "git -C $REPO add ."                                  block
probe "add by path"                  "$TWO" "git -C $REPO add a.txt b.txt"                        allow
probe "stash"                        "$TWO" "git -C $REPO stash"                                  block
probe "reset --hard"                 "$TWO" "git -C $REPO reset --hard HEAD~1"                    block
probe "reset --soft"                 "$TWO" "git -C $REPO reset --soft HEAD~1"                    allow
probe "checkout branch"              "$TWO" "git -C $REPO checkout fixture-private"              block
probe "checkout -b"                  "$TWO" "git -C $REPO checkout -b new"                        block
probe "checkout -- path"             "$TWO" "git -C $REPO checkout -- a.txt"                      allow
probe "switch"                       "$TWO" "git -C $REPO switch main"                            block
probe "rebase"                       "$TWO" "git -C $REPO rebase origin/main"                     block
probe "merge"                        "$TWO" "git -C $REPO merge topic"                            block
probe "merge --ff-only"              "$TWO" "git -C $REPO merge --ff-only origin/main"            allow
probe "pull"                         "$TWO" "git -C $REPO pull"                                   block
probe "pull --rebase"                "$TWO" "git -C $REPO pull --rebase"                          block
probe "pull --ff-only"               "$TWO" "git -C $REPO pull --ff-only origin main"             allow
probe "push --force"                 "$TWO" "git -C $REPO push --force origin main"               block
probe "push --force-with-lease"      "$TWO" "git -C $REPO push --force-with-lease"                block
probe "push plain"                   "$TWO" "git -C $REPO push origin main"                       allow
probe "status / log / diff"          "$TWO" "git -C $REPO status --short; git -C $REPO log -1"    allow
probe "marker opens"                 "$TWO" "git -C $REPO commit -m x  # MECHANISM-OK: fixture"   allow
probe "mention in grep, not a call"  "$TWO" "grep -n 'git commit --amend' README.md"             allow
probe "private worktree, commit"     "$TWO" "git -C $PRIV commit -m x"                            allow
probe "private worktree, rebase"     "$TWO" "git -C $PRIV rebase origin/main"                     allow
probe "two sessions, not this repo"  "$TMP/x;$TMP/y" "git -C $REPO commit -m x"                   block
probe "count without cwd (windows)"  "-;-"  "git -C $REPO commit -m x"                            block

echo "single session:"
probe "commit without pathspec"      "$ONE" "git -C $REPO commit -m x"                            allow
probe "amend"                        "$ONE" "git -C $REPO commit --amend --no-edit"              allow
probe "rebase"                       "$ONE" "git -C $REPO rebase origin/main"                     allow
probe "no process list at all"       ""     "git -C $REPO commit -m x"                            allow

echo "open operation, owner check:"
GD="$(git -C "$REPO" rev-parse --git-dir)"
case "$GD" in /*) ;; *) GD="$REPO/$GD";; esac
# a rebase this session starts (single session lets it through) records the owner
probe "rebase start records owner"   "$ONE" "git -C $REPO rebase origin/main"                     allow sess-A
[ "$(cat "$GD/claude-op-owner" 2>/dev/null)" = "sess-A" ] && ok "owner file = sess-A" || bad "owner file not written: $(cat "$GD/claude-op-owner" 2>/dev/null)"
mkdir -p "$GD/rebase-merge"
probe "foreign rebase open: add"     "$TWO" "git -C $REPO add a.txt"                              block sess-B
probe "foreign rebase open: commit"  "$TWO" "git -C $REPO commit a.txt -m x"                      block sess-B
probe "foreign rebase open: continue" "$TWO" "git -C $REPO rebase --continue"                     block sess-B
probe "foreign rebase open: status"  "$TWO" "git -C $REPO status"                                 allow sess-B
probe "own rebase open: continue"    "$TWO" "git -C $REPO rebase --continue"                      allow sess-A
probe "own rebase open: add"         "$TWO" "git -C $REPO add a.txt"                              allow sess-A
probe "foreign rebase, marker"       "$TWO" "git -C $REPO rebase --abort  # MECHANISM-OK: fixture" allow sess-B
probe "foreign rebase, one session"  "$ONE" "git -C $REPO rebase --continue"                      allow sess-B
rmdir "$GD/rebase-merge"
probe "no operation: write passes"   "$TWO" "git -C $REPO add a.txt"                              allow sess-B
[ -e "$GD/claude-op-owner" ] && bad "owner file not cleared after the operation ended" || ok "owner file cleared"

echo "fail-open:"
probe "not a git repo"               "$TWO" "git -C $TMP/nowhere commit -m x"                     allow
probe "broken json"                  "$TWO" ""                                                     allow

exit $fail
