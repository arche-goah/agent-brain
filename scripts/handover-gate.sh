#!/usr/bin/env bash
# Pre-handover gate — everything that must be true before a suite goes to someone else.
#
# WHY a local script and not CI: the shared repos are private and there is no enforceable
# merge gate on a personal GitHub account. This script IS the gate — both sides run the
# SAME file out of the core checkout (submodule), not a copy each. Declaring a CI step
# that only echoes would be worse: a green tick that checks nothing.
#
# Layout since the core/instance split:
#   CORE     = the brain-core checkout this script lives in (usually <instance>/core)
#   INSTANCE = the private brain: carries config/ecosystem.json, .claude/skills,
#              dependencies.json. Run this from the instance root, or set BRAIN_DIR.
#
# Checks, in order of what they catch:
#   1. contract   — suite-check.py over every suite in the instance's ecosystem.json
#   2. deps       — dep-lint.py --strict over the instance
#   3. skills     — skill-lint.py over the instance
#   4. leaks      — leak-scan.py in every suite AND over the core checkout itself
#   5. state      — ecosystem drift (uncommitted or unpushed work anywhere)
#
# Exit 0 = safe to hand over. Any non-zero = read the output, nothing is implied fixed.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTANCE="${BRAIN_DIR:-$PWD}"
cd "$INSTANCE" || exit 1

if [ ! -f "$INSTANCE/config/ecosystem.json" ]; then
  echo "handover-gate: no config/ecosystem.json under $INSTANCE"
  echo "  Run from the instance root (the private brain), or set BRAIN_DIR."
  exit 1
fi

fail=0
step() { printf '\n=== %s\n' "$1"; }
note() { printf '  %s\n' "$1"; }

# encoding is not optional: without it Python uses the platform codepage, and on
# Windows a single non-cp1252 byte in ecosystem.json kills this read with
# UnicodeDecodeError — measured 2026-08-04, the gate died before check 1.
suites=$(python3 -c "
import json,pathlib
d=json.loads(pathlib.Path('config/ecosystem.json').read_text(encoding='utf-8'))
print(' '.join(e['path'] for e in d['repos'].values() if e.get('kind')=='suite'))")

step "1. contract (suite-check)"
if [ -z "$suites" ]; then
  # An instance may legitimately carry no suite repos (a brain with only core).
  # suite-check.py without paths exits 2 on its own usage error — that is an empty
  # ecosystem, not a contract breach.
  note "no suite repos in config/ecosystem.json — nothing to check"
else
  # shellcheck disable=SC2086
  python3 "$CORE/scripts/suite-check.py" $suites || fail=1
fi

step "2. dependencies (dep-lint --strict)"
python3 "$CORE/scripts/dep-lint.py" --strict || fail=1

step "3. skills (skill-lint)"
python3 "$CORE/scripts/skill-lint.py" || fail=1

step "4. leaks"
for s in $suites; do
  s="${s/#\~/$HOME}"
  if [ -f "$s/scripts/leak-scan.py" ]; then
    out=$(cd "$s" && python3 scripts/leak-scan.py) || fail=1
    note "$(basename "$s"): $out"
  else
    note "$(basename "$s"): NO leak-scan.py — contract violation"; fail=1
  fi
done
note "core checkout:"
out=$(cd "$CORE" && python3 scripts/leak-scan.py) || fail=1
note "  $out"

step "5. state (ecosystem drift)"
python3 "$CORE/scripts/ecosystem-sync.py" || fail=1

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "handover-gate: PASS"
else
  echo "handover-gate: FAIL — nothing above is fixed automatically"
fi
exit "$fail"
