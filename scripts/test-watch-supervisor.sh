#!/usr/bin/env bash
# covers: watch-supervisor.sh
# Fixture for scripts/watch-supervisor.sh, three properties:
#   1. FIRES    a child that exits produces a WATCHER-DIED line (with rc) and is restarted
#   2. SILENT   a child that keeps running produces NO death line — a false alarm would
#               train the reader to ignore the real one
#   3. CLEANUP  killing the supervisor kills its child too, without pkill (absent in Git
#               Bash on Windows) — otherwise the payload polls on with nobody listening
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUP="$HERE/watch-supervisor.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
pass() { echo "  ok   $1"; }
flunk() { echo "  FAIL $1"; fail=1; }
export WATCH_SUPERVISOR_BACKOFF=1   # only shortens the wait; proves the same restart

echo "1. dying child"
printf '#!/usr/bin/env bash\necho "child alive"\nexit 3\n' > "$T/dies.sh"
bash "$SUP" test-dies bash "$T/dies.sh" > "$T/out.dies" 2>&1 &
P=$!
sleep 4
kill "$P" 2>/dev/null; wait "$P" 2>/dev/null
# grep -c prints 0 AND exits 1 on no match: never append an `|| echo 0` (two-line value).
DEATHS=$(grep -c '^WATCHER-DIED:' "$T/out.dies") || true
STARTS=$(grep -c '^child alive$' "$T/out.dies") || true
[[ "$DEATHS" -ge 1 ]] && pass "death announced" || flunk "watcher died silently ($(cat "$T/out.dies"))"
[[ "$STARTS" -ge 2 ]] && pass "child restarted" || flunk "child started $STARTS time(s)"
grep -q 'rc=3' "$T/out.dies" && pass "exit code in the line" || flunk "exit code missing"

echo "2. healthy child"
printf '#!/usr/bin/env bash\necho $$ > "%s"\nwhile true; do sleep 1; done\n' "$T/child.pid" > "$T/lives.sh"
bash "$SUP" test-lives bash "$T/lives.sh" > "$T/out.lives" 2>&1 &
Q=$!
sleep 3
QUIET=$(grep -c '^WATCHER-DIED:' "$T/out.lives") || true
[[ "$QUIET" -eq 0 ]] && pass "healthy child announced nothing" || flunk "false death report"

echo "3. killing the supervisor takes the child with it"
CHILD=$(cat "$T/child.pid" 2>/dev/null)
kill -0 "$CHILD" 2>/dev/null && pass "child running before the kill (control)" || flunk "child never ran"
kill "$Q" 2>/dev/null; wait "$Q" 2>/dev/null
gone=0
for _ in 1 2 3 4 5 6; do kill -0 "$CHILD" 2>/dev/null || { gone=1; break; }; sleep 1; done
[[ $gone -eq 1 ]] && pass "child gone after supervisor TERM" || { flunk "child survived its supervisor"; kill "$CHILD" 2>/dev/null; }

echo "4. child that declines the channel (exit 0 right away, 'already armed') is not restarted"
# Measured 2026-10-15 (Windows) and 2026-10-16 (macOS): a second arm while the first still ran
# produced a restart loop — every child skipped with rc=0, every supervisor revived it.
printf '#!/usr/bin/env bash\necho "already armed: lock names live pid 1"\nexit 0\n' > "$T/skips.sh"
bash "$SUP" test-skips bash "$T/skips.sh" > "$T/out.skips" 2>&1 &
R=$!
sleep 4
kill "$R" 2>/dev/null; wait "$R" 2>/dev/null
SKIPS=$(grep -c '^WATCHER-SKIPPED:' "$T/out.skips") || true
SKIPSTARTS=$(grep -c '^already armed' "$T/out.skips") || true
SKIPDEATHS=$(grep -c '^WATCHER-DIED:' "$T/out.skips") || true
[[ "$SKIPS" -eq 1 ]] && pass "skip announced once" || flunk "skip lines: $SKIPS ($(cat "$T/out.skips"))"
[[ "$SKIPSTARTS" -eq 1 ]] && pass "child started once, not restarted" || flunk "child started $SKIPSTARTS time(s)"
[[ "$SKIPDEATHS" -eq 0 ]] && pass "no death line for a skip" || flunk "a skip was reported as a death"
# Control: a child that dies with rc!=0 at once is still a death (case 1 covers it, rc=3).

echo
[[ $fail -eq 0 ]] && echo "test-watch-supervisor: all checks passed" || echo "test-watch-supervisor: FAILURES above"
exit "$fail"
