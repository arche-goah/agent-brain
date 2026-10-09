#!/usr/bin/env bash
# Fixture test for scripts/open-items.py — both directions, no network.
# A fake shared-memory-inbox.py next to a copy of the script stands in for the real inbox;
# --owner "" skips the PR search. Proves: the repeat counter (same session once, a new
# session louder), a LOG-only request is listed, a capped / unreadable / "not checked"
# inbox reads as NOT checked (never as "nothing open"), "nothing open" is said when both
# sources are clean, parked items stay on one line, a lost counter says so.
# Usage: bash scripts/test-open-items.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
SRC="$(cd "$(dirname "$0")" && pwd)/open-items.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$SRC" ] || { echo "  FAIL script missing: $SRC"; exit 1; }

mkdir -p "$T/core/scripts" "$T/repo/.git" "$T/root"
cp "$SRC" "$T/core/scripts/open-items.py"
# The fake inbox prints whatever $T/inbox.txt holds.
printf '%s\n' 'import os, sys' \
  'sys.stdout.write(open(os.path.join(os.path.dirname(__file__), "..", "..", "inbox.txt"), encoding="utf-8").read())' \
  > "$T/core/scripts/shared-memory-inbox.py"

# OS-3: python is a native process; a Git-Bash /tmp path handed to it as DATA (--repo,
# --root) does not resolve on Windows, and every case would read an empty tree.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
mkdir -p "$T/tx"
# PR source: a saved GraphQL answer with no open PRs, unless a case says otherwise.
printf '%s\n' '{"data":{"viewer":{"login":"me"},"search":{"issueCount":0,"nodes":[]}}}' > "$T/noprs.json"
export OPEN_ITEMS_PR_FIXTURE; OPEN_ITEMS_PR_FIXTURE="$(native "$T/noprs.json")"
run() { # $1 session id ("" = hand run), [$2 root]; the transcript path sits next to the others
  local hi="{}"
  [ -n "$1" ] && hi="{\"session_id\":\"$1\",\"transcript_path\":\"$(native "$T/tx/$1.jsonl")\"}"
  "$PY" "$(native "$T/core/scripts/open-items.py")" --owner "${OWNER-me}" --repo "$(native "$T/repo")" \
    --root "$(native "${2:-$T/root}")" --hook-input "$hi" 2>&1
}
# A transcript in which the list reached a human: the bootup block, then a real prompt.
# $2 = "notif" writes only a background notification after the bootup (nobody read it).
tx() {
  local p='{"type":"user","message":{"role":"user","content":"stand?"}}'
  [ "${2:-}" = notif ] && p='{"type":"user","message":{"role":"user","content":"<task-notification>done</task-notification>"}}'
  printf '%s\n' '{"attachment":{"type":"hook_success","hookEvent":"SessionStart","content":"open for us: 2"}}' "$p" > "$T/tx/$1.jsonl"
}
has() { case "$2" in *"$1"*) return 0;; esac; return 1; }

printf '%s\n' 'shared-memory open requests to this instance: 2' \
  '  - 2026-09-05 [show-tools] peer-b: ANFRAGE an inst-a (show-tools/anfrage-td-2026-09-05.md)' \
  '  - 2026-10-05 [core] peer-b: AN inst-a: #196 Windows-Check OK (LOG)' > "$T/inbox.txt"

out=$(run a); tx a
has "open for us: 2" "$out" && ok "count line" || bad "count line: $out"
has "2026-10-05 core/LOG" "$out" && ok "LOG-only request listed" || bad "LOG request missing: $out"
has "first report" "$out" && ok "first session = first report" || bad "first report: $out"
out=$(run a)
has "!! reported in" "$out" && bad "same session counted twice: $out" || ok "same session counts once"
out=$(run b); tx b
has "!! reported in 2 sessions" "$out" && ok "new session is louder" || bad "no escalation: $out"
# Counter inflation (measured 2026-10-09): a session without a transcript, a hand run, and a
# session where only a background notification followed the bootup never reached a human.
run ghost >/dev/null; run "" >/dev/null; run nobody >/dev/null; tx nobody notif
out=$(run c); tx c
has "!! reported in 3 sessions" "$out" && ok "phantom, hand and unread runs do not count" || bad "counter inflated: $out"
out=$(run d)
has "!! reported in 4 sessions" "$out" && ok "real sessions keep counting" || bad "real session lost: $out"
# A hand run never writes the counter — not even with a source skipped (measured 2026-10-09:
# such a run rewrote the file and every item lost its history).
tx d; S="$T/root/.claude-state/open-items-seen.json"; before=$(cat "$S")
OWNER= run "" >/dev/null; run "" >/dev/null
[ "$(cat "$S")" = "$before" ] && ok "hand runs leave the counter file untouched" || bad "hand run rewrote the counter"
out=$(run e1)
has "!! reported in 5 sessions" "$out" && ok "history survives hand runs" || bad "history lost: $out"

# Capped list: the inbox says 3, prints 2 — must read as NOT checked.
sed -i.bak 's/instance: 2/instance: 3/' "$T/inbox.txt"
out=$(run c)
has "shared-memory requests NOT checked" "$out" && ok "count mismatch = NOT checked" || bad "count mismatch silent: $out"
has "- nothing open" "$out" && bad "count mismatch read as nothing open" || ok "count mismatch is not 'nothing open'"

# SHARED_MEMORY_SELF unset: the inbox says "not checked".
printf '%s\n' 'shared-memory open requests: not checked - SHARED_MEMORY_SELF unset' > "$T/inbox.txt"
out=$(run d)
has "NOT checked" "$out" && ok "inbox 'not checked' = NOT checked" || bad "unset SELF read as clean: $out"

# Clean: zero requests, no owner.
printf '%s\n' 'shared-memory open requests to this instance: 0 (last 36500 days)' > "$T/inbox.txt"
out=$(run e)
has "- nothing open" "$out" && ok "clean = 'nothing open' said" || bad "clean not said: $out"
has "open for us: 0" "$out" && ok "clean count 0" || bad "clean count: $out"
# A source that was never asked is not "nothing open" (measured 2026-10-09: no --owner).
out=$(OWNER= run e2)
has "PRs (no owner given) NOT checked" "$out" && ok "no owner = PRs NOT checked" || bad "no owner silent: $out"
has "- nothing open" "$out" && bad "no owner read as nothing open: $out" || ok "no owner is not 'nothing open'"

# Parked: one line, not dropped, not counted as active.
mkdir -p "$T/root/.claude/rules"
printf '%s\n' '{"parked":["grandma"]}' > "$T/root/.claude/rules/open-items.json"
printf '%s\n' 'shared-memory open requests to this instance: 1' \
  '  - 2026-09-08 [grandma3] peer-c: Rueckfrage (grandma3/rueckfrage-2026-09-08.md)' > "$T/inbox.txt"
out=$(run f)
# A REQUEST from another side in a parked domain is not parked away: it gets an answer.
has "open for us: 1 — ai 1" "$out" && ok "parked-domain request is answerable" || bad "parked request hidden: $out"
has "answer anyway: receipt, state, when it resumes" "$out" && ok "parked request says how to answer" || bad "parked answer hint: $out"
has "[parked]" "$out" && bad "request still on the parked line: $out" || ok "request off the parked line"

# Pull requests (a saved GraphQL answer stands in for gh): whose move it is, dated waits,
# the shown date, parked repos. Viewer = me.
NOW=$(date +%Y)-12-31; PAST=2020-01-01
pr() { # repo num author created body lastcommit reviews-json requests-json
  printf '{"number":%s,"title":"t%s","isDraft":false,"createdAt":"%sT10:00:00Z","body":"%s","author":{"login":"%s"},"repository":{"name":"%s"},"reviewRequests":{"nodes":%s},"latestReviews":{"nodes":%s},"commits":{"nodes":[{"commit":{"committedDate":"%s"}}]},"comments":{"nodes":[]}}' \
    "$2" "$2" "$4" "$5" "$3" "$1" "$8" "$7" "$6"
}
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":7,"nodes":[%s,%s,%s,%s,%s,%s,%s]}}}\n' \
  "$(pr suite-x 1 peer 2026-09-28 '' 2026-09-28T11:00:00Z '[{"author":{"login":"me"},"submittedAt":"2026-10-08T19:45:00Z"}]' '[]')" \
  "$(pr suite-x 2 peer 2026-09-29 '' 2026-10-09T11:00:00Z '[{"author":{"login":"me"},"submittedAt":"2026-10-08T19:45:00Z"}]' '[]')" \
  "$(pr owned 3 peer 2026-09-30 '' 2026-09-30T11:00:00Z '[]' '[]')" \
  "$(pr owned 4 peer 2026-10-01 '' 2026-10-01T11:00:00Z '[]' '[{"requestedReviewer":{"login":"me"}}]')" \
  "$(pr core 5 me 2026-10-02 "waiting-until: $NOW: alpha measurement" 2026-10-02T11:00:00Z '[]' '[]')" \
  "$(pr core 6 me 2026-10-03 "waiting-until: $PAST: alpha" 2026-10-03T11:00:00Z '[]' '[]')" \
  "$(pr grandma-suite 7 peer 2026-10-04 '' 2026-10-04T11:00:00Z '[]' '[]')" > "$T/prs.json"
printf '%s\n' 'shared-memory open requests to this instance: 0' > "$T/inbox.txt"
printf '%s\n' '{"parked":["grandma"],"owners":{"owned":"peer"}}' > "$T/root/.claude/rules/open-items.json"
export OPEN_ITEMS_PR_FIXTURE; OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs.json")"
out=$(OWNER=me run p1); tx p1; out2=$(OWNER=me run p2)
line() { grep -F -- "$1" <<<"$2"; }
has "waiting on peer: we reviewed" "$(line 'suite-x#1 ' "$out")" && ok "approved, no commit since = waiting on author" || bad "approved PR: $(line 'suite-x#1 ' "$out")"
has "[PR|ai]" "$(line 'suite-x#2 ' "$out")" && ok "commit after our review = our move" || bad "new commit: $(line 'suite-x#2 ' "$out")"
has "is peer's to merge" "$(line 'owned#3 ' "$out")" && ok "owner's repo, no review asked = waiting" || bad "owner: $(line 'owned#3 ' "$out")"
has "[PR|ai]" "$(line 'owned#4 ' "$out")" && ok "review asked of us = our move" || bad "requested: $(line 'owned#4 ' "$out")"
has "waiting until $NOW: alpha measurement" "$(line 'core#5 ' "$out")" && ok "dated wait is quiet" || bad "dated wait: $(line 'core#5 ' "$out")"
has "that date has passed" "$(line 'core#6 ' "$out")" && ok "past wait is louder" || bad "past wait: $(line 'core#6 ' "$out")"
has "2026-09-28 suite-x#1" "$out" && ok "shown date = opened date" || bad "date: $out"
has "[parked] grandma-suite#7" "$out" && ok "parked PR on the parked line" || bad "parked PR: $out"
has "(+3 waiting on others or a date)" "$out" && ok "header counts the waits apart" || bad "wait header: $(head -1 <<<"$out")"
l1=$(line 'suite-x#1 ' "$out2")
has "waiting on peer" "$l1" && ! has "reported in" "$l1" && ok "a wait does not count up" || bad "a wait was counted: $l1"
has "!! reported in 2 sessions" "$(line 'core#6 ' "$out2")" && ok "past wait counts up" || bad "past wait count: $(line 'core#6 ' "$out2")"
OPEN_ITEMS_PR_FIXTURE="$(native "$T/noprs.json")"

# WHO acts: circle field in the request file (read at origin/main), a request addressed to
# a person by name, an agent class from --classify, and the rest printed as '?'.
GIT() { git -C "$T/repo" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
rm -rf "$T/repo" && mkdir -p "$T/repo/core" "$T/repo/ops" && GIT init -q
printf '%s\n' '---' 'name: a' 'metadata:' '  von: peer-b' '  circle: C' '---' 'body' > "$T/repo/core/anfrage-c-2026-09-13.md"
printf '%s\n' '---' 'name: b' 'metadata:' '  von: peer-b' '  circle: E' '---' 'body' > "$T/repo/ops/anfrage-e-2026-09-26.md"
printf '%s\n' '---' 'name: c' 'metadata:' '  von: peer-c' '---' 'body' > "$T/repo/ops/anfrage-x-2026-09-06.md"
GIT add -A && GIT commit -q -m init && GIT update-ref refs/remotes/origin/main HEAD
printf '%s\n' '{"humans":["Opname"]}' > "$T/root/.claude/rules/open-items.json"
printf '%s\n' 'shared-memory open requests to this instance: 5' \
  '  - 2026-09-13 [core] peer-b: ANFRAGE an inst-a (core/anfrage-c-2026-09-13.md)' \
  '  - 2026-09-26 [ops] peer-b: ANFRAGE an inst-a (ops/anfrage-e-2026-09-26.md)' \
  '  - 2026-09-06 [ops] peer-c: ANFRAGE an Opname-mac, braucht Netz (ops/anfrage-x-2026-09-06.md)' \
  '  - 2026-09-08 [ops] peer-c: Rueckfrage an Opname (ops/rueckfrage-y-2026-09-08.md)' \
  '  - 2026-10-05 [core] peer-b: AN inst-a: Check OK (LOG)' > "$T/inbox.txt"
out=$(run h)
has "[request|ai] 2026-09-13" "$out" && ok "circle C = ai" || bad "circle C: $out"
has "[request|human] 2026-09-26" "$out" && ok "circle E = human" || bad "circle E: $out"
has "[request|human] 2026-09-08" "$out" && ok "addressed to a person = human" || bad "person: $out"
has "[request|?] 2026-09-06" "$out" && ok "no data = '?'" || bad "unclassified: $out"
has "[request|?] 2026-09-06" "$out" && ok "machine id built from the name is not the person" || bad "machine id read as a person: $out"
has "unclassified 2" "$out" && ok "header counts the '?'" || bad "header: $(head -1 <<<"$out")"
has "classify every '?' item" "$out" && ok "'?' asks for --classify" || bad "no classify hint: $out"
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" \
  --classify 'anfrage-x-2026-09-06.md=human:needs the operator net definition' >/dev/null 2>&1
out=$(run i)
has "[request|human] 2026-09-06" "$out" && ok "--classify by file name sticks" || bad "classify lost: $out"
has "needs the operator net definition" "$out" && ok "the reason is printed" || bad "reason missing: $out"
out=$("$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --classify 'x=maybe' 2>&1)
has "bad --classify" "$out" && ok "bad class refused" || bad "bad class accepted: $out"

# A counter that cannot be saved says so (root is a FILE, so .claude-state cannot exist).
printf x > "$T/rootfile"
out=$(run g "$T/rootfile")
has "repeat counter NOT saved" "$out" && ok "lost counter is loud" || bad "lost counter silent: $out"

[ "$fail" = 0 ] && echo "open-items: all cases pass" || { echo "open-items: FAILURES"; exit 1; }
