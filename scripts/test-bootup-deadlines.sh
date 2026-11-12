#!/usr/bin/env bash
# covers: session-bootup deadlines
# The deadline reporter of helpers/session-bootup.sh, both directions. A deadline entry may carry
# `check: <reading command>` (the ledgers' convention): a passing check means the event happened, so the
# entry is reported DONE and named for deletion, never OVERDUE. Measured 2026-11-04 (macOS instance): a
# coherence scan run two days earlier left its entry untouched, the bootup said OVERDUE, the operator was
# offered a second run. Cases: overdue without check -> OVERDUE; overdue with passing check -> DONE, no
# OVERDUE; failing check -> OVERDUE; a writing check -> refused, file not written, OVERDUE; a check on an
# entry 30 days out is not run (budget).
# Usage: bash scripts/test-bootup-deadlines.sh   (SRC= another session-bootup.sh to judge; exit 0 = pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="${SRC:-$HERE/../helpers/session-bootup.sh}"
BLOCK="$(sed -n '/^if \[\[ -f "\$R\/docs\/business\/deadlines.md" \]\]; then/,/^fi$/p' "$SRC")"
[ -n "$BLOCK" ] || { echo "bootup-deadlines: deadline block not found in $SRC"; exit 1; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# OS-3: python opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
mkdir -p "$T/brain/docs/business" "$T/brain/core/helpers" "$T/brain/core/scripts"
cp "$HERE/ledger-reconcile.py" "$T/brain/core/scripts/ledger-reconcile.py"
fail=0
# OS-17: the bootup probes its interpreter before the block runs; the block alone does not.
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Local dates, as the block uses date.today() (Windows review of #489: UTC dates failed 00:00-01:00 local).
yday="$(date -v-1d +%F 2>/dev/null || date -d '-1 day' +%F)"
later="$(date -v+30d +%F 2>/dev/null || date -d '+30 day' +%F)"
in2="$(date -v+2d +%F 2>/dev/null || date -d '+2 day' +%F)"
in5="$(date -v+5d +%F 2>/dev/null || date -d '+5 day' +%F)"
run() { # name, deadlines text, expect-substring, forbid-substring
  printf '%b' "$2" > "$T/brain/docs/business/deadlines.md"
  local out; out="$(cd "$T/brain" && R="$(native "$T/brain")" HERE="$(native "$T/brain/core/helpers")" PY="$PY" bash -c "$BLOCK" 2>&1)"
  if [[ "$out" == *"$3"* ]] && { [ -z "$4" ] || [[ "$out" != *"$4"* ]]; }; then echo "  OK  $1"; else echo "  FAIL $1 (got: ${out:0:160})"; fail=1; fi
}
: > "$T/brain/exists.txt"
run "overdue, no check -> OVERDUE"            "## $yday — a plain entry\n\ntext\n" "deadline OVERDUE" ""
run "overdue, passing check -> DONE, not OVERDUE" "## $yday — a scan that ran\n\ncheck: test -f exists.txt\n" "DONE by its check" "OVERDUE"
run "overdue, failing check -> OVERDUE"       "## $yday — a scan that did not run\n\ncheck: test -f missing.txt\n" "deadline OVERDUE" "DONE"
run "a writing check is refused -> OVERDUE"   "## $yday — a trap\n\ncheck: echo x > written.txt\n" "deadline OVERDUE" "DONE"
[ -f "$T/brain/written.txt" ] && { echo "  FAIL the refused check wrote a file"; fail=1; } || echo "  OK  the refused check wrote nothing"
run "far entry: check not run, reported as next" "## $later — far away\n\ncheck: test -f exists.txt\n" "deadlines: next" "DONE"
run "two entries: the done one steps aside"   "## $yday — done one\n\ncheck: test -f exists.txt\n\n## $later — next one\n\ntext\n" "deadlines: next $later" "OVERDUE"
d2="$(date -v-2d +%F 2>/dev/null || date -d '-2 day' +%F)"
run "two overdue: the later one is reported too" "## $d2 — first overdue\n\ntext\n\n## $yday — second overdue\n\ntext\n" "OVERDUE by 1 d: $yday" ""
run "two overdue: the earlier one stays reported" "## $d2 — first overdue\n\ntext\n\n## $yday — second overdue\n\ntext\n" "OVERDUE by 2 d: $d2" ""
run "overdue plus a future entry: the next one follows" "## $yday — overdue\n\ntext\n\n## $later — next one\n\ntext\n" "deadlines: next $later" ""
# two entries inside the 7-day band: both named (Windows review of #489, finding 1)
run "two soon: the second one is named too" "## $in2 — soon one\n\ntext\n\n## $in5 — soon two\n\ntext\n" "$in5 in 5 d" ""
run "two soon: the first one stays named" "## $in2 — soon one\n\ntext\n\n## $in5 — soon two\n\ntext\n" "$in2 in 2 d" ""
[ "$fail" = 0 ] && echo "bootup-deadlines: all cases pass" || { echo "bootup-deadlines: FAILURES"; exit 1; }
