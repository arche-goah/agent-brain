#!/usr/bin/env bash
# covers: autonomous-idle-gate
# Fixture for helpers/autonomous-idle-gate.cjs - both directions.
# The must-block case is the incident (2026-10-28, macOS instance): in an autonomous run a turn woken by
# a CI notification ended on a status report while own items stayed open, a watcher still running.
# Usage: bash scripts/test-autonomous-idle-gate.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/autonomous-idle-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
tool() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"w1","name":"%s","input":{"command":"x","run_in_background":true}}]}}\n' "$1"; }
B="$T/brain"; mkdir -p "$B/.claude"
check() { # $1 label, $2 transcript, $3 block|allow, [$4 brain root]
  local out r="${4:-$B}"
  out=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$2")" "$(native "$r")" | CLAUDE_PROJECT_DIR="$(native "$r")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"decision":"block"'*) [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}
f="$T/1.jsonl"; { user "work through the open points autonomously"; tool Bash; user "<task-notification>CI green</task-notification>"; asst "PR 185 is green. Still with me: three items, not started."; } > "$f"
check "the incident: a notification turn ends on a status report, a watcher running" "$f" block
f="$T/2.jsonl"; { user "work through the open points autonomously"; asst "Done with A."; tool ScheduleWakeup; } > "$f"
check "ScheduleWakeup in the turn continues the run" "$f" allow
bash_cmd() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":%s}}]}}\n' "$(js "$1")"; }
MEAS="core/scripts/open-items.py --brief"   # the gate matches the script, not the interpreter (OS-17 reads a bare interpreter name as a choice)
f="$T/3.jsonl"; { user "work through the open points autonomously"; bash_cmd "$MEAS"; asst "BLOCKED: item C — needs the operator's word on the deploy"; } > "$f"
check "a BLOCKED line after measuring the list ends the turn" "$f" allow
f="$T/4.jsonl"; { user "work through the open points autonomously"; bash_cmd "$MEAS"; asst "POOL EMPTY: open-items lists 0 agent items (run 18:20)"; } > "$f"
check "a POOL EMPTY line after measuring the list ends the turn" "$f" allow
# 2026-10-28 (macOS instance): "BLOCKED: waiting on the watchers, the peer, the operator" while the session
# start listed 16 own items — a recollection, never read against the list.
f="$T/4b.jsonl"; { user "work through the open points autonomously"; asst "BLOCKED: waiting on the CI watchers and the operator"; } > "$f"
check "a BLOCKED line without measuring the list in this turn" "$f" block
f="$T/4c.jsonl"; { user "work through the open points autonomously"; bash_cmd "$MEAS"; user "<task-notification><task-id>x</task-id></task-notification>"; asst "POOL EMPTY: measured earlier"; } > "$f"
check "a measurement of an earlier turn does not count" "$f" block
# Measured on an instance: eight end lines stood on the list piped into a filter that kept only the counts.
f="$T/4e.jsonl"; { user "work through the open points autonomously"; bash_cmd "$MEAS | head -3"; asst "BLOCKED: item D — the peer's merge"; } > "$f"
check "the list piped into a filter is no measurement" "$f" block
IN="$T/inst"; mkdir -p "$IN/.claude/rules"
printf '%s\n' '{"own_items_commands": ["offene-punkte\\.py"]}' > "$IN/.claude/rules/autonomous-patterns.json"
f="$T/4d.jsonl"; { user "work through the open points autonomously"; bash_cmd "scripts/offene-punkte.py --liste"; asst "BLOCKED: item D — the peer's merge"; } > "$f"
check "the instance's own measuring command counts (data)" "$f" allow "$IN"
check "the same command without the instance data does not count (control)" "$f" block
f="$T/5.jsonl"; { user "fix the parser"; asst "Done, tests green."; } > "$f"
check "outside the autonomous mode it is silent" "$f" allow
f="$T/6.jsonl"; { user "work through the open points autonomously"; asst "x"; user "back to normal mode"; asst "Here is the summary."; } > "$f"
check "after the off word it is silent" "$f" allow
out=$(printf '{"transcript_path":"%s","cwd":"%s","stop_hook_active":true}' "$(native "$T/1.jsonl")" "$(native "$B")" | CLAUDE_PROJECT_DIR="$(native "$B")" node "$(native "$G")" 2>&1)
[ -z "$out" ] && ok "a re-issue (stop_hook_active) passes" || bad "re-issue blocked: $out"
f="$T/7.jsonl"; { user "work through the open points autonomously"; asst "The word BLOCKED: in the middle of a sentence is no end line, nor is it here."; } > "$f"
check "BLOCKED only counts as its own line" "$f" block
echo
[ "$fail" -eq 0 ] && echo "autonomous-idle-gate: all cases pass" || echo "autonomous-idle-gate: FAILURES"
exit "$fail"
