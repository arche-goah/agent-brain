#!/usr/bin/env bash
# wait-mcp-reconnect.sh — block until an MCP server has actually come back up, so asking
# for a reconnect is never a wait state.
#
#   wait-mcp-reconnect.sh [--allow-absent] <boot-stamp-file> [timeout_s]   (the proof)
#   wait-mcp-reconnect.sh --process <pattern> [timeout_s]                  (POSIX fallback)
#
# WHY (operator 2026-08-06, sharpened 2026-08-14): a tool fix that needs the server
# reloaded used to end the turn — the agent said "needs a restart" and waited for a
# human reply. It must instead arm this watcher in the background (Bash
# run_in_background), keep working, and get re-invoked on exit to run the
# verification itself. Arm FIRST, then ask for the reconnect.
#
# STAMP MODE — the proof. An MCP server writes, at startup, a small file whose CONTENT
# changes on every boot (pid + start timestamp is enough) and documents its path in its
# AGENTS.md (grandma3-suite: <GMA3_IPC_DIR>/mcp-boot.json). This script snapshots the
# content and waits for it to change. Content, not mtime: mtime formatting diverges
# between BSD and GNU (`stat -c/-f`, `date -r`), and that class broke the bootup once
# (v1.2.0, PR #27). Reading a file the SERVER writes is one `cat` on every platform and
# reports the process that actually serves this session.
#   A stamp that is ABSENT at arm time is refused (exit 3): a watcher without a starting
# state cannot prove a change, and the absent case is almost always a wrong path or a
# server that writes no stamp — waiting 30 minutes to learn that is the wait state this
# script exists to remove. `--allow-absent` is for the one legitimate case: the first
# boot of a server that has just gained its stamp.
#
# PROCESS MODE — the fallback for a server that writes no stamp yet; POSIX only (pgrep,
# ps). Never "it answers again": a stale server answers too, with the OLD code. A restart
# is proven when NONE of the pids seen at arm time is alive and at least one new match
# is. Lessons it carries, each measured on the proving instance:
#   - only children of THIS session's claude process count — a second session runs the
#     same server, its pid survives every reconnect here, and "all old pids gone" never
#     becomes true (override the parent with MCP_WAIT_PARENT=<pid>, 0 = no filter);
#   - a shrinking match set is not a restart (three matches, two vanish: the server
#     itself still runs on old code);
#   - an empty match set at arm time is refused, not waited on: the first transient
#     match (the agent's own tool chain) would otherwise read as "restarted".
# On Windows this mode refuses: Git Bash sees only its own processes, never the native
# server — there the stamp is the only proof, and a server without one is the finding.
#
# Exit: 0 = the server came back (fresh stamp / new process) · 2 = timed out — LOUD on
# purpose: "unknown" must never be read as "reconnected" · 3 = usage error or refused.
set -u

POLL="${MCP_WAIT_POLL:-2}"
usage() {
  echo "usage: wait-mcp-reconnect.sh [--allow-absent] <boot-stamp-file> [timeout_s]" >&2
  echo "       wait-mcp-reconnect.sh --process <pattern> [timeout_s]" >&2
  exit 3
}
MODE=stamp ALLOW_ABSENT=0
case "${1:-}" in
  --allow-absent) ALLOW_ABSENT=1; shift ;;
  --process) MODE=process; shift ;;
esac
TARGET="${1:-}"
TMO="${2:-1800}"
[ -n "$TARGET" ] || usage
case "$TMO" in (*[!0-9]*|'') echo "timeout must be whole seconds, got: $TMO" >&2; exit 3;; esac

if [ "$MODE" = stamp ]; then
  STAMP="$TARGET"
  if [ ! -f "$STAMP" ] && [ "$ALLOW_ABSENT" -ne 1 ]; then
    echo "REFUSED: no boot stamp at $STAMP — nothing to compare against." >&2
    echo "  Check the path in the server's AGENTS.md. A server that writes no stamp cannot be" >&2
    echo "  waited on (that missing carrier is the finding); first boot of a new stamp:" >&2
    echo "  --allow-absent." >&2
    exit 3
  fi
  read_stamp() { cat "$STAMP" 2>/dev/null || printf '<absent>'; }
  before="$(read_stamp)"
  echo "waiting for MCP reconnect — stamp: $STAMP (timeout ${TMO}s)"
  echo "  before: $(printf '%s' "$before" | tr -d '\n' | cut -c1-200)"
  SECONDS=0
  while [ "$SECONDS" -lt "$TMO" ]; do
    now="$(read_stamp)"
    if [ "$now" != "$before" ]; then
      echo "RECONNECT DETECTED after ${SECONDS}s — the server wrote a new boot stamp"
      echo "  after: $(printf '%s' "$now" | tr -d '\n' | cut -c1-200)"
      exit 0
    fi
    sleep "$POLL"
  done
  echo "TIMEOUT after ${TMO}s — the stamp at $STAMP never changed." >&2
  echo "Do NOT read this as reconnected: either no reconnect happened, or that server" >&2
  echo "does not write a boot stamp (then the missing carrier is the finding)." >&2
  exit 2
fi

# --- process mode ---------------------------------------------------------------------
PATTERN="$TARGET"
if ! command -v pgrep >/dev/null 2>&1 || ! command -v ps >/dev/null 2>&1 \
   || command -v cygpath >/dev/null 2>&1; then
  echo "REFUSED: process mode needs POSIX pgrep/ps that see the server — not available here." >&2
  echo "  Only a boot stamp proves a reconnect on this platform." >&2
  exit 3
fi

own_claude() {  # the claude process this shell descends from (MCP servers are its children)
  local p=$$ comm
  while [ "${p:-0}" -gt 1 ] 2>/dev/null; do
    comm="$(ps -o comm= -p "$p" 2>/dev/null | tr -d ' ')"
    case "$comm" in *claude*) echo "$p"; return 0 ;; esac
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
  return 1
}
PARENT="${MCP_WAIT_PARENT-}"
[ -n "$PARENT" ] || PARENT="$(own_claude || true)"
[ "$PARENT" = 0 ] && PARENT=""

pids_of() {  # matching pids, one per line, sorted; children of PARENT only when set
  pgrep -f -- "$PATTERN" 2>/dev/null | while IFS= read -r p; do
    [ "$p" = "$$" ] && continue
    if [ -z "$PARENT" ] || [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$PARENT" ]; then
      echo "$p"
    fi
  done | sort -n
  return 0
}
in_set() { case "
$2
" in *"
$1
"*) return 0 ;; esac; return 1; }

OLD="$(pids_of)"
if [ -n "$PARENT" ]; then
  echo "session filter: only children of pid $PARENT"
else
  echo "WARNING: no session filter (own claude pid not found or MCP_WAIT_PARENT=0) — every match counts, foreign sessions included" >&2
fi
if [ -z "$OLD" ]; then
  echo "REFUSED: '$PATTERN' matches no process right now — nothing to observe." >&2
  echo "  running candidates:" >&2
  ps ax -o pid,command 2>/dev/null | grep -aiE 'mcp|server\.py|index\.ts' | grep -av grep | sed 's/^/    /' >&2
  exit 3
fi
echo "waiting for restart of '$PATTERN' (pid(s) $(echo $OLD), timeout ${TMO}s)"

SECONDS=0
while [ "$SECONDS" -lt "$TMO" ]; do
  NEW="$(pids_of)"
  if [ -n "$NEW" ]; then
    survivors="$(printf '%s\n' "$OLD" | while IFS= read -r p; do in_set "$p" "$NEW" && echo "$p"; done)"
    if [ -z "$survivors" ]; then
      echo "RESTART DETECTED after ${SECONDS}s: pid(s) $(echo $OLD) -> $(echo $NEW)"
      exit 0
    fi
  fi
  sleep "$POLL"
done
echo "TIMEOUT after ${TMO}s — no restart (still running: $(echo $OLD))." >&2
exit 2
