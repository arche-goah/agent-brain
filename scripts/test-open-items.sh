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
cp "$(dirname "$SRC")/instance_key.py" "$T/core/scripts/instance_key.py"
cp "$(dirname "$SRC")/project_dir.py" "$T/core/scripts/project_dir.py"
cp "$(dirname "$SRC")/shared_answers.py" "$T/core/scripts/shared_answers.py"
cp "$(dirname "$SRC")/shared_channels.py" "$T/core/scripts/shared_channels.py"
cp "$(dirname "$SRC")/ledger-reconcile.py" "$T/core/scripts/ledger-reconcile.py"
# The work-ledger registry: empty here (registered nothing on purpose); the ledger cases below
# use their own root.
mkdir -p "$T/root/.claude/rules"; printf '%s\n' '{"ledgers": []}' > "$T/root/.claude/rules/ledgers.json"
# The fake inbox prints whatever $T/inbox.txt holds — in UTF-8, like the real one (OS-9): unpinned,
# Windows wrote the em dash of an "optional: … —" line in cp1252 and the item read differently than
# on Linux (measured on PR #355: Windows '?', CI 'wait').
printf '%s\n' 'import os, sys' 'sys.stdout.reconfigure(encoding="utf-8")' \
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
  '  - 2026-10-05 [core] peer-b: AN inst-a: #196 Windows-Check OK (core/LOG@2026-10-05#1)' > "$T/inbox.txt"

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
pr() { # repo num author created body lastcommit reviews-json requests-json [comments-json]
  printf '{"number":%s,"title":"t%s","isDraft":false,"createdAt":"%sT10:00:00Z","body":"%s","author":{"login":"%s"},"repository":{"name":"%s"},"reviewRequests":{"nodes":%s},"latestReviews":{"nodes":%s},"commits":{"nodes":[{"commit":{"committedDate":"%s"}}]},"comments":{"nodes":%s}}' \
    "$2" "$2" "$4" "$5" "$3" "$1" "$8" "$7" "$6" "${9:-[]}"
}
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":10,"nodes":[%s,%s,%s,%s,%s,%s,%s,%s,%s,%s]}}}\n' \
  "$(pr suite-x 1 peer 2026-09-28 '' 2026-09-28T11:00:00Z '[{"author":{"login":"me"},"submittedAt":"2026-10-08T19:45:00Z"}]' '[]')" \
  "$(pr suite-x 2 peer 2026-09-29 '' 2026-10-09T11:00:00Z '[{"author":{"login":"me"},"submittedAt":"2026-10-08T19:45:00Z"}]' '[]')" \
  "$(pr owned 3 peer 2026-09-30 '' 2026-09-30T11:00:00Z '[]' '[]')" \
  "$(pr owned 4 peer 2026-10-01 '' 2026-10-01T11:00:00Z '[]' '[{"requestedReviewer":{"login":"me"}}]')" \
  "$(pr core 5 me 2026-10-02 "waiting-until: $NOW: alpha measurement" 2026-10-02T11:00:00Z '[]' '[]')" \
  "$(pr core 6 me 2026-10-03 "waiting-until: $PAST: alpha" 2026-10-03T11:00:00Z '[]' '[]')" \
  "$(pr grandma-suite 7 peer 2026-10-04 '' 2026-10-04T11:00:00Z '[]' '[]')"   "$(pr owned 8 me 2026-10-05 '' 2026-10-05T11:00:00Z '[]' '[]')"   "$(pr owned 9 me 2026-10-06 '' 2026-10-06T11:00:00Z '[{"author":{"login":"peer"},"submittedAt":"2026-10-07T09:00:00Z"}]' '[]')"   "$(pr owned 10 me 2026-10-06 '' 2026-10-06T11:00:00Z '[{"author":{"login":"peer"},"submittedAt":"2026-10-07T09:00:00Z"}]' '[]' '[{"author":{"login":"me"},"createdAt":"2026-10-07T10:00:00Z"}]')" > "$T/prs.json"
printf '%s\n' 'shared-memory open requests to this instance: 0' > "$T/inbox.txt"
printf '%s\n' '{"parked":["grandma"],"owners":{"owned":"peer"}}' > "$T/root/.claude/rules/open-items.json"
export OPEN_ITEMS_PR_FIXTURE; OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs.json")"
out=$(OWNER=me run p1); tx p1; out2=$(OWNER=me run p2)
line() { grep -F -- "$1" <<<"$2"; }
has "waiting on peer: we reviewed" "$(line 'suite-x#1 ' "$out")" && ok "approved, no commit since = waiting on author" || bad "approved PR: $(line 'suite-x#1 ' "$out")"
has "[PR|ai]" "$(line 'suite-x#2 ' "$out")" && ok "commit after our review = our move" || bad "new commit: $(line 'suite-x#2 ' "$out")"
has "is peer's to merge" "$(line 'owned#3 ' "$out")" && ok "owner's repo, no review asked = waiting" || bad "owner: $(line 'owned#3 ' "$out")"
has "[PR|ai]" "$(line 'owned#4 ' "$out")" && ok "review asked of us = our move" || bad "requested: $(line 'owned#4 ' "$out")"
has "waiting on peer: owned is peer's to merge, our own PR waits on that" "$(line 'owned#8 ' "$out")" && ok "own PR in an owner's repo = waiting on the owner" || bad "own PR, owner: $(line 'owned#8 ' "$out")"
has "[PR|ai]" "$(line 'owned#9 ' "$out")" && ok "owner reviewed our PR after the last commit = our move" || bad "own PR, review: $(line 'owned#9 ' "$out")"
has "waiting on peer" "$(line 'owned#10 ' "$out")" && ok "we answered the owner's review = waiting again" || bad "own PR, answered: $(line 'owned#10 ' "$out")"
# One login, two instances (measured 2026-10-11): the sibling's PR in an owner's repo was read
# as our own and filed as "waiting on the owner". With the instance key it is ours to look at.
KWS="$("$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import instance_key as k; print(k.key_for("ws"))' "$(native "$T/core/scripts")")"
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":1,"nodes":[%s]}}}\n' \
  "$(pr owned 11 me 2026-10-06 "fix <!-- instance-key: $KWS -->" 2026-10-06T11:00:00Z '[]' '[]')" > "$T/prs-sib.json"
sib=$(OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-sib.json")" SHARED_MEMORY_SELF=mac OWNER=me run s1)
has "[PR|ai]" "$(line 'owned#11 ' "$sib")" && ok "sibling instance's PR = our move, not the owner's" || bad "sibling: $(line 'owned#11 ' "$sib")"
sib0=$(OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-sib.json")" SHARED_MEMORY_SELF= OWNER=me run s0)
has "waiting on peer" "$(line 'owned#11 ' "$sib0")" && ok "negative control: without an own key the old reading (waiting) holds" || bad "no key: $(line 'owned#11 ' "$sib0")"
# The check was answered in the shared memory, not on the PR (measured 2026-10-11: two
# sibling PRs checked at their heads stayed "our move"). Our text naming THIS head = waiting;
# an older head, or someone else's text naming it, leaves the move with us.
HEAD12=abcdef1234567890abcdef1234567890abcdef12
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":1,"nodes":[%s]}}}\n' \
  "$(pr core 12 me 2026-10-06 "fix <!-- instance-key: $KWS -->" 2026-10-06T11:00:00Z '[]' '[]' | sed "s/\"commit\":{/\"commit\":{\"oid\":\"$HEAD12\",/")" > "$T/prs-sm.json"
smrun() { OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-sm.json")" SHARED_MEMORY_SELF=mac OWNER=me run "$1"; }
mkdir -p "$T/repo/core"
printf '%s\n' '---' 'name: a' 'metadata:' '  von: mac' '---' 'Checked at head `abcdef1`: OK.' > "$T/repo/core/antwort.md"
has "our check of this head is in the shared memory" "$(line 'core#12 ' "$(smrun m1)")" && ok "own shared-memory answer at this head = waiting" || bad "sm answer: $(line 'core#12 ' "$(smrun m1)")"
printf '%s\n' '---' 'name: a' 'metadata:' '  von: mac' '---' 'Checked at head `1111111`: OK.' > "$T/repo/core/antwort.md"
printf '%s\n' '# LOG' '' '## 2026-10-11 · mac — AN ws: checked 2222222' 'ok' '' '## 2026-10-11 · ws — AN mac: please check abcdef1' 'x' > "$T/repo/core/LOG.md"
has "[PR|ai]" "$(line 'core#12 ' "$(smrun m2)")" && ok "negative control: an older head or a foreign text naming the head stays our move" || bad "stale/foreign sha: $(line 'core#12 ' "$(smrun m2)")"
printf '%s\n' '# LOG' '' '## 2026-10-11 · mac — AN ws: checked abcdef1 OK' 'ok' > "$T/repo/core/LOG.md"
has "our check of this head is in the shared memory" "$(line 'core#12 ' "$(smrun m3)")" && ok "own LOG section naming this head = waiting" || bad "sm LOG: $(line 'core#12 ' "$(smrun m3)")"
# The real setting is a comma list "<device>,<alias>,…" (macOS check of #286): the device token counts.
sml=$(OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-sm.json")" SHARED_MEMORY_SELF="mac,person:x,os:macos" OWNER=me run m4)
has "our check of this head is in the shared memory" "$(line 'core#12 ' "$sml")" && ok "self as a comma list: the device token counts" || bad "comma-list self: $(line 'core#12 ' "$sml")"
rm -rf "$T/repo/core"
has "waiting until $NOW: alpha measurement" "$(line 'core#5 ' "$out")" && ok "dated wait is quiet" || bad "dated wait: $(line 'core#5 ' "$out")"
has "that date has passed" "$(line 'core#6 ' "$out")" && ok "past wait is louder" || bad "past wait: $(line 'core#6 ' "$out")"
has "2026-09-28 suite-x#1" "$out" && ok "shown date = opened date" || bad "date: $out"
has "[parked] grandma-suite#7" "$out" && ok "parked PR on the parked line" || bad "parked PR: $out"
has "(+5 waiting on others or a date)" "$out" && ok "header counts the waits apart" || bad "wait header: $(head -1 <<<"$out")"
outc=$(OWNER=me OPEN_ITEMS_WAIT_COLLAPSE=2 run p3)
has "- [wait] 5 waiting on others or a date: " "$outc" && [ -z "$(line '|wait] ' "$outc")" ] && ok "many waits collapse into one line" || bad "collapse: $outc"
l1=$(line 'suite-x#1 ' "$out2")
has "waiting on peer" "$l1" && ! has "reported in" "$l1" && ok "a wait does not count up" || bad "a wait was counted: $l1"
has "!! reported in 2 sessions" "$(line 'core#6 ' "$out2")" && ok "past wait counts up" || bad "past wait count: $(line 'core#6 ' "$out2")"
has "nothing done yet" "$(line 'core#6 ' "$out2")" && ok "no own move since the first report = nothing done yet" || bad "idle claim: $(line 'core#6 ' "$out2")"
# "nothing done yet" is a claim (measured 2026-10-12: an own PR with a commit and a comment the
# same day was printed so in 17 sessions). An own commit after the first report names that move.
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":1,"nodes":[%s]}}}\n' \
  "$(pr core 13 me 2026-10-03 '' "${NOW}T09:00:00Z" '[]' '[]')" > "$T/prs-mv.json"
OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-mv.json")" OWNER=me run v1 >/dev/null; tx v1
mv=$(line 'core#13 ' "$(OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-mv.json")" OWNER=me run v2)")
has "last own move $NOW — still ours" "$mv" && ! has "nothing done yet" "$mv" && ok "own move since the first report is named, not 'nothing done'" || bad "own move: $mv"
# A wait dated TODAY is due today, not quiet (measured 2026-10-15: quiet through its own date, a
# measurement done that day read as missing the next morning — the marker was never moved).
TODAY=$(date +%Y-%m-%d)
printf '{"data":{"viewer":{"login":"me"},"search":{"issueCount":1,"nodes":[%s]}}}\n' \
  "$(pr core 14 me 2026-10-03 "waiting-until: $TODAY: third measurement" 2026-10-03T11:00:00Z '[]' '[]')" > "$T/prs-due.json"
due=$(OPEN_ITEMS_PR_FIXTURE="$(native "$T/prs-due.json")" OWNER=me run d1)
has "!! due today (third measurement) — do it, then move or drop the waiting-until line" "$(line 'core#14 ' "$due")" && ok "wait on its own date is due" || bad "due today: $due"
has "open for us: 1 — ai 1" "$due" && ok "a due wait counts as ours" || bad "due count: $(head -1 <<<"$due")"
has "read the work's own record before calling it undone" "$(line 'core#6 ' "$out")" && ok "past wait names the stale-marker reading" || bad "past wording: $(line 'core#6 ' "$out")"
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
  '  - 2026-10-05 [core] peer-b: AN inst-a: Check OK (core/LOG@2026-10-05#1)' > "$T/inbox.txt"
out=$(run h)
has "[request|ai] 2026-09-13" "$out" && ok "circle C = ai" || bad "circle C: $out"
has "[request|human] 2026-09-26" "$out" && ok "circle E = human" || bad "circle E: $out"
has "[request|human] 2026-09-08" "$out" && ok "addressed to a person = human" || bad "person: $out"
has "[request|?] 2026-09-06" "$out" && ok "no data = '?'" || bad "unclassified: $out"
has "[request|?] 2026-09-06" "$out" && ok "machine id built from the name is not the person" || bad "machine id read as a person: $out"
has "unclassified 2" "$out" && ok "header counts the '?'" || bad "header: $(head -1 <<<"$out")"
has "classify every '?' item" "$out" && ok "'?' asks for --classify" || bad "no classify hint: $out"
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" \
  --classify 'anfrage-x-2026-09-06.md=human:needs the operator net definition' >/dev/null 2>&1
out=$(run i)
has "[request|human] 2026-09-06" "$out" && ok "--classify by file name sticks" || bad "classify lost: $out"
has "needs the operator net definition" "$out" && ok "the reason is printed" || bad "reason missing: $out"
out=$("$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" --classify 'x=maybe' 2>&1)
has "bad --classify" "$out" && ok "bad class refused" || bad "bad class accepted: $out"

# Two LOG entries of one sender on one day: the inbox prints each with its own id
# (`<area>/LOG@<date>#<n>`), and a class or a counter belongs to that id alone. The old key
# (date + sender + first 40 chars) collided, cut at blanks and passed classes on (15 fixes).
printf '%s\n' 'shared-memory open requests to this instance: 2' \
  '  - 2026-10-07 [core] peer-b: AN inst-a: first note (core/LOG@2026-10-07#1)' \
  '  - 2026-10-07 [core] peer-b: AN inst-a: second, a real request (core/LOG@2026-10-07#2)' > "$T/inbox.txt"
out=$(run j0)
has "--classify 'core/LOG@2026-10-07#1=" "$out" \
  && ok "hint prints the exact LOG id" || bad "hint lacks the exact id: $out"
# The old short form is no id: refused, nothing saved, the exact ids offered.
cout=$("$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" \
  --classify 'LOG 2026-10-07 peer-b=ai:short form' 2>&1); rc=$?
[ "$rc" = 2 ] && has "matches no open request" "$cout" && ! has "classified:" "$cout" \
  && ok "unknown id refused, nothing saved" || bad "unknown id accepted (rc=$rc): $cout"
has "   core/LOG@2026-10-07#2" "$cout" && ok "refusal lists the exact ids" || bad "no exact ids offered: $cout"
out=$(run j)
[ "$(grep -c '\[request|?\] 2026-10-07' <<<"$out")" = 2 ] && ok "short LOG form classifies nothing" \
  || bad "short LOG form leaked a class: $out"
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" \
  --classify 'core/LOG@2026-10-07#1=ai:ack only' >/dev/null 2>&1
out=$(run k)
[ "$(grep -c '\[request|ai\] 2026-10-07' <<<"$out")" = 1 ] && [ "$(grep -c '\[request|?\] 2026-10-07' <<<"$out")" = 1 ] \
  && ok "a LOG id classifies exactly its own entry" || bad "LOG id class spread or missed: $out"
# Several --classify flags all count (measured 2026-10-11: only the last one did).
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" \
  --classify 'core/LOG@2026-10-07#1=ai:first' --classify 'core/LOG@2026-10-07#2=ai:second' >/dev/null 2>&1
out=$(run l)
[ "$(grep -c '\[request|ai\] 2026-10-07' <<<"$out")" = 2 ] && ok "two --classify flags both stick" || bad "classify lost: $out"

# The first entry is answered and leaves the inbox: the second keeps its own id, class and
# counter — nothing is taken over (the old key passed the first one's class to the second).
printf '%s\n' 'shared-memory open requests to this instance: 2' \
  '  - 2026-10-09 [core] peer-b: AN inst-a, inst-b, inst-c, inst-d, inst-e: run one (core/LOG@2026-10-09#1)' \
  '  - 2026-10-09 [core] peer-b: AN inst-a, inst-b, inst-c, inst-d, inst-e: run two (core/LOG@2026-10-09#2)' > "$T/inbox.txt"
"$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$T/root")" --repo "$(native "$T/repo")" \
  --classify 'core/LOG@2026-10-09#1=ai:first only' >/dev/null 2>&1
run twin1 >/dev/null; tx twin1; run twin2 >/dev/null; tx twin2; out=$(run twin3); tx twin3
has "!! reported in 3 sessions" "$(line 'run two' "$out")" && ok "second entry counts while both are open" || bad "twin count: $(line 'run two' "$out")"
printf '%s\n' 'shared-memory open requests to this instance: 1' \
  '  - 2026-10-09 [core] peer-b: AN inst-a, inst-b, inst-c, inst-d, inst-e: run two (core/LOG@2026-10-09#2)' > "$T/inbox.txt"
out=$(run twin4); tx twin4
l=$(line 'run two' "$out")
has "[request|?] 2026-10-09" "$l" && ! has "first only" "$l" \
  && ok "the second entry does not take over the first one's class" || bad "class taken over: $l"
has "!! reported in 4 sessions" "$l" && ok "the second entry keeps its own counter" || bad "counter lost: $l"
# Same id, edited wording: class and counter stay (they belong to the id, not to the words).
printf '%s\n' 'shared-memory open requests to this instance: 1' \
  '  - 2026-10-09 [core] peer-b: AN inst-a, inst-b, inst-c, inst-d, inst-e: run one (core/LOG@2026-10-09#1)' > "$T/inbox.txt"
run twin5 >/dev/null; tx twin5
printf '%s\n' 'shared-memory open requests to this instance: 1' \
  '  - 2026-10-09 [core] peer-b: AN inst-a, inst-b, inst-c, inst-d, inst-e: run one, reworded (core/LOG@2026-10-09#1)' > "$T/inbox.txt"
out=$(run twin6)
l=$(line 'reworded' "$out")
has "[request|ai] 2026-10-09" "$l" && has "!! reported in" "$l" && ok "edited text keeps class and counter" || bad "edit reset the entry: $l"
# Standing approval (full-audit 2026-10-15, Windows instance): a class the operator approved once
# for good prints as `standing` in its own group. The same topic to another machine, an excluded
# text and an item the data gives to a person are not standing; an entry without the operator's
# quoted words and date is refused with a line, and its items are asked as before.
rm -rf "$T/repo" && mkdir -p "$T/repo/core" && GIT init -q
printf '%s\n' '---' 'name: s1' 'metadata:' '  von: peer-b' '  audience: inst-a' '---' 'body' > "$T/repo/core/request-mine-2026-10-14.md"
printf '%s\n' '---' 'name: s2' 'metadata:' '  von: peer-b' '  audience: inst-b, os:shared' '---' 'body' > "$T/repo/core/request-other-2026-10-14.md"
printf '%s\n' '---' 'name: s3' 'metadata:' '  von: peer-b' '  audience: inst-a' '  circle: E' '---' 'body' > "$T/repo/core/request-person-2026-10-14.md"
printf '%s\n' '---' 'name: s4' 'metadata:' '  von: peer-b' '  audience: inst-a' '---' 'body' > "$T/repo/core/request-pin-2026-10-14.md"
GIT add -A && GIT commit -q -m standing && GIT update-ref refs/remotes/origin/main HEAD
printf '%s\n' 'shared-memory open requests to this instance: 5' \
  '  - 2026-10-14 [core] peer-b: check the fixture run (core/request-mine-2026-10-14.md)' \
  '  - 2026-10-14 [core] peer-b: check the other run (core/request-other-2026-10-14.md)' \
  '  - 2026-10-14 [core] peer-b: decide the budget (core/request-person-2026-10-14.md)' \
  '  - 2026-10-14 [core] peer-b: move the stable pin (core/request-pin-2026-10-14.md)' \
  '  - 2026-10-14 [core] peer-b: AN inst-a: answer the log question (core/LOG@2026-10-14#1)' > "$T/inbox.txt"
SR="$T/root-st"; mkdir -p "$SR/.claude/rules"
printf '%s\n' '{"classes":[{"name":"requests to this machine","kind":"request","audience":["inst-a"],"excludes":["\\bpin\\b"],"granted":"\"handle them without asking\" 2026-10-11"}]}' \
  > "$SR/.claude/rules/open-items-standing.json"
st=$(run st1 "$SR")
has "[request|standing] 2026-10-14 core/request-mine-2026-10-14.md" "$st" && ok "item of a standing class = standing" || bad "standing class missed: $st"
has "standing approval 'requests to this machine', granted 2026-10-11" "$(line 'request-mine' "$st")" && ok "standing item names its class and date" || bad "standing why: $(line 'request-mine' "$st")"
has "[request|standing]" "$(line 'answer the log question' "$st")" && ok "LOG request addressed to this instance = standing" || bad "LOG standing: $(line 'answer the log question' "$st")"
has "[request|?]" "$(line 'request-other' "$st")" && ok "negative control: same topic to another machine is not standing" || bad "other machine: $(line 'request-other' "$st")"
has "[request|?]" "$(line 'request-pin' "$st")" && ok "negative control: an excluded text is not standing" || bad "excluded: $(line 'request-pin' "$st")"
has "[request|human]" "$(line 'request-person' "$st")" && ok "negative control: an item the data gives to a person stays human" || bad "person: $(line 'request-person' "$st")"
has "open for us: 5 — ai 0 · human 1 · unclassified 2 · standing 2" "$st" && ok "header counts the standing items" || bad "standing header: $(head -1 <<<"$st")"
gl=$(grep -n -F -- '- standing approval — handle these, then report what was done' <<<"$st" | cut -d: -f1)
pl=$(grep -n -F -- 'request-person' <<<"$st" | cut -d: -f1)
ml=$(grep -n -F -- 'request-mine' <<<"$st" | cut -d: -f1)
[ -n "$gl" ] && [ "$gl" -gt "$pl" ] && [ "$ml" -gt "$gl" ] && ok "standing items form their own group after the others" || bad "standing group order: $st"
printf '%s\n' '{"classes":[{"name":"requests to this machine","kind":"request","audience":["inst-a"],"granted":"the operator said so 2026-10-11"}]}' \
  > "$SR/.claude/rules/open-items-standing.json"
st=$(run st2 "$SR")
has "!! open for us: standing approval 'requests to this machine' refused — \"granted\" must quote the operator's words" "$st" && ok "entry without the quoted words is refused with a line" || bad "unquoted grant accepted: $st"
has "[request|standing]" "$st" && bad "refused entry still applied: $st" || ok "refused entry applies to nothing"
printf '%s\n' '{"classes":[{"name":"requests to this machine","kind":"request","audience":["inst-a"],"granted":"\"handle them without asking\""}]}' \
  > "$SR/.claude/rules/open-items-standing.json"
st=$(run st3 "$SR")
has "standing approval 'requests to this machine' refused" "$st" && ! has "[request|standing]" "$st" && ok "entry without a date is refused" || bad "undated grant accepted: $st"
printf '%s\n' 'shared-memory open requests to this instance: 2' \
  '  - 2026-09-05 [show-tools] peer-b: ANFRAGE an inst-a (show-tools/anfrage-td-2026-09-05.md)' \
  '  - 2026-10-05 [core] peer-b: AN inst-a: #196 Windows-Check OK (core/LOG@2026-10-05#1)' > "$T/inbox.txt"

# Work ledgers (measured 2026-10-25: "open for us: 3" while ordered points sat in the brain's
# own ledgers). Open entries are listed (todo = ai, decision = human), done ones and lessons not;
# no registry and an unreadable format each say NOT checked, never "nothing open".
L="$T/root-led"; mkdir -p "$L/.claude/rules" "$L/docs/x"
printf '%s\n' 'shared-memory open requests to this instance: 0 (last 36500 days)' > "$T/inbox.txt"
out=$(run "" "$L")
has "work ledgers (no readable .claude/rules/ledgers.json) NOT checked" "$out" && ok "no ledger registry = NOT checked" || bad "no registry silent: $out"
has "- nothing open" "$out" && bad "no registry read as nothing open: $out" || ok "no registry is not 'nothing open'"
printf '%s\n' '{"ledgers": ["docs/x/open.md", "docs/x/heads.md"]}' > "$L/.claude/rules/ledgers.json"
printf '%s\n' '# x' '' '- [ ] Remeasure the ipc folders 2026-10-11' '  - `id: ipc-remeasure`  `class: todo`  `origin: derived`' '' \
  '- [ ] Pick a name' '  id: pick-name' '  class: decision' '' \
  '- [x] Done thing' '  id: done-thing' '' \
  '- [ ] Never minimise the window' '  id: minimise-lesson' '  class: lesson' > "$L/docs/x/open.md"
printf '%s\n' '# y' '' '## Heading entry' '' '- id: `heading-entry`' '- class: todo' > "$L/docs/x/heads.md"
out=$(run "" "$L")
has "[ledger|ai] 2026-10-11 ipc-remeasure — derived: Remeasure the ipc folders" "$out" && ok "open ledger todo listed as ai" || bad "ledger todo missing: $out"
has "[ledger|human]  pick-name" "$out" && ok "ledger decision listed as human" || bad "ledger decision: $out"
has "done-thing" "$out" && bad "done entry listed: $out" || ok "done entry not listed"
has "minimise-lesson" "$out" && bad "lesson listed: $out" || ok "lesson not listed"
has "ledger docs/x/heads.md (id: fields but no '- [ ]' entries" "$out" && ok "unreadable ledger format = NOT checked" || bad "heading-format ledger silent: $out"
printf '%s\n' '{"ledgers": ["docs/x/open.md"]}' > "$L/.claude/rules/ledgers.json"
out=$(run "" "$L")
has "open for us: 2 — ai 1 · human 1" "$out" && ok "ledger items counted" || bad "ledger count: $out"
# A backlog-catch-up exit that puts the move elsewhere waits quietly; ai-does-it stays the agent's.
printf '%s\n' '' '- [ ] Ask the other side' '  id: other-thing' '  exit: other-side 2026-10-25 — peer is on it' '' \
  '- [ ] Mine to build' '  id: mine-thing' '  exit: ai-does-it 2026-10-25 — clear' >> "$L/docs/x/open.md"
out=$(run "" "$L")
has "[ledger|wait] 2026-10-25 other-thing" "$out" && has "waiting on the ledger exit other-side: since 2026-10-25" "$out" \
  && ok "exit other-side waits quietly" || bad "exit other-side: $out"
has "[ledger|ai] 2026-10-25 mine-thing" "$out" && ok "exit ai-does-it stays open work" || bad "exit ai-does-it: $out"
cl=$("$PY" "$(native "$T/core/scripts/open-items.py")" --root "$(native "$L")" --repo "$(native "$T/repo")" --classify 'ledger:pick-name=ai:mine' 2>&1)
out=$(run "" "$L")
has "[ledger|ai]  pick-name" "$out" && ok "ledger item classified by its id" || bad "ledger classify: $cl / $out"

# A counter that cannot be saved says so (root is a FILE, so .claude-state cannot exist).
printf x > "$T/rootfile"
out=$(run g "$T/rootfile")
has "repeat counter NOT saved" "$out" && ok "lost counter is loud" || bad "lost counter silent: $out"

# PR search over several owners (instance data `pr_owners`): one search, every owner a
# `user:` qualifier (GitHub ORs them), the --owner itself not doubled. Control: no
# pr_owners = the search is the single owner, as before.
mkdir -p "$T/root-po/.claude/rules"
q1=$(OPEN_ITEMS_SHOW_PR_SEARCH=1 OWNER=me run "" "$T/root-po" | sed -n 's/^pr-search: //p')
[ "$q1" = "user:me is:pr is:open archived:false" ] && ok "no pr_owners: the search is the single owner" || bad "single-owner search: '$q1'"
printf '%s\n' '{"pr_owners": ["Personal", "ME"]}' > "$T/root-po/.claude/rules/open-items.json"
q2=$(OPEN_ITEMS_SHOW_PR_SEARCH=1 OWNER=me run "" "$T/root-po" | sed -n 's/^pr-search: //p')
[ "$q2" = "user:me user:Personal is:pr is:open archived:false" ] && ok "pr_owners: one search over both owners, --owner not doubled" \
  || bad "several-owner search: '$q2'"

[ "$fail" = 0 ] && echo "open-items: all cases pass" || { echo "open-items: FAILURES"; exit 1; }
