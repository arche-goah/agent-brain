#!/usr/bin/env bash
# wait-mcp-reconnect.sh <boot-stamp-file> [timeout_s] — block until an MCP server has
# actually come back up, so asking for a reconnect is never a wait state.
#
# WHY (operator 2026-08-06, sharpened 2026-08-14): a tool fix that needs the server
# reloaded used to end the turn — the agent said "needs a restart" and waited for a
# human reply. It must instead arm this watcher in the background (Bash
# run_in_background), keep working, and get re-invoked on exit to run the
# verification itself.
#
# WHY A STAMP FILE AND NOT A PROCESS LOOK-UP: the earlier watcher matched `ps` output
# and compared PID sets. That is neither OS-agnostic (no `ps -o comm=` on Windows) nor
# decidable when a second session runs the same server — a foreign session's PID
# survives every reconnect of this one, so "all old PIDs gone" can never become true
# and the watcher sleeps through the real restart. Reading a file the SERVER writes at
# boot has neither problem: it is one `cat` on every platform, and it reports the
# process that actually serves this session.
#
# THE CONTRACT (this is the agent-brain half; the suite half is the stamp):
#   An MCP server writes, at startup, a small file whose CONTENT changes on every boot
#   (pid + start timestamp is enough) and documents its path. This script snapshots that
#   content and waits for it to change. Content, not mtime: mtime formatting/reading
#   diverges between BSD and GNU (`stat -c/-f`, `date -r`), and that class already broke
#   the bootup once (v1.2.0, PR #27).
#
#   grandma3-suite writes it to  <GMA3_IPC_DIR>/mcp-boot.json  (default ~/.grandma3-mcp).
#   Other suites: see their AGENTS.md. No stamp, no proof — do not fake one from
#   "the tool answers again": a stale server answers too, with the OLD code.
#
# Usage (arm FIRST, then ask the operator for the reconnect):
#   scripts/wait-mcp-reconnect.sh "$HOME/.grandma3-mcp/mcp-boot.json"        # 30 min
#   scripts/wait-mcp-reconnect.sh "$HOME/.grandma3-mcp/mcp-boot.json" 600
#
# Exit: 0 = a fresh server wrote a new stamp · 2 = timed out / never changed (LOUD on
# purpose: "unknown" must never be read as "reconnected") · 3 = usage error.
set -u

STAMP="${1:-}"
TMO="${2:-1800}"
POLL="${MCP_WAIT_POLL:-2}"

if [ -z "$STAMP" ]; then
  echo "usage: wait-mcp-reconnect.sh <boot-stamp-file> [timeout_s]" >&2
  exit 3
fi
case "$TMO" in (*[!0-9]*|'') echo "timeout must be whole seconds, got: $TMO" >&2; exit 3;; esac

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
