#!/usr/bin/env bash
# Fixture test for the stop dispatcher: does it collect several gates into ONE block,
# keep every gate's cooldown marker, and stay silent when nothing fires?
# Usage: bash scripts/test-stop-dispatcher.sh   (exit 0 = all fixtures pass)
set -u
# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other — so resolution is explicit, and a missing subject is
# SKIPPED loudly rather than passing quietly.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
skip() { echo "  --  $1 (not in this layout)"; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D=$(cd "$ROOT" && resolve helpers/stop-dispatcher.cjs || resolve scripts/hooks/stop-dispatcher.cjs)
D="$ROOT/$D"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }



# The check list is INSTANCE data. Outside a brain there is none, and a dispatcher
# with an empty config correctly does nothing — which would make this fixture pass by
# testing nothing. So it builds its own project root with a minimal config and points
# the dispatcher at that.
CFG="$(mktemp -d)"
mkdir -p "$CFG/.claude/rules"
CG=$(cd "$ROOT" && resolve helpers/class-gate.cjs)
PG=$(cd "$ROOT" && resolve helpers/premise-gate.cjs || resolve scripts/hooks/premise-gate.cjs)
TG=$(cd "$ROOT" && resolve scripts/hooks/time-gate.cjs || true)
python3 - "$CFG/.claude/rules/stop-checks.json" "$ROOT/$CG" "$ROOT/$PG" "${TG:+$ROOT/$TG}" <<'PYEOF'
import json, sys
path, cg, pg, tg = sys.argv[1:5]
checks = [
    {"label": "CLASS", "marker": "CLASS-GATE", "cmd": cg, "mode": "block",
     "extract": r"Touched this turn:\s*(.+)", "template": "{1} -> class?",
     "basename": True},
    {"label": "PREMISE", "marker": "PREMISE-GATE", "cmd": pg, "mode": "block",
     "extract": r"Rule-shaped wording:\s*(.+)", "template": "{1} carries an action"},
]
if tg:
    checks.append({"label": "TIME", "marker": "TIME-GATE", "cmd": tg,
                   "mode": "record", "args": ["--record"]})
json.dump({"header": "STOP-CHECKS ({n})", "checks": checks},
          open(path, "w", encoding="utf-8"))
PYEOF
trap 'rm -rf "$T" "$CFG"' EXIT

feed() { # $1 transcript -> dispatcher output
  printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$1" "$CFG" \
    | CLAUDE_PROJECT_DIR="$CFG" node "$D" 2>/dev/null
}

# --- a turn that trips THREE gates: time + premise + class -------------------
TR="$T/three.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$TR"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"That has been open since yesterday. In a conflict the one who lets go last always wins."},{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"scripts/hooks/probe-fixture.cjs","content":"x"}}]}}' >> "$TR"
OUT="$(feed "$TR")"

case "$OUT" in *'STOP-CHECKS'*) ok "emits one combined block";; *) bad "no combined block: $OUT";; esac
n=$(printf '%s' "$OUT" | grep -o '·' | wc -l | tr -d ' ')
[ "$n" -ge 2 ] && ok "collects $n findings in one message" || bad "only $n findings"
# ZEIT is a RECORDING check since 2026-08-20: it must NOT appear in the block, and its
# findings must land in the log instead. Both halves are asserted — a recorder that
# silently records nothing looks exactly like one that had nothing to record.
case "$OUT" in *'[TIME-GATE]'*) bad "TIME-GATE blocked although it only records";; *) ok "TIME-GATE does not block";; esac
if [ -n "$TG" ]; then
  LOG="$CFG/.claude-state/time-gate.jsonl"
  grep -q '"phrase"' "$LOG" 2>/dev/null && ok "recording check wrote to its log" \
    || bad "recorder registered but nothing landed in $LOG"
else
  skip "recording check (no recorder in this layout)"
fi
case "$OUT" in *'[PREMISE-GATE]'*) ok "keeps PREMISE-GATE cooldown marker";; *) bad "PREMISE-GATE marker lost";; esac
case "$OUT" in *'[CLASS-GATE]'*) ok "keeps CLASS-GATE cooldown marker";; *) bad "CLASS-GATE marker lost";; esac
lines=$(printf '%s' "$OUT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['reason'].splitlines()))")
[ "$lines" -le 6 ] && ok "compact ($lines lines)" || bad "not compact ($lines lines)"

# --- a clean turn: nothing fires --------------------------------------------
TR2="$T/clean.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$TR2"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"Messwert 34 s steht im Log, sonst nichts offen."}]}}' >> "$TR2"
OUT2="$(feed "$TR2")"
[ -z "$OUT2" ] && ok "silent when no gate fires" || bad "fired on a clean turn: $OUT2"

# --- re-issue pass: stop_hook_active silences everything ---------------------
OUT3="$(printf '{"transcript_path":"%s","stop_hook_active":true,"cwd":"%s"}' "$TR" "$CFG" \
  | CLAUDE_PROJECT_DIR="$CFG" node "$D" 2>/dev/null)"
[ -z "$OUT3" ] && ok "silent on the re-issue pass" || bad "blocked twice: $OUT3"

echo
[ "$fail" -eq 0 ] && echo "stop-dispatcher fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
