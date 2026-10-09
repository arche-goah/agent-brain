#!/usr/bin/env bash
# test-brain-scan-files.sh — the brain-scan workflow moves its bulk data across the agent
# boundary as FILES, never as prompt text ("only the producer writes",
# rules/intelligence.md), and has the shape the operator decided on 2026-10-09: it reports
# and sorts, never fixes; it starts with the return channel; every finding leaves with one
# exit; every checklist section has an executor. This fixture proves that without running
# the workflow.
#
# WHY (files): until 2026-09-13 the report prompt carried every finding line of eight scan
# sections and the fix protocols — unbounded, no marker if cut. Measured on a coherence-scan
# run of the same shape: 241,137 chars went in, 60,000 arrived.
# WHY (shape, audit of the audit process 2026-10-09): 19 of 32 fix agents did nothing; two
# checklist sections had no executor; a hard-coded FRESHNESS-OK marker disabled the
# freshness gate for one workflow permanently; findings left without an exit and came back
# up to ten times. Each shape rule below is checked against the real file (must pass) AND
# against a mutated copy that carries the defect (must fail) — a check that is only ever
# shown a clean file might pass everything.
#
# Three parts:
#   1. static    — relay limits, consumer gates, producer instructions
#   2. shape     — no fix stage, no shipped FRESHNESS-OK marker, every template section has
#                  an executor, the machine step runs the prep script; each with a mutant
#   3. behaviour — the helper block is extracted VERBATIM from the workflow and run
#                  against synthetic scan files and synthetic report indexes
#
# OS-3 (docs/os-traps.md): the temp dir never crosses into node as DATA — node gets the
# harness file as an ARGUMENT and the file NAMES via env.
#
# Usage: scripts/test-brain-scan-files.sh [workflow.js]   (default: the repo's)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${1:-$ROOT/workflows/brain-scan.js}"
TEMPLATE="$ROOT/templates/brain-scan-checklist.md"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -f "$WF" ] || { bad "workflow not found: $WF"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. static: only indexes are relayed, every consumer is gated ───────────
hits="$(grep -En 'relay\(.*,[[:space:]]*[0-9]{5,}[[:space:]]*,' "$WF" || true)"
if [ -n "$hits" ]; then
  bad "relay() with a bulk limit (>= 10000 chars) — findings must travel as files, only an index through the prompt:"
  printf '%s\n' "$hits" | sed 's/^/         /'
else
  ok "no bulk relay() in brain-scan.js (every limit below 10000 chars)"
fi
# The unguarded shape the relay() helper exists to replace: a whole result array
# interpolated into a prompt. It has no limit at all, so it is worse than a bulk relay.
hits="$(grep -En '\$\{JSON\.stringify\((scans|scanResults|allFindings|summary)' "$WF" || true)"
if [ -n "$hits" ]; then
  bad "a whole result array is interpolated into a prompt — unbounded and unmarked:"
  printf '%s\n' "$hits" | sed 's/^/         /'
else
  ok "no result array interpolated into a prompt"
fi
for stage in scan report; do
  if grep -Eq "assertFiles\(.*'${stage}: " "$WF"; then
    ok "stage '${stage}' is gated by assertFiles()"
  else
    bad "stage '${stage}' has no assertFiles() gate — it could report on a partial set silently"
  fi
done
for gate in "assertExits(summary.index" "assertReport(REPORT"; do
  if grep -qF "$gate" "$WF"; then ok "the report is gated by ${gate%%(*}()"
  else bad "the report is not gated by ${gate%%(*}() — it could finish without exits or without its file"; fi
done
# The headless runner is a CALLER of the workflow and must satisfy the same contract.
# Measured 2026-09-13: the workflow started to throw without `scratch` while
# scripts/brain-scan.sh still passed only the date.
RUNNER="$ROOT/scripts/brain-scan.sh"
if grep -Eq "Workflow\(\{name:'brain-scan'.*scratch:" "$RUNNER"; then
  ok "the headless runner passes scratch to the workflow"
else
  bad "scripts/brain-scan.sh calls the workflow without scratch — the scheduled scan throws at its first line"
fi
if grep -q -- '--add-dir "\$SCRATCH"' "$RUNNER"; then
  ok "the headless runner grants the session access to its scratch dir"
else
  bad "scripts/brain-scan.sh does not --add-dir its scratch — the agents cannot write their findings there"
fi
if grep -q 'OUTPUT — you are the producer, you write' "$WF"; then
  ok "scan agents are instructed to write their output to a file"
else
  bad "no producer-writes instruction — the scan stage returns its bulk through the return value"
fi

# ── 2. shape: each rule against the real file AND a mutant ─────────────────
# Each check prints nothing when the file is fine, one reason when it is not.
no_fix_stage() { # $1 = workflow
  grep -Eq "phase\('Fix|title: 'Fix|implementing a task ORDERED|fixResults" "$1" && echo "the workflow has a fix stage"
}
no_marker() { # $@ = workflow files
  for f in "$@"; do grep -l 'FRESHNESS-OK:' "$f"; done | sed 's/^/FRESHNESS-OK marker shipped in /'
}
sections_covered() { # $1 = workflow, $2 = checklist template
  line="$(grep -E '^// SECTION_EXECUTORS:' "$1")"
  [ -n "$line" ] || { echo "no SECTION_EXECUTORS line in the workflow"; return; }
  for n in $(sed -n -E 's/^## ([0-9]+)\..*/\1/p' "$2"); do
    case " ${line#*:} " in *" $n="*) ;; *) echo "checklist section $n has no executor" ;; esac
  done
}
machine_step() { # $1 = workflow
  grep -qE '(core|\$\{CORE\})/scripts/brain-scan-prep.py' "$1" || echo "the machine step does not run brain-scan-prep.py"
  [ -f "$ROOT/scripts/brain-scan-prep.py" ] || echo "scripts/brain-scan-prep.py is not shipped"
}
expect() { # $1 = name, $2 = must be empty ("pass") or non-empty ("fail"), $3 = output
  if [ "$2" = pass ]; then
    [ -z "$3" ] && ok "$1" || bad "$1 — $3"
  else
    [ -n "$3" ] && ok "$1" || bad "$1 — the check stayed silent on a planted defect"
  fi
}
expect "no fix stage in brain-scan.js" pass "$(no_fix_stage "$WF")"
sed "s/^phase('Report')/phase('Fixes')\nphase('Report')/" "$WF" > "$TMP/mut-fix.js"
expect "a planted fix stage is caught" fail "$(no_fix_stage "$TMP/mut-fix.js")"

expect "no FRESHNESS-OK marker in any shipped workflow" pass "$(no_marker "$ROOT"/workflows/*.js)"
{ echo "// FRESHNESS-OK: planted"; cat "$WF"; } > "$TMP/mut-marker.js"
expect "a planted FRESHNESS-OK marker is caught" fail "$(no_marker "$TMP/mut-marker.js")"

expect "every checklist template section has an executor" pass "$(sections_covered "$WF" "$TEMPLATE")"
{ cat "$TEMPLATE"; printf '\n## 11. Planted section\n\n- [ ] nobody runs this\n'; } > "$TMP/mut-template.md"
expect "a section without an executor is caught" fail "$(sections_covered "$WF" "$TMP/mut-template.md")"

expect "the machine step runs the shipped prep script" pass "$(machine_step "$WF")"
grep -v 'brain-scan-prep.py' "$WF" > "$TMP/mut-machine.js"
expect "a machine step without the script is caught" fail "$(machine_step "$TMP/mut-machine.js")"

# ── 3. behaviour: the real helpers against synthetic files and indexes ─────
sed -n '/Producer-writes helpers (begin)/,/Producer-writes helpers (end)/p' "$WF" > "$TMP/helpers.js"
if ! grep -q 'const assertFiles' "$TMP/helpers.js" || ! grep -q 'const assertExits' "$TMP/helpers.js"; then
  bad "helper block not extractable — the (begin)/(end) markers moved; the fixture would test nothing"
  exit 1
fi
ok "helper block extracted verbatim from the workflow"

mkdir -p "$TMP/findings"
for slug in machine docs memory; do
  printf '{"section":"%s","summary":"fixture","findings":[{"severity":"OK","title":"fixture check %s","state":"configured"}]}\n' \
    "$slug" "$slug" > "$TMP/findings/scan-$slug.json"
done
printf '{"earlier":[]}\n' > "$TMP/findings/return-channel.json"
FOUND_ALL="$(ls "$TMP/findings")"
rm "$TMP/findings/return-channel.json"
FOUND_NO_RC="$(ls "$TMP/findings")"

cat "$TMP/helpers.js" - > "$TMP/harness.js" <<'JS'
const scanFiles = ['/scratch/findings/scan-machine.json', '/scratch/findings/scan-docs.json', '/scratch/findings/scan-memory.json']
const expected = [...scanFiles, '/scratch/findings/return-channel.json']
const all = process.env.FOUND_ALL.split('\n').filter(Boolean)
const noRc = process.env.FOUND_NO_RC.split('\n').filter(Boolean)
const run = (found, exp) => { try { assertFiles(exp || expected, found, 'fixture'); return null } catch (e) { return e.message } }
let m = run(all)
console.log(m === null ? 'PASS all-present-silent' : 'FAIL all-present-silent: ' + m)
m = run(noRc)
console.log(m && m.includes('return-channel.json') ? 'PASS missing-return-channel-loud' : 'FAIL missing-return-channel-loud: ' + m)
console.log(m && !m.includes('scan-machine.json') && m.includes('1 of 4') ? 'PASS present-files-not-blamed' : 'FAIL present-files-not-blamed: ' + m)
m = run([scanFiles[0], null, scanFiles[2], '/scratch/findings/return-channel.json'])
console.log(m && m.includes('scan-docs.json') ? 'PASS dead-agent-null-loud' : 'FAIL dead-agent-null-loud: ' + m)
m = run(all.map(n => 'C:\\Users\\someone\\scratch\\findings\\' + n))
console.log(m === null ? 'PASS directory-spelling-ignored' : 'FAIL directory-spelling-ignored: ' + m)

// assertExits: only the helper's OWN refusal counts as "loud" — a ReferenceError from a
// missing helper must not pass a must-fail case (the #194 lesson).
const ex = (index, nonOk, due, decisions) => {
  try { assertExits(index, nonOk, due, decisions, 'fixture'); return null }
  catch (e) { return e instanceof ReferenceError || e instanceof TypeError ? 'CRASH ' + e.message : e.message }
}
const loud = (name, m, part) => console.log(m && !m.startsWith('CRASH') && m.includes(part) ? `PASS ${name}` : `FAIL ${name}: ${m}`)
const quiet = (name, m) => console.log(m === null ? `PASS ${name}` : `FAIL ${name}: ${m}`)
const idx = [
  { key: 'a', severity: 'P1', exit: 'ai-does-it' },
  { key: 'b', severity: 'P2', exit: 'drop', merged: 2 },
  { key: 'c', severity: 'P1', exit: 'operator-decision' },
]
const dec = [{ key: 'c', question: 'q', recommendation: 'r' }]
quiet('exits: a complete index passes (merged entries count their raw findings)', ex(idx, 4, [], dec))
loud('exits: a finding without an exit is caught', ex([...idx, { key: 'd', severity: 'P2', exit: 'later' }], 5, [], dec), 'without a valid exit')
loud('exits: an index short of the raw findings is caught', ex(idx, 5, [], dec), 'accounts for 4')
loud('exits: a key used twice is caught', ex([...idx, { key: 'a', severity: 'P2', exit: 'drop' }], 5, [], dec), 'used twice')
loud('exits: a third recurrence left as a normal line is caught', ex(idx, 4, ['a'], dec), 'third time')
const idx3 = idx.map(i => i.key === 'a' ? { ...i, exit: 'operator-decision' } : i)
quiet('exits: a third recurrence as an operator decision passes', ex(idx3, 4, ['a'], [...dec, { key: 'a', question: 'q', recommendation: 'r' }]))
const many = ['w', 'x', 'y', 'z'].map(k => ({ key: k, severity: 'P2', exit: 'operator-decision' }))
const three = many.slice(0, 3).map(i => ({ key: i.key, question: 'q', recommendation: 'r' }))
quiet('exits: four decisions, three presented, passes (the rest offered as a list)', ex(many, 4, [], three))
loud('exits: four decisions all presented is caught', ex(many, 4, [], [...three, { key: 'z', question: 'q', recommendation: 'r' }]), 'present min(3, n)')
loud('exits: a decision without a recommendation is caught', ex(idx, 4, [], [{ key: 'c', question: 'q', recommendation: '' }]), 'no recommendation')
JS

out="$(FOUND_ALL="$FOUND_ALL" FOUND_NO_RC="$FOUND_NO_RC" node "$TMP/harness.js" 2>&1)" \
  || { bad "helper harness did not run: $out"; out=""; }

while IFS= read -r line; do
  [ -z "$line" ] && continue
  case "$line" in
    PASS*) ok "${line#PASS }" ;;
    FAIL*) bad "${line#FAIL }" ;;
    *)     bad "unexpected harness output: $line" ;;
  esac
done <<EOF
$out
EOF

[ "$fail" -eq 0 ] && echo "test-brain-scan-files: all checks passed"
exit "$fail"
