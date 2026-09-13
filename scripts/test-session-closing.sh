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

run_close() { (cd "$BRAIN" && CLAUDE_PROJECT_DIR="$BRAIN" SHARED_MEMORY_REPO="$SHARED" bash "$CLOSING" 2>&1); }

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

echo
if [ "$fails" -eq 0 ]; then echo "test-session-closing: all checks passed"; exit 0; fi
echo "test-session-closing: $fails check(s) FAILED"; exit 1
