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
# push is git's SUBCOMMAND (class of watch-gate GIT_PUSH, 2026-10-26): a local commit whose message
# says push is not external; a push through -C is
mk "$T/commit-says-push.jsonl" '"after the mac answers, push it"' 0 ''
run_case commit-says-push allow Bash '{"command":"git commit -q -m \"push after review\""}'
mk "$T/push-via-C.jsonl" '"after the mac answers, push it"' 0 ''
run_case push-via-C block Bash '{"command":"git -C /x/y push -q origin feat/x"}'
mk "$T/merge-delegated.jsonl" '"clear it with Alex first, and merge once he answers"' 0 ''
run_case merge-delegated block Bash '{"command":"gh pr merge 12 -R o/r --merge"}'
mk "$T/decides-ps.jsonl" '"Alex decides this one; then publish the comment"' 0 ''
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
# the line in the call itself: the hook sees its own input even when the same-response text
# never reached the transcript (2026-10-21, Windows)
mk "$T/in-call.jsonl" '"after the mac answers, push it"' 0 ''
run_case in-call allow Bash '{"command":"git push origin feat/x  # CONDITION-NONE: the sentence is quoted rule text, not this order"}'
mk "$T/in-call-short.jsonl" '"after the mac answers, push it"' 0 ''
run_case in-call-short block Bash '{"command":"git push origin feat/x  # CONDITION-NONE: no"}'
mk "$T/in-prompt.jsonl" '"dann coherence scan"' 2 ''
run_case in-prompt allow Agent '{"prompt":"lens 3\nCONDITION-MET: dann coherence scan — the answer came 12:40 in core/LOG.md"}'

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

# --- a skill loaded through the Skill tool arrives as a user record with "isMeta" AND
# --- "sourceToolUseID" (measured on Claude Code 2.1.303); its "then" is the skill author's,
# --- not the operator's (2026-10-19, session-close)
mk "$T/skill-text.jsonl" '"close the session"' 0 ''
printf '{"isMeta":true,"sourceToolUseID":"toolu_x","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: x\\n\\nCommit, then push."}]}}\n' >> "$T/skill-text.jsonl"
run_case skill-text allow Bash '{"command":"git push origin feat/x"}'
# ... the operator's own condition survives a skill expansion in between
mk "$T/cond-then-skill.jsonl" '"after the mac answers, push it"' 0 ''
printf '{"isMeta":true,"sourceToolUseID":"toolu_x","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: x"}]}}\n' >> "$T/cond-then-skill.jsonl"
run_case cond-then-skill block Bash '{"command":"git push origin feat/x"}'
# ... and a message the operator sends mid-turn (isMeta, no sourceToolUseID) still counts
mk "$T/midturn-operator.jsonl" '"run the scan"' 0 ''
printf '{"isMeta":true,"message":{"role":"user","content":"after the mac answers, push it"}}\n' >> "$T/midturn-operator.jsonl"
run_case midturn-operator block Bash '{"command":"git push origin feat/x"}'

# --- discriminator: the German hit must come from the DATA — same transcript, cwd without
# --- the pattern file, the gate has to fall silent
mk "$T/disc.jsonl" '"dann coherence scan"' 0 ''
run_case disc allow Workflow '{"scriptPath":"x.js"}' "$T/empty"

# --- the measured shape (2026-10-21): the operator's last message carries no condition, but an
# api-request-blob record after it carries the instruction dump with a rule heading that does.
# Only user/assistant records are the conversation; the blob must not become the operator text.
mk "$T/blob.jsonl" '"weiter im programm"' 0 ''
printf '{"type":"api-request-blob","message":{"role":"user","content":[{"type":"text","text":"<system-reminder>\\n**SECHS KREISE — wer entscheidet** (2026-09-21; kanonisch)\\n</system-reminder>"}]}}\n' >> "$T/blob.jsonl"
run_case blob allow Bash '{"command":"git push"}'
# discriminator: the same record as a real user record IS the operator's text and blocks
mk "$T/blob-as-user.jsonl" '"weiter im programm"' 0 ''
printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"**SECHS KREISE — wer entscheidet** (2026-09-21; kanonisch)"}]}}\n' >> "$T/blob-as-user.jsonl"
run_case blob-as-user block Bash '{"command":"git push"}'

# --- the measured shape (2026-10-22): a subagent's hand-back arrives as a user record with
# origin.kind "peer" and carries a condition word; the operator's own words carry "human".
mk "$T/peer.jsonl" '"weiter im programm"' 0 ''
printf '{"type":"user","isMeta":true,"origin":{"kind":"peer","from":"a1"},"message":{"role":"user","content":"[Subagent hand-back] take it out of draft sobald 1 and 2 are in"}}\n' >> "$T/peer.jsonl"
run_case peer allow Bash '{"command":"git push"}'
# discriminator: the same text from the operator blocks
mk "$T/peer-as-human.jsonl" '"weiter im programm"' 0 ''
printf '{"type":"user","origin":{"kind":"human"},"message":{"role":"user","content":"take it out of draft sobald 1 and 2 are in"}}\n' >> "$T/peer-as-human.jsonl"
run_case peer-as-human block Bash '{"command":"git push"}'

# --- the measured shapes (2026-10-26): a compaction summary is a user record with isCompactSummary
# --- and retells conditions the operator gave long ago; it is no operator message.
mk "$T/compact.jsonl" '"run the scan"' 0 ''
printf '{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"Summary: retrying is only allowed after the operator grants it."}}\n' >> "$T/compact.jsonl"
run_case compact allow Bash '{"command":"git push origin feat/x"}'
# ... a message typed mid-turn is an attachment record (queued_command, origin human) - it IS the
# operator's last message, and a condition in it binds
mk "$T/queued-human.jsonl" '"run the scan"' 0 ''
printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":"after the mac answers, push it","origin":{"kind":"human"}}}\n' >> "$T/queued-human.jsonl"
run_case queued-human block Bash '{"command":"git push origin feat/x"}'
# ... and it replaces an older condition: a later plain message frees the call
mk "$T/queued-replaces.jsonl" '"after the mac answers, push it"' 0 ''
printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":"push it now","origin":{"kind":"human"}}}\n' >> "$T/queued-replaces.jsonl"
run_case queued-replaces allow Bash '{"command":"git push origin feat/x"}'
# discriminator: the same attachment from a peer session is not the operator
mk "$T/queued-peer.jsonl" '"run the scan"' 0 ''
printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":"after the mac answers, push it","origin":{"kind":"peer"}}}\n' >> "$T/queued-peer.jsonl"
run_case queued-peer allow Bash '{"command":"git push origin feat/x"}'

# --- the measured shape (2026-10-28, Windows instance): text the operator PASTES arrives wrapped as
# --- <pasted_content id="…">…</pasted_content id="…"> (same id on both tags), and the harness says it may
# --- hold instructions the operator did not write. A pasted trading plan ("… erst zu langsam und dann
# --- herdenartig reagieren") was read as the operator's condition and held every push of the session.
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
PLAN=$'<pasted_content id="81eb">\nAnleger, die erst zu langsam und dann herdenartig reagieren.\nThen the price overshoots.\n</pasted_content id="81eb">'
# (a) the condition word only inside the pasted block: no condition
mk "$T/paste-only-inside.jsonl" "$(js "$PLAN"$'\nread this plan and push the summary branch')" 0 ''
run_case paste-only-inside allow Bash '{"command":"git push origin feat/x"}'
mk "$T/paste-only.jsonl" "$(js "$PLAN")" 0 ''
run_case paste-only allow Bash '{"command":"git push origin feat/x"}'
# ... tag attributes besides the id are tolerated
mk "$T/paste-attrs.jsonl" "$(js $'<pasted_content source="clipboard" id="81eb" lines="2">\nwait for the CI, then merge\n</pasted_content id="81eb">\nmerge it now')" 0 ''
run_case paste-attrs allow Bash '{"command":"gh pr merge 12 -R o/r --merge"}'
# ... a pasted block in a message typed mid-turn (queued_command, measured: two such records)
mk "$T/paste-queued.jsonl" '"run the scan"' 0 ''
printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"human"}}}\n' "$(js "$PLAN"$'\npush it now')" >> "$T/paste-queued.jsonl"
run_case paste-queued allow Bash '{"command":"git push origin feat/x"}'
# (b) the same word outside the tags is still the operator's condition
mk "$T/paste-word-outside.jsonl" "$(js "$PLAN"$'\ndann push es')" 0 ''
run_case paste-word-outside block Bash '{"command":"git push origin feat/x"}'
mk "$T/paste-word-before.jsonl" "$(js $'after the mac answers, push it\n'"$PLAN")" 0 ''
run_case paste-word-before block Bash '{"command":"git push origin feat/x"}'
# (c) two pasted blocks with the operator's text between them: the text between counts ...
TWO_A=$'<pasted_content id="a1f0">\nplan one, dann sell\n</pasted_content id="a1f0">\n'
TWO_B=$'\n<pasted_content id="b2e1">\nplan two, then buy\n</pasted_content id="b2e1">'
mk "$T/paste-two-between-cond.jsonl" "$(js "${TWO_A}after the mac answers, push it${TWO_B}")" 0 ''
run_case paste-two-between-cond block Bash '{"command":"git push origin feat/x"}'
# ... and with plain words between them, neither block's condition word counts
mk "$T/paste-two-between-plain.jsonl" "$(js "${TWO_A}compare the two plans and push the notes${TWO_B}")" 0 ''
run_case paste-two-between-plain allow Bash '{"command":"git push origin feat/x"}'
# discriminator: a closing tag with ANOTHER id closes nothing - the text is not stripped, the word binds
mk "$T/paste-id-mismatch.jsonl" "$(js $'<pasted_content id="a1f0">\nwait for the CI\n</pasted_content id="ffff">')" 0 ''
run_case paste-id-mismatch block Bash '{"command":"git push origin feat/x"}'

# --- fail-open: no transcript -> silent
out="$(printf '{"tool_name":"Workflow","tool_input":{},"transcript_path":"%s","cwd":"%s"}' \
  "$(native "$T/missing.jsonl")" "$(native "$T")" | node "$G" 2>&1)"
[ -z "$out" ] && ok "missing transcript allows (fail-open, measured not guessed)" || bad "missing transcript: '$out'"

echo
[ "$fail" -eq 0 ] && echo "conditional-order-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
