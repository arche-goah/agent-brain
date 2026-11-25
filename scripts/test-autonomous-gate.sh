#!/usr/bin/env bash
# covers: autonomous-gate
# Fixture for helpers/autonomous-gate.cjs - both directions.
# The must-block case is the incident (2026-10-26, Windows instance): in an autonomous run an edit
# of .claude/settings.json (an ask rule) raised a dialog, and the operator had to answer it.
# Usage: bash scripts/test-autonomous-gate.sh   (exit 0 = pass)
set -u
# The mode is set by its words here (the latch before the mode-confirm answer); the confirmation: test-mode-confirm.sh.
export MODE_READING=words
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/autonomous-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }

B="$T/brain"; mkdir -p "$B/.claude" "$T/userdir"
# one open operator question (the presentation gate's duty; the mode no longer reads a count, 2026-11-23)
mkdir -p "$B/.claude-state"; printf '%s\n' '{"q1": {"q": "Release now?", "status": "unanswered"}}' > "$B/.claude-state/open-questions.json"
printf '%s\n' '{"permissions":{"ask":["Edit(.claude/settings.json)","Bash(git -C * push * main*)","Bash(gh pr close*)"]}}' > "$B/.claude/settings.json"
printf '%s\n' '{"permissions":{"ask":["WebFetch"]}}' > "$T/userdir/settings.json"
AUTO="$T/auto.jsonl"; user "work through the open points autonomously" > "$AUTO"
INTER="$T/inter.jsonl"; { user "work through the open points autonomously"; user "back to normal mode"; } > "$INTER"
STAT="$T/stat.jsonl"; { user "work through the open points autonomously"; user "status?"; } > "$STAT"
# A message typed mid-turn is a queued_command attachment, not a user record (macOS finding on #142).
queued() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"%s"}}}\n' "$(js "$1")" "${2-human}"; }
MID="$T/mid.jsonl"; { user "work through the open points autonomously"; queued "put the open decisions to me now"; } > "$MID"
PEER="$T/peer.jsonl"; { user "work through the open points autonomously"; queued "a note from another session" peer; } > "$PEER"

probe() { # $1 label, $2 tool, $3 tool_input JSON, $4 transcript, $5 block|allow
  local out
  # JSON built by node from argv (escaping; a printf-built input broke on a double quote, 2026-11-02)
  out=$(node -e 'const a=process.argv;process.stdout.write(JSON.stringify({tool_name:a[1],tool_input:JSON.parse(a[2]),transcript_path:a[3],cwd:a[4]}))' "$2" "$3" "$(native "$4")" "$(native "$B")" \
        | CLAUDE_PROJECT_DIR="$(native "$B")" CLAUDE_CONFIG_DIR="$(native "$T/userdir")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"permissionDecision":"deny"'*) [ "$5" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$5" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}
SET="$(js "$(native "$B")/.claude/settings.json")"

probe "the incident: settings edit in an autonomous run" Edit "{\"file_path\":$SET}" "$AUTO" block
probe "same edit, relative path" Edit '{"file_path":".claude/settings.json"}' "$AUTO" block
# a double quote in the transcript path (escaping of the hook input); Windows refuses " in a file name
if cp "$AUTO" "$T/q\"auto.jsonl" 2>/dev/null; then
  probe "same edit, a double quote in the transcript path (escaping)" Edit '{"file_path":".claude/settings.json"}' "$T/q\"auto.jsonl" block
else
  echo "  SKIP a double quote in the transcript path: this file system refuses the name"
fi
probe "same edit, not autonomous (the operator is there)" Edit "{\"file_path\":$SET}" "$INTER" allow
probe "question tool in an autonomous run" AskUserQuestion '{"questions":[]}' "$AUTO" block
probe "question tool, not autonomous" AskUserQuestion '{"questions":[]}' "$INTER" allow
# 2026-11-06 (Windows instance): after "questions for me now" every operator item got answered and done, the
# "asks" latch re-read "open for operator = 0" and the run counted as autonomous again - the mandatory closing mode
# question (question-gate: alone, last) was refused. A call that asks ONLY the mode question is the run's end, no stop.
# Since 2026-11-25 it is asked as the mode-confirm question (header mode-confirm, interactive option last); the old form is held.
MODEQ='{"questions":[{"question":"Continue autonomously?","header":"mode-confirm","multiSelect":false,"options":[{"label":"Yes","description":"a"},{"label":"Continue interactively","description":"b"}]}]}'
probe "the mode question alone in an autonomous run passes" AskUserQuestion "$MODEQ" "$AUTO" allow
MODEQ_OLD='{"questions":[{"question":"Continue autonomously?","header":"Mode","multiSelect":false,"options":[{"label":"Yes","description":"a"},{"label":"No","description":"b"}]}]}'
probe "the mode question in the old form (no mode-confirm header)" AskUserQuestion "$MODEQ_OLD" "$AUTO" block
MIXQ='{"questions":[{"question":"Delete the branch?","header":"X","multiSelect":false,"options":[{"label":"Yes","description":"a"},{"label":"No","description":"b"}]},{"question":"Continue autonomously?","header":"Mode","multiSelect":false,"options":[{"label":"Yes","description":"a"},{"label":"No","description":"b"}]}]}'
probe "the mode question next to another question stays held (control)" AskUserQuestion "$MIXQ" "$AUTO" block
# The gate's own words are locked inside the run (2026-10-28: a refused question was made to pass by widening them).
probe "edit of the ask patterns in an autonomous run" Edit '{"file_path":".claude/rules/open-items.json"}' "$AUTO" block
probe "write of the on/off words in an autonomous run" Write '{"file_path":".claude/rules/autonomous-patterns.json"}' "$AUTO" block
probe "edit of the ask patterns in the conversation" Edit '{"file_path":".claude/rules/open-items.json"}' "$INTER" allow
probe "edit of another rules file in an autonomous run" Edit '{"file_path":".claude/rules/ledgers.json"}' "$AUTO" allow
probe "a status question mid-run keeps the mode: no question tool" AskUserQuestion '{"questions":[]}' "$STAT" block
probe "push naming main (ask glob)" Bash '{"command":"git -C /r push -q origin main"}' "$AUTO" block
probe "branch-less push (no ask rule)" Bash '{"command":"git -C /r push"}' "$AUTO" allow
# A compound command: the harness applies an ask rule per sub-command (measured 2026-11-16 on an instance: a
# sub-agent's `D=…; … ; git -C xa push -q -u origin HEAD:main; …` raised the dialog mid-run; the gate had
# tested only the whole string).
probe "ask-rule push inside a compound command" Bash '{"command":"D=/tmp/x; mkdir -p $D; git -C xa push -q -u origin main; git -C xa rev-parse HEAD"}' "$AUTO" block
probe "ask-rule push after cd &&" Bash '{"command":"cd /r && git -C . push -q origin main"}' "$AUTO" block
probe "compound command without an ask-rule part (control)" Bash '{"command":"D=/tmp/x; mkdir -p $D; git -C xa status"}' "$AUTO" allow
probe "compound ask-rule push in an interactive run (control)" Bash '{"command":"D=/tmp/x; git -C xa push -q origin main"}' "$INTER" allow
probe "gh pr close (ask prefix)" Bash '{"command":"gh pr close 5 -R o/r"}' "$AUTO" block
probe "a plain edit outside every ask rule" Edit '{"file_path":"docs/notes.md"}' "$AUTO" allow
# Hook data the classifier holds without an ask rule (macOS measurement 2026-10-26).
probe "stop-checks.json, no ask rule, autonomous" Edit '{"file_path":".claude/rules/stop-checks.json"}' "$AUTO" block
probe "plugin hooks.json, autonomous" Write '{"file_path":"hooks/hooks.json"}' "$AUTO" block
probe "stop-checks.json outside the mode" Edit '{"file_path":".claude/rules/stop-checks.json"}' "$INTER" allow
probe "local-machinery.json is not held (control)" Edit '{"file_path":".claude/rules/local-machinery.json"}' "$AUTO" allow
# No dialog in an autonomous run (operator 2026-11-03, replaces the 2026-11-02 exception): a message from the
# operator in the turn ("hooks yes", typed or queued) does not mean the operator is there - the call stays held.
tend() { printf '%s\n' '{"type":"system","subtype":"turn_duration","durationMs":1000}'; }
note() { user "<task-notification><task-id>x</task-id><status>completed</status></task-notification>"; }
APPR="$T/appr.jsonl"; { user "work through the open points autonomously"; tend; user "hooks yes, coordinate with the collaborator"; } > "$APPR"
APPQ="$T/appq.jsonl"; { user "work through the open points autonomously"; tend; queued "hooks yes"; } > "$APPQ"
GONE="$T/gone.jsonl"; { user "work through the open points autonomously"; tend; user "hooks yes"; tend; note; } > "$GONE"
probe "operator wrote in this turn: the held hooks edit stays held" Write '{"file_path":"hooks/hooks.json"}' "$APPR" block
probe "operator wrote mid-turn (phone): the ask rule stays held" Edit "{\"file_path\":$SET}" "$APPQ" block
probe "the answer's turn has ended, a notification woke the run: held again" Write '{"file_path":"hooks/hooks.json"}' "$GONE" block
# The turn's prompt asked what is open, the last answer switched the run on again (macOS 2026-11-03):
# the operator left the dialog, so the ask rule is held, not shown.
answer() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t9","name":"AskUserQuestion","input":{"questions":[]}}]}}\n'
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":%s}]}}\n' "$(js "Your questions have been answered: $1. You can now continue")"; }
BACK="$T/back.jsonl"; { user "work through the open points autonomously"; tend; user "anything open for me?"; answer '"Continue autonomously?"="Yes, continue (Recommended)"'; } > "$BACK"
probe "last answer switched the run back on: the ask rule is held again" Edit "{\"file_path\":$SET}" "$BACK" block
STAY="$T/stay.jsonl"; { user "work through the open points autonomously"; tend; user "anything open for me?"; answer '"Continue autonomously?"="No, interactive"'; } > "$STAY"
probe "last answer chose interactive: the ask rule goes to the dialog (control)" Edit "{\"file_path\":$SET}" "$STAY" allow
probe "operator in this turn, but the question tool stays collected" AskUserQuestion '{"questions":[]}' "$APPR" block
probe "a bare tool rule from the user settings" WebFetch '{"url":"https://example.com"}' "$AUTO" block
probe "a tool no rule names" Read '{"file_path":"README.md"}' "$AUTO" allow
probe "a mid-turn operator message ends the mode: the asked-for question passes" AskUserQuestion '{"questions":[]}' "$MID" allow
probe "a queued message from another origin keeps the mode (control)" AskUserQuestion '{"questions":[]}' "$PEER" block
# The way out stays open (2026-11-01, macOS instance): the operator's "continue interactively" matched no
# off-pattern and the lock refused the edit that would have taught it. An added pattern passes only when it
# matches an operator prompt of this session and nothing else changes.
mkdir -p "$B/.claude/rules"
printf '%s\n' '{"_note":"x","on_patterns":[],"off_patterns":["\\bbye\\b"]}' > "$B/.claude/rules/autonomous-patterns.json"
printf '%s\n' '{"ask_patterns":[]}' > "$B/.claude/rules/open-items.json"
STUCK="$T/stuck.jsonl"; { user "work through the open points autonomously"; user "carry on interactively, if you need anything"; } > "$STUCK"
probe "the stuck run is still autonomous (precondition)" AskUserQuestion '{"questions":[]}' "$STUCK" block
AP='.claude/rules/autonomous-patterns.json'
probe "adding the operator's own off-words passes" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"carry on interactively\\\"]\"}" "$STUCK" allow
probe "an off-word that also matches the order which switched the run on stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"\\\\\\\\bpoints\\\\\\\\b\\\"]\"}" "$STUCK" block
probe "an off-word plus a changed on-list stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"on_patterns\\\":[],\\\"off_patterns\\\":[\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"on_patterns\\\":[\\\"go\\\"],\\\"off_patterns\\\":[\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"carry on interactively\\\"]\"}" "$STUCK" block
probe "removing an off-word stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"\",\"new_string\":\"\\\"carry on interactively\\\"\"}" "$STUCK" block
probe "the 2026-10-28 incident: an ask-pattern no prompt carries stays held" Edit '{"file_path":".claude/rules/open-items.json","old_string":"[]","new_string":"[\"\\\\bzebra\\\\b\"]"}' "$STUCK" block
probe "a note-only edit is no way out (held)" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"x\\\"\",\"new_string\":\"\\\"y\\\"\"}" "$STUCK" block

# Permission mode `default` (2026-11-02): the harness dialog for a call without an allow rule comes before
# any hook; the gate says it once per session, then lets the call through.
mprobe() { # $1 label, $2 permission_mode, $3 session, $4 transcript, $5 block|allow
  local out
  out=$(printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"permission_mode":"%s","session_id":"%s","transcript_path":"%s","cwd":"%s"}' "$2" "$3" "$(native "$4")" "$(native "$B")" \
        | CLAUDE_PROJECT_DIR="$(native "$B")" CLAUDE_CONFIG_DIR="$(native "$T/userdir")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"permissionDecision":"deny"'*) [ "$5" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$5" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}
mprobe "default mode, autonomous run: first call says it" default s1 "$AUTO" block
mprobe "default mode, same session: second call passes" default s1 "$AUTO" allow
mprobe "default mode, a new session says it again" default s2 "$AUTO" block
mprobe "auto mode, autonomous run (control)" auto s3 "$AUTO" allow
mprobe "default mode, not autonomous (control)" default s4 "$INTER" allow

# 2026-11-23, the ask window: the operator's newest prompt asks what is open - in THAT turn the question tool and the
# dialogs pass, with no count of what is filed as open. Incident (macOS instance, third of its kind): the operator typed
# "questions now", the count read 0 (the question entry carried the agent's own exit), the question tool was refused.
# B2 has NOTHING filed as open: every pass below is a case the count refused.
B2="$T/brain2"; mkdir -p "$B2/.claude/rules" "$B2/.claude-state"
printf '%s\n' '{"permissions":{"ask":["Edit(.claude/settings.json)","Bash(gh pr close*)"]}}' > "$B2/.claude/settings.json"
tick() { printf '{"type":"user","isMeta":true,"promptSource":"system","queuePriority":"later","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
ASK2="$T/ask2.jsonl"; { user "work through the open points autonomously"; user "what is open for me?"; } > "$ASK2"
RUN2="$T/run2.jsonl"; { user "work through the open points autonomously"; user "status?"; } > "$RUN2"
LATE2="$T/late2.jsonl"; { user "work through the open points autonomously"; user "what is open for me?"; asst "Nothing open."; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$LATE2"
MIDASK="$T/midask.jsonl"; { user "work through the open points autonomously"; queued "I am here, everything interactive to me now - what is open for me?"; } > "$MIDASK"
out2() { node -e 'const a=process.argv;process.stdout.write(JSON.stringify({tool_name:a[1],tool_input:JSON.parse(a[2]),transcript_path:a[3],cwd:a[4]}))' "$1" "$2" "$(native "$3")" "$(native "$B2")" \
  | CLAUDE_PROJECT_DIR="$(native "$B2")" CLAUDE_CONFIG_DIR="$(native "$T/userdir")" node "$(native "$G")" 2>&1; }
p2() { # $1 label, $2 tool, $3 tool_input JSON, $4 transcript, $5 block|allow
  case "$(out2 "$2" "$3" "$4")" in
    *'"permissionDecision":"deny"'*) [ "$5" = block ] && ok "$1 blocks" || bad "$1 blocked";;
    *) [ "$5" = allow ] && ok "$1 allows" || bad "$1 did NOT block";;
  esac
}
QQ='{"questions":[{"question":"Release now?"}]}'
p2 "the incident: asked what is open, nothing filed as open - the question tool passes" AskUserQuestion "$QQ" "$ASK2" allow
p2 "asked what is open: a dialog edit (ask rule) passes in that turn" Edit '{"file_path":".claude/settings.json"}' "$ASK2" allow
p2 "asked what is open: a dialog command (ask rule) passes in that turn" Bash '{"command":"gh pr close 7"}' "$ASK2" allow
p2 "asked what is open: an edit the classifier holds passes in that turn" Edit '{"file_path":".claude/rules/stop-checks.json"}' "$ASK2" allow
p2 "asked mid-turn (a queued message): the question tool passes" AskUserQuestion "$QQ" "$MIDASK" allow
p2 "mid-run, the operator asked nothing: the question tool stays refused (control)" AskUserQuestion "$QQ" "$RUN2" block
p2 "mid-run, the operator asked nothing: the dialog edit stays refused (control)" Edit '{"file_path":".claude/settings.json"}' "$RUN2" block
p2 "mid-run, the operator asked nothing: the dialog command stays refused (control)" Bash '{"command":"gh pr close 7"}' "$RUN2" block
p2 "the asking turn ended without a question: a later timer turn is outside the window" AskUserQuestion "$QQ" "$LATE2" block
p2 "the gate's own words stay locked inside the window" Edit '{"file_path":".claude/rules/autonomous-patterns.json"}' "$ASK2" block
out=$(out2 AskUserQuestion "$QQ" "$RUN2")
case "$out" in *'Still autonomous because'*'not read as asking what is open'*'word lists'*) ok "the refusal names its measured reason and the reader (not read as an ask)";; *) bad "refusal without its reason: '${out:0:260}'";; esac
out=$(out2 AskUserQuestion "$QQ" "$LATE2")
case "$out" in *'its turn ended without a question'*) ok "the refusal after the window names that the asking turn has ended";; *) bad "late refusal without its reason: '${out:0:260}'";; esac
# 2026-11-23, the DEFERRED ask window. The operator ordered (translated): "continue autonomously; as soon as you are ready
# for the train build, switch back to interactive on your own and put the train-build question to me" - and the gate
# refused exactly that question hours later (a timer turn, a peer's message in between). Such an order opens a window that
# outlives the turns the operator did not open, for the QUESTION only, until a question is answered or the operator writes.
DEFER="continue autonomously; as soon as you are ready for the train build, switch back to interactive on your own and put the train-build question to me"
TQ='{"questions":[{"question":"Build the train now?"}]}'
D1="$T/defer1.jsonl"; { user "work through the open points autonomously"; user "$DEFER"; asst "Working on the review."; tend; tick "# Autonomous loop check  You're being invoked on a timer"; queued "task 22 for you" peer; asst "Ready."; } > "$D1"
p2 "the incident: a pre-authorized later question passes after timer and peer turns" AskUserQuestion "$TQ" "$D1" allow
p2 "the deferred window passes the question only - a dialog edit stays refused" Edit '{"file_path":".claude/settings.json"}' "$D1" block
D2="$T/defer2.jsonl"; { cat "$D1"; answer '"Build the train now?"="Yes, build it"'; answer '"Continue autonomously?"="Yes, continue (Recommended)"'; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D2"
p2 "after the question was answered and the run went on, a second question is refused again" AskUserQuestion "$QQ" "$D2" block
D3="$T/defer3.jsonl"; { user "work through the open points autonomously"; queued "$DEFER" peer; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D3"
p2 "a peer's message with the same words opens nothing" AskUserQuestion "$TQ" "$D3" block
D4="$T/defer4.jsonl"; { user "work through the open points autonomously"; user "as soon as you are ready for the train build, will you ask me the train question?"; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D4"
p2 "a sentence that is itself a question opens nothing" AskUserQuestion "$TQ" "$D4" block
D5="$T/defer5.jsonl"; { user "work through the open points autonomously"; user "$DEFER"; tend; user "and also check the CI of the train"; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D5"
p2 "a later prompt that only adds to the work keeps the window (the incident: three such prompts came first)" AskUserQuestion "$TQ" "$D5" allow
D5b="$T/defer5b.jsonl"; { user "work through the open points autonomously"; user "$DEFER"; tend; user "stop the autonomous run"; tend; user "work through the open points autonomously"; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D5b"
p2 "a prompt that ends or re-orders the run closes the deferred window" AskUserQuestion "$TQ" "$D5b" block
# a language is data: the same order in another language opens it only with the instance's defer_ask_patterns
B3="$T/brain3"; mkdir -p "$B3/.claude/rules"; cp "$B2/.claude/settings.json" "$B3/.claude/settings.json"
printf '%s\n' '{"defer_ask_patterns": ["en cuanto[^.?!]{0,80}preg[uú]ntame"]}' > "$B3/.claude/rules/autonomous-patterns.json"
D6="$T/defer6.jsonl"; { user "work through the open points autonomously"; user "sigue; en cuanto estés listo para el tren, pregúntame"; tend; tick "# Autonomous loop check  You're being invoked on a timer"; } > "$D6"
p2 "another language without the instance words opens nothing (control)" AskUserQuestion "$TQ" "$D6" block
out=$(node -e 'const a=process.argv;process.stdout.write(JSON.stringify({tool_name:"AskUserQuestion",tool_input:JSON.parse(a[1]),transcript_path:a[2],cwd:a[3]}))' "$TQ" "$(native "$D6")" "$(native "$B3")" \
  | CLAUDE_PROJECT_DIR="$(native "$B3")" CLAUDE_CONFIG_DIR="$(native "$T/userdir")" node "$(native "$G")" 2>&1)
case "$out" in *'"permissionDecision":"deny"'*) bad "the instance's defer_ask_patterns did not open the window";; *) ok "with the instance's defer_ask_patterns the same order opens it";; esac
# A factual question the classifier misreads as "what is open" (one such case in a brain's register, 2026-11-15): the
# tools are ALLOWED in that turn, nothing is forced - the worst case is one needless question, never a refused tool.
IC2="$B2/.claude-state/intent-classifier.jsonl"
MIS="$T/sess-mis.jsonl"; { printf '{"type":"user","timestamp":"2026-11-15T20:00:30Z","message":{"role":"user","content":"work through the list autonomously"}}\n'; printf '{"type":"user","timestamp":"2026-11-15T20:00:35Z","message":{"role":"user","content":"when does the order arrive, and what is the deadline?"}}\n'; } > "$MIS"
printf '%s\n' '{"at":"2026-11-15T20:00:37Z","session":"sess-mis","mode":"hook","prompt":"when does the order arrive, and what is the deadline?","model":{"asks_open":true,"mode_on":false,"mode_off":false,"correction":false}}' > "$IC2"
p2 "a factual question misread as an ask: the question tool is allowed" AskUserQuestion "$QQ" "$MIS" allow
{ cat "$MIS"; asst "It arrives on Friday; the deadline is the 26th."; } > "$T/sess-mis2.jsonl"; cp "$T/sess-mis2.jsonl" "$MIS"
dp=$(node -e 'const a=process.argv;process.stdout.write(JSON.stringify({transcript_path:a[1],cwd:a[2]}))' "$(native "$MIS")" "$(native "$B2")" | CLAUDE_PROJECT_DIR="$(native "$B2")" node "$(native "$_D/../helpers/decision-presentation-gate.cjs")" 2>&1)
[ -z "$dp" ] && ok "... and nothing is forced: the turn that only answers ends without a demanded question" || bad "misread ask forced a question: '${dp:0:200}'"
rm -f "$IC2"
# The count stays a DUTY (presentation gate): something filed as open and a turn that asked nothing is held at its end.
printf '%s\n' '{"q1": {"q": "Release now?", "status": "unanswered"}}' > "$B2/.claude-state/open-questions.json"
{ cat "$ASK2"; asst "Nothing from my side."; } > "$T/duty.jsonl"
dp=$(node -e 'const a=process.argv;process.stdout.write(JSON.stringify({transcript_path:a[1],cwd:a[2]}))' "$(native "$T/duty.jsonl")" "$(native "$B2")" | CLAUDE_PROJECT_DIR="$(native "$B2")" node "$(native "$_D/../helpers/decision-presentation-gate.cjs")" 2>&1)
case "$dp" in *'"decision":"block"'*'through the question tool'*) ok "asked, a decision filed as open, the turn asked nothing: held at the turn end (the count as a duty)";; *) bad "duty not held: '${dp:0:200}'";; esac

[ "$fail" = 0 ] && echo "autonomous-gate: all cases pass" || { echo "autonomous-gate: FAILURES"; exit 1; }
