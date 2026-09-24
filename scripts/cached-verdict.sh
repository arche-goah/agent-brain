#!/usr/bin/env bash
# cached-verdict.sh — run an expensive check at most once per machine per key/window,
# and make the REUSE visible.
#
# THE OCCASION, measured 2026-09-13 on a full brain: `session-bootup.sh` took 102.5 s
# against a 30 s hook timeout, so it was killed at every session start — 41 times across
# 33 transcripts since 2026-08-21, the last one at the start of the session that found
# it. The first lines of the summary arrive, the `brain-check` line never does. A carrier
# that never delivers looks exactly like one with nothing to report, which is why it went
# unnoticed for three weeks on two different machines and two operating systems.
#
# THE SECOND OCCASION, operator order the same day: collaborators start several sessions
# in parallel and many per day. Today every one of them repeats the identical work on the
# same machine, which is what turns a slow check into "the PC dies on me".
#
# WHAT KEY, AND WHY IT IS NOT ALWAYS TIME. The question is never "how often may this run"
# but "what would have to change for this check to answer differently":
#
#   * FOREIGN state (marketplace pins, suite tags, open PRs, shared-memory commits)
#     changes because someone else acted. Nothing local predicts it, so time is the only
#     key available — use `--max-age`.
#   * OWN CONTENT (a fixture suite over scripts that only depend on a commit and the
#     tooling) has an exact key. A time window is wrong in BOTH directions here: 24 h is
#     too long right after a core update, which is the one moment the answer can change,
#     and too short when nothing changed for a week. Use `--key`.
#
# Both may be combined; the entry is reused only if key AND age both allow it.
#
# NON-NEGOTIABLE: a reused verdict says so, with its age and key. Silence that reads as
# green is the exact defect this script exists because of — rebuilding it here would be
# absurd.
#
# usage:
#   cached-verdict.sh <name> [--key <k>] [--max-age <s>] [--background-on-miss] -- <cmd...>
#
# exit code: the stored or freshly measured exit code of <cmd>. On a background miss the
# exit code is that of the LAST completed run (0 if there is none) — the run in flight
# reports at the next start.
set -uo pipefail

NAME=""; KEY="-"; MAX_AGE=0; BG=0
NAME="${1:?usage: $0 <name> [--key k] [--max-age s] [--background-on-miss] -- <cmd...>}"; shift
while [ $# -gt 0 ]; do
  case "$1" in
    --key) KEY="${2:?--key needs a value}"; shift 2 ;;
    --max-age) MAX_AGE="${2:?--max-age needs seconds}"; shift 2 ;;
    --background-on-miss) BG=1; shift ;;
    --) shift; break ;;
    *) echo "cached-verdict: unknown option $1" >&2; exit 64 ;;
  esac
done
[ $# -gt 0 ] || { echo "cached-verdict: no command given" >&2; exit 64; }

case "$NAME" in
  ""|*/*|*..*) echo "cached-verdict: bad name '$NAME'" >&2; exit 64 ;;
esac

STATE_DIR="${CACHED_VERDICT_STATE:-.claude-state}"
mkdir -p "$STATE_DIR" 2>/dev/null || true
OUT="$STATE_DIR/verdict-$NAME.out"
META="$STATE_DIR/verdict-$NAME.meta"
LOCK="$STATE_DIR/verdict-$NAME.lock"

now() { date +%s; }

# Portable age formatting — no `date -d`/`date -r` (BSD and GNU disagree, and Git Bash
# brings GNU while macOS does not; core register OS-agnostic carriers).
human_age() {
  local s="$1"
  if   [ "$s" -lt 90 ];    then echo "${s}s"
  elif [ "$s" -lt 5400 ];  then echo "$((s / 60))m"
  else echo "$((s / 3600))h"
  fi
}

read_meta() { # sets M_KEY M_AT M_RC; returns 1 if unreadable
  [ -f "$META" ] || return 1
  # shellcheck disable=SC2034
  IFS='|' read -r M_KEY M_AT M_RC < "$META" || return 1
  [ -n "${M_AT:-}" ] || return 1
  case "$M_AT" in (*[!0-9]*) return 1 ;; esac
  return 0
}

emit_cached() { # <reason>
  local age; age=$(( $(now) - M_AT ))
  [ -f "$OUT" ] && cat "$OUT"
  echo "   (reused: $1, measured $(human_age "$age") ago, key ${M_KEY:0:12})"
  return "${M_RC:-0}"
}

fresh_enough() {
  read_meta || return 1
  [ "$M_KEY" = "$KEY" ] || return 1
  if [ "$MAX_AGE" -gt 0 ]; then
    [ $(( $(now) - M_AT )) -le "$MAX_AGE" ] || return 1
  fi
  return 0
}

if fresh_enough; then
  emit_cached "unchanged"
  exit $?
fi

# The lock is a DIRECTORY: mkdir is atomic on every filesystem we run on, unlike a
# test-then-touch on a file, which two sessions starting together will both win.
# Per machine, not per session — that is the point.
#
# A lock whose holder is gone is REAPED, not honoured. Before this, a run killed without
# its EXIT trap firing (SIGKILL, sleep-then-shutdown, a hook timeout that takes the whole
# process group) left the directory behind, and every later session printed "another
# session is measuring now" and replayed the verdict of the dead run — measured
# 2026-09-18 on a real brain: an 18 h old red fixture verdict, no measuring process
# alive, re-served at every start. Same answer the shared-memory watcher already gives
# (a PID in the lock, `kill -0`), plus an age ceiling, because after a reboot the dead
# holder's PID can belong to some unrelated process and `kill -0` alone would keep the
# wedge. The holder writes an owner token next to the PID so that a run which outlived
# the ceiling and got reaped does not delete its successor's lock on the way out.
# Accepted residue: two sessions that find the same corpse in the same instant can both
# reap it and both measure. The cost is one duplicate run, never a wedge — and the lock
# exists to save work, not to guard correctness (a re-run stores the same verdict).
LOCK_MAX_MIN="${CACHED_VERDICT_LOCK_MAX_MIN:-60}"
TOKEN="$$-$(now)-${RANDOM:-0}"
lock_is_stale() {
  local pid
  # `find -mmin` rather than `stat`/`date -r`: BSD and GNU agree on it.
  [ -n "$(find "$LOCK" -maxdepth 0 -mmin +"$LOCK_MAX_MIN" 2>/dev/null)" ] && return 0
  pid=$(cat "$LOCK/pid" 2>/dev/null)
  if [ -z "$pid" ]; then
    # Between mkdir and the pid write a live holder has no pid yet. Only a pid-less lock
    # older than a minute is a corpse.
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +1 2>/dev/null)" ]
    return
  fi
  ! kill -0 "$pid" 2>/dev/null
}
release_lock() {
  [ "$(cat "$LOCK/token" 2>/dev/null)" = "$TOKEN" ] && rm -rf "$LOCK"
  return 0
}
claim_lock() {
  mkdir "$LOCK" 2>/dev/null || return 1
  echo "$TOKEN" > "$LOCK/token"
  echo "$$" > "$LOCK/pid"
}
if ! claim_lock && lock_is_stale; then
  echo "   (a previous run left its lock behind and is gone — reclaiming it)"
  rm -rf "$LOCK"
  claim_lock || true
fi
if [ "$(cat "$LOCK/token" 2>/dev/null)" != "$TOKEN" ]; then
  # Someone else is measuring right now. Do not queue and do not duplicate the work:
  # report what we have, clearly marked, and let their run land for the next start.
  if read_meta; then
    emit_cached "another session is measuring now; this is the previous result"
    exit $?
  fi
  echo "   (skipped: another session is measuring this right now, and there is no previous result yet)"
  exit 0
fi
# A signal only MARKS the run; the lock goes on EXIT. A trap that merely cleans up lets bash
# carry on after it — measured 2026-09-24: the session-start hook was killed at its 30 s
# timeout, TERM reached the fixture run and this script alike, the handler released the
# lock, and execution continued into the store: one line of output with rc 143, filed
# under the CURRENT key as if it were the answer. Every later start replayed that red
# verdict as "unchanged" and named no failing check, because none had failed.
INTERRUPTED=0
trap release_lock EXIT
trap 'INTERRUPTED=1' INT TERM HUP

# Capture and store, then REPLAY to stdout. Capturing without replaying would make a
# fresh run silent while a cached one talks — the caller would see output only when
# nothing had been measured, which is the inversion this whole script exists to prevent.
# The fixture caught exactly that on the first run.
run_and_store() {
  local tmp rc
  tmp="$OUT.$$"
  "$@" > "$tmp" 2>&1
  rc=$?
  # An interrupted run measured nothing. Storing it would turn "cut off" into "failed" and
  # keep it for as long as the key holds; keeping the previous verdict and re-measuring at
  # the next call is the honest answer.
  if [ "$INTERRUPTED" -eq 1 ]; then
    rm -f "$tmp"
    echo "   (interrupted before it finished — nothing stored, the next call measures again)"
    return "$rc"
  fi
  mv -f "$tmp" "$OUT" 2>/dev/null || true
  printf '%s|%s|%s\n' "$KEY" "$(now)" "$rc" > "$META"
  [ -f "$OUT" ] && cat "$OUT"
  return "$rc"
}

if [ "$BG" -eq 1 ]; then
  # Detach, and hand the lock to the child: the parent's EXIT trap must not remove a lock
  # the background run still holds, or a second session starts the same work seconds later.
  trap - EXIT INT TERM HUP
  (
    trap release_lock EXIT
    trap 'INTERRUPTED=1' INT TERM HUP
    run_and_store "$@"
  ) >/dev/null 2>&1 &
  # The holder is now the child, so the lock must name the child — the parent exits in a
  # moment and a parent PID would read as a dead holder while the work is still running.
  echo "$!" > "$LOCK/pid"
  if read_meta; then
    emit_cached "out of date, re-measuring in the background; this is the previous result"
    exit $?
  fi
  echo "   (measuring in the background for the first time — the verdict lands at the next session start)"
  exit 0
fi

run_and_store "$@"
exit $?
