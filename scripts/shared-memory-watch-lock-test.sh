#!/usr/bin/env bash
# Negative control for the ARM LOCK of shared-memory-watch.sh.
#
# The find path already has a proof (shared-memory-watch-test.sh). The lock had none,
# and that is exactly where it failed: two sessions on one machine both armed, `status`
# showed one of them, and the invisible one kept polling the same cursor.
#
# Three properties. Property 3 is the actual negative control — it is the one the
# unfixed script FAILS; 1 and 2 pass either way and are kept as regression guards.
#   1. RACE      — N sessions arming at once leave exactly ONE watcher running
#   2. STALE     — a lock whose owner died is claimable again, not a permanent block
#   3. OWNERSHIP — an exiting watcher never deletes a lock that names someone else
#
# Usage: shared-memory-watch-lock-test.sh [path-to-watch.sh]   (exit 0 = all pass)
#
# The path argument stays, because the negative control needs to run this against an
# UNPATCHED copy. But it defaults to the sibling script: the fixture runners discover
# suites by name and call them with no arguments, so a fixture that insists on an
# argument is a fixture that fails under its own runner (measured 2026-08-31 — the
# widened discovery in this repo executes every `*-test.sh` it finds, argument-less).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WATCH="${1:-$HERE/shared-memory-watch.sh}"
[ -f "$WATCH" ] || { echo "SKIP: no watch script at $WATCH"; exit 0; }
N=8

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BARE="$TMP/remote.git"; WORK="$TMP/work"
git -c init.defaultBranch=main init -q --bare "$BARE"
git -c init.defaultBranch=main init -q "$WORK"
git -C "$WORK" config core.autocrlf false
git -C "$WORK" config user.email me@local
git -C "$WORK" config user.name Me
git -C "$WORK" remote add origin "$BARE"
printf 'one\n' > "$WORK/a.md"
git -C "$WORK" add -A; git -C "$WORK" commit -qm first; git -C "$WORK" push -q -u origin main
git -C "$WORK" rev-parse origin/main >/dev/null 2>&1 || { echo "SETUP FAILED: sandbox has no origin/main"; exit 1; }

STATE="$TMP/state.json"
printf '{\n  "lastSeenSha": "%s",\n  "lastCheckedAt": "x"\n}\n' "$(git -C "$WORK" rev-parse HEAD)" > "$STATE"
export SHARED_MEMORY_REPO="$WORK" SHARED_MEMORY_STATE="$STATE" SHARED_MEMORY_LOCK_DIR="$TMP/lock"

fail=0

# --- property 1: RACE -------------------------------------------------------
# All N start from one `wait` on the same FIFO, so they hit the lock inside the same
# few milliseconds. Staggered starts would pass even with the broken lock.
# The barrier is a flag FILE all of them spin on, not a fifo: a fifo pairs one reader
# with one writer, so N readers and N writers can pair up in an order that deadlocks —
# measured here, the first version of this test hung before a single watcher started.
GATE="$TMP/go"
pids=()
for i in $(seq 1 $N); do
  ( while [ ! -f "$GATE" ]; do :; done; exec bash "$WATCH" watch 60 > "$TMP/out.$i" 2>&1 ) &
  pids+=($!)
done
sleep 1
: > "$GATE"
sleep 3

alive=0
for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=$((alive+1)); done
skipped=$(grep -l 'skipping duplicate watcher' "$TMP"/out.* 2>/dev/null | wc -l | tr -d ' ')
echo "--- race: $N armed simultaneously -> alive=$alive, refused=$skipped"
if [[ "$alive" -eq 1 ]]; then echo "PASS: exactly one watcher survived"
else echo "FAIL: $alive watchers running (expected 1) — duplicates poll the same cursor"; fail=1; fi
if [[ "$skipped" -eq $((N-1)) ]]; then echo "PASS: the other $((N-1)) refused with a reason"
else echo "FAIL: $skipped refusals (expected $((N-1))) — a session armed without saying so"; fail=1; fi

# `-a`: this grep reads a REPORT line. Git Bash decides a stream is binary on the first
# odd byte and then prints "Binary file (standard input) matches" INSTEAD of the line —
# the pid would come back empty and the check would fail for a reason that has nothing
# to do with the lock (OS-5 in docs/os-traps.md).
STATUS_PID=$(bash "$WATCH" status | grep -ao '[0-9]*' | head -1)
still=0; for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && still="$p"; done
if [[ -n "$STATUS_PID" ]] && kill -0 "$STATUS_PID" 2>/dev/null; then echo "PASS: status names a LIVE pid ($STATUS_PID)"
else echo "FAIL: status names pid '$STATUS_PID', which is not running"; fail=1; fi

for p in "${pids[@]}"; do { kill "$p"; wait "$p"; } 2>/dev/null || true; done

# --- property 2: STALE ------------------------------------------------------
# A watcher killed hard (-9) never runs its trap. The next arm must clear the corpse.
bash "$WATCH" watch 60 > "$TMP/out.stale1" 2>&1 &
V=$!; sleep 2
kill -9 "$V" 2>/dev/null; wait "$V" 2>/dev/null || true
bash "$WATCH" watch 60 > "$TMP/out.stale2" 2>&1 &
W=$!; sleep 2
echo "--- stale: owner killed with -9, next session arms"
if kill -0 "$W" 2>/dev/null && ! grep -q 'skipping duplicate' "$TMP/out.stale2"; then
  echo "PASS: stale lock reclaimed"
else
  echo "FAIL: stale lock blocks every later session"; cat "$TMP/out.stale2"; fail=1
fi
{ kill "$W"; wait "$W"; } 2>/dev/null || true

# --- property 3: OWNERSHIP (the measured failure) ---------------------------
# Real sequence, 2026-08-20: a watcher from an earlier session exited LATE, after a
# newer session had claimed the lock. Its EXIT trap removed that lock, `status` then
# said "not armed", and a second watcher was armed on the same cursor.
# Reproduced deterministically: let A arm, hand the lock to a live foreign pid, then
# let A exit normally so its trap runs.
bash "$WATCH" watch 60 > "$TMP/out.own" 2>&1 &
A=$!; sleep 2
LOCKFILE=$(ls "$TMP/lock"/shared-memory-watch.* 2>/dev/null | head -1)
if [[ -z "$LOCKFILE" ]]; then echo "SETUP FAILED: no lock created by the watcher"; exit 1; fi
echo $$ > "$LOCKFILE"          # a LIVE pid that is not A — the newer session
{ kill "$A"; wait "$A"; } 2>/dev/null || true
sleep 1
echo "--- ownership: watcher exits while the lock names another live session"
if [[ -e "$LOCKFILE" ]] && [[ "$(cat "$LOCKFILE" 2>/dev/null)" == "$$" ]]; then
  echo "PASS: foreign lock survived the exit"
else
  echo "FAIL: exiting watcher deleted a lock it did not own — next session arms a duplicate"; fail=1
fi

echo "--- verdict"; [[ $fail -eq 0 ]] && echo "ALL PASSED" || echo "FAILURES ABOVE"
exit "$fail"
