#!/bin/bash
# loop-watchdog.sh — external heartbeat guard for autonomous Claude loops (F9).
# Problem (memory autonomous-means-never-stop + SOTA research): ScheduleWakeup
# lives IN the session — if the session dies, the wakeup dies silently. This
# watchdog runs outside (launchd) and reports when a loop marked "running" stops
# writing its heartbeat.
#
# Contract (deliberately simple, file-based like the rig):
#   Loop on:    scripts/loop-watchdog.sh arm "<name>" <max-silence-minutes>
#   Heartbeat:  scripts/loop-watchdog.sh beat      (on every loop step)
#   Loop off:   scripts/loop-watchdog.sh disarm
#   Check:      scripts/loop-watchdog.sh check     (launchd, every 5 min)
# State: .claude-state/loop-watchdog.state (not in git).
set -euo pipefail
cd "$(dirname "$0")/.."
STATE_DIR=".claude-state"
STATE="$STATE_DIR/loop-watchdog.state"
mkdir -p "$STATE_DIR"

notify() {  # macOS notification + log; Telegram deliberately NOT wired (rig chain stays separate)
  osascript -e "display notification \"$1\" with title \"Claude Loop-Watchdog\"" 2>/dev/null || true
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$STATE_DIR/loop-watchdog.log"
}

hm() {  # epoch -> HH:MM. `date -r` means TWO things: BSD takes seconds, GNU takes a FILE
        # (--reference) — on GNU every epoch failed with "No such file" (measured on
        # Git Bash 2026-08-08, PR #27 thread), and under `set -e` above that ended
        # every arm/beat/disarm call. Hence both forms, GNU fallback `-d @<epoch>`.
  date -r "$1" '+%H:%M' 2>/dev/null || date -d "@$1" '+%H:%M' 2>/dev/null || echo '??:??'
}

# State lines: 1=name 2=max-silence-min 3=last-beat-ts 4=start-ts 5=deadline-ts(0=open)
#              6=core-done (0/1)
# Lines 4/5 were added 2026-08-02: until then the watchdog had NO idea how long a run
# was supposed to last — so "2h autonomous" could end after 54 min without anything
# firing. Line 6 (operator directive 2026-08-02): the DURATION IS A MINIMUM, NOT A CAP.
# As long as the CORE TASK is still running, overrunning it is correct and must not
# trigger an alarm — the deadline alarm only fires once the core has been reported
# DONE and is still running anyway.
case "${1:-check}" in
  arm)
    dur="${4:-0}"                      # minimum runtime in minutes, 0 = no deadline
    now=$(date +%s)
    dl=0; [ "$dur" -gt 0 ] 2>/dev/null && dl=$(( now + dur * 60 ))
    printf '%s\n%s\n%s\n%s\n%s\n%s\n' "${2:?name missing}" "${3:-30}" "$now" "$now" "$dl" "0" > "$STATE"
    if [ "$dl" -gt 0 ]; then
      echo "armed: ${2} (max ${3:-30} min silence, runtime ${dur} min, end $(hm "$dl"))"
    else
      echo "armed: ${2} (max ${3:-30} min silence, NO deadline)"
    fi ;;
  beat)
    [ -f "$STATE" ] || { echo "no armed loop — beat ignored"; exit 0; }
    cd_flag=$(sed -n 6p "$STATE" 2>/dev/null || echo 0); cd_flag=${cd_flag:-0}
    { head -2 "$STATE"; date +%s; sed -n '4p;5p' "$STATE"; echo "$cd_flag"; } > "$STATE.tmp" \
      && mv "$STATE.tmp" "$STATE"
    "$0" remaining ;;
  core-done)
    # Marks: the CORE TASK is done. Only from now on is the deadline binding
    # (before that, overrunning is correct, see header). After this: remaining
    # time -> reserve pool.
    [ -f "$STATE" ] || { echo "no loop armed"; exit 0; }
    { head -5 "$STATE"; echo "1"; } > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
    echo "core task marked DONE"
    "$0" remaining ;;
  remaining)
    # IMPORTANT for the autonomous run: query after EVERY work step and only stop
    # once this reads 0 — not once the task list merely looks empty.
    [ -f "$STATE" ] || { echo "no loop armed"; exit 0; }
    dl=$(sed -n 5p "$STATE" 2>/dev/null || echo 0); dl=${dl:-0}
    start=$(sed -n 4p "$STATE" 2>/dev/null || echo 0); start=${start:-0}
    el=$(( ( $(date +%s) - start ) / 60 ))
    cd_flag=$(sed -n 6p "$STATE" 2>/dev/null || echo 0); cd_flag=${cd_flag:-0}
    core=$([ "$cd_flag" = "1" ] && echo "core DONE" || echo "core RUNNING")
    if [ "$dl" -le 0 ]; then
      echo "runtime ${el} min, no minimum time — end = once the tasks are through (${core})"
      exit 0
    fi
    rem=$(( ( dl - $(date +%s) ) / 60 ))
    [ "$rem" -lt 0 ] && rem=0
    echo "runtime ${el} min, REST ${rem} min until minimum time (end $(hm "$dl")), ${core}"
    # note '|| true': under 'set -e' a false [ ] would end the whole call with exit 1 —
    # and with it every 'beat' that calls remaining (found in self-test)
    { [ "$rem" -eq 0 ] && [ "$cd_flag" = "1" ] \
        && echo "-> MINIMUM TIME REACHED + CORE DONE: wrap up and disarm"; } || true
    { [ "$rem" -eq 0 ] && [ "$cd_flag" != "1" ] \
        && echo "-> minimum time reached, but CORE STILL OPEN: KEEP WORKING (duration is a floor, not a ceiling)"; } || true ;;
  disarm)
    if [ -f "$STATE" ]; then
      start=$(sed -n 4p "$STATE" 2>/dev/null || echo 0); start=${start:-0}
      name=$(sed -n 1p "$STATE")
      if [ "$start" -gt 0 ]; then
        el=$(( ( $(date +%s) - start ) / 60 ))
        # the TIME PROOF: measured runtime, not estimated (lesson 2026-08-02)
        echo "disarmed: '$name' ran $(hm "$start") -> $(date '+%H:%M') = ${el} min"
        echo "$(date '+%Y-%m-%d %H:%M:%S') loop '$name' ended after ${el} min" >> "$STATE_DIR/loop-watchdog.log"
      else echo "disarmed"; fi
      rm -f "$STATE"
    else echo "no loop armed"; fi ;;
  check)
    [ -f "$STATE" ] || exit 0
    name=$(sed -n 1p "$STATE"); maxmin=$(sed -n 2p "$STATE"); last=$(sed -n 3p "$STATE")
    dl=$(sed -n 5p "$STATE" 2>/dev/null || echo 0); dl=${dl:-0}
    silent=$(( ( $(date +%s) - last ) / 60 ))
    if [ "$silent" -ge "$maxmin" ]; then
      notify "Loop '$name' silent for ${silent} min (limit ${maxmin}) — session presumably dead."
      mv "$STATE" "$STATE.stale"   # only ONE notification, no spam (lesson netwatch v2)
    elif [ "$dl" -gt 0 ] && [ "$(date +%s)" -ge "$dl" ] \
         && [ "$(sed -n 6p "$STATE" 2>/dev/null || echo 0)" = "1" ]; then
      # second alarm class: minimum time up, CORE reported DONE — and still running
      # anyway. With an OPEN core, overrunning is correct and deliberately stays quiet.
      notify "Loop '$name': minimum time up and core done, but still running — check."
      mv "$STATE" "$STATE.stale"
    fi ;;
  status)
    if [ -f "$STATE" ]; then
      echo "armed: $(sed -n 1p "$STATE"), last beat $(( ( $(date +%s) - $(sed -n 3p "$STATE") ) / 60 )) min ago"
      "$0" remaining
    else echo "no loop armed"; fi ;;
  *) echo "usage: $0 {arm <name> <max-silence-min> [runtime-min]|beat|remaining|disarm|check|status}"; exit 2 ;;
esac
