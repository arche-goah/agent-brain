#!/usr/bin/env bash
# test-full-audit-synthesis-files.sh — the synthesis workflow moves its catalog across
# the agent boundary as a FILE, never as prompt text ("only the producer writes",
# rules/intelligence.md). This fixture proves that without running the workflow.
#
# WHY: until 2026-09-13 the catalog agent returned up to 40 measures INCLUDING sources
# and proposals, and the script relayed all of them into the report prompt behind one
# 50,000-char limit. Measured on a coherence-scan run of the same shape: 241,137 chars
# went in, 60,000 arrived, and the counts stayed green because they matched while the
# content did not. The synthesis is the last stage of the most expensive run in the
# system — a silent cut here throws away the result of all three scans.
#
# Two checks:
#   1. static    — no relay() with a bulk limit, both consumer gates (catalog, report)
#                  pass through assertFiles(), and the catalog agent is told to write
#   2. behaviour — the helper block is extracted VERBATIM from the workflow and run
#                  against a synthetic catalog file
#
# OS-3 (docs/os-traps.md): the temp dir never crosses into node as DATA — node gets the
# harness file as an ARGUMENT and the file NAMES via env.
#
# Usage: scripts/test-full-audit-synthesis-files.sh [workflow.js]   (default: the repo's)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WF="${1:-$ROOT/workflows/full-audit-synthesis.js}"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

[ -f "$WF" ] || { bad "workflow not found: $WF"; exit 1; }

# ── 1. static: only the index is relayed, every consumer is gated ──────────
hits="$(grep -En 'relay\(.*,[[:space:]]*[0-9]{5,}[[:space:]]*,' "$WF" || true)"
if [ -n "$hits" ]; then
  bad "relay() with a bulk limit (>= 10000 chars) — the catalog must travel as a file, only an index through the prompt:"
  printf '%s\n' "$hits" | sed 's/^/         /'
else
  ok "no bulk relay() in full-audit-synthesis.js (every limit below 10000 chars)"
fi
for stage in catalog report; do
  if grep -Eq "assertFiles\(.*'${stage}: " "$WF"; then
    ok "stage '${stage}' is gated by assertFiles()"
  else
    bad "stage '${stage}' has no assertFiles() gate — it could work from a remembered catalog silently"
  fi
done
if grep -q 'OUTPUT — you are the producer, you write' "$WF"; then
  ok "the catalog agent is instructed to write the catalog to a file"
else
  bad "no producer-writes instruction in the catalog prompt — sources and proposals would come back through the return value again"
fi

# ── 2. behaviour: the real helper against a synthetic catalog file ─────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -n '/Producer-writes helpers (begin)/,/Producer-writes helpers (end)/p' "$WF" > "$TMP/helpers.js"
if ! grep -q 'const assertFiles' "$TMP/helpers.js"; then
  bad "helper block not extractable — the (begin)/(end) markers moved; the fixture would test nothing"
  exit 1
fi
ok "helper block extracted verbatim from the workflow"

mkdir -p "$TMP/scratch"
printf '{"summary":"fixture","skipped_existing":0,"massnahmen":[{"prio":"P2","typ":"mechanisch","titel":"fixture measure","quellen":["report.md#section"],"vorschlag":"fixture"}]}\n' \
  > "$TMP/scratch/catalog.json"
FOUND_ALL="$(ls "$TMP/scratch")"

cat "$TMP/helpers.js" - > "$TMP/harness.js" <<'JS'
const expected = ['/scratch/catalog.json']
const all = process.env.FOUND_ALL.split('\n').filter(Boolean)
const run = (found) => { try { assertFiles(expected, found, 'fixture'); return null } catch (e) { return e.message } }
let m = run(all)
console.log(m === null ? 'PASS catalog-present-silent' : 'FAIL catalog-present-silent: ' + m)
m = run([])
console.log(m && m.includes('catalog.json') && m.includes('1 of 1') ? 'PASS catalog-missing-loud' : 'FAIL catalog-missing-loud: ' + m)
m = run([null])
console.log(m !== null ? 'PASS dead-agent-null-loud' : 'FAIL dead-agent-null-loud')
m = run(['gesamt-2026-09-13.md'])
console.log(m !== null ? 'PASS other-file-does-not-count' : 'FAIL other-file-does-not-count')
m = run(all.map(n => 'C:\\Users\\someone\\scratch\\' + n))
console.log(m === null ? 'PASS directory-spelling-ignored' : 'FAIL directory-spelling-ignored: ' + m)
JS

out="$(FOUND_ALL="$FOUND_ALL" node "$TMP/harness.js" 2>&1)" \
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

[ "$fail" -eq 0 ] && echo "test-full-audit-synthesis-files: all checks passed"
exit "$fail"
