#!/usr/bin/env bash
# test-brain-scan-files.sh — the brain-scan workflow moves its bulk data across the agent
# boundary as FILES, never as prompt text ("only the producer writes",
# rules/intelligence.md). This fixture proves that without running the workflow.
#
# WHY: until 2026-09-13 the report prompt carried every finding line of eight scan
# sections, their summaries, AND `JSON.stringify(fixResults)` — the fix protocols, whose
# "detail" field is as long as the agent makes it. None of it had a limit or a marker, so
# a cut left no trace anywhere. Measured on a coherence-scan run of the same shape:
# 241,137 chars went in, 60,000 arrived, 6 of 9 producers never reached the consumer,
# with the counts green because they matched while the content did not.
#
# Two checks:
#   1. static    — no relay() with a bulk limit, no bare JSON.stringify() of a result
#                  array in a prompt, all three consumer gates (scan, fixes, report)
#                  pass through assertFiles(), and the producers are told to write
#   2. behaviour — the helper block is extracted VERBATIM from the workflow and run
#                  against synthetic scan and fix files
#
# OS-3 (docs/os-traps.md): the temp dir never crosses into node as DATA — node gets the
# harness file as an ARGUMENT and the file NAMES via env.
#
# Usage: scripts/test-brain-scan-files.sh [workflow.js]   (default: the repo's)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${1:-$ROOT/workflows/brain-scan.js}"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -f "$WF" ] || { bad "workflow not found: $WF"; exit 1; }

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
hits="$(grep -En '\$\{JSON\.stringify\((fixResults|scans|scanResults|allFindings)' "$WF" || true)"
if [ -n "$hits" ]; then
  bad "a whole result array is interpolated into a prompt — unbounded and unmarked:"
  printf '%s\n' "$hits" | sed 's/^/         /'
else
  ok "no result array interpolated into a prompt"
fi
for stage in scan fixes report; do
  if grep -Eq "assertFiles\(.*'${stage}: " "$WF"; then
    ok "stage '${stage}' is gated by assertFiles()"
  else
    bad "stage '${stage}' has no assertFiles() gate — it could report on a partial set silently"
  fi
done
# The headless runner is a CALLER of the workflow and must satisfy the same contract.
# Measured 2026-09-13 (review of this change): the workflow started to throw without
# `scratch` while scripts/brain-scan.sh still passed only the date — the scheduled scan
# would have died at its first line, and `claude -p` exits 0 on that.
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
if [ "$(grep -c 'OUTPUT — you are the producer, you write' "$WF")" -ge 2 ]; then
  ok "scan agents and fix agents are both instructed to write their output to a file"
else
  bad "fewer than two producer-writes instructions — one of the two stages still returns its bulk through the return value"
fi

# ── 2. behaviour: the real helper against synthetic scan/fix files ─────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -n '/Producer-writes helpers (begin)/,/Producer-writes helpers (end)/p' "$WF" > "$TMP/helpers.js"
if ! grep -q 'const assertFiles' "$TMP/helpers.js"; then
  bad "helper block not extractable — the (begin)/(end) markers moved; the fixture would test nothing"
  exit 1
fi
ok "helper block extracted verbatim from the workflow"

mkdir -p "$TMP/findings"
for slug in effect docs memory; do
  printf '{"section":"%s","summary":"fixture","findings":[{"severity":"OK","title":"fixture check %s","state":"configured"}]}\n' \
    "$slug" "$slug" > "$TMP/findings/scan-$slug.json"
done
printf '{"order":"fixture order","status":"umgesetzt-verifiziert","detail":"fixture"}\n' > "$TMP/findings/fix-1.json"
FOUND_ALL="$(ls "$TMP/findings")"
rm "$TMP/findings/fix-1.json"
FOUND_NO_FIX="$(ls "$TMP/findings")"

cat "$TMP/helpers.js" - > "$TMP/harness.js" <<'JS'
const scanFiles = ['/scratch/findings/scan-effect.json', '/scratch/findings/scan-docs.json', '/scratch/findings/scan-memory.json']
const expected = [...scanFiles, '/scratch/findings/fix-1.json']
const all = process.env.FOUND_ALL.split('\n').filter(Boolean)
const noFix = process.env.FOUND_NO_FIX.split('\n').filter(Boolean)
const run = (found, exp) => { try { assertFiles(exp || expected, found, 'fixture'); return null } catch (e) { return e.message } }
let m = run(all)
console.log(m === null ? 'PASS all-present-silent' : 'FAIL all-present-silent: ' + m)
m = run(noFix)
console.log(m && m.includes('fix-1.json') ? 'PASS missing-fix-protocol-loud' : 'FAIL missing-fix-protocol-loud: ' + m)
console.log(m && !m.includes('scan-effect.json') && m.includes('1 of 4') ? 'PASS present-files-not-blamed' : 'FAIL present-files-not-blamed: ' + m)
m = run([scanFiles[0], null, scanFiles[2], '/scratch/findings/fix-1.json'])
console.log(m && m.includes('scan-docs.json') ? 'PASS dead-agent-null-loud' : 'FAIL dead-agent-null-loud: ' + m)
m = run([], scanFiles)
console.log(m && m.includes('3 of 3') ? 'PASS nothing-found-loud' : 'FAIL nothing-found-loud: ' + m)
m = run(all.map(n => 'C:\\Users\\someone\\scratch\\findings\\' + n))
console.log(m === null ? 'PASS directory-spelling-ignored' : 'FAIL directory-spelling-ignored: ' + m)
JS

out="$(FOUND_ALL="$FOUND_ALL" FOUND_NO_FIX="$FOUND_NO_FIX" node "$TMP/harness.js" 2>&1)" \
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
