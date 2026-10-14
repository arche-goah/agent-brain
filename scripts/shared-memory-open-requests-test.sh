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

entry() { # file von audience description [status]
  local st=""
  [[ -n "${5:-}" ]] && st="  status: $5
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
# A THIRD party answers request-either and says so in its own frontmatter.
printf -- '---\nname: x\ndescription: "answer"\nmetadata:\n  type: project\n  von: kim-win\n  audience: sam-laptop\n  topic: core\n  answers: request-either\n---\n\nbody\n' > "$WORK/core/kim-answer.md"
# Dates are TODAY: a fixed date falls out of the 30-day window and the test would tip silently.
D=$(date +%Y-%m-%d)
# A reply closes only the request it NAMES (title text, or `re <start of it>`), never the
# sender as a whole (measured 2026-10-14: one answer about X closed the same sender's open Y).
# So: "ping" and LOGONLY-REPLIED are closed by one reply that names both; LOGONLY-BYNAME by a
# reply to the person's name that carries the title; LOGONLY-TWIN-A by `re …` while TWIN-B of
# the same sender stays open; LOGONLY-UNNAMED stays open behind a reply to its sender that
# names nothing (the old reading closed it — the NEGATIVE CONTROL below proves that).
printf '# Log\n\n## %s · me-mac — AN sam-laptop: answer\n\nSee request-answered: done.\n\n## %s · sam-laptop — AN me-mac: ping\n\nAbout request-open-one again.\n\n## %s · kim-win — AN me-mac: LOGONLY-OPEN please check something\n\nno file behind this one\n\n## %s · sam-laptop — AN me-mac: LOGONLY-REPLIED quick question\n\nno file either\n\n## %s · me-mac — AN sam-laptop: re LOGONLY-REPLIED quick question\n\nanswered in the stream; and re ping: seen.\n\n## %s · ana-win — AN me-mac: LOGONLY-BYNAME a question\n\nno file\n\n## %s · me-mac — AN Anas KI: answer by name\n\nLOGONLY-BYNAME a question: the reply names the person, not the machine id\n\n## %s · sam-laptop — AN me-mac: LOGONLY-TWIN-A first of two\n\nno file\n\n## %s · sam-laptop — AN me-mac: LOGONLY-TWIN-B second of two\n\nno file\n\n## %s · me-mac — AN sam-laptop: re LOGONLY-TWIN-A first\n\nonly the first one is answered here\n\n## %s · kim-win — AN me-mac: LOGONLY-UNNAMED still waiting\n\nno file\n\n## %s · me-mac — AN kim-win: something else entirely\n\nthis names no request of kim-win\n' "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" "$D" > "$WORK/core/LOG.md"
git -C "$WORK" add -A
git -C "$WORK" commit -qm seed
git -C "$WORK" push -q origin HEAD:main

OUT="$(SHARED_MEMORY_SELF=me-mac "$PY" "$INBOX" --open --repo "$WORK" --to HEAD 2>&1)"
grep -q 'OPEN-ONE' <<<"$OUT" && pass "unanswered request is listed" || fail "unanswered request missing: $OUT"
grep -q 'STATUS-ONE' <<<"$OUT" && pass "status: open counts as a request" || fail "status open missing"
grep -q 'ANSWERED-ONE' <<<"$OUT" && fail "request named in OUR log section still listed" || pass "our answer closes the request"
# The foreign LOG section names request-open-one too — that must NOT count as our answer.
for x in REPORT-ONE MINE-ONE CLOSED-ONE LOCAL-ONE STATUSCAST-ONE EITHER-ONE LOGONLY-REPLIED LOGONLY-BYNAME LOGONLY-TWIN-A; do
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
# OPEN-ONE, STATUS-ONE, LOGONLY-OPEN, BROADCAST-ONE (optional), LOGONLY-TWIN-B, LOGONLY-UNNAMED.
# sam-laptop's "ping" is closed by our later reply that says "re ping".
grep -q 'open requests to this instance: 6$' <<<"$OUT" && pass "count line says 6" || fail "count line wrong: $(head -1 <<<"$OUT")"
# NEGATIVE CONTROL: the unpatched reader (origin/main before this fix, passed as $1) closed every
# request of a sender with any later reply to that sender — it must FAIL the two checks above.
if [[ -n "${1:-}" ]]; then
  OLD="$(SHARED_MEMORY_SELF=me-mac "$PY" "$1" --open --repo "$WORK" --to HEAD 2>&1)"
  grep -q 'LOGONLY-TWIN-B' <<<"$OLD" && fail "control: the old reader also keeps TWIN-B — the planted case proves nothing" \
    || pass "control: the old reader swept TWIN-B away (planted case is real)"
  grep -q 'LOGONLY-UNNAMED' <<<"$OLD" && fail "control: the old reader also keeps UNNAMED — the planted case proves nothing" \
    || pass "control: the old reader closed UNNAMED behind an unnamed reply (planted case is real)"
fi

OUT2="$(SHARED_MEMORY_SELF=me-mac SHARED_MEMORY_REQUEST_PREFIXES=ask "$PY" "$INBOX" --open --repo "$WORK" --to HEAD 2>&1)"
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

exit $FAIL
