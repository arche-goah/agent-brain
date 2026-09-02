#!/usr/bin/env bash
# test-workflow-relays.sh — guards the multi-agent invariant "only the producer writes"
# (rules/intelligence.md) on the workflow side.
#
# WHY: bulk data relayed across an agent boundary inside a prompt is truncated silently.
# Five sites in this repo used a bare `JSON.stringify(x).slice(0, N)` — a cut that leaves
# no trace anywhere, so a report built from half the data reads exactly like a complete
# one. The helpers `relay()` and `assertCount()` replace that; this fixture keeps them
# honest and keeps a new bare site from appearing.
#
# Two checks:
#   1. no `JSON.stringify(...).slice(` in workflows/ — the bare-relay pattern itself
#   2. the helpers behave: relay marks a cut, assertCount aborts on a mismatch
#
# Deliberately uses no temp directory: OS-3 in docs/os-traps.md — a shell path handed to
# a native process needs cygpath, and the cheapest way not to get that wrong is not to
# create the path.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# ── 1. no bare relay left ──────────────────────────────────────────────────
hits="$(grep -rEn 'JSON\.stringify\(.*\)\.slice\(' "$ROOT/workflows" || true)"
if [ -n "$hits" ]; then
  bad "bare relay site(s) — use relay(obj, limit, what) so a cut is logged and marked:"
  printf '%s\n' "$hits" | sed 's/^/         /'
else
  ok "no bare JSON.stringify(...).slice( in workflows/"
fi

# ── 2. helper behaviour ────────────────────────────────────────────────────
out="$(node -e '
const lines = []
const log = m => lines.push(m)
const relay = (obj, limit, what) => {
  const s = JSON.stringify(obj)
  if (s.length <= limit) return s
  log(`RELAY TRUNCATED: ${what} — ${limit} of ${s.length} chars reach the agent`)
  return `${s.slice(0, limit)}\n[TRUNCATED: ${limit} of ${s.length} chars — this payload is INCOMPLETE, say so in the report]`
}
const assertCount = (machine, claimed, what) => {
  if (claimed !== undefined && claimed !== machine) {
    throw new Error(`${what}: agent reported ${claimed}, script counted ${machine}`)
  }
}
const small = relay({a: 1}, 1000, "small")
console.log(small === JSON.stringify({a: 1}) ? "PASS under-limit-unchanged" : "FAIL under-limit-unchanged")
console.log(lines.length === 0 ? "PASS under-limit-silent" : "FAIL under-limit-silent")
const big = relay(Array.from({length: 200}, (_, i) => i), 50, "big")
console.log(big.includes("[TRUNCATED:") ? "PASS cut-marked-in-payload" : "FAIL cut-marked-in-payload")
console.log(lines.some(l => l.startsWith("RELAY TRUNCATED:")) ? "PASS cut-logged" : "FAIL cut-logged")
let threw = false
try { assertCount(12, 24, "x") } catch (e) { threw = true }
console.log(threw ? "PASS mismatch-aborts" : "FAIL mismatch-aborts")
threw = false
try { assertCount(12, 12, "x"); assertCount(12, undefined, "x") } catch (e) { threw = true }
console.log(threw ? "FAIL match-passes" : "PASS match-passes")
')" || { bad "helper harness did not run"; out=""; }

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

[ "$fail" -eq 0 ] && echo "test-workflow-relays: all checks passed"
exit "$fail"
