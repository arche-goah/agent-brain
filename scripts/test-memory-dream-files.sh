#!/usr/bin/env bash
# test-memory-dream-files.sh — the memory-dream workflow moves its bulk data across the
# agent boundary as FILES, never as prompt text ("only the producer writes",
# rules/intelligence.md). This fixture proves that without running the workflow.
#
# WHY: until 2026-09-13 both analysis agents returned their complete findings arrays and
# the script relayed them, together with the summaries, through ONE 50,000-char relay
# into the report prompt. Measured on a coherence-scan run of the same shape: 241,137
# chars went in, 60,000 arrived, 6 of 9 producers never reached the consumer — with the
# counts green, because they matched while the content did not. relay() marks a cut; it
# cannot make one harmless. The fix is that nothing bulky crosses at all.
#
# Two checks:
#   1. static    — no relay() in the workflow carries more than an index (a five-digit
#                  char limit is bulk by definition), and both consumer gates
#                  (analysis, report) pass through assertFiles()
#   2. behaviour — the helper block is extracted VERBATIM from the workflow (no inline
#                  copy that can drift) and run against synthetic analysis files
#
# OS-3 (docs/os-traps.md): the temp dir never crosses into node as DATA — node gets the
# harness file as an ARGUMENT and the file NAMES via env.
#
# Usage: scripts/test-memory-dream-files.sh [workflow.js]   (default: the repo's)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${1:-$ROOT/workflows/memory-dream.js}"
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
  ok "no bulk relay() in memory-dream.js (every limit below 10000 chars)"
fi
for stage in analysis report; do
  if grep -Eq "assertFiles\(.*'${stage}: " "$WF"; then
    ok "stage '${stage}' is gated by assertFiles()"
  else
    bad "stage '${stage}' has no assertFiles() gate — it could report on a partial set silently"
  fi
done
if grep -q 'OUTPUT — you are the producer, you write' "$WF"; then
  ok "the analysis agents are instructed to write their findings to a file"
else
  bad "no producer-writes instruction in the analysis prompt — the findings would come back through the return value again"
fi

# ── 2. behaviour: the real helper against synthetic analysis files ─────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -n '/Producer-writes helpers (begin)/,/Producer-writes helpers (end)/p' "$WF" > "$TMP/helpers.js"
if ! grep -q 'const assertFiles' "$TMP/helpers.js"; then
  bad "helper block not extractable — the (begin)/(end) markers moved; the fixture would test nothing"
  exit 1
fi
ok "helper block extracted verbatim from the workflow"

mkdir -p "$TMP/findings"
for slug in content mechanics; do
  printf '{"lens":"%s","summary":"fixture","findings":[{"severity":"P2","title":"fixture finding %s","proposal":"fixture"}]}\n' \
    "$slug" "$slug" > "$TMP/findings/analysis-$slug.json"
done
FOUND_ALL="$(ls "$TMP/findings")"
rm "$TMP/findings/analysis-mechanics.json"
FOUND_ONE_MISSING="$(ls "$TMP/findings")"

cat "$TMP/helpers.js" - > "$TMP/harness.js" <<'JS'
const expected = ['/scratch/findings/analysis-content.json', '/scratch/findings/analysis-mechanics.json']
const all = process.env.FOUND_ALL.split('\n').filter(Boolean)
const oneMissing = process.env.FOUND_ONE_MISSING.split('\n').filter(Boolean)
const run = (found) => { try { assertFiles(expected, found, 'fixture'); return null } catch (e) { return e.message } }
let m = run(all)
console.log(m === null ? 'PASS all-present-silent' : 'FAIL all-present-silent: ' + m)
m = run(oneMissing)
console.log(m !== null ? 'PASS missing-file-loud' : 'FAIL missing-file-loud')
console.log(m && m.includes('analysis-mechanics.json') ? 'PASS missing-file-named' : 'FAIL missing-file-named: ' + m)
console.log(m && !m.includes('analysis-content.json') && m.includes('1 of 2') ? 'PASS present-files-not-blamed' : 'FAIL present-files-not-blamed: ' + m)
m = run([all[0], null])
console.log(m && m.includes('analysis-mechanics.json') ? 'PASS dead-agent-null-loud' : 'FAIL dead-agent-null-loud: ' + m)
m = run([])
console.log(m && m.includes('2 of 2') ? 'PASS nothing-found-loud' : 'FAIL nothing-found-loud: ' + m)
m = run(all.map(n => 'C:\\Users\\someone\\scratch\\findings\\' + n))
console.log(m === null ? 'PASS directory-spelling-ignored' : 'FAIL directory-spelling-ignored: ' + m)
JS

out="$(FOUND_ALL="$FOUND_ALL" FOUND_ONE_MISSING="$FOUND_ONE_MISSING" node "$TMP/harness.js" 2>&1)" \
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

[ "$fail" -eq 0 ] && echo "test-memory-dream-files: all checks passed"
exit "$fail"
