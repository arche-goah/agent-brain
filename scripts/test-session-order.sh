#!/usr/bin/env bash
# covers: session-order
# Fixture for scripts/session-order.sh: a session writes its order in one sentence, show reads it back, a stale file
# of a pid that no longer runs is removed on the next set, and an empty sentence is refused.
# Usage: bash scripts/test-session-order.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/session-order.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export CLAUDE_PROJECT_DIR; CLAUDE_PROJECT_DIR="$(native "$T")"   # OS-3: a path crossing into another process goes native

SESSION_ORDER_PID=$$ bash "$S" set "only heavy-metal: bench and firmware" >/dev/null
got=$(bash "$S" show $$)
case "$got" in *"only heavy-metal: bench and firmware") ok "set then show returns the sentence";; *) bad "show: '$got'";; esac
case "$got" in 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ *) ok "the line carries its date";; *) bad "no date: '$got'";; esac

[ -z "$(bash "$S" show 999999)" ] && ok "unknown pid shows nothing" || bad "unknown pid printed something"

mkdir -p "$T/.claude-state/session-orders"
echo "2026-01-01 00:00 old" > "$T/.claude-state/session-orders/999998"
SESSION_ORDER_PID=$$ bash "$S" set "generic main session" >/dev/null
[ ! -e "$T/.claude-state/session-orders/999998" ] && ok "a stale file of a dead pid is removed on set" || bad "stale file kept"
case "$(bash "$S" show $$)" in *"generic main session") ok "set replaces the own order";; *) bad "own order not replaced";; esac

SESSION_ORDER_PID=$$ bash "$S" set "" >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "an empty sentence is refused (rc 2)" || bad "empty sentence rc=$rc"

[ "$fail" -eq 0 ] && echo "session-order: all checks passed" || echo "session-order: FAILED"
exit "$fail"
