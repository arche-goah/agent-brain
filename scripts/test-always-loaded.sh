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
out=$(run); grep -q 'grew from 2300 to 4800 bytes (+2500)' <<< "$out" && ok "creep-in-steps-loud" || bad "creep-in-steps-loud: $out"
grow "$T/MEMORY.md" 10
out=$(run); grep -q '+2510' <<< "$out" && ok "memory-index-counted" || bad "memory-index-counted: $out"
out=$(run --accept); grep -q 'baseline set: 4810' <<< "$out" && ok "accept-sets-baseline" || bad "accept-sets-baseline: $out"
out=$(run); [[ -z "$out" ]] && ok "after-accept-silent" || bad "after-accept-silent: $out"
# a baseline over another file set is named, never read as growth (the incident: --accept by
# hand without --memory, the session start measuring with it reported the index as +22 KB)
nomem() { "$PY" "$HERE/always-loaded.py" --repo "$T/b" "$@"; }
out=$(nomem); grep -q 'accepted with the memory index and this run measures without it' <<< "$out" && ok "file-set-mismatch-named-not-growth" || bad "file-set-mismatch-named-not-growth: $out"
out=$(nomem --accept); grep -q 'baseline set: 4500' <<< "$out" && ok "accept-without-memory" || bad "accept-without-memory: $out"
out=$(run); grep -q 'accepted without the memory index and this run measures with it' <<< "$out" && ok "mismatch-other-way-named" || bad "mismatch-other-way-named: $out"
grep -q 'grew from' <<< "$out" && bad "mismatch-reported-as-growth" || ok "mismatch-not-growth"
out=$(run --accept); grep -q 'baseline set: 4810' <<< "$out" && ok "re-accept-with-memory" || bad "re-accept-with-memory: $out"
out=$(run); [[ -z "$out" ]] && ok "after-re-accept-silent" || bad "after-re-accept-silent: $out"
# the hard limit: silent below 90 %, named from 90 %, OVER above — independent of the baseline
out=$(run --limit 6000); [[ -z "$out" ]] && ok "below-90pct-of-limit-silent" || bad "below-90pct-of-limit-silent: $out"
out=$(run --limit 5300); grep -q 'at 4810 of 5300 bytes (90 % of the harness limit)' <<< "$out" && ok "at-90pct-of-limit-named" || bad "at-90pct-of-limit-named: $out"
out=$(run --limit 4000); grep -q 'OVER the harness limit: 4810 of 4000' <<< "$out" && ok "over-limit-loud" || bad "over-limit-loud: $out"
out=$(run --limit 4000 --accept); grep -q 'OVER the harness limit' <<< "$out" && ok "over-limit-loud-even-on-accept" || bad "over-limit-loud-even-on-accept: $out"
mkdir -p "$T/memdir"; out=$("$PY" "$HERE/always-loaded.py" --repo "$T/b" --memory "$T/memdir")
grep -q 'must be the MEMORY.md file, not a directory' <<< "$out" && ok "directory-as-memory-refused" || bad "directory-as-memory-refused: $out"

(( fail )) && { echo "test-always-loaded: FAILED"; exit 1; }
echo "test-always-loaded: all checks passed"
