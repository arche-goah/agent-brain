#!/usr/bin/env bash
# Fixture for `shared-memory-inbox.py --open` and the clean-start line of
# helpers/shared-memory-check.sh — both directions.
# covers: scripts/shared-memory-inbox.py helpers/shared-memory-check.sh
#
# Why: the range inbox only shows what arrived since the cursor, and the cursor moves when
# a start SHOWS an entry, not when anyone answers it. Measured 2026-10-05: three requests
# addressed to one instance were shown once, never relayed, and every later start was
# silent. The open list must (1) keep an unanswered request listed on every start, (2) drop
# it once one of our own entries names it, (3) ignore reports, broadcasts and our own
# requests, and the check must (4) print a line on a clean start instead of nothing.
#
# Sandbox only (bash, git, mktemp, python). Exit 0 = all pass.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INBOX="$HERE/shared-memory-inbox.py"
CHECK="$HERE/../helpers/shared-memory-check.sh"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

BARE="$TMP/remote.git"
WORK="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$BARE"
git -c init.defaultBranch=main init -q "$WORK"
git -C "$WORK" config core.autocrlf false
git -C "$WORK" config user.email me@local
git -C "$WORK" config user.name Me
git -C "$WORK" remote add origin "$BARE"
mkdir -p "$WORK/core"

entry() { # file von audience description [status] [next]
  local st=""
  [[ -n "${5:-}" ]] && st="  status: $5
"
  [[ -n "${6:-}" ]] && st="$st  next: $6
"
  printf -- '---\nname: %s\ndescription: "%s"\nmetadata:\n  type: project\n  von: %s\n  audience: %s\n  topic: core\n  date: %s\n%s---\n\nbody\n' \
    "$(basename "$1" .md)" "$4" "$2" "$3" "$(date +%Y-%m-%d)" "$st" > "$WORK/$1"
}
entry core/request-open-one.md sam-laptop me-mac "OPEN-ONE asks me something"
entry core/request-answered.md sam-laptop me-mac "ANSWERED-ONE asks me something"
entry core/result-report.md sam-laptop me-mac "REPORT-ONE only informs me"
entry core/request-broadcast.md sam-laptop all "BROADCAST-ONE asks everyone"
entry core/request-mine.md me-mac sam-laptop "MINE-ONE is my own request"
entry core/status-open-note.md sam-laptop me-mac "STATUS-ONE carries status open" open
entry core/status-open-broadcast.md sam-laptop "me-mac, kim-win, sam-desk" "STATUSCAST-ONE status open to three parties" open
entry core/request-closed.md sam-laptop me-mac "CLOSED-ONE was answered in place" answered
entry core/ask-local.md sam-laptop me-mac "LOCAL-ONE uses an instance prefix"
entry core/request-either.md sam-laptop "me-mac, kim-win" "EITHER-ONE asks either of two machines"
# Measured 2026-10-18: a German-named question to two devices, and an open note to several
# parties whose `next:` names us, reached no inbox. Both are requests now.
entry core/frage-to-two.md sam-laptop "me-mac, kim-win" "GERMAN-ONE German file name, two addressees"
entry core/fork-before-cut.md sam-laptop "me-mac, kim-win, person:sam" "NEXT-ONE status open, next names me" open "me-mac, kim-win"
# A THIRD party answers request-either and says so in its own frontmatter.
printf -- '---\nname: x\ndescription: "answer"\nmetadata:\n  type: project\n  von: kim-win\n  audience: sam-laptop\n  topic: core\n  answers: request-either\n---\n\nbody\n' > "$WORK/core/kim-answer.md"
# A fixed date before STATE_SINCE (the runs pass --days, so it never falls out of the window).
D=2026-10-15  # before STATE_SINCE: these cases run the word heuristics of older entries
# A reply closes only the request it NAMES (title text, or `re <start of it>`), never the
# sender as a whole (measured 2026-10-14: one answer about X closed the same sender's open Y).
# So: "ping" and LOGONLY-REPLIED are closed by one reply that names both; LOGONLY-BYNAME by a
# reply to the person's name that carries the title; LOGONLY-TWIN-A by `re …` while TWIN-B of
# the same sender stays open; LOGONLY-UNNAMED stays open behind a reply to its sender that
# names nothing (the old reading closed it — the NEGATIVE CONTROL below proves that).
printf '# Log\n\n## %s · me-mac — AN sam-laptop: answer\n\nSee request-answered: done.\n\n## %s · sam-laptop — AN me-mac: ping\n\nAbout request-open-one again.\n\n## %s · kim-win — AN me-mac: LOGONLY-OPEN please check something\n\nno file behind this one\n\n## %s · sam-laptop — AN me-mac: LOGONLY-REPLIED quick question\n\nno file either\n\n## %s · me-mac — AN sam-laptop: re LOGONLY-REPLIED quick question\n\nanswered in the stream; and re ping: seen.\n\n## %s · ana-win — AN me-mac: LOGONLY-BYNAME a question\n\nno file\n\n## %s · me-mac — AN Anas KI: answer by name\n\nLOGONLY-BYNAME a question: the reply names the person, not the machine id\n\n## %s · sam-laptop — AN me-mac: LOGONLY-TWIN-A first of two\n\nno file\n\n## %s · sam-laptop — AN me-mac: LOGONLY-TWIN-B second of two\n\nno file\n\n## %s · me-mac — AN sam-laptop: re LOGONLY-TWIN-A first\n\nonly the first one is answered here\n\n## %s · kim-win — AN me-mac: LOGONLY-UNNAMED still waiting\n\nno file\n\n## %s · me-mac — AN kim-win: something else entirely\n\nthis names no request of kim-win\n\n## %s · bo-win — AN me-mac: re announce-the-cut — LOGONLY-REREF fork measured, work saved; deleting on the owner'"'"'s word\n\nno file\n\n## %s · me-mac — AN bo-win (status: info): re LOGONLY-REREF fork measured, work saved — thanks\n\nseen\n' "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" > "$WORK/core/LOG.md"
# A request about numbered things is answered by naming the numbers ("Windows #901 OK"), not by
# repeating the title (measured 2026-10-15: answered requests of this shape came back open after the
# naming rule). LOGONLY-NUM closes that way; LOGONLY-NUMPAIR asks for two and the answer names one.
printf '\n## %s · lee-win — AN me-mac: LOGONLY-NUM Windows check core #901 please\n\nno file\n\n## %s · lee-win — AN me-mac: LOGONLY-NUMPAIR check #902 and #903\n\nno file\n\n## %s · me-mac — AN lee-win: Windows #901 OK, #902 OK\n\nmeasured at the head\n' "$D" "$D" "$D" >> "$WORK/core/LOG.md"
git -C "$WORK" add -A
git -C "$WORK" commit -qm seed
git -C "$WORK" push -q origin HEAD:main

OUT="$(SHARED_MEMORY_SELF=me-mac "$PY" "$INBOX" --open --repo "$WORK" --to HEAD --days 100000 2>&1)"
grep -q 'OPEN-ONE' <<<"$OUT" && pass "unanswered request is listed" || fail "unanswered request missing: $OUT"
grep -q 'STATUS-ONE' <<<"$OUT" && pass "status: open counts as a request" || fail "status open missing"
grep -q 'ANSWERED-ONE' <<<"$OUT" && fail "request named in OUR log section still listed" || pass "our answer closes the request"
# The foreign LOG section names request-open-one too — that must NOT count as our answer.
# LOGONLY-REREF: a request that is itself a reply ("re <earlier> — <what>") is answered by
# "re <what>" — measured 2026-10-15: such an answer of 2026-10-14 sat open into the next start.
for x in REPORT-ONE MINE-ONE CLOSED-ONE LOCAL-ONE STATUSCAST-ONE EITHER-ONE LOGONLY-REPLIED LOGONLY-BYNAME LOGONLY-TWIN-A LOGONLY-REREF LOGONLY-NUM\\b; do
  grep -q "$x" <<<"$OUT" && fail "$x must not be listed" || pass "$x not listed"
done
# One reply, one request: the sender's OTHER open request stays listed, and a reply to a sender
# that names nothing closes nothing.
grep -q 'LOGONLY-TWIN-B' <<<"$OUT" && pass "a named reply leaves the sender's other request open" \
  || fail "LOGONLY-TWIN-B swept away by a reply that named only TWIN-A"
grep -q 'LOGONLY-UNNAMED' <<<"$OUT" && pass "a reply that names no request closes none" \
  || fail "LOGONLY-UNNAMED closed by an unnamed reply to its sender"
# Operator order 2026-10-13: a request to everyone reaches everyone — as optional, never as a duty.
grep -a 'BROADCAST-ONE' <<<"$OUT" | grep -aq 'optional: to everyone' \
  && pass "a request to everyone is listed as optional" || fail "broadcast request not listed as optional: $OUT"
grep -q 'LOGONLY-OPEN' <<<"$OUT" && pass "a request that lives only as a LOG heading is listed" || fail "LOG-only request missing"
grep -q 'LOGONLY-NUMPAIR' <<<"$OUT" && pass "an answer naming one of two numbers leaves the request open" \
  || fail "LOGONLY-NUMPAIR closed by an answer that named only #902"
grep -q 'GERMAN-ONE' <<<"$OUT" && pass "a German request word is a default prefix" || fail "German-named request missing"
grep -q 'NEXT-ONE' <<<"$OUT" && pass "status open with next naming us counts, whatever the audience size" \
  || fail "status open + next: us missing"
# OPEN-ONE, STATUS-ONE, LOGONLY-OPEN, BROADCAST-ONE (optional), LOGONLY-TWIN-B, LOGONLY-UNNAMED,
# LOGONLY-NUMPAIR, GERMAN-ONE, NEXT-ONE. sam-laptop's "ping" is closed by our later reply that says "re ping".
grep -q 'open requests to this instance: 9$' <<<"$OUT" && pass "count line says 9" || fail "count line wrong: $(head -1 <<<"$OUT")"
# NEGATIVE CONTROL: the unpatched reader (origin/main before this fix, passed as $1) closed every
# request of a sender with any later reply to that sender — it must FAIL the two checks above.
if [[ -n "${1:-}" ]]; then
  OLD="$(SHARED_MEMORY_SELF=me-mac "$PY" "$1" --open --repo "$WORK" --to HEAD --days 100000 2>&1)"
  grep -q 'LOGONLY-TWIN-B' <<<"$OLD" && fail "control: the old reader also keeps TWIN-B — the planted case proves nothing" \
    || pass "control: the old reader swept TWIN-B away (planted case is real)"
  grep -q 'LOGONLY-UNNAMED' <<<"$OLD" && fail "control: the old reader also keeps UNNAMED — the planted case proves nothing" \
    || pass "control: the old reader closed UNNAMED behind an unnamed reply (planted case is real)"
fi
# NEGATIVE CONTROL 2: a reader without the number rule (passed as $2) keeps LOGONLY-NUM open.
if [[ -n "${2:-}" ]]; then
  OLD2="$(SHARED_MEMORY_SELF=me-mac "$PY" "$2" --open --repo "$WORK" --to HEAD --days 100000 2>&1)"
  grep -q 'LOGONLY-NUM\b' <<<"$OLD2" && pass "control: the reader without the number rule keeps NUM open (planted case is real)" \
    || fail "control: the reader without the number rule also closes NUM — the planted case proves nothing"
fi
# NEGATIVE CONTROL 3: the reader before the request-by-frontmatter fix (passed as $3) shows neither.
if [[ -n "${3:-}" ]]; then
  OLD3="$(SHARED_MEMORY_SELF=me-mac "$PY" "$3" --open --repo "$WORK" --to HEAD --days 100000 2>&1)"
  grep -qE 'GERMAN-ONE|NEXT-ONE' <<<"$OLD3" && fail "control: the old reader already lists GERMAN-ONE/NEXT-ONE — the planted cases prove nothing" \
    || pass "control: the old reader missed GERMAN-ONE and NEXT-ONE (planted cases are real)"
fi

OUT2="$(SHARED_MEMORY_SELF=me-mac SHARED_MEMORY_REQUEST_PREFIXES=ask "$PY" "$INBOX" --open --repo "$WORK" --to HEAD --days 100000 2>&1)"
grep -q 'LOCAL-ONE' <<<"$OUT2" && pass "instance prefix extends the request words" || fail "instance prefix ignored"

OUT3="$("$PY" "$INBOX" --open --repo "$WORK" --to HEAD --self '' 2>&1)"
grep -q 'not checked' <<<"$OUT3" && pass "unset SELF says not checked" || fail "unset SELF silent: $OUT3"

# Clean start: cursor already at HEAD -> one line, never silence; open list still printed.
STATE="$TMP/state.json"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "2026-10-01T00:00:00Z"\n}\n' "$(git -C "$WORK" rev-parse HEAD)" > "$STATE"
CLONE="$TMP/clone"
git clone -q "$BARE" "$CLONE"
OUT4="$(SHARED_MEMORY_SELF=me-mac SHARED_MEMORY_REPO="$CLONE" SHARED_MEMORY_STATE="$STATE" bash "$CHECK" 2>&1)"
grep -q 'nothing new since last start' <<<"$OUT4" && pass "clean start prints a line" || fail "clean start silent: $OUT4"
grep -q 'OPEN-ONE' <<<"$OUT4" && pass "clean start still lists the open request" || fail "open request lost on clean start"

# Cost does not grow with the repo: one git process per file made the session start outgrow
# its hook budget (measured: 264 processes, ~5 s). A `git` shim on PATH counts the calls of
# one --open run, then 40 more entries are added and the count must stay the same.
REAL_GIT="$(command -v git)"
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\necho x >> "%s"\nexec "%s" "$@"\n' "$TMP/git-calls" "$REAL_GIT" > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
count_calls() {
  : > "$TMP/git-calls"
  PATH="$TMP/bin:$PATH" SHARED_MEMORY_SELF=me-mac "$PY" "$INBOX" --open --repo "$WORK" --to HEAD >/dev/null 2>&1
  wc -l < "$TMP/git-calls" | tr -d ' '
}
BEFORE=$(count_calls)
for i in $(seq 1 20); do
  entry "core/result-more-$i.md" sam-laptop me-mac "MORE-$i report to me"
  entry "core/request-more-$i.md" me-mac sam-laptop "MORE-$i my own request"
done
git -C "$WORK" add -A
git -C "$WORK" commit -qm more
AFTER=$(count_calls)
if [[ "$BEFORE" == 0 ]]; then
  echo "SKIP: git shim not used on this platform (process count not measured)"
elif [[ "$AFTER" -le "$BEFORE" ]]; then
  pass "git processes do not grow with the repo ($BEFORE -> $AFTER for +40 files)"
else
  fail "git processes grow with the repo: $BEFORE -> $AFTER for +40 files"
fi

# WRITTEN STATE (from STATE_SINCE on): a LOG request is settled only by its id
# (`<area>/LOG@<date>#<n>`, n = the heading's place that day in that LOG) — a file's `answers:`/`claims:`/`closes:`, or a
# later LOG entry that carries the id. Words no longer settle anything. Own repo, so the
# count line above stays the older entries' measurement.
W2="$TMP/work2"
git -c init.defaultBranch=main init -q "$W2"
git -C "$W2" config core.autocrlf false
git -C "$W2" config user.email me@local
git -C "$W2" config user.name Me
mkdir -p "$W2/ops"
S=2026-10-21
# kim-win: #1 S-OPEN · #2 S-WORDS · #3 S-FILE · #4 S-LOGREF · #5 S-SELFREF · #6 S-DONEHEAD · #7 S-CLOSE ·
# #8 reminder about #5 (info) · #9 its own close of #7. me-mac: #1 a reply in words only · #2 a reply by id.
printf '# Log\n\n## %s · kim-win — AN me-mac: S-OPEN nobody answers\n\nx\n\n## %s · kim-win — AN me-mac: S-WORDS answered in words\n\nx\n\n## %s · kim-win — AN me-mac: S-FILE answered by a file\n\nx\n\n## %s · kim-win — AN me-mac: S-LOGREF answered in the stream by id\n\nx\n\n## %s · kim-win — AN me-mac: S-SELFREF the asker repeats it\n\nx\n\n## %s · kim-win — AN me-mac (status: done): S-DONEHEAD a report\n\nx\n\n## %s · kim-win — AN me-mac: S-CLOSE the asker settles it\n\nx\n\n## %s · kim-win — AN me-mac (status: info): reminder\n\nstill open: ops/LOG@%s#5\n\n## %s · kim-win — AN me-mac (status: done): settled\n\nops/LOG@%s#7 is no longer needed\n\n## %s · me-mac — AN kim-win: re S-WORDS answered in words\n\nhere is the answer, in words only\n\n## %s · me-mac — AN kim-win (status: answered): reply\n\nanswers ops/LOG@%s#4\n' \
  "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" "$S" > "$W2/ops/LOG.md"
# Who may settle by naming the id in the stream (counter-check on #33): an addressee — also another
# device of the addressed person — or the asker with a settled heading; a party that was not asked
# and only mentions the id settles nothing. #12 S-THIRD, #13 lee-win mentions it; #14 S-OTHER,
# #15 me-pc (me-mac's person) answers it.
printf '\n## %s · kim-win — AN me-mac: S-THIRD a party not asked mentions it\n\nx\n\n## %s · lee-win — AN kim-win (status: info): side note\n\nmy work waits on ops/LOG@%s#12\n\n## %s · kim-win — AN me-mac: S-OTHER the addressee answers from another machine\n\nx\n\n## %s · me-pc — AN kim-win (status: answered): reply\n\nanswers ops/LOG@%s#14\n' \
  "$S" "$S" "$S" "$S" "$S" "$S" >> "$W2/ops/LOG.md"
# Claims on a LOG id: #16 S-CLAIMED is claimed by me-mac (stays on my list, marked), #17
# S-CLAIMOTHER by lee-win (leaves my list).
printf '\n## %s · kim-win — AN me-mac, lee-win: S-CLAIMED I took it, not answered yet\n\nx\n\n## %s · kim-win — AN me-mac, lee-win: S-CLAIMOTHER lee took it\n\nx\n' "$S" "$S" >> "$W2/ops/LOG.md"
printf -- '---\nname: claim-mine\ndescription: "claim"\nmetadata:\n  type: project\n  von: me-mac\n  audience: kim-win\n  topic: ops\n  date: %s\n  claims: ops/LOG@%s#16\n---\n\nx\n' "$S" "$S" > "$W2/ops/claim-mine.md"
printf -- '---\nname: claim-lee\ndescription: "claim"\nmetadata:\n  type: project\n  von: lee-win\n  audience: kim-win\n  topic: ops\n  date: %s\n  claims: ops/LOG@%s#17\n---\n\nx\n' "$S" "$S" > "$W2/ops/claim-lee.md"
printf '{"people": {"kim": {"devices": {"kim-win": {"os": "windows"}}}, "lee": {"devices": {"lee-win": {"os": "windows"}}}, "me": {"devices": {"me-mac": {"os": "macos"}, "me-pc": {"os": "windows"}}}}}\n' > "$W2/parties.json"
printf -- '---\nname: reply-s-file\ndescription: "reply"\nmetadata:\n  type: project\n  von: me-mac\n  audience: kim-win\n  topic: ops\n  date: %s\n  status: answered\n  answers: ops/LOG@%s#3\n---\n\nbody\n' "$S" "$S" > "$W2/ops/reply-s-file.md"
git -C "$W2" add -A
git -C "$W2" commit -qm seed
ST="$(SHARED_MEMORY_SELF=me-mac "$PY" "$INBOX" --open --repo "$W2" --to HEAD --days 100000 2>&1)"
grep -q "S-OPEN nobody answers (ops/LOG@$S#1)" <<<"$ST" && pass "a LOG request is printed with its id" || fail "id missing: $ST"
grep -q 'S-WORDS' <<<"$ST" && pass "words no longer settle a request from STATE_SINCE on" || fail "S-WORDS closed by words: $ST"
grep -q 'S-SELFREF' <<<"$ST" && pass "the asker repeating its own id settles nothing" || fail "S-SELFREF closed by a reminder: $ST"
grep -q 'S-THIRD' <<<"$ST" && pass "a party that was not asked and only mentions the id settles nothing" || fail "S-THIRD closed by a bystander: $ST"
grep -q 'claimed by you.*S-CLAIMED' <<<"$ST" && pass "a claim keeps the request on the claimer's list, marked" || fail "own claim lost or unmarked: $ST"
for x in S-FILE S-LOGREF S-DONEHEAD S-CLOSE S-OTHER S-CLAIMOTHER reminder; do
  grep -q "$x" <<<"$ST" && fail "$x must not be listed: $ST" || pass "$x not listed"
done
grep -q 'open requests to this instance: 5$' <<<"$ST" && pass "written state: count line says 5" || fail "written state count: $ST"
# NEGATIVE CONTROL 4: the reader before the written state (passed as $4) prints no id and
# settles S-WORDS by its words — the planted cases are real.
if [[ -n "${4:-}" ]]; then
  OLD4="$(SHARED_MEMORY_SELF=me-mac "$PY" "$4" --open --repo "$W2" --to HEAD --days 100000 2>&1)"
  grep -q 'LOG@' <<<"$OLD4" && fail "control: the old reader already prints ids — the planted case proves nothing" \
    || pass "control: the old reader prints no id (planted case is real)"
  grep -q 'S-WORDS' <<<"$OLD4" && fail "control: the old reader also keeps S-WORDS — the planted case proves nothing" \
    || pass "control: the old reader settled S-WORDS by its words (planted case is real)"
fi

exit $FAIL
