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

# Pasted text is not the operator's words (measured 2026-10-28: `<pasted_content id="81eb">…</pasted_content
# id="81eb">`; a pasted plan's "then" became the operator's condition). words() prints the operator's words
# with whitespace squashed; raw() prints them as JSON, to see the line break that keeps sentences apart.
words() { node -e 'const {operatorWords}=require(process.argv[1]);process.stdout.write(operatorWords(process.argv[2]).replace(/\s+/g," ").trim())' "$(native "$D/turn-kind.cjs")" "$1"; }
raw() { node -e 'const {operatorWords}=require(process.argv[1]);process.stdout.write(JSON.stringify(operatorWords(process.argv[2])))' "$(native "$D/turn-kind.cjs")" "$1"; }
P1=$'<pasted_content id="81eb">\nInvestors first react too slowly, then like a herd.\n</pasted_content id="81eb">'
[ -z "$(words "$P1")" ] && ok "a prompt that is only pasted content has no operator words" || bad "paste only: '$(words "$P1")'"
[ "$(words "$P1"$'\nread it and push')" = "read it and push" ] && ok "the words after a pasted block stay" || bad "after: '$(words "$P1"$'\nread it and push')'"
[ "$(words "dann push $P1")" = "dann push" ] && ok "the words before a pasted block stay" || bad "before: '$(words "dann push $P1")'"
case "$(raw "do it once${P1}now")" in *'once\nnow'*) ok "a removed block leaves a line break, the words around it do not fuse";; *) bad "fused: $(raw "do it once${P1}now")";; esac
TWO=$'<pasted_content id="a1f0">\nplan one, then sell\n</pasted_content id="a1f0">\nafter the mac answers, push it\n<pasted_content id="b2e1">\nplan two, then buy\n</pasted_content id="b2e1">'
[ "$(words "$TWO")" = "after the mac answers, push it" ] && ok "two pasted blocks: the text between them stays, both blocks go" || bad "two blocks: '$(words "$TWO")'"
[ "$(words $'<pasted_content source="clipboard" id="a1f0" lines="2">\nthen\n</pasted_content id="a1f0">tail')" = "tail" ] && ok "other tag attributes are tolerated" || bad "attributes not tolerated"
[ "$(words $'<pasted_content id="a1f0">\nx </pasted_content id="ffff"> then y\n</pasted_content id="a1f0">z')" = "z" ] && ok "a closing tag with another id inside the block does not end it" || bad "inner foreign closer ended the block"
[ "$(words $'<pasted_content id="a1f0">\nwait for the CI\n</pasted_content id="ffff">')" = '<pasted_content id="a1f0"> wait for the CI </pasted_content id="ffff">' ] && ok "a closer with another id closes nothing (text kept)" || bad "mismatched ids stripped"
[ "$(words 'push it, then merge')" = "push it, then merge" ] && ok "a prompt without a pasted block is unchanged" || bad "plain prompt changed"
[ "$(node -e 'const {operatorWords}=require(process.argv[1]);process.stdout.write(JSON.stringify([operatorWords(null),operatorWords(undefined)]))' "$(native "$D/turn-kind.cjs")")" = '["",""]' ] && ok "no text gives no words" || bad "null/undefined not handled"
[ "$(probe "$P1")" = false ] && ok "a paste-only record is still a prompt (it opens a turn)" || bad "paste-only record read as notification"

# Another agent's message (subagent hand-back, peer session): origin.kind "peer"; the operator's words: "human".
peer() { node -e 'const {isPeerMessage}=require(process.argv[1]);process.stdout.write(String(isPeerMessage(JSON.parse(process.argv[2]))))' "$(native "$D/turn-kind.cjs")" "$1"; }
[ "$(peer '{"type":"user","isMeta":true,"origin":{"kind":"peer","from":"a1"}}')" = true ] && ok "a peer record is another agent's message" || bad "peer record not recognised"
[ "$(peer '{"type":"user","origin":{"kind":"human"}}')" = false ] && ok "an operator record is no peer message" || bad "operator record read as peer"
[ "$(peer '{"type":"user","isMeta":true}')" = false ] && ok "isMeta alone is no peer message (mid-turn operator text)" || bad "isMeta alone read as peer"
# A timer-fired prompt (ScheduleWakeup, /loop; Claude Code 2.1.312): queuePriority "later", no human origin.
agent() { node -e 'const {isAgentOrigin}=require(process.argv[1]);process.stdout.write(String(isAgentOrigin(JSON.parse(process.argv[2]))))' "$(native "$D/turn-kind.cjs")" "$1"; }
[ "$(agent '{"type":"user","isMeta":true,"promptSource":"system","queuePriority":"later"}')" = true ] && ok "a timer-fired prompt is agent origin" || bad "timer prompt not recognised"
[ "$(agent '{"type":"user","isMeta":true,"origin":{"kind":"peer"}}')" = true ] && ok "a peer record is agent origin" || bad "peer not agent origin"
[ "$(agent '{"type":"user","queuePriority":"later","origin":{"kind":"human"}}')" = false ] && ok "a human prompt waiting in the queue is the operator's" || bad "queued human prompt read as agent"
[ "$(agent '{"type":"user","isMeta":true}')" = false ] && ok "isMeta alone is no agent origin" || bad "isMeta alone read as agent"

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

# --- questionAnswers(): the operator's question-tool answer is an operator word (2026-10-30) -----------
qa() { node -e '
const { questionAnswers } = require(process.argv[1]);
const t = questionAnswers();
const recs = JSON.parse(process.argv[2]);
console.log(recs.map((r) => t(r) ? 1 : 0).join(""));' "$D/turn-kind.cjs" "$1"; }
ASK='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}'
BASH='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"Bash","input":{}}]}}'
res() { printf '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":%s,"content":"The user answered: yes"}]}}' "$1" "$2"; }
[ "$(qa "[$ASK,$(res q1 false)]")" = 01 ] && ok "a question-tool answer is a boundary" || bad "question-tool answer not seen"
[ "$(qa "[$BASH,$(res b1 false)]")" = 00 ] && ok "another tool's answer-like result is no boundary" || bad "answer-like tool output taken as an answer"
[ "$(qa "[$ASK,$(res q1 true)]")" = 00 ] && ok "a refused question is no boundary" || bad "refused question taken as an answer"
[ "$(qa "[$(res q1 false)]")" = 0 ] && ok "a result without its question in the pass is no boundary" || bad "orphan result taken as an answer"

[ "$fail" = 0 ] && echo "turn-kind: all cases pass" || { echo "turn-kind: FAILURES"; exit 1; }
