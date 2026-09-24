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
# grep -c prints 0 AND exits 1 on no match, so `|| echo 0` would print a second 0.
runs()  { local n; n=$(grep -c . "$COUNTER" 2>/dev/null); echo "${n:-0}"; }

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

echo "property 7: a lock left behind by a dead run is reaped; a live one is honoured"
# The occasion (2026-09-18): a lock directory outlived its run, and every later session
# replayed an 18 h old red verdict as "another session is measuring now". Each case below
# pairs a lock that MUST be reaped with one that must be left alone.
LK="$CACHED_VERDICT_STATE/verdict-p7.lock"
probe fresh
sh -c 'exit 0' & dead=$!; wait "$dead"
fresh_lock() { rm -rf "$LK"; mkdir -p "$LK"; [ -n "${1:-}" ] && echo "$1" > "$LK/pid"; }
old_lock()   { fresh_lock "${1:-}"; touch -t 202001010000 "$LK"; }

: > "$COUNTER"; fresh_lock "$dead"
out7=$(bash "$CV" p7 --key K -- "$TMP/p.sh")
eq    "dead holder: the check runs" "1" "$(runs)"
has   "dead holder: the reclaim is announced" "reclaiming it" "$out7"
[ -d "$LK" ] && bad "dead holder: lock released after the run" "lock dir still there" \
             || ok "dead holder: lock released after the run"

: > "$COUNTER"; fresh_lock "$$"
out7=$(bash "$CV" p7 --key K2 -- "$TMP/p.sh")
eq    "live holder: the check does NOT run" "0" "$(runs)"
has   "live holder: it says another session is measuring" "another session is measuring" "$out7"
[ "$(cat "$LK/pid" 2>/dev/null)" = "$$" ] && ok "live holder: its lock is left untouched" \
                                          || bad "live holder: its lock is left untouched" "lock gone or rewritten"

: > "$COUNTER"; fresh_lock
bash "$CV" p7 --key K3 -- "$TMP/p.sh" >/dev/null
eq    "pid-less fresh lock (holder mid-claim): honoured" "0" "$(runs)"
: > "$COUNTER"; old_lock
bash "$CV" p7 --key K3 -- "$TMP/p.sh" >/dev/null
eq    "pid-less old lock: reaped" "1" "$(runs)"

# After a reboot the dead holder's PID can be reused by an unrelated live process;
# `kill -0` then says alive forever. The age ceiling is what ends that wedge.
: > "$COUNTER"; old_lock "$$"
bash "$CV" p7 --key K4 -- "$TMP/p.sh" >/dev/null
eq    "live pid but past the age ceiling: reaped" "1" "$(runs)"
rm -rf "$LK"

echo "property 8: a background run's lock names the CHILD, so it is not reaped mid-run"
# The parent returns at once; a lock still naming the parent would read as dead and let
# the very next session start the same work in parallel.
printf '#!/usr/bin/env bash\necho run >> "%s"\nsleep 3\necho slowbg\n' "$COUNTER" > "$TMP/slowbg.sh"
chmod +x "$TMP/slowbg.sh"
: > "$COUNTER"
bash "$CV" p8 --key K --background-on-miss -- "$TMP/slowbg.sh" >/dev/null 2>&1
sleep 0.5
bash "$CV" p8 --key K2 --background-on-miss -- "$TMP/slowbg.sh" >/dev/null 2>&1
sleep 0.5
eq    "second call while the child runs does not start a second run" "1" "$(runs)"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do [ -d "$CACHED_VERDICT_STATE/verdict-p8.lock" ] || break; sleep 0.5; done
[ -d "$CACHED_VERDICT_STATE/verdict-p8.lock" ] && bad "the child releases the lock when done" "lock dir still there" \
                                                || ok "the child releases the lock when done"

echo "property 9: a run cut off by a signal stores nothing; a finished failure still does"
# The occasion (2026-09-24): the session-start hook hit its timeout, TERM landed mid-run,
# and the cleanup trap let the script carry on into the store — one line of output and
# rc 143 became the verdict under the current key. The pid file lets the fixture kill
# the payload itself without pkill, which Git Bash on Windows does not ship.
printf '#!/usr/bin/env bash\necho $$ > "%s/payload.pid"\necho "  ok  first"\nsleep 20\necho "  ok  second"\n' "$TMP" > "$TMP/cut.sh"
chmod +x "$TMP/cut.sh"
wait_pid() { for _ in $(seq 1 30); do [ -s "$TMP/payload.pid" ] && return 0; sleep 0.2; done; return 1; }
cut_off() { # <runner pid>: the group kill a hook timeout delivers, done by hand
  wait_pid; kill -TERM "$1" "$(cat "$TMP/payload.pid")" 2>/dev/null; rm -f "$TMP/payload.pid"
}
seed() { printf 'OLD|%s|0\n' "$(date +%s)" > "$CACHED_VERDICT_STATE/verdict-$1.meta"
         echo "  ok  previous" > "$CACHED_VERDICT_STATE/verdict-$1.out"; }

seed p9f
bash "$CV" p9f --key NEW -- "$TMP/cut.sh" > "$TMP/p9f.out" 2>&1 & fg_pid=$!
cut_off "$fg_pid"; wait "$fg_pid" 2>/dev/null
eq  "foreground cut off: the previous meta is kept" "OLD" "$(cut -d'|' -f1 "$CACHED_VERDICT_STATE/verdict-p9f.meta")"
has "foreground cut off: the previous output is kept" "previous" "$(cat "$CACHED_VERDICT_STATE/verdict-p9f.out")"
has "foreground cut off: it says nothing was stored" "nothing stored" "$(cat "$TMP/p9f.out")"
[ -d "$CACHED_VERDICT_STATE/verdict-p9f.lock" ] && bad "foreground cut off: lock released" "lock dir still there" \
                                                 || ok "foreground cut off: lock released"

seed p9b
bash "$CV" p9b --key NEW --background-on-miss -- "$TMP/cut.sh" >/dev/null 2>&1
wait_pid; child=$(cat "$CACHED_VERDICT_STATE/verdict-p9b.lock/pid" 2>/dev/null)
cut_off "$child"
for _ in $(seq 1 20); do [ -d "$CACHED_VERDICT_STATE/verdict-p9b.lock" ] || break; sleep 0.2; done
eq  "background cut off: the previous meta is kept" "OLD" "$(cut -d'|' -f1 "$CACHED_VERDICT_STATE/verdict-p9b.meta")"
[ -d "$CACHED_VERDICT_STATE/verdict-p9b.lock" ] && bad "background cut off: lock released" "lock dir still there" \
                                                 || ok "background cut off: lock released"

# Counter-check: a run that FINISHES with a failure is a verdict and must be stored.
probe finished 1
seed p9c
bash "$CV" p9c --key NEW -- "$TMP/p.sh" >/dev/null 2>&1
eq  "finished failure: stored under the new key" "NEW|1" \
    "$(cut -d'|' -f1,3 "$CACHED_VERDICT_STATE/verdict-p9c.meta")"

echo
if [ "$fails" -eq 0 ]; then echo "cached-verdict-test: all checks passed"; exit 0; fi
echo "cached-verdict-test: $fails check(s) FAILED"; exit 1
