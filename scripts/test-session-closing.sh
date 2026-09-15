#!/usr/bin/env bash
# Fixture for helpers/session-closing.sh — its first. Every property has one input that
# MUST fire it and one that must stay silent.
#
# The property worth proving is the shared-memory write gate (2026-09-13): an entry that
# was written but never left the machine must produce a FAIL line at close, and a clean
# shared repo must produce none. Measured 2026-08-17: three merged PRs corrected a claim
# the shared record still stated as open — the entry existed in someone's intention, not
# in the repo the others read. "Committed but not pushed" is that failure with better
# intentions, and until today nothing mechanical said so.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOSING="$HERE/../helpers/session-closing.sh"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2]" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2]" ;; *) ok "$1" ;; esac; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git_q() { git -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

# A brain repo the hook runs in, and a shared repo with a real remote — "unpushed" is
# only computable against a remote, and a repo with none reports every commit as unpushed.
BRAIN="$TMP/brain"; mkdir -p "$BRAIN/.claude" "$BRAIN/docs/maintenance"
git_q -C "$BRAIN" init -q; : > "$BRAIN/README.md"; git_q -C "$BRAIN" add -A; git_q -C "$BRAIN" commit -qm brain
SHARED="$TMP/shared"; REMOTE="$TMP/remote.git"
git_q init -q --bare "$REMOTE"
git_q -C "$TMP" clone -q "$REMOTE" shared
: > "$SHARED/seed.md"; git_q -C "$SHARED" add -A; git_q -C "$SHARED" commit -qm seed; git_q -C "$SHARED" push -q -u origin HEAD:main
git_q -C "$SHARED" branch -M main

run_close() { (cd "$BRAIN" && CLAUDE_PROJECT_DIR="$BRAIN" SHARED_MEMORY_REPO="$SHARED" bash "$CLOSING" 2>&1 </dev/null); }

echo "negative control: shared repo clean and pushed"
out="$(run_close)"
hasnt "no FAIL line on a clean shared repo" "FAIL shared-memory" "$out"
has   "the session-log line still records the shared state" "shared=dirty:0,unpushed:0" "$(tail -1 "$BRAIN/docs/maintenance/session-log.md")"
hasnt "HANDOFF carries no delivery warning" "NOT delivered" "$(cat "$BRAIN/.claude/HANDOFF.md")"

echo "positive control 1: an entry edited but not committed"
echo "draft" > "$SHARED/draft.md"
out="$(run_close)"
has "FAIL line names the uncommitted file count" "1 uncommitted file(s)" "$out"
has "HANDOFF says it was not delivered" "NOT delivered" "$(cat "$BRAIN/.claude/HANDOFF.md")"

echo "positive control 2: an entry committed but not pushed"
git_q -C "$SHARED" add -A; git_q -C "$SHARED" commit -qm "local only"
out="$(run_close)"
has "FAIL line names the unpushed commit count" "1 unpushed commit(s)" "$out"
has "and the session-log line carries it" "unpushed:1" "$(tail -1 "$BRAIN/docs/maintenance/session-log.md")"

echo "negative control 2: after the push, silence again"
git_q -C "$SHARED" push -q origin HEAD:main
out="$(run_close)"
hasnt "no FAIL line once pushed" "FAIL shared-memory" "$out"

echo "no shared repo at all: the hook must not invent one"
out="$(cd "$BRAIN" && CLAUDE_PROJECT_DIR="$BRAIN" SHARED_MEMORY_REPO="$TMP/nowhere" bash "$CLOSING" 2>&1)"
hasnt "no FAIL line without a shared repo" "FAIL shared-memory" "$out"
hasnt "and no shared field in the log line" "shared=" "$(tail -1 "$BRAIN/docs/maintenance/session-log.md")"

# --- invariant (2026-09-13): after the close commit no hook touches a tracked file -------
# Measured on two machines: the hook's line after the commit carried `last:`/`uncommitted=`
# and so never matched the skill's line, and the tree was dirty at every session start.
# A second throwaway brain with the template's ignores, so "clean" means what git means.
echo "post-commit invariant: the template ignores what the hook writes after the commit"
has "bootstrap .gitignore excludes .claude/HANDOFF.md" ".claude/HANDOFF.md" "$(sed -n '/cat > .gitignore/,/^EOF/p' "$HERE/bootstrap-brain.sh")"
has "bootstrap .gitignore excludes .claude-state/" ".claude-state/" "$(sed -n '/cat > .gitignore/,/^EOF/p' "$HERE/bootstrap-brain.sh")"

B2="$TMP/brain2"; mkdir -p "$B2/.claude" "$B2/docs/maintenance"
printf '.claude-state/\n.claude/HANDOFF.md\n' > "$B2/.gitignore"
: > "$B2/docs/maintenance/session-log.md"
git_q -C "$B2" init -q; git_q -C "$B2" add -A; git_q -C "$B2" commit -qm brain
LOG2="$B2/docs/maintenance/session-log.md"
# the skill step (before the commit), then the hook run with the harness' stdin JSON
pre()  { (cd "$B2" && CLAUDE_PROJECT_DIR="$B2" SHARED_MEMORY_REPO="$TMP/nowhere" bash "$CLOSING" --pre-commit "$@" 2>&1 </dev/null); }
hook() { (cd "$B2" && printf '{"session_id":"%s","hook_event_name":"SessionEnd"}' "$1" | CLAUDE_PROJECT_DIR="$B2" SHARED_MEMORY_REPO="$TMP/nowhere" bash "$CLOSING" 2>&1); }
lines() { wc -l < "$LOG2" | tr -d ' '; }

echo "skill step: the line has no post-commit state, then the close commit carries it"
pre --session S1
has   "pre-commit line is marked close" "| close" "$(tail -1 "$LOG2")"
hasnt "pre-commit line carries no last:" "last:" "$(tail -1 "$LOG2")"
hasnt "pre-commit line carries no uncommitted=" "uncommitted=" "$(tail -1 "$LOG2")"
[ -f "$B2/.claude-state/session-close.stamp" ] && ok "stamp written" || bad "stamp written" "missing"
[ "$(git -C "$B2" status --porcelain | wc -l | tr -d ' ')" -eq 1 ] && ok "only the log is dirty before the commit" || bad "only the log is dirty before the commit" "$(git -C "$B2" status --porcelain)"
git_q -C "$B2" add -A; git_q -C "$B2" commit -qm "close"

echo "hook after the close commit: git status stays EMPTY"
n=$(lines); hook S1 >/dev/null
[ -z "$(git -C "$B2" status --porcelain)" ] && ok "git status --porcelain is empty after the hook" || bad "git status --porcelain is empty after the hook" "$(git -C "$B2" status --porcelain)"
[ "$(lines)" -eq "$n" ] && ok "log line count unchanged" || bad "log line count unchanged" "$n -> $(lines)"
[ -f "$B2/.claude-state/session-close.stamp" ] && bad "stamp consumed" "still there" || ok "stamp consumed"
[ -f "$B2/.claude/HANDOFF.md" ] && ok "HANDOFF still written (ignored, not tracked)" || bad "HANDOFF still written" "missing"

echo "hard-kill fallback: no skill step, the hook writes the trace and the tree is dirty"
n=$(lines); hook S2 >/dev/null
[ "$(lines)" -eq $((n + 1)) ] && ok "hook appended one line" || bad "hook appended one line" "$n -> $(lines)"
has "fallback line is marked hook-end" "hook-end" "$(tail -1 "$LOG2")"
has "fallback line carries uncommitted=" "uncommitted=" "$(tail -1 "$LOG2")"
[ -n "$(git -C "$B2" status --porcelain)" ] && ok "tree is dirty — the honest state" || bad "tree is dirty" "clean"
git_q -C "$B2" add -A; git_q -C "$B2" commit -qm "hook line"

echo "two sessions in one repo: another session's stamp does not silence the hook"
pre --session S3; git_q -C "$B2" add -A; git_q -C "$B2" commit -qm "close S3"
n=$(lines); hook S4 >/dev/null
[ "$(lines)" -eq $((n + 1)) ] && ok "hook of S4 still writes its line" || bad "hook of S4 still writes its line" "$n -> $(lines)"
[ -f "$B2/.claude-state/session-close.stamp" ] && bad "stale stamp removed" "still there" || ok "stale stamp removed"
git_q -C "$B2" add -A; git_q -C "$B2" commit -qm "S4"

echo "older harness: a stamp without a session id still dedupes"
pre; git_q -C "$B2" add -A; git_q -C "$B2" commit -qm "close keyless"
n=$(lines); hook S5 >/dev/null
[ -z "$(git -C "$B2" status --porcelain)" ] && ok "git status empty after a keyless close" || bad "git status empty after a keyless close" "$(git -C "$B2" status --porcelain)"
[ "$(lines)" -eq "$n" ] && ok "no second line" || bad "no second line" "$n -> $(lines)"

echo
if [ "$fails" -eq 0 ]; then echo "test-session-closing: all checks passed"; exit 0; fi
echo "test-session-closing: $fails check(s) FAILED"; exit 1
