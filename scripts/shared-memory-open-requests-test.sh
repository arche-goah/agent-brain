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
printf '# Log\n\n## %s · me-mac — AN sam-laptop: answer\n\nSee request-answered: done.\n\n## %s · sam-laptop — AN me-mac: ping\n\nAbout request-open-one again.\n\n## %s · kim-win — AN me-mac: LOGONLY-OPEN please check something\n\nno file behind this one\n\n## %s · sam-laptop — AN me-mac: LOGONLY-REPLIED quick question\n\nno file either\n\n## %s · me-mac — AN sam-laptop: reply\n\nanswered in the stream\n' "$D" "$D" "$D" "$D" "$D" > "$WORK/core/LOG.md"
git -C "$WORK" add -A
git -C "$WORK" commit -qm seed
git -C "$WORK" push -q origin HEAD:main

OUT="$(SHARED_MEMORY_SELF=me-mac "$PY" "$INBOX" --open --repo "$WORK" --to HEAD 2>&1)"
grep -q 'OPEN-ONE' <<<"$OUT" && pass "unanswered request is listed" || fail "unanswered request missing: $OUT"
grep -q 'STATUS-ONE' <<<"$OUT" && pass "status: open counts as a request" || fail "status open missing"
grep -q 'ANSWERED-ONE' <<<"$OUT" && fail "request named in OUR log section still listed" || pass "our answer closes the request"
# The foreign LOG section names request-open-one too — that must NOT count as our answer.
for x in REPORT-ONE BROADCAST-ONE MINE-ONE CLOSED-ONE LOCAL-ONE STATUSCAST-ONE EITHER-ONE LOGONLY-REPLIED; do
  grep -q "$x" <<<"$OUT" && fail "$x must not be listed" || pass "$x not listed"
done
grep -q 'LOGONLY-OPEN' <<<"$OUT" && pass "a request that lives only as a LOG heading is listed" || fail "LOG-only request missing"
# OPEN-ONE, STATUS-ONE, LOGONLY-OPEN. sam-laptop's "ping" is closed by our later "reply" to sam-laptop.
grep -q 'open requests to this instance: 3$' <<<"$OUT" && pass "count line says 3" || fail "count line wrong: $(head -1 <<<"$OUT")"

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

exit $FAIL
