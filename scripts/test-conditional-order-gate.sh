#!/usr/bin/env bash
# Fixture for helpers/conditional-order-gate.cjs — both directions. The gate fires only when
# THREE things meet: the operator's last message carries a condition word, the call is
# expensive or externally effective, and no CONDITION-MET / CONDITION-NONE line stands in
# the turn yet. Each leg alone is a negative control.
# Usage: bash scripts/test-conditional-order-gate.sh   (exit 0 = all fixtures pass)
set -u

# Paths that travel INSIDE data (JSON fields read by node) are stated natively — Git Bash
# would hand node /tmp/... otherwise and the gate would fail open on an unreadable path
# (OS-3, docs/os-traps.md).
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

resolve() {
  for cand in "core/$1" "$1"; do [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }; done
  return 1
}
G="$ROOT/$(cd "$ROOT" && resolve helpers/conditional-order-gate.cjs)" || {
  echo "  -- conditional-order-gate.cjs not in this layout"; exit 1; }

# The fixture brings its OWN language data: the engine keeps English built-ins only, and
# the incident was German ("dann"). Same contract as test-promise-gate.sh.
mkdir -p "$T/.claude/rules" "$T/empty"
{
  printf '%s' '{"condition_patterns":['
  printf '%s' '"\\bdann\\b","\\bdanach\\b","\\bsobald\\b","\\berst\\s+(nach|wenn|danach)\\b",'
  printf '%s' '"\\bnach\\s+(der|deiner|seiner|ihrer|\\w+s)\\s+antwort\\b","\\bwarte\\b",'
  printf '%s' '"\\bklaer\\w*\\s+das\\s+mit\\b","\\b\\w+\\s+entscheidet\\b"]}'
} > "$T/.claude/rules/condition-patterns.json"

# Build a transcript: $1 file, $2 operator text (json string), $3 number of Agent tool_use
# blocks already in the turn, $4 assistant text (json string or empty), $5 optional trailing
# user record (json string) appended after the operator text (a hook echo / notification).
mk() {
  local tr="$1" op="$2" n="$3" asst="$4" trail="${5:-}"
  printf '{"message":{"role":"user","content":"earlier prompt"}}\n' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":"earlier answer"}]}}\n' >> "$tr"
  printf '{"message":{"role":"user","content":%s}}\n' "$op" >> "$tr"
  [ -n "$trail" ] && printf '{"message":{"role":"user","content":%s}}\n' "$trail" >> "$tr"
  local i=0
  while [ "$i" -lt "$n" ]; do
    printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"prompt":"x"}}]}}\n' >> "$tr"
    printf '{"message":{"role":"user","content":[{"type":"tool_result","content":"done"}]}}\n' >> "$tr"
    i=$((i+1))
  done
  [ -n "$asst" ] && printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$asst" >> "$tr"
  return 0
}

# $1 name, $2 block|allow, $3 tool name, $4 tool_input json, $5 cwd; transcript is $T/$1.jsonl
run_case() {
  local name="$1" want="$2" tool="$3" ti="$4" cwd="${5:-$T}"
  local out
  out="$(printf '{"tool_name":"%s","tool_input":%s,"transcript_path":"%s","cwd":"%s"}' \
    "$tool" "$ti" "$(native "$T/$name.jsonl")" "$(native "$cwd")" | node "$G" 2>&1)"
  if [ "$want" = block ]; then
    case "$out" in *CONDITIONAL-ORDER-GATE*) ok "$name blocks";; *) bad "$name did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$name allows" || bad "$name blocked wrongly: '$out'"
  fi
}

# --- the incident (2026-10-16): "dann coherence scan", nine agents; the third one trips it
mk "$T/incident-de.jsonl" '"dann coherence scan"' 2 ''
run_case incident-de block Agent '{"prompt":"lens 3"}'
mk "$T/below-threshold.jsonl" '"dann coherence scan"' 1 ''
run_case below-threshold allow Agent '{"prompt":"lens 2"}'
mk "$T/workflow-de.jsonl" '"dann coherence scan"' 0 ''
run_case workflow-de block Workflow '{"scriptPath":"core/workflows/coherence-scan.js"}'

# --- English built-ins: external commands trip on the first call
mk "$T/push-after.jsonl" '"after the mac answers, push it"' 0 ''
run_case push-after block Bash '{"command":"git push origin feat/x"}'
mk "$T/merge-delegated.jsonl" '"clear it with the operator first, and merge once he answers"' 0 ''
run_case merge-delegated block Bash '{"command":"gh pr merge 12 -R o/r --merge"}'
mk "$T/decides-ps.jsonl" '"the operator decides this one; then publish the comment"' 0 ''
run_case decides-ps block PowerShell '{"command":"gh pr comment 12 -R o/r --body-file n.md"}'
mk "$T/claude-p.jsonl" '"wait for the CI, then run the headless check"' 0 ''
run_case claude-p block Bash '{"command":"claude -p --safe-mode < brief.md > out.md"}'

# --- the markers release the call
mk "$T/met.jsonl" '"after the mac answers, push it"' 0 '"CONDITION-MET: after the mac answers — answered 16:19 in core/LOG.md (commit b757532)."'
run_case met allow Bash '{"command":"git push origin feat/x"}'
mk "$T/none.jsonl" '"ok then, carry on with the scan"' 0 '"CONDITION-NONE: then opens the sentence here, nothing is awaited; the scan was ordered in the previous turn."'
run_case none allow Workflow '{"scriptPath":"x.js"}'
mk "$T/met-short.jsonl" '"after the mac answers, push it"' 0 '"CONDITION-MET: yes"'
run_case met-short block Bash '{"command":"git push origin feat/x"}'

# --- negative controls: each leg alone stays silent
mk "$T/no-condition.jsonl" '"run the coherence scan now"' 5 ''
run_case no-condition allow Agent '{"prompt":"lens 6"}'
mk "$T/cheap-call.jsonl" '"dann coherence scan"' 0 ''
run_case cheap-call allow Bash '{"command":"git -C core log -3"}'
run_case cheap-call allow Read '{"file_path":"docs/x.md"}'
mk "$T/quoted.jsonl" '"he wrote \"dann\" in the log; run the scan"' 0 ''
run_case quoted allow Workflow '{"scriptPath":"x.js"}'
mk "$T/old-turn.jsonl" '"start the scan"' 0 ''
run_case old-turn allow Workflow '{"scriptPath":"x.js"}'

# --- a hook echo or a harness notification after the operator text is NOT a new operator
# --- message, and a condition word inside it must not count (turn-kind contract)
mk "$T/hook-echo.jsonl" '"run the scan now"' 0 '' '"Stop hook feedback: WATCHER — then arm it"'
run_case hook-echo allow Workflow '{"scriptPath":"x.js"}'
mk "$T/notification.jsonl" '"run the scan now"' 0 '' '"<task-notification>CI green; then merge</task-notification>"'
run_case notification allow Workflow '{"scriptPath":"x.js"}'
# ... and the other way round: the operator's condition survives a notification in between
mk "$T/cond-then-notif.jsonl" '"dann coherence scan"' 0 '' '"<task-notification>agent 1 done</task-notification>"'
run_case cond-then-notif block Workflow '{"scriptPath":"x.js"}'

# --- discriminator: the German hit must come from the DATA — same transcript, cwd without
# --- the pattern file, the gate has to fall silent
mk "$T/disc.jsonl" '"dann coherence scan"' 0 ''
run_case disc allow Workflow '{"scriptPath":"x.js"}' "$T/empty"

# --- fail-open: no transcript -> silent
out="$(printf '{"tool_name":"Workflow","tool_input":{},"transcript_path":"%s","cwd":"%s"}' \
  "$(native "$T/missing.jsonl")" "$(native "$T")" | node "$G" 2>&1)"
[ -z "$out" ] && ok "missing transcript allows (fail-open, measured not guessed)" || bad "missing transcript: '$out'"

echo
[ "$fail" -eq 0 ] && echo "conditional-order-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
