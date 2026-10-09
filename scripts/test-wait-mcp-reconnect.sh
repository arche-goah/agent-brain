#!/usr/bin/env bash
# Fixture for scripts/wait-mcp-reconnect.sh. Both directions in both modes:
#   stamp:   a changed stamp is a reconnect; an unchanged one times out LOUD (exit 2); an
#            absent stamp at arm time is refused at once, unless --allow-absent.
#   process: all old pids gone + a new match is a restart; a SHRINKING set is not; no
#            match at arm time is refused; a match that is not a child of the session's
#            parent does not count. Skipped (said so) where pgrep/ps cannot see servers.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/wait-mcp-reconnect.sh"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
expect() {  # expect <title> <want-rc> <got-rc> <needle> <output>
  if [ "$3" -eq "$2" ] && case "$5" in *"$4"*) true ;; *) false ;; esac; then ok "$1"
  else bad "$1" "rc=$3 (want $2): $(printf '%s' "$5" | tr '\n' ' ' | cut -c1-200)"; fi
}

T="$(mktemp -d)"
PIDS=""
cleanup() { [ -n "$PIDS" ] && kill $PIDS 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
export MCP_WAIT_POLL=1

echo "stamp mode"
echo "boot-1" > "$T/stamp"
( sleep 2; echo "boot-2" > "$T/stamp" ) &
out="$(bash "$S" "$T/stamp" 15 2>&1)"; rc=$?
expect "a new stamp is a reconnect" 0 "$rc" "RECONNECT DETECTED" "$out"

out="$(bash "$S" "$T/stamp" 2 2>&1)"; rc=$?
expect "negative control: an unchanged stamp times out with exit 2" 2 "$rc" "TIMEOUT" "$out"

SECONDS=0
out="$(bash "$S" "$T/no-stamp" 30 2>&1)"; rc=$?
expect "an absent stamp is refused" 3 "$rc" "REFUSED" "$out"
[ "$SECONDS" -lt 5 ] && ok "refused at once, not after the timeout" || bad "refused at once" "${SECONDS}s"

( sleep 2; echo "first" > "$T/new-stamp" ) &
out="$(bash "$S" --allow-absent "$T/new-stamp" 15 2>&1)"; rc=$?
expect "--allow-absent: the first stamp ever written counts" 0 "$rc" "RECONNECT DETECTED" "$out"

out="$(bash "$S" 2>&1)"; rc=$?
expect "no argument is a usage error" 3 "$rc" "usage" "$out"
out="$(bash "$S" "$T/stamp" soon 2>&1)"; rc=$?
expect "a non-numeric timeout is a usage error" 3 "$rc" "whole seconds" "$out"

echo "process mode"
if ! command -v pgrep >/dev/null 2>&1 || command -v cygpath >/dev/null 2>&1; then
  out="$(bash "$S" --process anything 5 2>&1)"; rc=$?
  expect "without POSIX pgrep the mode refuses instead of guessing" 3 "$rc" "REFUSED" "$out"
  echo "  SKIP restart cases — pgrep/ps cannot see native servers here"
else
  MARK="wmr-fixture-$$-srv"
  srv() { bash -c "sleep 60; : $MARK-$1" & PIDS="$PIDS $!"; }
  export MCP_WAIT_PARENT=$$

  srv a; A=$!
  bash "$S" --process "$MARK" 20 > "$T/out1" 2>&1 & W=$!
  sleep 2; { kill "$A"; wait "$A"; } 2>/dev/null; srv b
  wait "$W"; rc=$?
  expect "all old pids gone + a new one = restart" 0 "$rc" "RESTART DETECTED" "$(cat "$T/out1")"

  srv c; C=$!; srv d
  sleep 1
  bash "$S" --process "$MARK" 4 > "$T/out2" 2>&1 & W=$!
  sleep 1; { kill "$C"; wait "$C"; } 2>/dev/null
  wait "$W"; rc=$?
  expect "negative control: a shrinking set is not a restart" 2 "$rc" "TIMEOUT" "$(cat "$T/out2")"

  { kill $PIDS; wait $PIDS; } 2>/dev/null; PIDS=""; sleep 1
  out="$(bash "$S" --process "$MARK" 5 2>&1)"; rc=$?
  expect "no match at arm time is refused" 3 "$rc" "REFUSED" "$out"

  # a matching process that is NOT a child of the session parent (double fork)
  ( bash -c "sleep 60; : $MARK-orphan" & echo $! > "$T/orphan" ) ; PIDS="$(cat "$T/orphan")"
  out="$(bash "$S" --process "$MARK" 5 2>&1)"; rc=$?
  expect "a foreign session's match does not count" 3 "$rc" "REFUSED" "$out"
fi

echo
if [ "$fails" -eq 0 ]; then echo "test-wait-mcp-reconnect: all checks passed"; exit 0; fi
echo "test-wait-mcp-reconnect: $fails check(s) FAILED"; exit 1
