#!/usr/bin/env bash
# Fixture test for scripts/clock-skew.py — both directions, no network.
# The must-report case is the incident (2026-10-09): the clock two hours behind.
# Must stay silent: within the threshold, an unreachable reference (offline is no finding).
# Usage: bash scripts/test-clock-skew.sh (exit 0 = pass)
set -u
S="$(cd "$(dirname "$0")" && pwd)/clock-skew.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
httpdate() { "$PY" -c 'import email.utils,sys,time; print(email.utils.formatdate(time.time()+float(sys.argv[1]), usegmt=True))' "$1"; }

run() { CLOCK_SKEW_REFERENCE="$(httpdate "$1")" "$PY" "$S" 2>&1; }

out="$(run 7200)"   # reference is two hours AHEAD of us: we are behind
case "$out" in *'!! clock:'*'120 min behind'*) ok "two hours behind is reported";; *) bad "two hours behind: '$out'";; esac
out="$(run -600)"
case "$out" in *'!! clock:'*'ahead of'*) ok "ten minutes ahead is reported";; *) bad "ten minutes ahead: '$out'";; esac
out="$(run 30)"
[ -z "$out" ] && ok "30 s off stays silent" || bad "30 s off reported: '$out'"
out="$("$PY" "$S" --url http://127.0.0.1:9/ --timeout 1 2>&1)"; rc=$?
[ -z "$out" ] && [ "$rc" = 0 ] && ok "unreachable reference stays silent, exit 0" || bad "unreachable: rc=$rc '$out'"

# negative control: a script that never reports must fail the must-report case
printf 'import sys\nsys.exit(0)\n' > "${TMPDIR:-/tmp}/clock-noop-$$.py"
out="$(CLOCK_SKEW_REFERENCE="$(httpdate 7200)" "$PY" "${TMPDIR:-/tmp}/clock-noop-$$.py" 2>&1)"
rm -f "${TMPDIR:-/tmp}/clock-noop-$$.py"
[ -z "$out" ] && ok "no-op stub misses the incident (control)" || bad "control printed '$out'"

[ "$fail" = 0 ] && echo "clock-skew: all checks passed" || echo "clock-skew: FAILURES"
exit "$fail"
