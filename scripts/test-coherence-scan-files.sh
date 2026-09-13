#!/usr/bin/env bash
# test-coherence-scan-files.sh — the coherence-scan workflow moves its bulk data across
# agent boundaries as FILES, never as prompt text ("only the producer writes",
# rules/intelligence.md). This fixture proves that without running the workflow.
#
# WHY: measured 2026-09-13 on a real run (16 agents, 2.47M tokens): 9 lens agents
# produced 241,137 chars of findings, the merge prompt relayed 60,000 of them, and
# 6 of 9 lenses never reached the consolidation — while assertCount() stayed green,
# because the numbers agreed and the content did not. Same at the register stage:
# 75,345 chars of verified findings, 60,000 arrived, findings 16-20 missing from the
# prose. relay() marks a cut; it cannot make one harmless. The fix is that nothing
# bulky crosses the boundary at all, and this fixture is what keeps that true:
#
#   1. static  — no relay() in coherence-scan.js carries more than an index (a
#                five-digit char limit is bulk by definition), and every consumer
#                stage (merge, verify, register) passes through assertFiles()
#   2. behaviour — the helper block is extracted VERBATIM from the workflow (no
#                inline copy that can drift) and run against a directory of synthetic
#                lens files: all present = silent; one missing = loud and names it;
#                a dead agent (null) = loud; a differently spelled directory = silent
#
# The workflow itself is never run here — it costs seven figures in tokens and its
# repeat gate (freshness) exists for a reason. Only the script logic is under test.
#
# OS-3 (docs/os-traps.md): the temp dir never crosses into node as DATA — node gets
# the harness file as an ARGUMENT (Git Bash converts argv) and the file NAMES via env,
# which is exactly the comparison the helper makes (names, not directories).
#
# Usage: scripts/test-coherence-scan-files.sh [workflow.js]   (default: the repo's)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${1:-$ROOT/workflows/coherence-scan.js}"
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
  ok "no bulk relay() in coherence-scan.js (every limit below 10000 chars)"
fi
for stage in merge verify register; do
  if grep -Eq "assertFiles\(.*'${stage}: " "$WF"; then
    ok "consumer stage '${stage}' is gated by assertFiles()"
  else
    bad "consumer stage '${stage}' has no assertFiles() gate — it could read a partial set silently"
  fi
done

# ── 2. behaviour: the real helper against real (synthetic) lens files ──────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -n '/Producer-writes helpers (begin)/,/Producer-writes helpers (end)/p' "$WF" > "$TMP/helpers.js"
if ! grep -q 'const assertFiles' "$TMP/helpers.js"; then
  bad "helper block not extractable — the (begin)/(end) markers moved; the fixture would test nothing"
  exit 1
fi
ok "helper block extracted verbatim from the workflow"

# Synthetic, anonymous lens files — the shape the lens agents write, nothing from a run.
mkdir -p "$TMP/findings"
for slug in alpha beta gamma; do
  printf '{"lens":"%s","summary":"fixture","findings":[{"severity":"P2","title":"fixture finding %s","claim":"fixture","sources":[{"file":"corpus/rules/example.md","quote":"example"}]}]}\n' \
    "$slug" "$slug" > "$TMP/findings/lens-$slug.json"
done
FOUND_ALL="$(ls "$TMP/findings")"
rm "$TMP/findings/lens-gamma.json"
FOUND_ONE_MISSING="$(ls "$TMP/findings")"

cat "$TMP/helpers.js" - > "$TMP/harness.js" <<'JS'
const expected = ['/scratch/findings/lens-alpha.json', '/scratch/findings/lens-beta.json', '/scratch/findings/lens-gamma.json']
const all = process.env.FOUND_ALL.split('\n').filter(Boolean)
const oneMissing = process.env.FOUND_ONE_MISSING.split('\n').filter(Boolean)
const run = (found) => { try { assertFiles(expected, found, 'fixture'); return null } catch (e) { return e.message } }
let m = run(all)
console.log(m === null ? 'PASS all-present-silent' : 'FAIL all-present-silent: ' + m)
m = run(oneMissing)
console.log(m !== null ? 'PASS missing-file-loud' : 'FAIL missing-file-loud')
console.log(m && m.includes('lens-gamma.json') ? 'PASS missing-file-named' : 'FAIL missing-file-named: ' + m)
console.log(m && !m.includes('lens-alpha.json') && m.includes('1 of 3') ? 'PASS present-files-not-blamed' : 'FAIL present-files-not-blamed: ' + m)
m = run([all[0], null, all[2]])
console.log(m && m.includes('lens-beta.json') ? 'PASS dead-agent-null-loud' : 'FAIL dead-agent-null-loud: ' + m)
m = run([])
console.log(m && m.includes('3 of 3') ? 'PASS nothing-found-loud' : 'FAIL nothing-found-loud: ' + m)
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

[ "$fail" -eq 0 ] && echo "test-coherence-scan-files: all checks passed"
exit "$fail"
