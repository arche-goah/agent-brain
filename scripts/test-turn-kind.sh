#!/usr/bin/env bash
# Fixture test for helpers/turn-kind.cjs and its effect on a gate's cooldown.
# The defect (2026-10-07): a harness notification (task done, watcher event) reached the
# transcript as a plain user string, and every gate counted it as an operator turn — so a
# cooldown ran out on turns nobody had written. Proved on stoppen-gate (cooldown 3 turns):
# after it fired, three NOTIFICATION turns must keep it quiet; three OPERATOR turns must not.
# Usage: bash scripts/test-turn-kind.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
D="$(cd "$(dirname "$0")" && pwd)/../helpers"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$D/turn-kind.cjs" ] || { echo "  FAIL helper missing"; exit 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

NOTE='<system-reminder>
[SYSTEM NOTIFICATION - NOT USER INPUT]
<task-notification>
<task-id>b1</task-id>
<status>completed</status>
</task-notification>
</system-reminder>'

# --- the definition ------------------------------------------------------------------
probe() { node -e 'const {isNotification}=require(process.argv[1]);process.stdout.write(String(isNotification(process.argv[2])))' "$(native "$D/turn-kind.cjs")" "$1"; }
[ "$(probe "$NOTE")" = true ] && ok "frames only = notification" || bad "frames only not recognised"
[ "$(probe "$NOTE please go on")" = false ] && ok "frames + operator words = operator" || bad "operator words ignored"
[ "$(probe "go on")" = false ] && ok "plain text = operator" || bad "plain text read as notification"
[ "$(probe "<system-reminder>x</system-reminder>")" = false ] && ok "a reminder without a task notification is not one" || bad "bare reminder read as notification"
# A local command (/mcp, /model) runs without the model: its three records are not a prompt.
[ "$(probe '<local-command-caveat>The command below was run directly in Claude Code.</local-command-caveat>')" = true ] && ok "local-command caveat = not a prompt" || bad "local caveat read as prompt"
[ "$(probe '<command-name>/mcp</command-name>
            <command-message>mcp</command-message>
            <command-args></command-args>')" = true ] && ok "local command name record = not a prompt" || bad "command record read as prompt"
[ "$(probe '<local-command-stdout>Reconnected to grandma3.</local-command-stdout>')" = true ] && ok "local-command stdout = not a prompt" || bad "local stdout read as prompt"
[ "$(probe '<command-name>/mcp</command-name> and please also check the PR')" = false ] && ok "command frames + operator words = operator" || bad "operator words after a command ignored"
[ "$(probe 'Base directory for this skill: x. Do the review.')" = false ] && ok "a skill text record stays a prompt" || bad "skill text read as notification"

# --- the effect on a cooldown ----------------------------------------------------------
user() { printf '{"message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
Q="Shall I proceed with the merge?"
build() { # $1 file, $2 text of the three later turns' opening records
  { user "start"; asst "$Q"; user "Stop hook feedback: STOPPEN-GATE fired"; asst "$Q"
    for _ in 1 2 3; do user "$2"; asst "$Q"; done; } > "$1"
}
run() { printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$1")" "$(native "$T")" | node "$D/stoppen-gate.cjs" 2>&1; }
build "$T/notif.jsonl" "$NOTE"
build "$T/oper.jsonl" "go on"
[ -z "$(run "$T/notif.jsonl")" ] && ok "three notification turns keep the cooldown" || bad "notification turns ran the cooldown out"
case "$(run "$T/oper.jsonl")" in *'"decision":"block"'*) ok "three operator turns end the cooldown";; *) bad "operator turns did not end the cooldown";; esac

[ "$fail" = 0 ] && echo "turn-kind: all cases pass" || { echo "turn-kind: FAILURES"; exit 1; }
