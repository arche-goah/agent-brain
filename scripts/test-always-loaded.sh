#!/usr/bin/env bash
# Fixture for scripts/always-loaded.py — silent at baseline and within slack, loud after creep
# past the ACCEPTED baseline (also when it came in small steps), silent again after --accept.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
run() { "$PY" "$HERE/always-loaded.py" --repo "$T/b" --memory "$T/MEMORY.md" "$@"; }
grow() { head -c "$2" /dev/zero | tr '\0' 'x' >> "$1"; }

mkdir -p "$T/b/.claude/rules" "$T/b/core/rules"
grow "$T/b/CLAUDE.md" 1000; grow "$T/b/.claude/rules/a.md" 500; grow "$T/b/core/rules/c.md" 500; grow "$T/MEMORY.md" 300

out=$(run); [[ -z "$out" && -f "$T/b/.claude-state/always-loaded.json" ]] && ok "first-run-silent-baseline-created" || bad "first-run-silent-baseline-created: $out"
grow "$T/b/CLAUDE.md" 1500
out=$(run); [[ -z "$out" ]] && ok "within-slack-silent" || bad "within-slack-silent: $out"
grow "$T/b/.claude/rules/a.md" 1000
out=$(run); grep -q 'grew 2300 -> 4800 bytes (+2500)' <<< "$out" && ok "creep-in-steps-loud" || bad "creep-in-steps-loud: $out"
grow "$T/MEMORY.md" 10
out=$(run); grep -q '+2510' <<< "$out" && ok "memory-index-counted" || bad "memory-index-counted: $out"
out=$(run --accept); grep -q 'baseline set: 4810' <<< "$out" && ok "accept-sets-baseline" || bad "accept-sets-baseline: $out"
out=$(run); [[ -z "$out" ]] && ok "after-accept-silent" || bad "after-accept-silent: $out"

(( fail )) && { echo "test-always-loaded: FAILED"; exit 1; }
echo "test-always-loaded: all checks passed"
