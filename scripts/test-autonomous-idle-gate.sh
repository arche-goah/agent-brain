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
check() { # $1 label, $2 transcript, $3 block|allow
  local out
  out=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$2")" "$(native "$B")" | CLAUDE_PROJECT_DIR="$(native "$B")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"decision":"block"'*) [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}
f="$T/1.jsonl"; { user "work through the open points autonomously"; tool Bash; user "<task-notification>CI green</task-notification>"; asst "PR 185 is green. Still with me: three items, not started."; } > "$f"
check "the incident: a notification turn ends on a status report, a watcher running" "$f" block
f="$T/2.jsonl"; { user "work through the open points autonomously"; asst "Done with A."; tool ScheduleWakeup; } > "$f"
check "ScheduleWakeup in the turn continues the run" "$f" allow
f="$T/3.jsonl"; { user "work through the open points autonomously"; asst "BLOCKED: item C — needs the operator's word on the deploy"; } > "$f"
check "a BLOCKED line ends the turn" "$f" allow
f="$T/4.jsonl"; { user "work through the open points autonomously"; asst "POOL EMPTY: open-items lists 0 agent items (run 18:20)"; } > "$f"
check "a POOL EMPTY line ends the turn" "$f" allow
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
