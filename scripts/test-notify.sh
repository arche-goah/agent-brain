#!/usr/bin/env bash
# covers: notify
# test-notify.sh — the Windows sound branch runs to its end before the hook exits.
# Measured 2026-11-02 on the Windows instance: a spawned-and-unref'd PowerShell child wrote nothing once node
# exited at once (0/3, with and without `detached`); the environment ends the children with the parent, so the
# notification sound never played. The fixture runs the Windows branch with a stand-in command (NOTIFY_WIN_CMD)
# that writes a file after a short delay: the file must exist the moment notify.cjs has exited.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OUT="$(native "$T")/beep.txt"
NOTIFY_WIN_CMD="setTimeout(() => require('fs').writeFileSync('$OUT', 'ok'), 300)" \
  node "$(native "$ROOT/helpers/notify.cjs")" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$T/beep.txt" ]; then
  echo "  OK   the Windows branch ran to its end before notify exited"
  echo "test-notify: all checks passed"; exit 0
fi
echo "  FAIL the Windows branch did not finish before notify exited (rc=$rc, file $( [ -f "$T/beep.txt" ] && echo present || echo missing))"
echo "test-notify: FAILURES"; exit 1
