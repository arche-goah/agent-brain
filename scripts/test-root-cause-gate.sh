#!/usr/bin/env bash
# covers: root-cause-gate
# Fixture test for helpers/root-cause-gate.cjs — both directions, the review, the control.
# Must block: the operator's message that opened the turn reads as a correction or a mishap
# and no assistant text of the turn names a cause (the 2026-10-26 class: fixed on the spot,
# no cause named). Must allow: a cause line in any text of the turn, no correction, a
# correction only quoted, a notification turn, a re-issue, a second stop in the same turn.
# Other languages only as instance data. `--review` counts over a directory of transcripts.
# Usage: bash scripts/test-root-cause-gate.sh (exit 0 = pass)
set -u
# the gate reads CLAUDE_PROJECT_DIR before the cwd in --review; a session-start run points it at the real brain
unset CLAUDE_PROJECT_DIR
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/root-cause-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$G" ] || { echo "  FAIL gate missing: $G"; exit 1; }

# OS-3: node opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' "${WHEN:-2026-10-26T10:00:00.000Z}" "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
# write <path> [text]: a register path carries a complete class entry unless the text is given (2026-11-11: invariant + replay)
GOOD_ENTRY='invariant: a summary over a set of sources reads every source before it counts
replay: 28 turns in 401 transcripts'
# run <command> <output>: a Bash call of the session and its result (2026-11-23: a replay count must stand in a real output)
RUNID=0
run() {
  RUNID=$((RUNID + 1))
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"r%s","name":"%s","input":{"command":%s}}]}}\n' "$RUNID" "${RUNTOOL:-Bash}" "$(js "$1")"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"r%s","content":%s}]}}\n' "$RUNID" "$(js "$2")"
}
write() {
  local t="${2-}"; case "$1" in *carrier-register.md) [ $# -lt 2 ] && t="$GOOD_ENTRY"
    # the detector ran: its output carries the replay line's count, unless a case tests the claim without a run (NORUN=1)
    [ -z "${NORUN:-}" ] && run "node scripts/replay.cjs" "$(printf '%s\n' "$t" | sed -n 's/^replay:[[:space:]]*//p')";; esac
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":%s,"new_string":%s}}]}}\n' "$(js "$1")" "$(js "$t")"
}
tres() { printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}\n'; }

check() { # $1 name, $2 transcript, $3 block|allow, $4 cwd, [$5 stop_hook_active], [$6 turn_kind]
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"%s%s}' "$(native "$2")" "${5:-false}" "$(native "$4")" \
    "${6:+,\"turn_kind\":\"$6\"}" "${XP:-}" | CLAUDE_PROJECT_DIR="$(native "$4")" node "${GATE:-$G}" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}
CWD="$T/cwd"; mkdir -p "$CWD"

# --- 2026-11-23: a hook refused the very step the operator asked for ("questions now" -> AskUserQuestion refused)
aq() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"AskUserQuestion","input":{"questions":[{"question":"Release now?"}]}}]}}\n' "$1"; }
refuse() { printf '{"type":"user","timestamp":"2026-11-23T17:14:12.774Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":true,"content":%s}]}}\n' "$1" "$(js "PreToolUse:AskUserQuestion hook error: $2")"; }
{ user "work through it autonomously"; asst "ok"; user "what is open for me?"; aq a1; refuse a1 "AUTONOMOUS-GATE: the operator ordered this run autonomous, and this is a question"; asst "Fixed the ledger entry, going on."; } > "$T/ra1.jsonl"
check "the incident: a hook refused the question the operator asked for, no cause" "$T/ra1.jsonl" block "$CWD"
{ user "work through it autonomously"; asst "ok"; user "what is open for me?"; aq a2; refuse a2 "MODE-QUESTION-ORDER: the mode question comes right after answered decisions"; asst "Running the steps first."; } > "$T/ra2.jsonl"
check "a refusal that only orders the step (mode-question order) is no surprise" "$T/ra2.jsonl" allow "$CWD"
{ user "fix the readme"; aq a3; refuse a3 "AUTONOMOUS-GATE: the operator ordered this run autonomous"; asst "Filed the question."; } > "$T/ra3.jsonl"
check "a refused question the operator did not ask for is no surprise (control)" "$T/ra3.jsonl" allow "$CWD"
# --- 2026-11-23: a gate MALFUNCTION (timed out, crashed) is no decision - 45 in the 60 newest transcripts, no cause named
bashq() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":"gh pr comment 1 -b x"}}]}}\n' "$1"; }
bres() { printf '{"type":"user","timestamp":"2026-11-23T17:30:00.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":true,"content":%s}]}}\n' "$1" "$(js "PreToolUse:Bash hook error: $2")"; }
{ user "post the review"; bashq b1; bres b1 '[node "$CLAUDE_PROJECT_DIR/core/helpers/content-review-gate.cjs"]: timed out; blocking because onFailure is "block"'; asst "Retried, it went through."; } > "$T/mf1.jsonl"
check "a gate that timed out, retried without a cause" "$T/mf1.jsonl" block "$CWD"
{ user "post the review"; bashq b2; bres b2 '[command hook 29]: timed out; blocking because onFailure is "block"'; asst "Retried."; } > "$T/mf2.jsonl"
check "a numbered hook that timed out (its name unreadable) is a malfunction too" "$T/mf2.jsonl" block "$CWD"
{ user "post the review"; bashq b3; bres b3 'MECHANISM CHECK (agent-brain): a heredoc'; asst "Used a file instead."; } > "$T/mf3.jsonl"
check "a gate's decision (a refusal with a reason) is no malfunction (control)" "$T/mf3.jsonl" allow "$CWD"
# --- 2026-11-23: anomaly signals in the turn's tool results must be classified (an own command's Traceback blocks)
okres() { printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":%s,"content":%s}]}}\n' "$1" "$2" "$(js "$3")"; }
{ user "count the rules"; bashq c1; okres c1 true 'Traceback (most recent call last):
  File "<string>", line 1
KeyError: rules'; asst "Done, there are 12."; } > "$T/an1.jsonl"
check "an own command failed with a Traceback and the turn does not classify it" "$T/an1.jsonl" block "$CWD"
{ user "count the rules"; bashq c2; okres c2 true 'Traceback (most recent call last):
KeyError: rules'; asst "Anomaly: KeyError in my one-liner - own mistake. Cause: the file keys rules under \"rules\" of each block, I read the top level."; } > "$T/an2.jsonl"
# strand review 2026-11-23: a classification releases only with its backing - an "own mistake" goes the cause path (a
# Cause line of its own, which then owes the carrier and the entry); a cause tucked into the classification line is none
check "an own mistake with the cause only inside the classification line is not backed (strand review)" "$T/an2.jsonl" block "$CWD"
{ user "count the rules"; bashq c2b; okres c2b true 'Traceback (most recent call last):
KeyError: rules'; asst "Anomaly: KeyError in my one-liner - own mistake.
Cause: the file keys rules under \"rules\" of each block, I read the top level."; } > "$T/an2b.jsonl"
out=$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s","session_id":"s1"}' "$(native "$T/an2b.jsonl")" "$(native "$CWD")" | CLAUDE_PROJECT_DIR="$(native "$CWD")" node "${GATE:-$G}" 2>&1)
case "$out" in *"names a cause"*) ok "an own mistake with its Cause line goes the cause path (carrier and entry owed)";; *) bad "own mistake not on the cause path: ${out:0:160}";; esac
{ user "count the entries"; bashq c4; okres c4 true 'Traceback (most recent call last):
KeyError: id'; asst "Anomaly: traceback in count.py - intended
Counted by hand instead: 12."; } > "$T/an4.jsonl"
check "a bare 'intended' with nothing it refers to is not backed (break case C)" "$T/an4.jsonl" block "$CWD"
{ user "count the entries"; asst "Plan: run \`python3 count.py --probe\` first; it fails on purpose when the ledger has no ids yet."; bashq c5; okres c5 true 'Traceback (most recent call last):
KeyError: id'; asst "Anomaly: the KeyError - intended, the probe step \`python3 count.py --probe\` of the plan above."; } > "$T/an5.jsonl"
check "'intended' quoting the agent's own plan line is not backed (second review N2)" "$T/an5.jsonl" block "$CWD"
{ user "count the entries"; bashq c6; okres c6 true 'Traceback (most recent call last):
KeyError: id'; asst "Signal: gate false positive, moving on."; } > "$T/an6.jsonl"
check "'gate false positive' without a register entry in the turn is not backed (break case C2)" "$T/an6.jsonl" block "$CWD"
{ user "count the entries"; bashq c7; okres c7 true 'Traceback (most recent call last):
KeyError: id'; asst "Anomaly: the KeyError - gate false positive, entry written."; write "$CWD/docs/maintenance/carrier-register.md"; } > "$T/an7.jsonl"
check "'gate false positive' with its register entry written in the turn is backed" "$T/an7.jsonl" allow "$CWD"
mcall() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":%s}}]}}\n' "$1" "$(js "$2")"; }
{ user "push the branch then open the PR"; mcall m1 "git push -u origin feat/x"; bres m1 'CONDITIONAL-ORDER-GATE: the order names a condition (then)'; mcall m2 "git push -u origin feat/x # CONDITION-NONE: no condition"; okres m2 false ok; asst "Pushed."; } > "$T/an8.jsonl"
check "a refusal passed by its override marker without a classification holds (break case M)" "$T/an8.jsonl" block "$CWD"
{ user "push the branch then open the PR"; mcall m3 "git push -u origin feat/x"; bres m3 'CONDITIONAL-ORDER-GATE: the order names a condition (then)'; mcall m4 "git push -u origin feat/x # CONDITION-NONE: the then is the order of steps"; okres m4 false ok; asst "Anomaly: CONDITIONAL-ORDER-GATE read 'then' as a condition - intended, \`# CONDITION-NONE\` in the push: the then is the order of steps."; } > "$T/an9.jsonl"
check "a marker pass 'intended' citing its own marker is not backed (second review N4)" "$T/an9.jsonl" block "$CWD"
# what still backs an "intended": the operator's prompt, or a call made before the signal's call
{ user "run count.py --probe, it fails on purpose while the ledger has no ids"; bashq c12; okres c12 true 'Traceback (most recent call last):
KeyError: id'; asst "Anomaly: the KeyError - intended, \"it fails on purpose while the ledger has no ids\"."; } > "$T/an12.jsonl"
check "'intended' quoting the operator's prompt is backed" "$T/an12.jsonl" allow "$CWD"
{ user "push the branch then open the PR"; mcall e0 "git log --oneline -1 # CONDITION-NONE: the then orders the steps"; okres e0 false ok; mcall e1 "git push -u origin feat/y"; bres e1 'CONDITIONAL-ORDER-GATE: the order names a condition (then)'; mcall e2 "git push -u origin feat/y # CONDITION-NONE: the then orders the steps"; okres e2 false ok; asst "Anomaly: CONDITIONAL-ORDER-GATE - intended, \`the then orders the steps\` was stated before the push."; } > "$T/an13.jsonl"
check "'intended' quoting a call made before the signal is backed" "$T/an13.jsonl" allow "$CWD"
{ user "count the entries"; bashq c14; okres c14 true 'Traceback (most recent call last):
KeyError: id'; asst "Anomaly: traceback in \`gh pr comment 1 -b x\` - intended"; } > "$T/an14.jsonl"
check "'intended' quoting the failing call itself is not backed (second review N1)" "$T/an14.jsonl" block "$CWD"
# main session 2026-11-23: a RULE-PATH marker (gate-markers.json rule_path true) is the gate followed - it owes no line
{ user "open the PR"; mcall p1 "gh pr create --title x"; bres p1 'PRS-FIRST: read the open PRs first'; mcall p2 "gh pr create --title x # PRS-READ: none is closer"; okres p2 false ok; asst "Opened."; } > "$T/an10.jsonl"
check "a refusal passed by its rule-path marker (PRS-READ) owes no classification" "$T/an10.jsonl" allow "$CWD"
{ user "open the PR"; mcall p3 "gh pr create --title y"; bres p3 'PRS-FIRST: read the open PRs first'; mcall p4 "gh pr create --title y # NEWLY-MADE-OK: nobody names this"; okres p4 false ok; asst "Opened."; } > "$T/an11.jsonl"
check "a marker no gate entry names holds like an exception (control)" "$T/an11.jsonl" block "$CWD"
{ user "check the build"; bashq c3; okres c3 true 'Exit code 1
3 tests failed'; asst "Three tests fail; fixing them."; } > "$T/an3.jsonl"
check "a command that fails on purpose-shaped output (a failing test run) is no anomaly (control)" "$T/an3.jsonl" allow "$CWD"
# --- 2026-11-23: the register lookup per refusal - a gate refusing a tool the carrier register already holds an EARLIER
# entry for is a REPEAT (the third "question tool refused on the operator's request" was handled as a first case)
regdir() { mkdir -p "$1/docs/maintenance"; printf '%s\n' "${@:2}" > "$1/docs/maintenance/carrier-register.md"; }
RG="$T/reg"; regdir "$RG" '# Carrier register' '' '## 2026-11-05 — a request for questions read as autonomous' 'id: asks-read-as-mode-on' \
  'incident: the operator asked for the blocking questions; the first AskUserQuestion call was refused by the' '  autonomous-gate' \
  'cause: the classifier record read mode_on' 'carrier: pull request fix/decision-count (open)' 'replay: 3 hits'
{ user "fix the readme"; aq r1; refuse r1 "AUTONOMOUS-GATE: the operator ordered this run autonomous"; asst "Filed the question."; } > "$T/rr1.jsonl"
check "a refusal the register holds an earlier entry for (same gate, same tool), not classified" "$T/rr1.jsonl" block "$RG"
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/rr1.jsonl")" "$(native "$RG")" | CLAUDE_PROJECT_DIR="$(native "$RG")" node "$G" 2>&1)"
case "$out" in *'a REPEAT'*'asks-read-as-mode-on'*'effective: not stated'*) ok "the block names the earlier entry, its carrier and that its effect is not stated";; *) bad "repeat block without the entry: '${out:0:300}'";; esac
check "the same refusal with no register (control)" "$T/rr1.jsonl" allow "$CWD"
# The classification is BACKED or it releases nothing (independent review 2026-11-23: one self-written line released the hold).
REF='AUTONOMOUS-GATE: the operator ordered this run autonomous'
{ user "fix the readme"; aq r2; refuse r2 "$REF"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - intended, the run is autonomous and the operator asked nothing."; } > "$T/rr2.jsonl"
check "a repeat with a bare 'intended' line stays held" "$T/rr2.jsonl" block "$RG"
{ user "fix the readme"; asst "Plan: I put the release question once; if the gate holds it, I file the question in the ledger."; aq r3; refuse r3 "$REF"
  asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - intended, \"if the gate holds it, I file the question in the ledger\"."; } > "$T/rr3.jsonl"
# train 2026-11-23: an intended is backed only by the operator's prompt or an earlier CALL (review fix) - a plan line the AI
# wrote itself in the turn backs nothing, also on a repeat
check "a repeat classified as intended, quoting only its own plan line, stays held" "$T/rr3.jsonl" block "$RG"
{ user "fix the readme"; aq r4; refuse r4 "$REF"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - gate false positive, moving on."; } > "$T/rr4.jsonl"
check "a repeat declared a false positive with no register entry stays held" "$T/rr4.jsonl" block "$RG"
ENTRY_NO_REL='## 2026-11-23 — the question tool refused again
refusal: AUTONOMOUS-GATE AskUserQuestion
invariant: a request for questions opens the question tool whatever is filed as open
related: none
replay: 3 turns in 60 transcripts'
{ user "fix the readme"; aq r5; refuse r5 "$REF"; write "$RG/docs/maintenance/carrier-register.md" "$ENTRY_NO_REL"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - gate false positive, entry written."; } > "$T/rr5.jsonl"
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/rr5.jsonl")" "$(native "$RG")" | CLAUDE_PROJECT_DIR="$(native "$RG")" node "$G" 2>&1)"
case "$out" in *'"decision":"block"'*'names the earlier one under related'*'asks-read-as-mode-on'*) ok "a false positive whose new entry says related: none stays held and is told which entry to name";; *) bad "related: none passed: '${out:0:300}'";; esac
{ user "fix the readme"; aq r6; refuse r6 "$REF"; write "$RG/docs/maintenance/carrier-register.md" "${ENTRY_NO_REL/related: none/related: asks-read-as-mode-on}"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - gate false positive, entry written."; } > "$T/rr6.jsonl"
check "a false positive with its entry written in the turn, naming the earlier one" "$T/rr6.jsonl" allow "$RG"
{ user "fix the readme"; aq r7; refuse r7 "$REF"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - own mistake."; } > "$T/rr7.jsonl"
check "a repeat declared an own mistake with no cause line stays held" "$T/rr7.jsonl" block "$RG"
{ user "fix the readme"; aq r8; refuse r8 "$REF"; asst "Anomaly: AUTONOMOUS-GATE refused AskUserQuestion again - own mistake.
Cause: read the run mode from memory, not from the gate — I asked inside the run."; } > "$T/rr8.jsonl"
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/rr8.jsonl")" "$(native "$RG")" | CLAUDE_PROJECT_DIR="$(native "$RG")" node "$G" 2>&1)"
case "$out" in *'"decision":"block"'*'names a cause'*) ok "an own mistake with its cause line goes the cause path (carrier and entry owed)";; *) bad "own mistake + cause did not reach the cause path: '${out:0:300}'";; esac
RS="$T/reg-same-day"; regdir "$RS" '## 2026-11-23 — the question tool refused' 'id: today' 'incident: AUTONOMOUS-GATE refused AskUserQuestion' 'cause: x'
check "an entry of the refusal's own day is the present case, not an earlier one" "$T/rr1.jsonl" allow "$RS"
RO="$T/reg-other-tool"; regdir "$RO" '## 2026-11-05 — an edit held' 'id: edit-held' 'incident: AUTONOMOUS-GATE held the Edit of the settings file' 'cause: x'
check "an earlier entry for the same gate but another tool is no repeat" "$T/rr1.jsonl" allow "$RO"
RF="$T/reg-field"; regdir "$RF" '## 2026-11-05 — the questions did not come' 'id: by-field' 'refusal: AUTONOMOUS-GATE AskUserQuestion' 'incident: the operator asked and got prose' 'cause: x'
check "the refusal: field matches where the prose names neither gate nor tool" "$T/rr1.jsonl" block "$RF"
RFO="$T/reg-field-other"; regdir "$RFO" '## 2026-11-05 — an edit held' 'id: by-field-other' 'refusal: AUTONOMOUS-GATE Edit' 'incident: AUTONOMOUS-GATE refused AskUserQuestion, said the prose' 'cause: x'
check "a refusal: field decides alone - its entry's prose is not searched" "$T/rr1.jsonl" allow "$RFO"
RA="$T/reg-alias"; regdir "$RA" '## 2026-11-05 — the questions did not come' 'id: by-alias' 'incident: the autonomous gate refused the question tool' 'cause: x'
check "an entry in other words for the tool, no instance alias (control)" "$T/rr1.jsonl" allow "$RA"
mkdir -p "$RA/.claude/rules"; printf '%s\n' '{"refusal_aliases":{"AskUserQuestion":["question tool"]}}' > "$RA/.claude/rules/root-cause-patterns.json"
check "the same entry with the instance's word for the tool as refusal_aliases" "$T/rr1.jsonl" block "$RA"
XP=',"session_id":"s-one"' check "a repeat is held once per session for a gate and tool ..." "$T/rr1.jsonl" block "$RG"
XP=',"session_id":"s-one"' check "... the second time it is only recorded" "$T/rr1.jsonl" allow "$RG"
n="$(grep -c '"gate":"AUTONOMOUS-GATE"' "$RG/.claude-state/register-repeats.jsonl" 2>/dev/null || echo 0)"
[ "$n" -ge 3 ] && ok "every repeat is recorded ($n lines)" || bad "repeats recorded: $n"
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/ra1.jsonl")" "$(native "$RG")" | CLAUDE_PROJECT_DIR="$(native "$RG")" node "$G" 2>&1)"
case "$out" in *'refused the very step'*'A REPEAT'*'asks-read-as-mode-on'*) ok "the refused asked-for step names the earlier register entry too";; *) bad "refused ask without the register hit: '${out:0:300}'";; esac
out="$(CLAUDE_PROJECT_DIR="$(native "$RG")" node "$G" --register-repeats "$(native "$T")" 2>&1)"
case "$out" in *'AUTONOMOUS-GATE AskUserQuestion:'*'first entry 2026-11-05 asks-read-as-mode-on'*) ok "--register-repeats replays the lookup over a folder";; *) bad "replay: '${out:0:300}'";; esac
# --- Windows review of #640: the gate's own way on is no bypass; a label with spaces is kept whole
bcmd() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Bash","input":{"command":%s}}]}}\n' "$1" "$(js "$2")"; }
skl() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"Skill","input":{"skill":"x"}}]}}\n' "$1"; }
mkdir -p "$T/anr"
{ user "go"; bcmd w1 "git commit -a -m wip"; bres w1 'SHARED WORKING COPY: two sessions share this copy'; bcmd w2 "git commit -a -m wip again now"; okres w2 false ok; asst "done"; } > "$T/anr/bypass.jsonl"
{ user "go"; bcmd s1 "mt health check"; bres s1 'SKILL-GATE: load the skill first'; skl s2; okres s2 false ok; bcmd s3 "mt health check"; okres s3 false ok; asst "done"; } > "$T/anr/followed.jsonl"
an_out=$(env CLAUDE_PROJECT_DIR="$CWD" node "${GATE:-$G}" --anomalies "$(native "$T/anr")" 10 2>&1)
printf '%s\n' "$an_out" | grep -aq '^bypass: 1 ' && ok "a refusal then another form of the same call is a bypass" || bad "bypass not counted: $an_out"
printf '%s\n' "$an_out" | grep -aq '^followed: 1 ' && ok "a refusal, the skill load it asks for, then the same call is the way on, not a bypass" || bad "followed not counted: $an_out"
printf '%s\n' "$an_out" | grep -aq 'by SHARED WORKING COPY: 1' && ok "a gate label with spaces is counted whole" || bad "label cut: $an_out"

# --- the class: a correction, a fix on the spot, no cause named
{ user "check the PRs"; asst "Done."; user "that is already active! something went wrong"; asst "Closed the question in the register."; } > "$T/t1.jsonl"
check "correction answered without a cause" "$T/t1.jsonl" block "$CWD"
# 2026-11-18: the agent's own text finds the mishap - same inquiry, no operator word needed
{ user "go on"; asst "Measured: my earlier claim was wrong - two of the four were built on 2026-10-31. Next the questions."; } > "$T/s1.jsonl"
check "own text finds a mishap, no cause line" "$T/s1.jsonl" block "$CWD"
{ user "go on"; asst "It turned out two of the four were built.
Cause: the correction stood in a research note, not in the entry (git log f3e152ed)."; write "core/helpers/ledger-reconcile.py"; write "$CWD/docs/maintenance/carrier-register.md"; } > "$T/s2.jsonl"
check "own text finds a mishap, names the cause, writes carrier and register" "$T/s2.jsonl" allow "$CWD"
{ user "go on"; asst "It turned out two of the four were built.
Cause: the correction stood in a research note."; } > "$T/s5.jsonl"
check "own text finds a mishap, names the cause, no carrier" "$T/s5.jsonl" block "$CWD"
{ user "go on"; asst "PR #600 is merged, CI green."; } > "$T/s3.jsonl"
check "a status line is no surprise" "$T/s3.jsonl" allow "$CWD"
{ user "go on"; asst "The oblique one turned out well."; } > "$T/s6.jsonl"
check "an everyday result sentence is no surprise (Windows review)" "$T/s6.jsonl" allow "$CWD"
{ user "go on"; asst "The reviewer wrote \"it turned out fine\" - quoted."; } > "$T/s4.jsonl"
check "a quoted surprise word stays silent" "$T/s4.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "why did you ask that again?"; asst "Sorry, I will not ask again."; } > "$T/t2.jsonl"
check "why-did-you answered with an apology" "$T/t2.jsonl" block "$CWD"
{ user "go"; asst "ok"; user "the same failure class again, this keeps happening"; tres; asst "Fixed."; } > "$T/t3.jsonl"
check "failure class named by the operator, reply says fixed" "$T/t3.jsonl" block "$CWD"

# --- must allow: a cause named, in any text of the turn — with its mechanism and its register entry
# (2026-10-28: a cause named is half the step; the same turn writes the carrier and the register)
REG="docs/maintenance/carrier-register.md"
{ user "go"; asst "ok"; user "that is already active! something went wrong"; asst "Cause: the register record is a snapshot of 2026-10-16, nothing re-measured the topic (question-gate.cjs list, line 296). Class: every deferred record."; write "core/helpers/question-gate.cjs"; write "$CWD/$REG"; } > "$T/t4.jsonl"
check "correction answered with a cause line, a mechanism and the register" "$T/t4.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "why did you ask that again?"; asst "Reading the record."; tres; asst "The cause was a stale record (asked 2026-10-16, never re-measured)."; write "scripts/recheck.py"; write "$CWD/$REG"; } > "$T/t5.jsonl"
check "the cause named in a later text of the same turn" "$T/t5.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "something went wrong, leave it, nothing to build there"; asst "Cause unknown — the transcript of that session is gone; what is missing: the register's state of that day.
Carrier: none — the cause is unknown, operator-ok: \"leave it, nothing to build there\""; write "$CWD/$REG"; } > "$T/t6.jsonl"
check "cause unknown, carrier none with the operator's own words, registered" "$T/t6.jsonl" allow "$CWD"
# --- 2026-11-08 (macOS instance): register and carrier written by a SHELL command count when the file changed in this turn
sh() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(js "$1")"; }
SHW="$T/shw"; mkdir -p "$SHW/docs/maintenance" "$SHW/scripts"
NOW="$(node -e 'process.stdout.write(new Date(Date.now()-5000).toISOString())')"
touch "$SHW/scripts/gen.py"
# the shell append lands a complete entry (the register-field check reads the newest entry on disk, train 2026-11-12)
printf '## 2026-11-08 — generator pads\nid: gen-pads\ninvariant: a generator takes positions from the data file, never from a photo\nreplay: 2 cases in 40 transcripts\n' > "$SHW/$REG"
{ WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> $REG"; } > "$T/t7.jsonl"
check "register and carrier written by shell commands, changed in this turn" "$T/t7.jsonl" allow "$SHW"
{ WHEN="2099-01-01T00:00:00.000Z" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> $REG"; } > "$T/t8.jsonl"
check "the same files named but unchanged since the turn began (negative control)" "$T/t8.jsonl" block "$SHW"
{ WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; sh "python3 /x/fix.py scripts/gen.py"; } > "$T/t9.jsonl"
check "shell-written carrier, no register entry" "$T/t9.jsonl" block "$SHW"
# --- Windows review 2026-11-12 (OS-19): the register named by an ABSOLUTE path - quoted with a space (native form on
# Windows), the drive form C:/... and the Git Bash form /c/... (only where cygpath exists: node elsewhere has no drives)
SPC="$T/sh w"; mkdir -p "$SPC/docs/maintenance" "$SPC/scripts"; touch "$SPC/scripts/gen.py"; cp "$SHW/$REG" "$SPC/$REG"
{ WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> \"$(native "$SPC")/$REG\""; } > "$T/t9a.jsonl"
check "register written by an absolute quoted path with a space" "$T/t9a.jsonl" allow "$SPC"
# portability windows-latest, train #510: the runner's temp folder is an 8.3 name (`RUNNER~1`, OS-8) - a `~` inside a
# segment ended the match. Measured on every OS with a folder named that way.
TLD="$T/RUN~1"; mkdir -p "$TLD/docs/maintenance" "$TLD/scripts"; touch "$TLD/scripts/gen.py"; cp "$SHW/$REG" "$TLD/$REG"
{ WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> $(native "$TLD")/$REG"; } > "$T/t9d.jsonl"
check "register written by a path with an 8.3 short segment (RUN~1)" "$T/t9d.jsonl" allow "$TLD"
if command -v cygpath >/dev/null 2>&1; then
  M="$(cygpath -m "$SHW")"; U="/$(printf %s "${M:0:1}" | tr 'A-Z' 'a-z')${M:2}"
  { WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> $M/$REG"; } > "$T/t9b.jsonl"
  check "register written by its drive path (cygpath -m form)" "$T/t9b.jsonl" allow "$SHW"
  { WHEN="$NOW" user "go"; asst "Cause: the generator took the pad positions from the photo."; run "node scripts/replay.cjs" "2 cases in 40 transcripts"; sh "python3 /x/fix.py scripts/gen.py"; sh "cat /x/e.md >> $U/$REG"; } > "$T/t9c.jsonl"
  check "register written by its Git Bash path (/c/... form)" "$T/t9c.jsonl" allow "$SHW"
else
  echo "  --  register written by its drive path and its /c/... path (Windows only: no cygpath here)"
fi

# --- 2026-11-08 (operator, question tool): a project repo names its own carriers in .claude/rules/carrier-paths.json
PRJ="$T/prj"; mkdir -p "$PRJ/.git" "$PRJ/.claude/rules" "$PRJ/docs/bench/layout" "$PRJ/.claude/skills/bench-run"
printf '%s\n' '{"carrier_paths": ["docs/bench/layout/*.py", ".claude/skills/*/SKILL.md"]}' > "$PRJ/.claude/rules/carrier-paths.json"
{ user "go"; asst "Cause: the generator took the pad positions from the photo."; write "$PRJ/docs/bench/layout/gen.py"; write "$CWD/$REG"; } > "$T/t10.jsonl"
check "a generator the project lists as a carrier counts" "$T/t10.jsonl" allow "$CWD"
{ user "go"; asst "Cause: the bench run read only the state file."; write "$PRJ/.claude/skills/bench-run/SKILL.md"; write "$CWD/$REG"; } > "$T/t11.jsonl"
check "a listed SKILL.md counts although it is .md" "$T/t11.jsonl" allow "$CWD"
{ user "go"; asst "Cause: the generator took the pad positions from the photo."; write "$PRJ/docs/notes.py"; write "$CWD/$REG"; } > "$T/t12.jsonl"
check "a project file outside the listed globs is no carrier (control)" "$T/t12.jsonl" block "$CWD"
NOP="$T/nop"; mkdir -p "$NOP/.git" "$NOP/docs/bench/layout"
{ user "go"; asst "Cause: the generator took the pad positions from the photo."; write "$NOP/docs/bench/layout/gen.py"; write "$CWD/$REG"; } > "$T/t13.jsonl"
check "the same path in a repo without carrier-paths.json is no carrier (control)" "$T/t13.jsonl" block "$CWD"

# --- must block: the instance fixed, the tool left as it was
{ user "go"; asst "Re-posted the request to the right group."; asst "Cause: the post tool does not check the audience."; } > "$T/t20.jsonl"
check "a self-found cause, no correction, no mechanism (the 2026-10-28 class)" "$T/t20.jsonl" block "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience."; write "scripts/post.py"; } > "$T/t21.jsonl"
check "cause and mechanism, but no register entry" "$T/t21.jsonl" block "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience."; write "$CWD/$REG"; } > "$T/t22.jsonl"
check "cause and register, but neither mechanism nor a carrier-none line" "$T/t22.jsonl" block "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience."; write ".claude/rules/working-rules.md"; write "$CWD/$REG"; } > "$T/t23.jsonl"
check "a rule written as prose (.md) is no mechanism" "$T/t23.jsonl" block "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience.
Carrier: none — the harness owns that path and offers no hook"; write "$CWD/$REG"; } > "$T/t24.jsonl"
check "carrier none with a reason but no operator words (the 2026-11-02 class)" "$T/t24.jsonl" block "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience.
Carrier: none — harness path, operator-ok: \"fine, just do it\""; write "$CWD/$REG"; } > "$T/t25.jsonl"
check "carrier none with an operator quote the operator never wrote" "$T/t25.jsonl" block "$CWD"
{ user "the harness owns that path, no hook there"; asst "Cause: the post tool does not check the audience.
Carrier: none — harness path, operator-ok: \"the harness owns that path\""; write "$CWD/$REG"; } > "$T/t26.jsonl"
check "carrier none with the operator's real words" "$T/t26.jsonl" allow "$CWD"
# --- must allow: no correction
{ user "go"; asst "ok"; user "and the show?"; asst "Fixed."; } > "$T/t7.jsonl"
check "no correction in the prompt" "$T/t7.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user 'he wrote "something went wrong" in the ticket, please read it'; asst "Read it."; } > "$T/t8.jsonl"
check "a correction only quoted" "$T/t8.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "why is the fan loud?"; asst "The fan curve."; } > "$T/t9.jsonl"
check "a why-question about the work, not about the agent" "$T/t9.jsonl" allow "$CWD"
# --- pasted text is not the operator's correction (turn-kind.cjs operatorWords, measured 2026-10-28):
# a pasted e-mail or log that says "why did you" / "something went wrong" opens no inquiry
MAIL=$'<pasted_content id="81eb">\nHi, why did you cancel the booking? Something went wrong on our side.\n</pasted_content id="81eb">'
{ user "go"; asst "ok"; user "$MAIL"$'\nplease draft a reply'; asst "Drafted."; } > "$T/t9a.jsonl"
check "a correction only inside a pasted block (a)" "$T/t9a.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "$MAIL"; asst "Read it."; } > "$T/t9b.jsonl"
check "a prompt that is only a paste" "$T/t9b.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "$MAIL"$'\nsomething went wrong with your last draft'; asst "Redrafted."; } > "$T/t9c.jsonl"
check "the correction outside the pasted block (b)" "$T/t9c.jsonl" block "$CWD"
P1=$'<pasted_content id="a1f0">\nlog one: fatal error\n</pasted_content id="a1f0">\n'
P2=$'\n<pasted_content id="b2e1">\nlog two: why did you restart?\n</pasted_content id="b2e1">'
{ user "go"; asst "ok"; user "${P1}compare these two logs${P2}"; asst "Compared."; } > "$T/t9d.jsonl"
check "two pasted blocks, plain words between them (c)" "$T/t9d.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "${P1}why did you skip the second one?${P2}"; asst "Reading it now."; } > "$T/t9e.jsonl"
check "two pasted blocks, the correction between them (c)" "$T/t9e.jsonl" block "$CWD"
# --- turn mechanics
{ user "go"; asst "ok"; user "something went wrong"; asst "Looking."; user "<task-notification>ci done</task-notification>"; asst "CI green."; } > "$T/t10.jsonl"
check "a notification turn after the correction (dispatcher says notification)" "$T/t10.jsonl" allow "$CWD" false notification
check "the correction turn itself, turn kind operator" "$T/t1.jsonl" block "$CWD" false operator
check "re-issue (stop_hook_active)" "$T/t1.jsonl" allow "$CWD" true
{ cat "$T/t1.jsonl"; user "Stop hook feedback: ROOT-CAUSE-GATE: ..."; asst "still looking"; } > "$T/t11.jsonl"
check "second stop in the same turn" "$T/t11.jsonl" allow "$CWD"
XP=',"stop_check":{"label":"CAUSE","marker":"ROOT-CAUSE-GATE"}'
{ cat "$T/t1.jsonl"; user "Stop hook feedback:
CAUSE — reads as a correction"; asst "still looking"; } > "$T/t12.jsonl"
check "second stop in the same turn, echo by label" "$T/t12.jsonl" allow "$CWD"
{ cat "$T/t1.jsonl"; user "Stop hook feedback:
CLASS — gate.cjs changed"; asst "ok"; } > "$T/t13.jsonl"
check "another check's line is not its own echo" "$T/t13.jsonl" block "$CWD"
XP=''
# --- 2026-11-11: held for a MISSING cause, the re-issued reply names the cause - the carrier is still owed (one more block)
{ cat "$T/t1.jsonl"; user "Stop hook feedback: ROOT-CAUSE-GATE: reads as a correction"; asst "Cause: the summary read a subset of the shopping folder (overview file never opened)."; } > "$T/t14.jsonl"
check "cause named only after the cause block, no mechanism (the 2026-11-11 class)" "$T/t14.jsonl" block "$CWD"
{ cat "$T/t14.jsonl"; user "Stop hook feedback: ROOT-CAUSE-GATE: names a cause - no mechanism written"; asst "Building it next."; } > "$T/t15.jsonl"
check "second block already given in the turn (at most two)" "$T/t15.jsonl" allow "$CWD"
{ cat "$T/t1.jsonl"; user "Stop hook feedback: ROOT-CAUSE-GATE: reads as a correction"; asst "Cause: the summary read a subset of the shopping folder."; write "scripts/sources.cjs"; write "$CWD/$REG"; } > "$T/t16.jsonl"
check "cause after the cause block, with mechanism and register" "$T/t16.jsonl" allow "$CWD"
{ user "go"; asst "Cause: the post tool does not check the audience."; user "Stop hook feedback: ROOT-CAUSE-GATE: names a cause - no mechanism written"; asst "ok"; } > "$T/t17.jsonl"
check "the first block was already the carrier block (cause before it): re-issue passes" "$T/t17.jsonl" allow "$CWD"
# --- 2026-11-11: the register entry is a CLASS entry - invariant without the instance's names, replay with a count
C="Cause: the summary read a subset of the source folder."
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "cause: subset read
replay: 3 hits"; } > "$T/t30.jsonl"
check "register entry without invariant" "$T/t30.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: pending - later"; } > "$T/t31.jsonl"
check "register entry with replay pending" "$T/t31.jsonl" block "$CWD"
# Windows review of #491: a date is no count; a core rule number is no instance name
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 2026-11-11, not run yet"; } > "$T/t31b.jsonl"
check "register entry whose replay is only a date" "$T/t31b.jsonl" block "$CWD"
# second Windows review: a digit that counts nothing is no count either
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: not run, waits for the v2.1.5 pin"; } > "$T/t31d.jsonl"
check "register entry whose replay names only a version" "$T/t31d.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: after 3 sessions"; } > "$T/t31e.jsonl"
check "register entry whose replay names a time span" "$T/t31e.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 12 of 40 transcripts"; } > "$T/t31f.jsonl"
check "register entry whose replay is n of m" "$T/t31f.jsonl" allow "$CWD"
# 2026-11-11 train-head review: real register lines count anything as "<n> <noun>", not only a fixed word list.
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 4 own drafts, 3 with the id"; } > "$T/t31g.jsonl"
check "register entry whose replay counts its own nouns" "$T/t31g.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 60 echoes, 47 blocks, 0 changed"; } > "$T/t31h.jsonl"
check "register entry whose replay lists several counts" "$T/t31h.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 1 (this case)"; } > "$T/t31i.jsonl"
check "register entry whose replay is a bare number (control)" "$T/t31i.jsonl" block "$CWD"
# 2026-11-23 (macOS instance, operator: "wenn ich auf einen fehler hinweise … musst du … generische fixes testen"; measured: 26 of
# 466 register replays counted only the incident's own session, 4 of them that day, all passed): a replay whose only scope is
# the incident's own session or the case itself is no replay over the history.
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: this session: 1 hit (this one)"; } > "$T/t31j.jsonl"
check "register entry whose replay counts only its own session" "$T/t31j.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: 2 hits (this case and one more) in the current transcript"; } > "$T/t31k.jsonl"
check "register entry whose replay scope is the current transcript" "$T/t31k.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: this session 1 hit; 7 hits in 60 earlier transcripts"; } > "$T/t31l.jsonl"
check "own session plus a wider scope with its count" "$T/t31l.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: none - the detector needs records that start today - recheck 2026-12-07"; } > "$T/t31m.jsonl"
check "a replay that cannot run yet, with reason and recheck (control)" "$T/t31m.jsonl" allow "$CWD"
# 2026-11-23, independent review of the strand: "the gate accepts the agent's claim that a replay ran" - a count must stand in
# the output of a command or an agent of the session, a printed text is no measurement.
E="invariant: a summary reads every source before it counts"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: 0 hits in 60 transcripts"; } > "$T/t31n.jsonl"
check "a replay count no command printed (the review's case G)" "$T/t31n.jsonl" block "$CWD"
{ user "go"; asst "$C"; run "echo '0 hits in 60 transcripts'" "0 hits in 60 transcripts"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: 0 hits in 60 transcripts"; } > "$T/t31o.jsonl"
check "a replay count only an echo printed" "$T/t31o.jsonl" block "$CWD"
{ user "go"; asst "$C"; run "node scripts/replay.cjs" "3 hits in 60 transcripts"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: 7 hits in 60 transcripts"; } > "$T/t31p.jsonl"
check "a replay count that differs from what the run printed" "$T/t31p.jsonl" block "$CWD"
{ user "go"; asst "$C"; run "node scripts/replay.cjs --history" "scanned 60 transcripts: 7 hits"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: 7 hits in 60 transcripts"; } > "$T/t31q.jsonl"
check "a replay count the run printed (control)" "$T/t31q.jsonl" allow "$CWD"
{ user "go"; asst "$C"; RUNTOOL=Agent run "count the hits over the history" "Result: 7 hits in 60 transcripts"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: 7 hits in 60 transcripts"; } > "$T/t31r.jsonl"
check "a replay count an agent of the session reported (control)" "$T/t31r.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; NORUN=1 write "$CWD/$REG" "$E
replay: none - the detector needs records that start today - recheck 2026-12-07"; } > "$T/t31s.jsonl"
check "none with recheck needs no run (control)" "$T/t31s.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: a promise binds only with a mechanism (Working Rule #10)
replay: 6 turns"; } > "$T/t31c.jsonl"
check "invariant citing a core rule number" "$T/t31c.jsonl" allow "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: the shopping overview must list docs/business/list.md
replay: 4 hits"; } > "$T/t32.jsonl"
check "invariant names a path (the instance, not the rule)" "$T/t32.jsonl" block "$CWD"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$CWD/$REG" "invariant: PR #472 must not repeat the missing-carrier slip
replay: 4 hits"; } > "$T/t33.jsonl"
check "invariant names a PR number" "$T/t33.jsonl" block "$CWD"
# --- 2026-11-16 root-cause review: an entry is judged whenever the register is written, not only in a cause turn
{ user "go"; asst "Register entry added."; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: pending - after the pin"; } > "$T/t40.jsonl"
check "register written without a cause line, replay pending" "$T/t40.jsonl" block "$CWD"
{ user "go"; asst "Register entry added."; write "$CWD/$REG"; } > "$T/t41.jsonl"
check "register written without a cause line, complete entry" "$T/t41.jsonl" allow "$CWD"
{ user "go"; asst "Register entry added."; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: none - single case, no instrument reads it yet - recheck 2026-12-01"; } > "$T/t42.jsonl"
check "replay none with reason and recheck date" "$T/t42.jsonl" allow "$CWD"
{ user "go"; asst "Register entry added."; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: none - later"; } > "$T/t43.jsonl"
check "replay none without a recheck date" "$T/t43.jsonl" block "$CWD"
{ user "go"; asst "Register entry added."; write "$CWD/$REG" "invariant: a summary reads every source before it counts
replay: none - looked once on 2025-01-01"; } > "$T/t43b.jsonl"
check "replay none with a date but no recheck word (Windows review 2026-11-17)" "$T/t43b.jsonl" block "$CWD"
{ user "go"; asst "Done."; write "docs/notes.md" "x"; } > "$T/t44.jsonl"
check "no register write, no cause (control)" "$T/t44.jsonl" allow "$CWD"
mkdir -p "$T/cwdf/.claude/rules"; printf '{"invariant_forbidden":["\\\\bwaveshare\\\\b"]}' > "$T/cwdf/.claude/rules/root-cause-patterns.json"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$T/cwdf/$REG" "invariant: a waveshare splitter decision reaches the purchase list
replay: 4 hits"; } > "$T/t34.jsonl"
check "invariant uses an instance proper noun (instance data)" "$T/t34.jsonl" block "$T/cwdf"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$T/cwdf/$REG" "invariant: a decision taken in a question reaches its single home in the same session
replay: 18 hits in 13 sessions"; } > "$T/t35.jsonl"
check "domain-free invariant with a replay count" "$T/t35.jsonl" allow "$T/cwdf"
# written without text in the transcript (shell append): the newest entry on disk is judged
mkdir -p "$T/disk/docs/maintenance"; printf '## old\ninvariant: an older rule said once\nreplay: 2\n\n## new\ncause: x\n' > "$T/disk/$REG"
{ user "go"; asst "$C"; run "node scripts/replay.cjs" "5 turns"; write "scripts/sources.cjs"; write "$T/disk/$REG" ""; } > "$T/t36.jsonl"
check "entry on disk: the newest one lacks the invariant (an older one has it)" "$T/t36.jsonl" block "$T/disk"
printf '## new\ninvariant: a summary reads every source before it counts\nreplay: 5 turns\n' >> "$T/disk/$REG"
check "entry on disk: the newest one is complete" "$T/t36.jsonl" allow "$T/disk"
# a register without `## ` headings: the last block is judged, not the whole file (Windows review of #491, finding 3)
mkdir -p "$T/disk2/docs/maintenance"; printf 'invariant: an older rule said once\nreplay: 2 hits\n\ncause: x\n' > "$T/disk2/$REG"
check "entry on disk without headings: the last block lacks the invariant" "$T/t36.jsonl" block "$T/disk2"
# an edit that completes an entry of an earlier turn is judged with the entry it lands in (same review, finding 4)
mkdir -p "$T/disk3/docs/maintenance"; printf '## e1\ninvariant: a summary reads every source before it counts\nreplay: 7 turns in 40 transcripts\n\n## e2\ncause: y\n' > "$T/disk3/$REG"
{ user "go"; asst "$C"; write "scripts/sources.cjs"; write "$T/disk3/$REG" "replay: 7 turns in 40 transcripts"; } > "$T/t37.jsonl"
check "edit adds the replay line to an entry whose invariant stands" "$T/t37.jsonl" allow "$T/disk3"
printf '## e1\ncause: z\nreplay: 7 turns in 40 transcripts\n' > "$T/disk3/$REG"
check "edit adds the replay line to an entry without invariant" "$T/t37.jsonl" block "$T/disk3"

# --- other languages only as instance data (the German lines here are DATA an instance carries)
DE="$T/cwd-de"; mkdir -p "$DE/.claude/rules"
printf '%s\n' '{"correction_patterns": ["\\bschief ?gelaufen\\b", "\\bist doch schon\\b"], "cause_patterns": ["^[ \\t>*_-]*ursache\\b[^\\n]{0,24}:"]}' > "$DE/.claude/rules/root-cause-patterns.json"
{ user "los"; asst "ok"; user "ist doch schon aktiv! da ist was schief gelaufen"; asst "Frage im Register geschlossen."; } > "$T/t14.jsonl"
check "German correction without instance data" "$T/t14.jsonl" allow "$CWD"
check "German correction with instance data, no cause" "$T/t14.jsonl" block "$DE"
{ user "los"; asst "ok"; user "ist doch schon aktiv! da ist was schief gelaufen"; asst "Ursache: der Eintrag ist ein Schnappschuss vom 16.10., das Thema war seitdem ungelesen."; write "core/helpers/question-gate.cjs"; write "$DE/$REG"; } > "$T/t15.jsonl"
check "German correction with a German cause line" "$T/t15.jsonl" allow "$DE"

# --- the review: counts over a directory of transcripts, carrier = a mechanism file written
# within five turns
RD="$T/review"; mkdir -p "$RD"
{ WHEN=2026-10-01T10:00:00.000Z user "go"; asst "ok"; WHEN=2026-10-01T11:00:00.000Z user "something went wrong"; asst "Fixed."; WHEN=2026-10-01T12:00:00.000Z user "next"; write "core/helpers/some-gate.cjs"; asst "built"; } > "$RD/a.jsonl"
{ WHEN=2026-10-02T10:00:00.000Z user "why did you stop?"; asst "Cause: the watcher had no deadline (loop-watchdog.sh line 40)."; WHEN=2026-10-02T11:00:00.000Z user "ok"; asst "done"; } > "$RD/b.jsonl"
{ WHEN=2026-09-30T10:00:00.000Z user "that is wrong"; asst "Changed the value."; } > "$RD/c.jsonl"
out="$(cd "$CWD" && node "$G" --review 10 --dir "$(native "$RD")" 2>&1)"
case "$out" in *'transcripts 3 · operator turns 6 · corrections 3 · reply named a cause 1 (33 %) · a mechanism file written within 5 turns 1 (33 %)'*) ok "review counts corrections, causes and carriers";;
  *) bad "review counts: $out";; esac
case "$out" in *'| 2026-09 | 1 | 0 | 0 |'*'| 2026-10 | 2 | 1 | 1 |'*) ok "review tallies per month";; *) bad "review months: $out";; esac
case "$out" in *'(no mechanism within 5 turns): "that is wrong"'*'(mechanism written later): "something went wrong"'*) ok "review lists the corrections without a cause, oldest first";; *) bad "review list: $out";; esac
out="$(cd "$CWD" && node "$G" --review 10 --since 2026-10-02 --dir "$(native "$RD")" 2>&1)"
case "$out" in *'corrections 1 ·'*) ok "review --since cuts older turns";; *) bad "review since: $out";; esac
# 2026-11-02: a headless classifier call's transcript (entrypoint sdk-cli) is no session and adds no correction.
printf '{"type":"user","entrypoint":"sdk-cli","timestamp":"2026-10-03T10:00:00.000Z","message":{"role":"user","content":"something went wrong"}}\n' > "$RD/headless.jsonl"
out="$(cd "$CWD" && node "$G" --review 10 --dir "$(native "$RD")" 2>&1)"
case "$out" in *'transcripts 3 · operator turns 6 · corrections 3 ·'*) ok "a headless classifier transcript is left out";; *) bad "headless counted: $out";; esac
rm -f "$RD/headless.jsonl"
# 2026-11-02 (audit-audit): the register says who found each mishap; the review counts it.
mkdir -p "$CWD/docs/maintenance"
printf '%s\n' '# reg' '## a' 'found-by: operator' 'should-have: brain-scan' 'replay: 1' '## b' 'found-by: recorder-report' 'replay: 1' '## c' 'replay: 1' > "$CWD/$REG"
out="$(cd "$CWD" && node "$G" --review 10 --dir "$(native "$RD")" 2>&1)"
case "$out" in *'found-by named 2, of them by a check 1'*) ok "review counts who found the register entries";; *) bad "found-by: $out";; esac
# without --dir the transcripts are found where Claude Code keeps them: every non-alphanumeric
# character of the project path becomes '-' (a dot here; the drive colon on Windows)
PROJ="$T/my.brain"; mkdir -p "$PROJ"
SLUG="$(node -e 'process.stdout.write(require("path").resolve(process.argv[1]).replace(/[^A-Za-z0-9]/g,"-"))' "$(native "$PROJ")")"
mkdir -p "$T/fakehome/.claude/projects/$SLUG"; cp "$RD/a.jsonl" "$T/fakehome/.claude/projects/$SLUG/"
out="$(cd "$PROJ" && HOME="$(native "$T/fakehome")" USERPROFILE="$(native "$T/fakehome")" CLAUDE_PROJECT_DIR="$(native "$PROJ")" node "$G" --review 10 2>&1)"
case "$out" in *'transcripts 1 ·'*) ok "review finds the project's transcripts by the minted folder name";; *) bad "review default dir: $out";; esac
out="$(cd "$CWD" && node "$G" --review 10 --dir "$T/nowhere" 2>&1)"
case "$out" in *'no transcripts under'*) ok "review without transcripts says so";; *) bad "review nowhere: $out";; esac

# --- negative control
printf 'process.stdin.resume();process.stdin.on("end",()=>process.exit(0));\n' > "$T/stub.cjs"
before=$fail; fail=0
for c in t1 t2 t3; do GATE="$T/stub.cjs" check "stub on $c" "$T/$c.jsonl" block "$CWD" >/dev/null; done
caught=$fail; fail=$before
[ "$caught" = 1 ] && ok "always-allow stub fails the must-block cases" || bad "negative control: stub passed"

# --- the prompt classifier's record opens the inquiry when the words miss (2026-10-30, macOS instance)
IC="$T/intent"; mkdir -p "$IC/.claude-state"
WHEN=2026-10-30T18:13:30.000Z
{ user "go"; asst "ok"; user "find the cause and fix it at the root, now"; asst "Done."; } > "$T/sess-rc.jsonl"
check "words miss, no classifier record: allows (control)" "$T/sess-rc.jsonl" allow "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"sess-rc","mode":"hook","model":{"asks_open":false,"mode_on":false,"mode_off":false,"correction":true}}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "classifier reads correction=true: the inquiry opens" "$T/sess-rc.jsonl" block "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"other","mode":"hook","model":{"correction":true}}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "a record of another session does not count" "$T/sess-rc.jsonl" allow "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"sess-rc","mode":"hook","model":{"correction":false}}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "classifier reads no correction: allows" "$T/sess-rc.jsonl" allow "$IC"
# 2026-11-18 (operator decision): the record decides both ways - a word hit the model reads as no correction passes
{ user "go"; asst "ok"; user "that is already active! something went wrong"; asst "Done."; } > "$T/sess-rw.jsonl"
: > "$IC/.claude-state/intent-classifier.jsonl"
check "words hit, no record: blocks (control)" "$T/sess-rw.jsonl" block "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"sess-rw","mode":"hook","model":{"correction":false}}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "words hit, the record reads no correction: allows" "$T/sess-rw.jsonl" allow "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"sess-rw","mode":"hook","model":null}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "a failed classifier call falls back to the words: blocks" "$T/sess-rw.jsonl" block "$IC"
printf '{"at":"2026-10-30T18:13:35.000Z","session":"sess-rw","mode":"hook","prompt":"something else entirely","model":{"correction":false}}\n' > "$IC/.claude-state/intent-classifier.jsonl"
check "a record of another prompt does not count: blocks" "$T/sess-rw.jsonl" block "$IC"
unset WHEN

# --- a correction typed mid-turn (queued_command attachment, 2026-10-29 / 2026-11-02, macOS instance)
qcmd() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"human"}}}\n' "$(js "$1")"; }
qpeer() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"peer"}}}\n' "$(js "$1")"; }
{ user "work through the list"; asst "on it"; qcmd "that is already active! something went wrong"; asst "Closed the question in the register."; } > "$T/q1.jsonl"
check "a correction typed mid-turn, answered without a cause" "$T/q1.jsonl" block "$CWD"
{ user "work through the list"; asst "on it"; qcmd "that is already active! something went wrong"; asst "Cause unknown — the transcript of that session is gone; what is missing: the register's state of that day.
Carrier: none — the cause is unknown, nothing to build until it is measured, operator-ok: \"that is already active! something went wrong\""; write "$CWD/$REG"; } > "$T/q2.jsonl"
check "a mid-turn correction answered with a cause line" "$T/q2.jsonl" allow "$CWD"
{ user "work through the list"; asst "on it"; qpeer "that is already active! something went wrong"; asst "noted"; } > "$T/q3.jsonl"
check "negative control: the same words from a peer session are no operator correction" "$T/q3.jsonl" allow "$CWD"
# --- a correction typed mid-turn and FOLLOWED by another typed message (2026-11-04, macOS instance: 18 of 33 correction
# segments in 80 transcripts were not the last of their turn and the gate judged the last only; 4 got no cause at all)
{ user "work through the list"; asst "on it"; qcmd "that is already active! something went wrong"; asst "On it."; qcmd "and note the log path for later"; asst "Noted."; } > "$T/q4.jsonl"
check "a mid-turn correction followed by another message, answered without a cause" "$T/q4.jsonl" block "$CWD"
{ user "work through the list"; asst "on it"; qcmd "that is already active! something went wrong"; asst "On it."; qcmd "and note the log path for later"; asst "Cause unknown — the transcript of that session is gone; what is missing: the register's state of that day.
Carrier: none — the cause is unknown, nothing to build until it is measured, operator-ok: \"that is already active! something went wrong\""; write "$CWD/$REG"; } > "$T/q5.jsonl"
check "the cause named after the later message answers the earlier correction" "$T/q5.jsonl" allow "$CWD"

# --- --pre (PreToolUse): in a correction turn the class comes before the instance (operator 2026-11-03: "or once again
# only the instance fixed afterwards instead of the class?"). The day's case: the first edit went to the model script.
pre() { # $1 name, $2 transcript, $3 target file, $4 deny|allow
  local out
  out="$(printf '{"transcript_path":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":%s}}' "$(native "$2")" "$(native "$CWD")" \
    "$(js "$3")" | CLAUDE_PROJECT_DIR="$(native "$CWD")" node "$G" --pre 2>&1)"
  if [ "$4" = deny ]; then
    case "$out" in *'"permissionDecision":"deny"'*) ok "$1 denies";; *) bad "$1 did not deny: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 denied wrongly: '$out'"
  fi
}
{ user "go"; asst "ok"; user "why did you build it like that? the card falls out, something went wrong"; asst "Cause: the lip was measured at one ray."; } > "$T/p1.jsonl"
pre "correction turn, first edit to the model (the 2026-11-03 case)" "$T/p1.jsonl" "models/card-holder/card_holder.py" deny
pre "the carrier itself (tools/) passes" "$T/p1.jsonl" "tools/print_gates.py" allow
pre "a ledger or register (.md) passes" "$T/p1.jsonl" "docs/maintenance/carrier-register.md" allow
{ user "go"; asst "ok"; user "why did you build it like that? something went wrong"; write "tools/print_gates.py"; } > "$T/p2.jsonl"
pre "a carrier already written this turn frees the instance edit" "$T/p2.jsonl" "models/card-holder/card_holder.py" allow
{ user "go"; asst "ok"; user "why did you build it like that? something went wrong"; asst "Carrier: none - a one-off typo in a label, no tool produced it"; } > "$T/p3.jsonl"
pre "Carrier: none with a reason frees it" "$T/p3.jsonl" "models/card-holder/card_holder.py" allow
{ user "make the tab narrower"; asst "ok"; } > "$T/p4.jsonl"
pre "negative control: an order, no correction" "$T/p4.jsonl" "models/card-holder/card_holder.py" allow

[ "$fail" = 0 ] && echo "root-cause-gate: all checks passed" || echo "root-cause-gate: FAILURES"
exit "$fail"
