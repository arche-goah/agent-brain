#!/usr/bin/env bash
# Fixture test for the premise-gate — both directions.
# The gate fires only on the COMBINATION (rule-shaped sentence + an action resting
# on it), so both halves are tested alone as negative controls: a gate nobody has
# seen stay silent is as useless as one nobody has seen fire.
# Usage: bash scripts/test-premise-gate.sh   (exit 0 = all fixtures pass)
set -u
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# The fixture brings its OWN language data. Two reasons: it must not measure whichever
# brain happens to surround it, and shipping a second language here proves the contract
# that a language is DATA — the engine keeps only English built-ins.
mkdir -p "$T/.claude/rules"
"$PY" - "$T/.claude/rules/premise-patterns.json" <<'PYEOF'
import json, sys
json.dump({"generalisation_patterns": [
    r"\b(muss|müssen|darf|soll|wird|gilt|ist|sind|bleibt)\s+(immer|nie|niemals|grundsätzlich|grundsaetzlich)\b",
    r"\b\w+t\s+(immer|nie|niemals)\s+(der|die|das|ein|eine)\b",
    r"\b\w+t\s+(immer|nie|niemals)\s+(von|selbst|mit|ohne|auf|aus)\b",
    r"\b\w+t\s+(grundsätzlich|grundsaetzlich|ausnahmslos)\b",
    r"\bjedes\s+Mal\b",
], "instruction_patterns": [r"^\s*\d+\.\s+\*\*"]},
    open(sys.argv[1], "w", encoding="utf-8"))
PYEOF
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

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
G="$ROOT/$(cd "$ROOT" && resolve helpers/premise-gate.cjs || resolve scripts/hooks/premise-gate.cjs)"


# $1 name, $2 assistant text (json string), $3 tool_use name or "-", $4 block|allow
run_case() {
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$tr"
  if [ "$3" = "-" ]; then
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$2" >> "$tr"
  else
    printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s},{"type":"tool_use","name":"%s","input":{}}]}}\n' "$2" "$3" >> "$tr"
  fi
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$tr" "$T" | node "$G" 2>&1)"
  if [ "$4" = "block" ]; then
    case "$out" in *PREMISE-GATE*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}

# --- the real incident (2026-08-20): a rule sentence carrying a decision menu ---
run_case incident-de '"Im Konflikt gewinnt immer der, der zuletzt loslaesst."' AskUserQuestion block
run_case incident-en '"In a conflict the one who lets go last always wins."' AskUserQuestion block

# --- the combination via written files, and via an operator instruction ---
run_case rule-plus-write '"Der Fader sendet grundsaetzlich absolut, darum baue ich das so."' Write block
run_case rule-plus-instruction '"Ein Motorfader haelt nie von selbst.\n\n1. **Pult 201** hochziehen."' - block

# --- negative controls: each half alone stays silent ---
run_case rule-alone '"Im Konflikt gewinnt immer der, der zuletzt loslaesst."' - allow
run_case action-alone '"Layout gebaut, gelintet, 0 Probleme."' Write allow
run_case quoted-rule '"Emil sagte: \"das gewinnt immer der Motor\" — daher die Frage."' AskUserQuestion allow
run_case plain-observation '"Von 270 Hand-Paketen trugen 0 den Pult-Wert."' Write allow
run_case talk-about-the-rule '"Die Formulierung `immer wenn` ist genau das Muster."' Write allow

# --- narration in the perfect tense is NOT a rule (measured false-positive class:
# the first pattern set matched the bare word and blocked 17 % of all real turns) ---
run_case narration-de-never '"Der Watchdog hat den Kommentar nie gesehen, PR-Watch war nie armiert."' Write allow
run_case narration-de-measured '"Die Systemleiste habe ich nie gemessen, das bleibt offen."' Write allow
run_case narration-en-never '"The CI never ran on that branch, the only run is queued."' Write allow
run_case narration-de-immer '"Bisher wurde immer der Einzelfall gefixt, nicht die Klasse."' Write allow

echo
[ "$fail" -eq 0 ] && echo "premise-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
