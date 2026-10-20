#!/usr/bin/env bash
# covers: live-watchdog
#
# Fixture test for helpers/live-watchdog.cjs — both directions. The planted live system has a
# check whose verdict the test sets through a file (0 green, 1 red, 3 = could not measure,
# hang = timeout); the check also appends to a run log, so "the check did NOT run" is measured,
# not assumed.
#
# Negative control: every must-block case is ALSO run against an always-allow stub and must
# come back "allow" there — proof that the case discriminates instead of passing for a reason
# unrelated to the gate. An alternative engine can be passed as $1.
#
# Usage: bash scripts/test-live-watchdog.sh [watchdog.cjs]   (exit 0 = all fixtures pass)
set -u

# Paths travel INSIDE data (the project dir, the check argv in the instance file). Git Bash
# /tmp/... does not resolve for node (docs/os-traps.md OS-3); cygpath states it natively.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
if [ $# -ge 1 ]; then GATE="$1"; else
  GATE=$(resolve helpers/live-watchdog.cjs) || { echo "  --  live-watchdog not in this layout"; exit 0; }
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NT=$(native "$T")
fail=0
must_block=0
flipped=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

STUB="$T/always-allow.cjs"
printf '%s\n' "process.stdin.resume(); process.stdin.on('end', () => process.exit(0));" > "$STUB"

# The planted check: verdict from $T/verdict, one line per run into $T/runs.
printf '%s\n' \
  "const fs=require('fs'),p=require('path'),d=__dirname;" \
  "fs.appendFileSync(p.join(d,'runs'),'run\n');" \
  "const v=fs.readFileSync(p.join(d,'verdict'),'utf8').trim();" \
  "if(v==='hang'){setTimeout(()=>{},10000);}else{console.log('fixture check: '+(v==='0'?'target state holds':'cue 3 missing'));process.exit(Number(v));}" \
  > "$T/check.cjs"
mkdir -p "$T/.claude/rules"
CFG='{"suites":[{"name":"stage","writes":["^mcp__stage__(set|create)"],"every":3,
  "check":["node","ROOT/check.cjs"],"timeout_s":2,"repair":["^mcp__stage__undo$"]}]}'
printf '%s\n' "${CFG//ROOT/$NT}" > "$T/.claude/rules/live-watchdog.json"

set_verdict() { printf '%s\n' "$1" > "$T/verdict"; }
runs() { if [ -f "$T/runs" ]; then wc -l < "$T/runs" | tr -d ' '; else echo 0; fi; }
raw() { # $1 engine, $2 event, $3 tool → the hook's stdout
  printf '{"hook_event_name":"%s","tool_name":"%s","tool_input":{},"session_id":"%s","cwd":"%s"}' "$2" "$3" "${SID:-s1}" "$NT" \
    | CLAUDE_PROJECT_DIR="$NT" node "$1"
}
verdict() {
  local o; o=$(raw "$@")
  if printf '%s' "$o" | grep -qE '"permissionDecision":"deny"|"decision":"block"'; then echo deny; else echo allow; fi
}
# check <name> <deny|allow> <event> <tool>
check() {
  local name="$1" want="$2"; shift 2
  local got; got=$(verdict "$GATE" "$@")
  [ "$got" = "$want" ] && ok "$name → $want" || bad "$name: expected $want, got $got"
  if [ "$want" = deny ]; then
    must_block=$((must_block + 1))
    [ "$(verdict "$STUB" "$@")" = allow ] && flipped=$((flipped + 1))
  fi
}

echo "live-watchdog:"
set_verdict 0
# 1. below N: two writes, the check does not run (negative control for the trigger)
check "1a write 1 of 3" allow PostToolUse mcp__stage__set_value
check "1b write 2 of 3" allow PostToolUse mcp__stage__create_cue
[ "$(runs)" = 0 ] && ok "1c below N the check did not run" || bad "1c check ran $(runs)x below N"

# 2. the N-th write runs the check; green passes and resets the count
check "2a write 3 of 3, check green" allow PostToolUse mcp__stage__set_value
[ "$(runs)" = 1 ] && ok "2b the check ran once at N" || bad "2b expected 1 run, got $(runs)"
check "2c next write passes (not red)" allow PreToolUse mcp__stage__set_value

# 3. reads are never counted, unrelated tools never touched
check "3a read tool after N" allow PostToolUse mcp__stage__get_state
check "3b unrelated MCP tool" allow PostToolUse mcp__other__set_value
[ "$(runs)" = 1 ] && ok "3c reads and unrelated tools ran no check" || bad "3c got $(runs) runs"

# 4. red at the N-th write: the agent is told at once, writes are refused afterwards
set_verdict 1
check "4a write 1 (red pending)" allow PostToolUse mcp__stage__set_value
check "4b write 2" allow PostToolUse mcp__stage__set_value
check "4c write 3, check red → block" deny PostToolUse mcp__stage__set_value
raw "$GATE" PreToolUse mcp__stage__set_value | grep -q 'cue 3 missing' \
  && ok "4d the refusal carries the check's output" || bad "4d expected the check output in the refusal"
check "4e next write refused while red" deny PreToolUse mcp__stage__create_cue
check "4f a read passes while red" allow PreToolUse mcp__stage__get_state
check "4g a repair tool passes while red" allow PreToolUse mcp__stage__undo
check "4h another system is not blocked" allow PreToolUse mcp__other__set_value

# 5. red persists across sessions (state is per project), then only GREEN clears it
SID=s2 check "5a still red in another session" deny PreToolUse mcp__stage__set_value
set_verdict 3
check "5b red + check cannot measure → still refused" deny PreToolUse mcp__stage__set_value
set_verdict 0
check "5c check green again → write passes" allow PreToolUse mcp__stage__set_value
check "5d and stays open" allow PreToolUse mcp__stage__set_value

# 6. could not measure (exit 3) at N: not red, the agent is told, retried after the next write
set_verdict 3
before=$(runs)
check "6a write 1" allow PostToolUse mcp__stage__set_value
check "6b write 2" allow PostToolUse mcp__stage__set_value
check "6c write 3, check unmeasured → not blocked" allow PostToolUse mcp__stage__set_value
raw "$GATE" PostToolUse mcp__stage__set_value | grep -q 'could not measure' \
  && ok "6d unmeasured is reported to the agent" || bad "6d expected a could-not-measure note"
[ "$(runs)" = $((before + 2)) ] && ok "6e retried after the next write" || bad "6e expected $((before + 2)) runs, got $(runs)"
check "6f writes stay open (unmeasured is not red)" allow PreToolUse mcp__stage__set_value

# 7. a hung check (timeout) is unmeasured too, never red
set_verdict hang
check "7a hung check at N → not blocked" allow PostToolUse mcp__stage__set_value
check "7b writes stay open" allow PreToolUse mcp__stage__set_value
set_verdict 0
check "7c green clears the retry" allow PostToolUse mcp__stage__set_value

# 8. broken instance file → fail-open, logged; no file → silent no-op
printf '{"suites": [' > "$T/.claude/rules/live-watchdog.json"
check "8a broken instance file (fail-open)" allow PreToolUse mcp__stage__set_value
grep -q BAD-CONFIG "$T/.claude-state/live-watchdog.log" 2>/dev/null \
  && ok "8b broken file is logged" || bad "8b expected a BAD-CONFIG log line"
rm -rf "$T/.claude/rules/live-watchdog.json" "$T/.claude-state"
check "8c no instance file (inert)" allow PostToolUse mcp__stage__set_value
[ ! -e "$T/.claude-state" ] && ok "8d no instance file writes no state and no log" || bad "8d inert gate wrote state"

# --- negative control: the always-allow stub must turn every must-block case red ----
if [ "$must_block" -gt 0 ] && [ "$flipped" -eq "$must_block" ]; then
  ok "negative control: always-allow stub fails all $must_block must-block cases"
else
  bad "negative control: only $flipped of $must_block must-block cases discriminate"
fi

echo
[ "$fail" -eq 0 ] && echo "live-watchdog fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
