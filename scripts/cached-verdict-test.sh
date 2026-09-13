#!/usr/bin/env bash
# Fixture for cached-verdict.sh. Every property gets an input that MUST trigger it and
# one that must stay silent — a guard that only ever fires, or never does, proves nothing.
#
# The properties worth proving are the ones the occasion was made of: a reused verdict
# must SAY it was reused (silence reading as green is the defect this exists because of),
# a content key must beat a time window in both directions, and two sessions starting at
# the same moment must do the work once.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CV="$HERE/cached-verdict.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export CACHED_VERDICT_STATE="$TMP/state"

ok()   { echo "  ok   $1"; }
bad()  { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2] in output" ;; esac; }
hasnt(){ case "$3" in *"$2"*) bad "$1" "unexpected [$2] in output" ;; *) ok "$1" ;; esac; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "expected [$2], got [$3]"; }

# A command that records every execution, so "did it run again?" is a measurement and not
# an inference from the output text.
COUNTER="$TMP/runs"
: > "$COUNTER"
probe() { printf '#!/usr/bin/env bash\necho run >> "%s"\necho "payload %s"\nexit %s\n' "$COUNTER" "$1" "${2:-0}" > "$TMP/p.sh"; chmod +x "$TMP/p.sh"; }
runs()  { grep -c . "$COUNTER" 2>/dev/null || echo 0; }

echo "property 1: same key -> the work happens once, and the reuse is announced"
probe first
out1=$(bash "$CV" p1 --key K1 -- "$TMP/p.sh"); rc1=$?
out2=$(bash "$CV" p1 --key K1 -- "$TMP/p.sh"); rc2=$?
eq    "first run executes" "1" "$(runs)"
has   "first run shows the payload" "payload first" "$out1"
hasnt "first run does not claim reuse" "reused" "$out1"
eq    "second run does NOT execute again" "1" "$(runs)"
has   "second run announces the reuse" "(reused: unchanged" "$out2"
has   "the reuse names its key" "key K1" "$out2"
eq    "exit code survives the cache" "$rc1" "$rc2"

echo "property 2: a CHANGED key re-runs, a stale time window alone does not save it"
# This is the half a 24 h stamp gets wrong: right after a core update the answer CAN
# change, and that is exactly when a fresh timestamp would skip the run.
out3=$(bash "$CV" p1 --key K2 --max-age 86400 -- "$TMP/p.sh")
eq    "changed key forces a re-run even inside a 24 h window" "2" "$(runs)"
hasnt "and it is not reported as reused" "reused" "$out3"

echo "property 3: an expired window re-runs, a live one does not"
probe second
: > "$COUNTER"
bash "$CV" p3 --max-age 3600 -- "$TMP/p.sh" >/dev/null
bash "$CV" p3 --max-age 3600 -- "$TMP/p.sh" >/dev/null
eq    "inside the window: one execution" "1" "$(runs)"
bash "$CV" p3 --max-age 0 -- "$TMP/p.sh" >/dev/null   # 0 = no time limit, key '-' matches
eq    "no time limit and unchanged key: still one" "1" "$(runs)"
# Backdate the stored measurement past the window instead of sleeping through it.
printf '%s|%s|%s\n' "-" "$(( $(date +%s) - 7200 ))" "0" > "$CACHED_VERDICT_STATE/verdict-p3.meta"
out4=$(bash "$CV" p3 --max-age 3600 -- "$TMP/p.sh")
eq    "expired window re-runs" "2" "$(runs)"
hasnt "a re-run is not announced as reuse" "reused" "$out4"

echo "property 4: a failing check keeps failing from the cache"
# A cached verdict that quietly returns 0 would be the original defect with extra steps.
probe broken 3
: > "$COUNTER"
bash "$CV" p4 --key K -- "$TMP/p.sh" >/dev/null; first_rc=$?
out5=$(bash "$CV" p4 --key K -- "$TMP/p.sh"); second_rc=$?
eq "the failure is reported the first time" "3" "$first_rc"
eq "and the SAME failure comes back from the cache" "3" "$second_rc"
eq "without running again" "1" "$(runs)"
has "the cached failure still shows its output" "payload broken" "$out5"

echo "property 5: two sessions starting together do the work once"
printf '#!/usr/bin/env bash\necho run >> "%s"\nsleep 2\necho slow\n' "$COUNTER" > "$TMP/slow.sh"
chmod +x "$TMP/slow.sh"
: > "$COUNTER"
bash "$CV" p5 --key K -- "$TMP/slow.sh" > "$TMP/a.out" 2>&1 &
A=$!
bash "$CV" p5 --key K -- "$TMP/slow.sh" > "$TMP/b.out" 2>&1 &
B=$!
wait "$A" "$B" 2>/dev/null || true
eq "the payload ran once, not twice" "1" "$(runs)"
both="$(cat "$TMP/a.out" "$TMP/b.out")"
has "the session that lost the lock says so" "another session is measuring" "$both"

echo "property 6: --background-on-miss does not block, and the next call sees the result"
probe bg
: > "$COUNTER"
bash "$CV" p6 --key B1 --background-on-miss -- "$TMP/p.sh" > "$TMP/bg1.out" 2>&1
has "first background miss says the verdict lands next time" "background for the first time" "$(cat "$TMP/bg1.out")"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$CACHED_VERDICT_STATE/verdict-p6.meta" ] && break; sleep 0.3; done
out6=$(bash "$CV" p6 --key B1 --background-on-miss -- "$TMP/p.sh")
has  "the next call serves the finished verdict" "payload bg" "$out6"
has  "and marks it as reused" "(reused: unchanged" "$out6"
eq   "the background run executed exactly once" "1" "$(runs)"

echo "property 7: a lock left behind by a crashed run does not wedge the check forever"
# Not yet true — recorded as a known limit rather than asserted as a pass. A stale lock
# directory currently makes every later session report the previous verdict instead of
# measuring. It is visible (the line says another session is measuring) rather than
# silent, which is why this ships as a limit and not as a blocker.
echo "  --   known limit: a stale lock directory is reported, not reaped (see header)"

echo
if [ "$fails" -eq 0 ]; then echo "cached-verdict-test: all checks passed"; exit 0; fi
echo "cached-verdict-test: $fails check(s) FAILED"; exit 1
