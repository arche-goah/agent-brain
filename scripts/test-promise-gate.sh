#!/usr/bin/env bash
# Fixture test for the promise-gate -- both directions.
# The gate fires only on the COMBINATION (a first-person commitment and the condition
# that bounds it, inside the SAME sentence), so each half alone is tested as a negative
# control: a gate nobody has seen stay silent is as useless as one nobody has seen fire.
# Usage: bash scripts/test-promise-gate.sh   (exit 0 = all fixtures pass)
set -u

# A path that travels INSIDE data (a JSON string, an env var read by a native process)
# is not translated by the shell -- on Git Bash node would receive /d/a/... or /tmp/...
# and resolve neither. cygpath states the same path natively; elsewhere it is a no-op.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

# The fixture brings its OWN language data. Two reasons: it must not measure whichever
# brain happens to surround it, and shipping a second language here proves the contract
# that a language is DATA -- the engine keeps only English built-ins.
mkdir -p "$T/.claude/rules"
{
  printf '%s' '{"commitment_patterns":['
  printf '%s' '"\\bich\\s+(fasse|ruehre|aendere|committe|pushe)\\s+\\w*\\s*nichts\\b",'
  printf '%s' '"\\bich\\s+(werde|wuerde)\\s+\\w+\\s+nicht\\b",'
  printf '%s' '"\\bkein\\s+(commit|push|schreibzugriff)\\s+von\\s+mir\\b"],'
  printf '%s' '"condition_patterns":['
  printf '%s' '"\\bsolange\\b","\\bwaehrend\\s+(du|er|sie|das|der|die)\\b","\\bbis\\s+(du|er|sie|das)\\b",'
  printf '%s' '"\\bfuer\\s+(diesen|den)\\s+(lauf|durchgang|abend)\\b"]}'
} > "$T/.claude/rules/promise-patterns.json"

ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other -- so resolution is explicit.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
G="$ROOT/$(cd "$ROOT" && resolve helpers/promise-gate.cjs)" || {
  echo "  -- promise-gate.cjs not in this layout"; exit 1; }

# $1 name, $2 assistant text (json string), $3 block|allow, $4.. extra argv for the gate
run_case() {
  local name="$1" text="$2" want="$3"; shift 3
  local tr="$T/$name.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$text" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
    "$(native "$tr")" "$(native "$T")" | node "$G" "$@" 2>&1)"
  if [ "$want" = "block" ]; then
    case "$out" in *PROMISE-GATE*) ok "$name blocks";; *) bad "$name did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$name allows" || bad "$name blocked wrongly: '$out'"
  fi
}

# --- the real incident (2026-09-11): an unattended-work promise bound to the operator
# --- being asleep, which then outlived the sleeping ---
run_case incident-en '"I will not commit or push anything while you are asleep."' block
run_case incident-de '"Ich fasse nichts an, solange du den Lauf pruefst."' block

# --- other bounded forms that lapse the same way ---
run_case horizon-run '"I won'"'"'t touch the desk for this run, you drive it."' block
run_case hold-off '"I'"'"'ll hold off on the merge until the colleague answers."' block
run_case promise-word '"I promise to stay off the rig while the show is running."' block

# --- negative controls: each half alone stays silent ---
run_case commitment-alone '"I will not touch the desk."' allow
run_case condition-alone '"The export runs until the colleague answers."' allow
run_case positive-commitment '"I will rebuild the layout while the render finishes."' allow
run_case quoted-promise '"Emil sagte: \"ich fasse nichts an, solange es laeuft\" — daher die Frage."' allow
run_case plain-report '"Committed and pushed; the fixture is green for now."' allow

# --- the pairing must be per SENTENCE, not per turn: a commitment in one sentence and
# --- an unrelated horizon in another is the false-positive class this design avoids ---
run_case split-across-sentences '"I will not touch the desk. The CI run is queued until tomorrow."' allow

# --- record mode never blocks, and the record is actually written ---
run_case record-mode '"I will not commit anything while you are asleep."' allow --record
if [ -s "$T/.claude-state/promises.jsonl" ] \
  && grep -q '"bound_by"' "$T/.claude-state/promises.jsonl"; then
  ok "record mode appends to .claude-state/promises.jsonl"
else
  bad "record mode wrote no usable record"
fi

# --- discriminator: the fixture must be able to distinguish two world states, or it
# --- proves nothing ([[ein-symbol-zwei-zustaende]]). Same German sentence as
# --- `incident-de`, but run against a cwd WITHOUT the instance pattern file: the
# --- built-ins are English by contract, so it has to fall silent. If it still blocks,
# --- something other than the patterns is firing and every green line above is suspect.
mkdir -p "$T/empty"
printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$T/disc.jsonl"
printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' \
  '"Ich fasse nichts an, solange du den Lauf pruefst."' >> "$T/disc.jsonl"
disc="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
  "$(native "$T/disc.jsonl")" "$(native "$T/empty")" | node "$G" 2>&1)"
if [ -z "$disc" ]; then
  ok "discriminator: same sentence, no instance patterns -> silent (fixture sees both states)"
else
  bad "discriminator: blocked without instance patterns -- the German hit is not coming from the data: '$disc'"
fi

echo
[ "$fail" -eq 0 ] && echo "promise-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
