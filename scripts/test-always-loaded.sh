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

# --diet: quote clauses (25+ chars, in a dated bullet) and carrier clauses in the preference file
F="$T/b/.claude/rules/feedback.md"
printf '%s\n' \
  '# Feedback' \
  '> Header: every entry names its `Traeger:` line in the protocol (2026-10-25).' \
  '' \
  '- **Rule one** (2026-10-26, the operator: "the last question should be keep going autonomously"): do X.' \
  '- **Rule two** (2026-10-27): the start report never disappears.' \
  '  Traeger: helpers/x.cjs.' \
  '- **Pointer line** (2026-10-26): holds through the core (`working-rules.md` "Order Fidelity"), date only.' \
  '- **Short term** (2026-09-18): say „Event-Netz", never the bare word.' \
  '- **Wrapped quote** (2026-11-03, the operator: „only when I write questions for me now,' \
  '  shall the mode switch“): wrapped over two lines.' \
  '- **Undated quote**: "a long quote of more than twenty-five characters" stays, no date.' \
  '- **Colon at line end** (2026-10-26, the operator:' \
  '  „a quote that starts on the continuation line"): reported on line 13.' \
  '- **Rule three** (2026-10-28): do Y. Carrier: helpers/y.cjs.' \
  > "$F"
out=$("$PY" "$HERE/always-loaded.py" --repo "$T/b" --diet); rc=$?
grep -q 'feedback.md: 3 quote clause(s) at lines 4, 9, 13 ' <<< "$out" && ok "diet-dated-quotes-reported-incl-wrapped" || bad "diet-dated-quotes-reported-incl-wrapped: $out"
grep -q 'feedback.md: 1 carrier clause(s) at lines 14 ' <<< "$out" && ok "diet-builtin-carrier-key-only-without-data" || bad "diet-builtin-carrier-key-only-without-data: $out"
printf '%s\n' '{"carrier_keys": ["Traeger"]}' > "$T/b/.claude/rules/lesson-carriers.json"
out=$("$PY" "$HERE/always-loaded.py" --repo "$T/b" --diet); rc=$?
grep -q 'feedback.md: 2 carrier clause(s) at lines 6, 14 ' <<< "$out" && ok "diet-instance-carrier-key-code-span-skipped" || bad "diet-instance-carrier-key-code-span-skipped: $out"
(( rc == 0 )) && ok "diet-report-only-exit-0" || bad "diet-report-only-exit-0: rc=$rc"
"$PY" "$HERE/always-loaded.py" --repo "$T/b" --diet --strict >/dev/null; rc=$?
(( rc == 1 )) && ok "diet-strict-exit-1" || bad "diet-strict-exit-1: rc=$rc"
printf '%s\n' '- **Pointer** (2026-10-26): holds through the core (`working-rules.md` „Order Fidelity"), date only.' \
  '- **Term** (2026-09-18): „Event-Netz", never the bare word.' \
  '- **Section name** (2026-10-09): see the core section „Presenting to the Operator, comparative test".' > "$T/clean.md"
out=$("$PY" "$HERE/always-loaded.py" --diet "$T/clean.md" --strict); rc=$?
grep -q 'clean.md: clean' <<< "$out" && (( rc == 0 )) && ok "diet-controls-pointer-and-short-term-silent" || bad "diet-controls-pointer-and-short-term-silent: rc=$rc $out"
out=$("$PY" "$HERE/always-loaded.py" --diet "$T/none.md" --strict); rc=$?
grep -q 'no preference file at' <<< "$out" && (( rc == 0 )) && ok "diet-missing-file-named" || bad "diet-missing-file-named: rc=$rc $out"

(( fail )) && { echo "test-always-loaded: FAILED"; exit 1; }
echo "test-always-loaded: all checks passed"
