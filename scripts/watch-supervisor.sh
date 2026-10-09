#!/usr/bin/env bash
# watch-supervisor.sh — keep a watcher running and, above all, SAY when it stopped.
#
#   watch-supervisor.sh <label> <command> [args ...]
#
# WHY (measured on the proving instance): a watcher process was gone while its Monitor task
# still reported `running`; nothing announced the death and the session believed it was
# covered for over an hour. A dead watcher and a quiet one look identical from outside.
# This cannot make a process immortal — it makes its death VISIBLE (one stdout line = one
# notification) and gives it another go, with a doubling backoff.
#
# PORTABLE TEARDOWN: the supervisor owns its child. On TERM/INT/EXIT it kills the child
# itself, so the caller only has to kill supervisors. The earlier shape relied on
# `pkill -P <supervisor>`, which Git Bash on Windows does not ship — and killing the
# supervisor FIRST re-parents the payload to init, after which `pkill -P` finds nothing and
# reports success while the payload keeps polling with nobody listening.
set -uo pipefail

LABEL="${1:?usage: $0 <label> <command> [args ...]}"; shift
[[ $# -gt 0 ]] || { echo "ERROR: no command given"; exit 64; }

# Injectable only so the fixture can prove the restart without waiting 15 s; nothing in
# production sets it.
BACKOFF_START="${WATCH_SUPERVISOR_BACKOFF:-15}"
delay="$BACKOFF_START"
restarts=0
PARENT=$PPID
child=""
stop_child() { [[ -n "$child" ]] && kill "$child" 2>/dev/null; child=""; }
trap 'stop_child; exit 0' TERM INT
trap 'stop_child' EXIT

while true; do
  start=$(date +%s)
  "$@" &
  child=$!
  wait "$child"; rc=$?
  child=""
  ran=$(( $(date +%s) - start ))
  restarts=$((restarts + 1))
  # A child that survived a while was healthy: its death is a one-off, the backoff restarts.
  if [[ "$ran" -ge 300 ]]; then delay="$BACKOFF_START"; fi
  # No parent, no restart: an orphaned supervisor would revive its payload forever for a
  # session that no longer exists.
  kill -0 "$PARENT" 2>/dev/null || exit 0
  # The counter is in the line on purpose: identical lines get collapsed upstream, and the
  # SECOND death is the one worth knowing about.
  echo "WATCHER-DIED: $LABEL exited rc=$rc after ${ran}s — restart #$restarts in ${delay}s"
  sleep "$delay" & wait $!     # backgrounded so a TERM is handled at once, not after the sleep
  kill -0 "$PARENT" 2>/dev/null || exit 0
  if [[ "$delay" -lt 480 ]]; then delay=$((delay * 2)); fi
done
