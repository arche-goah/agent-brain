#!/usr/bin/env bash
# covers: question-gate close-stamp
# Fixture test for helpers/question-gate.cjs — both directions, plus the CLI.
# The must-block case is the incident (2026-10-09): a proposal ended as a question, the
# operator's next prompt was about something else, and the question scrolled away.
# Must allow: a question the operator has not seen yet (the reply being ended), a settled
# question (answered/dropped/deferred), a question inside code or quotes, a plain "why?",
# a re-issue, a second stop in the same turn. German grips only as instance data.
# #269 (2026-10-11): a deferral is accepted only with words the operator wrote after the
# question in the recorded transcript (paraphrase refused, unreadable transcript refused);
# `adopt <id>` prints the operator's prompts after an orphaned question and marks it;
# `list` names that call for a question from an earlier day.
# Usage: bash scripts/test-question-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/question-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$G" ] || { echo "  FAIL gate missing: $G"; exit 1; }

# OS-3: node opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
tres() { printf '{"message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}\n'; }

check() { # $1 name, $2 transcript, $3 block|allow, $4 root, [$5 stop_hook_active]; $SID = session id
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"session_id":"%s"%s}' "$(native "$2")" "${5:-false}" "${SID:-}" "${XP:-}" \
    | CLAUDE_PROJECT_DIR="$(native "$4")" node "${GATE:-$G}" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *'"decision":"block"'*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}
fresh() { rm -rf "$1"; mkdir -p "$1"; }
cli() { CLAUDE_PROJECT_DIR="$(native "$1")" node "$G" "${@:2}"; }
Q="Shall I build the clock check as a PR?"

# --- the incident: question asked, operator moved on, question never settled
R="$T/r1"; fresh "$R"
{ user "check the PRs"; asst "Done. $Q"; user "are your watches running?"; tres; asst "Yes, re-armed."; } > "$T/t1.jsonl"
check "question scrolled past the operator's next prompt" "$T/t1.jsonl" block "$R"

# notifications between question and prompt do not hide it
R="$T/r2"; fresh "$R"
{ user "go"; asst "Done. $Q"; user "<task-notification>ci done</task-notification>"; asst "CI green."; user "next thing"; asst "ok"; } > "$T/t2.jsonl"
check "question, then notification replies, then a prompt" "$T/t2.jsonl" block "$R"

R="$T/r2b"; fresh "$R"
{ user "go"; asst "**3 items I can handle myself, shall I?**"; user "something else"; asst "ok"; } > "$T/t2b.jsonl"
check "question wrapped in bold markers" "$T/t2b.jsonl" block "$R"

# --- must allow
R="$T/r3"; fresh "$R"
{ user "go"; asst "Done. $Q"; } > "$T/t3.jsonl"
check "question in the reply being ended (not seen yet)" "$T/t3.jsonl" allow "$R"

for st in answered dropped deferred unanswered; do
  R="$T/r-$st"; fresh "$R"
  check "first run records the question ($st case)" "$T/t1.jsonl" block "$R" >/dev/null
  id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
  note=fixture; [ "$st" = deferred ] && note="are your watches running?"  # a deferral quotes the operator (#269)
  cli "$R" resolve "$id=$st:$note" >/dev/null
  check "question settled as $st" "$T/t1.jsonl" allow "$R"
done
R="$T/r-deferred"
case "$(cli "$R" list)" in *'[deferred]'*) ok "deferred question is listed for the session start";; *) bad "deferred not listed";; esac
R="$T/r-unanswered"
case "$(cli "$R" list)" in *'[unanswered]'*) ok "unanswered question is listed for the session start";; *) bad "unanswered not listed";; esac
# A listed question carries the text before it (measured 2026-10-12: a bare "Do you want it,
# and when?" stood at three session starts and no session could tell its topic).
case "$(cli "$R" list)" in *'about: Done.'*) ok "listed question names its context";; *) bad "no context line: $(cli "$R" list)";; esac
R="$T/r-noctx"; fresh "$R"
{ user "go"; asst "$Q"; user "something else"; asst "ok"; } > "$T/t-noctx.jsonl"
check "question without text before it" "$T/t-noctx.jsonl" block "$R" >/dev/null
case "$(cli "$R" list)" in *'about:'*) bad "empty context printed: $(cli "$R" list)";; *'[open]'*) ok "no text before it = no context line";; *) bad "question not recorded";; esac
# Deferred means the OPERATOR postponed it (operator decision 2026-10-10): the note must carry
# their words. Measured the same day: overlooked questions were filed as deferred.
R="$T/r-defer-bare"; fresh "$R"
check "first run records the question (bare deferred case)" "$T/t1.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
out="$(cli "$R" resolve "$id=deferred")"; rc=$?
case "$rc:$out" in [1-9]*:*"needs the operator's own words"*) ok "deferred without the operator's words is refused";;
  *) bad "bare deferred accepted (rc=$rc): $out";; esac
case "$(cli "$R" list)" in *'[open]'*) ok "refused deferral leaves the question open";; *) bad "refused deferral changed the state";; esac
# #269 gap 4: the words must stand in an operator prompt AFTER the question — a paraphrase is refused.
out="$(cli "$R" resolve "$id=deferred:later, not now")"; rc=$?
case "$rc:$out" in [1-9]*:*"not what the operator wrote"*) ok "deferred with words the operator never wrote is refused";;
  *) bad "paraphrased deferral accepted (rc=$rc): $out";; esac
R="$T/r-defer-quoted"; fresh "$R"
{ user "check the PRs"; asst "Done. $Q"; user "later, not now please — first the show"; asst "Noted."; } > "$T/t-defer.jsonl"
check "first run records the question (quoted deferred case)" "$T/t-defer.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
cli "$R" resolve "$id=deferred:later, not now" >/dev/null && ok "deferred with the operator's words is accepted" \
  || bad "deferred with the operator's own words refused"
# a record whose transcript is gone cannot prove a deferral
R="$T/r-defer-gone"; fresh "$R"; cp "$T/t-defer.jsonl" "$T/t-gone.jsonl"
check "first run records the question (gone transcript case)" "$T/t-gone.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
rm -f "$T/t-gone.jsonl"
out="$(cli "$R" resolve "$id=deferred:later, not now")"; rc=$?
case "$rc:$out" in [1-9]*:*"cannot be checked"*) ok "deferral without a readable transcript is refused";;
  *) bad "unverifiable deferral accepted (rc=$rc): $out";; esac
# #269 gaps 2+3: an orphan is adopted WITH what the operator said after it
R="$T/r-adopt"; fresh "$R"
{ user "check the PRs"; asst "Done. $Q"; user "way 1, build it"; asst "Building."; user "and the show?"; asst "ok"; } > "$T/t-adopt.jsonl"
check "first run records the question (adopt case)" "$T/t-adopt.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
out="$(cli "$R" adopt "$id")"
case "$out" in *'> way 1, build it'*'> and the show?'*'settle: node core/helpers/question-gate.cjs resolve'*) ok "adopt prints the operator's prompts after the question";;
  *) bad "adopt output: $out";; esac
grep -q '"adopted"' "$R/.claude-state/open-questions.json" && ok "adopt marks the record" || bad "adopt left no mark"
# a question asked on an earlier day is listed as an orphan with the adopt call
node -e '
const fs=require("fs");const p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
for (const k in s) s[k].asked="2020-01-01T00:00:00.000Z";fs.writeFileSync(p,JSON.stringify(s));' "$R/.claude-state/open-questions.json"
case "$(cli "$R" list)" in *"orphan — settle from evidence: node core/helpers/question-gate.cjs adopt $id"*) ok "an old open question is listed as an orphan with its adopt call";;
  *) bad "orphan hint missing: $(cli "$R" list)";; esac
R="$T/r-answered"
[ -z "$(cli "$R" list)" ] && ok "answered question is not listed" || bad "answered still listed"
case "$(cli "$R" resolve deadbeef=answered)" in *unknown*) ok "unknown id is refused";; *) bad "unknown id accepted";; esac

R="$T/r4"; fresh "$R"
{ user "go"; asst 'Run `should I do it?` in the shell. He asked "shall I go?" there.'; user "next"; asst "ok"; } > "$T/t4.jsonl"
check "question only inside code and quotes" "$T/t4.jsonl" allow "$R"
{ user "go"; asst "Why did it fail? The lock was stale."; user "next"; asst "ok"; } > "$T/t5.jsonl"
check "a plain why-question is not a proposal" "$T/t5.jsonl" allow "$R"

R="$T/r6"; fresh "$R"
check "re-issue (stop_hook_active)" "$T/t1.jsonl" allow "$R" true
{ cat "$T/t1.jsonl"; user "Stop hook feedback: QUESTION-GATE: ..."; asst "settling it"; } > "$T/t6.jsonl"
check "second stop in the same turn" "$T/t6.jsonl" allow "$R"
# Own echo by LABEL (operator 2026-10-10: no codes in the stop lines): behind the dispatcher the
# gate gets stop_check.label and its line carries no token; another check's line is not its own.
XP=',"stop_check":{"label":"QUESTION","marker":"QUESTION-GATE"}'
R="$T/r6l"; fresh "$R"
{ cat "$T/t1.jsonl"; user "Stop hook feedback:
QUESTION — 1 question(s) still open"; asst "settling it"; } > "$T/t6l.jsonl"
check "second stop in the same turn, echo by label" "$T/t6l.jsonl" allow "$R"
R="$T/r6f"; fresh "$R"
{ cat "$T/t1.jsonl"; user "Stop hook feedback:
CLASS — gate.cjs changed"; asst "ok"; } > "$T/t6f.jsonl"
check "another check's line is not its own echo" "$T/t6f.jsonl" block "$R"
XP=''

# --- German only as instance data
R="$T/r7"; fresh "$R"
{ user "los"; asst "Fertig. Soll ich den Uhr-Check als PR bauen?"; user "laufen die watches?"; asst "ja"; } > "$T/t7.jsonl"
check "German question without instance data" "$T/t7.jsonl" allow "$R"
fresh "$R"; mkdir -p "$R/.claude/rules"; printf '{"question_patterns":["\\\\bsoll ich\\\\b"]}\n' > "$R/.claude/rules/open-questions.json"
check "German question with instance data" "$T/t7.jsonl" block "$R"

# --- the close turn (coherence scan 2026-10-15, P1-2): an open question is carried to the next
# session as an open end of the close's session-log entry, not asked again while the operator
# leaves. A close stamp of this session and turn passes a question listed by id or sentence;
# a stamp without the listing, another session's stamp, or no stamp still block.
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(js "$1")"; }
CLOSE_LINE="- 2026-10-15 10:00:00 | main | close"
stamp() { # $1 root, $2 stamp session id, $3 open-end line of this close's entry (may be empty)
  mkdir -p "$1/.claude-state" "$1/docs/maintenance"
  printf '%s\n%s\n' "$2" "$CLOSE_LINE" > "$1/.claude-state/session-close.stamp"
  { echo "$CLOSE_LINE"; echo "  topic: fixture close"; [ -n "$3" ] && printf '%s\n' "$3"; } > "$1/docs/maintenance/session-log.md"
}
{ user "check the PRs"; asst "Done. $Q"; user "close the session"
  tool "bash core/helpers/session-closing.sh --pre-commit --session S1"; tres; asst "Persisted - you can shut down."; } > "$T/qc1.jsonl"
SID=S1
R="$T/rc"; fresh "$R"
check "close turn, no stamp: the open question still blocks" "$T/qc1.jsonl" block "$R"
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
stamp "$R" S1 "  open end: question $id (clock check as a PR) - ask at the next start"
check "close stamp + question listed by id" "$T/qc1.jsonl" allow "$R"
case "$(cli "$R" list)" in *'[open]'*) ok "a listed question stays open for the next session start";; *) bad "listed question was closed";; esac
stamp "$R" S1 "  open end: operator question \"$Q\""
check "close stamp + question listed by its sentence" "$T/qc1.jsonl" allow "$R"
stamp "$R" S1 ""
check "close stamp without the listing" "$T/qc1.jsonl" block "$R"
stamp "$R" OTHER "  open end: question $id"
check "close stamp of another session" "$T/qc1.jsonl" block "$R"
{ user "check the PRs"; asst "Done. $Q"; user "close the session"; asst "Persisted - you can shut down."; } > "$T/qc2.jsonl"
stamp "$R" S1 "  open end: question $id"
check "close stamp, but this turn never ran the close" "$T/qc2.jsonl" block "$R"
SID=""

# --- a recorded question is measured before it is asked again (2026-10-26): the question tool
# call that raises a deferred, unanswered or orphaned record is refused until the record carries
# a fresh `recheck` stamp or is settled. The incident: a question postponed ten days earlier was
# re-asked word for word from the record while the device already carried the answer.
ask() { # $1 name, $2 question text, $3 deny|allow, $4 root; $SID = session id
  local out
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"%s","tool_input":{"questions":[{"question":%s,"header":"h","options":[{"label":"yes","description":"go"},{"label":"no","description":"later"}]}]}}' "${SID:-}" "$(js "$2")" \
    | CLAUDE_PROJECT_DIR="$(native "$4")" node "${GATE:-$G}" 2>&1)"
  if [ "$3" = deny ]; then
    case "$out" in *'"permissionDecision":"deny"'*) ok "$1 is refused";; *) bad "$1 was not refused: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 passes" || bad "$1 refused wrongly: '$out'"
  fi
}
R="$T/r-reask"; fresh "$R"
{ user "check the PRs"; asst "Checked the clock drift ledger entry and the launchd schedule. $Q"; user "later, not now please — first the show"; asst "Noted."; } > "$T/t-reask.jsonl"
check "first run records the question (re-ask case)" "$T/t-reask.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
cli "$R" resolve "$id=deferred:later, not now" >/dev/null
case "$(cli "$R" list)" in *"measure its topic: node core/helpers/question-gate.cjs recheck $id="*) ok "a deferred record is listed with its recheck call";;
  *) bad "no recheck call for the deferred record: $(cli "$R" list)";; esac
ask "the deferred question, same sentence" "Clock check (deferred since Monday): $Q" deny "$R"
# the match thresholds come from a replay over the history (header of raisesAgain): most of the
# record's content words, sentence and context together, and only when there are enough of them
ask "the deferred question, paraphrased from the record and its context" "Shall we build the clock drift check now — the ledger entry and the launchd schedule say it is due?" deny "$R"
ask "a question sharing only the recurring words" "Shall I build the PR list check first?" allow "$R"
ask "an unrelated question" "Shall I order the spare cable for the stage switch?" allow "$R"
R="$T/r-reask-bare"; fresh "$R"
{ user "go"; asst "Shall I?"; user "something else"; asst "ok"; } > "$T/t-bare.jsonl"
mkdir -p "$R/.claude/rules"; printf '{"question_patterns":["^shall i\\\\?$"]}\n' > "$R/.claude/rules/open-questions.json"
check "first run records the bare question" "$T/t-bare.jsonl" block "$R" >/dev/null
bid="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
[ -n "$bid" ] && cli "$R" resolve "$bid=unanswered:fixture" >/dev/null
ask "a recorded bare 'shall I?' is inside every question and matches none" "Shall I order the spare cable for the stage switch?" allow "$R"
R="$T/r-reask"
out="$(cli "$R" recheck "$id=")"; rc=$?
case "$rc:$out" in [1-9]*:*"needs the measurement in words"*) ok "a bare recheck stamp is refused";; *) bad "bare recheck accepted (rc=$rc): $out";; esac
ask "still refused after the refused stamp" "Clock check: $Q" deny "$R"
cli "$R" recheck "$id=ledger clock-check still open, no PR on GitHub, measured now" >/dev/null && ok "recheck with the measurement is accepted" || bad "recheck refused"
ask "the same question after a fresh recheck" "Clock check: $Q" allow "$R"
node -e '
const fs=require("fs");const p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
for (const k in s) s[k].rechecked="2020-01-01T00:00:00.000Z";fs.writeFileSync(p,JSON.stringify(s));' "$R/.claude-state/open-questions.json"
ask "the same question with a stale recheck" "Clock check: $Q" deny "$R"
cli "$R" resolve "$id=answered:the PR exists since Tuesday" >/dev/null
ask "the same question once the record is settled" "Clock check: $Q" allow "$R"
# an unanswered record and an orphan (open, earlier day) are measured before a re-ask as well;
# an open question of this session and day passes — the operator has not seen it yet
R="$T/r-reask2"; fresh "$R"
check "first run records the question (unanswered re-ask case)" "$T/t1.jsonl" block "$R" >/dev/null
id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
SID=S9 ask "an open question of this session and day" "$Q" allow "$R"
cli "$R" resolve "$id=unanswered:fixture" >/dev/null
ask "an unanswered question asked again without a measurement" "$Q" deny "$R"
R="$T/r-reask3"; fresh "$R"
check "first run records the question (orphan re-ask case)" "$T/t1.jsonl" block "$R" >/dev/null
node -e '
const fs=require("fs");const p=process.argv[1];const s=JSON.parse(fs.readFileSync(p,"utf8"));
for (const k in s) s[k].asked="2020-01-01T00:00:00.000Z";fs.writeFileSync(p,JSON.stringify(s));' "$R/.claude-state/open-questions.json"
ask "an orphan (open, earlier day) asked again without adopting it" "$Q" deny "$R"
out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo hi"}}' | CLAUDE_PROJECT_DIR="$(native "$R")" node "$G" 2>&1)"
[ -z "$out" ] && ok "a Bash call passes the question hook" || bad "Bash call judged: $out"

# --- the mode question is asked alone (2026-10-26): bundled with decisions, the steps those
# decisions need opened their dialogs in the run that was autonomous again
ask2() { # $1 name, $2 first question, $3 second question, $4 deny|allow, $5 root
  local out
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":%s,"header":"a","options":[{"label":"yes","description":"y"},{"label":"no","description":"n"}]},{"question":%s,"header":"b","options":[{"label":"yes","description":"y"},{"label":"no","description":"n"}]}]}}' "$(js "$2")" "$(js "$3")" \
    | CLAUDE_PROJECT_DIR="$(native "$5")" node "${GATE:-$G}" 2>&1)"
  if [ "$4" = deny ]; then
    case "$out" in *'"permissionDecision":"deny"'*'mode question'*) ok "$1 is refused";; *) bad "$1 was not refused: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 passes" || bad "$1 refused wrongly: '$out'"
  fi
}
R="$T/r-mode"; fresh "$R"
ask2 "a decision bundled with 'continue autonomously?'" "Change the rule file now?" "Continue autonomously?" deny "$R"
ask2 "two decisions without a mode question" "Change the rule file now?" "Merge PR 5 now?" allow "$R"
ask2 "a question ABOUT autonomy that is not the last one" "How autonomous should the loop be at the desk?" "Merge PR 5 now?" allow "$R"
ask "'continue autonomously?' asked alone" "Continue autonomously?" allow "$R"
ask2 "a last decision that only mentions the autonomous gate in its context (2026-10-31)" "Merge PR 5 now?" "The autonomous gate held the edit back; the patch is in a file. Shall I apply it now?" allow "$R"
# --- the same across calls (2026-10-31): two question calls in ONE message, read by message id
qcall() { # $1 message id, $2 tool_use id, $3 question
  printf '{"type":"assistant","message":{"id":"%s","role":"assistant","content":[{"type":"tool_use","id":"%s","name":"AskUserQuestion","input":{"questions":[{"question":%s,"header":"h","options":[]}]}}]}}\n' "$1" "$2" "$(js "$3")"; }
askp() { # $1 name, $2 transcript, $3 tool_use id of this call, $4 its question, $5 deny|allow, $6 root
  local out
  out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","transcript_path":%s,"tool_use_id":"%s","tool_input":{"questions":[{"question":%s,"header":"a","options":[{"label":"yes","description":"y"},{"label":"no","description":"n"}]}]}}' "$(js "$(native "$2")")" "$3" "$(js "$4")" \
    | CLAUDE_PROJECT_DIR="$(native "$6")" node "${GATE:-$G}" 2>&1)"
  if [ "$5" = deny ]; then
    case "$out" in *'"permissionDecision":"deny"'*'mode question'*) ok "$1 is refused";; *) bad "$1 was not refused: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 passes" || bad "$1 refused wrongly: '$out'"
  fi
}
f="$T/par.jsonl"; { qcall m1 t1 "Put the five write tools on ask?"; qcall m1 t2 "Continue autonomously?"; } > "$f"
askp "the mode question in a parallel call next to a decision (the 2026-10-31 incident)" "$f" t2 "Continue autonomously?" deny "$R"
askp "the decision call next to a parallel mode question" "$f" t1 "Put the five write tools on ask?" deny "$R"
f="$T/seq.jsonl"; { qcall m1 t1 "Put the five write tools on ask?"; tres; qcall m2 t2 "Continue autonomously?"; } > "$f"
askp "the mode question as its own later call (control)" "$f" t2 "Continue autonomously?" allow "$R"
f="$T/par2.jsonl"; { qcall m1 t1 "Put the five write tools on ask?"; qcall m1 t2 "Merge PR 5 now?"; } > "$f"
askp "two parallel decisions without a mode question" "$f" t2 "Merge PR 5 now?" allow "$R"
askp "a call not yet in the transcript fails open" "$f" t9 "Continue autonomously?" allow "$R"
mkdir -p "$R/.claude/rules"; printf '{"on_patterns":["\\\\bcarry on alone\\\\b"]}\n' > "$R/.claude/rules/autonomous-patterns.json"
ask2 "the instance's mode words count too" "Switch the rule now?" "Carry on alone?" deny "$R"

# --- negative control
printf 'process.stdin.resume();process.stdin.on("end",()=>process.exit(0));\n' > "$T/stub.cjs"
before=$fail; fail=0
for c in t1 t2; do R="$T/stub-$c"; fresh "$R"; GATE="$T/stub.cjs" check "stub on $c" "$T/$c.jsonl" block "$R" >/dev/null; done
R="$T/r-reask3"; GATE="$T/stub.cjs" ask "stub on the orphan re-ask" "$Q" deny "$R" >/dev/null
caught=$fail; fail=$before
[ "$caught" = 1 ] && ok "always-allow stub fails the must-block cases" || bad "negative control: stub passed"

[ "$fail" = 0 ] && echo "question-gate: all checks passed" || echo "question-gate: FAILURES"
exit "$fail"
