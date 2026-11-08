#!/usr/bin/env bash
# session-order.sh — a session says in ONE sentence what it was ordered to do; parallel-sessions.sh shows it.
#
# WHY (measured 2026-11-07 on the macOS instance): a session handed its open points to "the main session", picked
# the one with the longest run time - it worked only on 3D printing - and that one passed them on again. The session
# list named pid, cwd and start time, never the order. Released by the operator 2026-11-08 (question tool).
#
# Usage:
#   session-order.sh set "<one sentence>"   — write this session's order (the claude process this shell runs under)
#   session-order.sh show <pid>             — print the order of that session, or nothing
# State: <repo>/.claude-state/session-orders/<pid> = "<YYYY-MM-DD HH:MM> <sentence>"; <repo> = CLAUDE_PROJECT_DIR,
# else the git top level of the cwd. A file whose pid no longer runs is stale and removed on the next `set`.
# Test seam: SESSION_ORDER_PID names the session instead of walking up the process tree.
set -u
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
dir="$root/.claude-state/session-orders"

own_pid() {   # the nearest ancestor process named claude
  [ -n "${SESSION_ORDER_PID:-}" ] && { printf '%s' "$SESSION_ORDER_PID"; return 0; }
  local p=$$ comm
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    comm=$(ps -o comm= -p "$p" 2>/dev/null)
    case "$comm" in *claude|*claude.exe) printf '%s' "$p"; return 0 ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
  done
  return 1
}

case "${1:-}" in
  set)
    shift
    text="$*"
    [ -n "$text" ] || { echo "session-order: give the order as one sentence" >&2; exit 2; }
    pid=$(own_pid) || { echo "session-order: no claude process above this shell - not run from a session" >&2; exit 2; }
    mkdir -p "$dir"
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      kill -0 "$(basename "$f")" 2>/dev/null || [ "$(basename "$f")" = "$pid" ] || rm -f "$f"
    done
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M')" "$(printf '%s' "$text" | tr '\n' ' ')" > "$dir/$pid"
    echo "session-order: pid $pid — $text"
    ;;
  show)
    [ -n "${2:-}" ] && [ -f "$dir/$2" ] && head -1 "$dir/$2"
    exit 0
    ;;
  *)
    echo "usage: session-order.sh set \"<one sentence>\" | show <pid>" >&2
    exit 2
    ;;
esac
