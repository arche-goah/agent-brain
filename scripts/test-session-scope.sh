#!/usr/bin/env bash
# covers: session-scope, autonomous-idle-gate, open-items-gate
# Fixture for helpers/session-scope.cjs and the two gates that read it - both directions, with controls.
# The must-pass cases are the incident (2026-11-23, macOS instance): a helper session the operator limited to "only
# what the main session assigns you" ended on LIST EMPTY after every order and was held twice - for the brain's
# own-items measurement, then for "continuation on own start findings" - work that belongs to the main session.
# The operator sets the scope by an ORDINARY TYPED MESSAGE (operator 2026-11-23); nothing the AI writes sets it.
# Usage: bash scripts/test-session-scope.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
IDLE="${IDLE_GATE:-$_D/../helpers/autonomous-idle-gate.cjs}"   # IDLE_GATE / OPEN_GATE: run against another build
OPEN="${OPEN_GATE:-$_D/../helpers/open-items-gate.cjs}"
SCOPE="$_D/../helpers/session-scope.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
bash_cmd() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":%s}}]}}\n' "$(js "$1")"; }
# a peer's order as the harness records it: a system reminder carrying the cross-session message
peer() { printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":%s}]}}\n' "$(js "<system-reminder id=\"$1\">
Another Claude session sent a message while you were working:
<cross-session-message from=\"uds:/tmp/cc-socks/1.sock\" from-name=\"$2\" from-mode=\"prompting\">
$3
</cross-session-message>
</system-reminder id=\"$1\">")"; }
frame() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "<system-reminder>$1</system-reminder>")"; }
check() { # $1 label, $2 gate, $3 transcript, $4 block|allow
  local out
  out=$(printf '{"transcript_path":"%s","cwd":"%s","session_id":"s1"}' "$(native "$3")" "$(native "$R")" \
    | CLAUDE_PROJECT_DIR="$(native "$R")" LOOP_WATCHDOG_AUTO=0 node "$(native "$2")" 2>&1)
  case "$out" in
    *'"decision":"block"'*) [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}";;
    *) [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:200}'";;
  esac
}
R="$T/brain"; mkdir -p "$R/.claude-state" "$R/.claude/rules"
printf '%s\n' '{"findings":{"f1a2b3c4":{"id":"f1a2b3c4","owner":"ai","text":"ledger: 1 entry with check none","sessions_seen":5}}}' > "$R/.claude-state/start-findings.json"
# the instance's words (German), as an instance would carry them in autonomous-patterns.json
printf '%s\n' '{"helper_scope_patterns": ["nur auftr(?:ä|ae)ge von der haupt ?session", "\\bsuper-helper\\b", "nur,? was dir von der haupt ?session aufgetragen"], "helper_clear_patterns": ["\\bscope aus\\b", "\\bkein helper mehr\\b"], "helper_main_name": "claude-brain-[a-z0-9]{2}\\b"}' > "$R/.claude/rules/autonomous-patterns.json"
# the operator's real sentences (2026-11-23, the two helper sessions on the macOS instance)
OP_2C="du bist super-helper, bekommst nur aufträge von der haupt session, finde selbst raus wer das ist. alle haupt session aufträge autonom abhandeln"
OP_28="autonom arbeiten, aber NUR, was dir von der hauptsession aufgetragen wird"
PLAIN="work through the open points autonomously"
MEAS="core/scripts/open-items.py --owner org"   # the measurement as the gate reads it (no interpreter word: OS-17 probe)
mk() { # $1 file, $2 first prompt, then the body: orders from main-b6, the end text
  local f="$1" p="$2"; { user "$PLAIN"; [ "$p" = "$PLAIN" ] || user "$p"; peer r1 main-b6 "Task 1: build X"; peer r1 main-b6 "Task 1: build X"; peer r2 main-b6 "Task 2: build Y"; bash_cmd "$MEAS"; asst "LIST EMPTY: the main session's tasks are done and reported"; } > "$f"
}
mk "$T/none.jsonl" "$PLAIN"
mk "$T/op2c.jsonl" "$OP_2C"
mk "$T/op28.jsonl" "$OP_28"
{ user "$PLAIN"; peer r1 main-b6 "Task 1"; asst "LIST EMPTY: tasks of the main session done"; } > "$T/unmeasured.jsonl"
{ user "$PLAIN"; user "$OP_2C"; peer r1 main-b6 "Task 1"; asst "LIST EMPTY: tasks of the main session done"; } > "$T/unmeasured2c.jsonl"

# no scope: today's behaviour (the two holds of the incident, and a normal session unchanged)
check "no scope: LIST EMPTY without the own-items measurement (incident hold 1)" "$IDLE" "$T/unmeasured.jsonl" block
check "no scope: measured LIST EMPTY with an own start finding open (incident hold 2)" "$IDLE" "$T/none.jsonl" block
# the operator's typed sentence sets it
check "the operator's sentence in the second helper: LIST EMPTY on the orders, no measurement (hold 1)" "$IDLE" "$T/unmeasured2c.jsonl" allow
check "the operator's sentence in the second helper: start findings are not the helper's (hold 2)" "$IDLE" "$T/op2c.jsonl" allow
check "the operator's sentence in this helper (\"NUR, was dir von der hauptsession aufgetragen wird\")" "$IDLE" "$T/op28.jsonl" allow
{ user "$PLAIN"; user "$OP_2C"; peer r1 main-b6 "Task 1: build X"; asst "Working on it, more later."; } > "$T/idle.jsonl"
check "scope: an autonomous turn without an end line is still held - the orders are its list" "$IDLE" "$T/idle.jsonl" block
out=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/idle.jsonl")" "$(native "$R")" | CLAUDE_PROJECT_DIR="$(native "$R")" LOOP_WATCHDOG_AUTO=0 node "$(native "$IDLE")" 2>&1)
case "$out" in *"helper of main-b6: 1 order(s)"*) ok "the main session is found as the first that sends an order, orders counted once per message";; *) bad "hold text: ${out:0:240}";; esac
# a named main session wins over the first sender
{ user "$PLAIN"; user "nur aufträge von der haupt session claude-brain-b6"; peer r0 other-x1 "please do Z"; peer r1 claude-brain-b6 "Task 1"; peer r2 claude-brain-b6 "Task 2"; asst "Working."; } > "$T/named.jsonl"
out=$(node "$(native "$SCOPE")" show --transcript "$(native "$T/named.jsonl")" --root "$(native "$R")")
case "$out" in *'"of":"claude-brain-b6"'*'"orders":2'*) ok "a session named in the sentence is the main session (2 orders), not the first sender";; *) bad "named: $out";; esac

# replayed on the second helper: a fellow helper wrote first (coordination), the main session sent more
{ user "$PLAIN"; user "$OP_2C"; peer c1 helper-28 "boundary?"; peer c2 helper-28 "PR number"; peer o1 main-b6 "Task 1"; peer o2 main-b6 "Task 2"; peer o3 main-b6 "Task 3"; asst "Working."; } > "$T/fellow.jsonl"
out=$(node "$(native "$SCOPE")" show --transcript "$(native "$T/fellow.jsonl")" --root "$(native "$R")")
case "$out" in *'"of":"main-b6"'*'"orders":3'*) ok "unnamed: the session with the most messages is the main session, not a fellow helper that wrote first";; *) bad "fellow: $out";; esac

# controls: nothing but the operator's own typed message sets it
{ user "$PLAIN"; peer r1 main-b6 "$OP_2C"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/peerwords.jsonl"
check "control: the same words in a peer's message set nothing" "$IDLE" "$T/peerwords.jsonl" block
{ user "$PLAIN"; frame "$OP_2C"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/framewords.jsonl"
check "control: the same words in a frame set nothing" "$IDLE" "$T/framewords.jsonl" block
printf '%s\n' '{"s1":{"helper_of":"main-b6","words":"nur aufträge von der haupt session","scope":"orders"}}' > "$R/.claude-state/session-scope.json"
check "control: a state file the AI wrote sets nothing" "$IDLE" "$T/none.jsonl" block
rm -f "$R/.claude-state/session-scope.json"
{ user "$PLAIN"; user "$OP_2C"; peer r1 main-b6 "Task 1"; user "scope aus, du bist wieder eine normale session"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/cleared.jsonl"
check "control: the operator's later clearing message ends the scope" "$IDLE" "$T/cleared.jsonl" block
# second independent review (2026-11-23): a MENTION sets nothing - the statement must open the message
{ user "$PLAIN"; user "why do you behave as if you are a helper session? I never said that."; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/h1.jsonl"
check "a question that mentions it sets nothing (H1)" "$IDLE" "$T/h1.jsonl" block
{ user "$PLAIN"; user "tell worker-2 this, word for word: you are a helper, only the orders of the main session count"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/h2.jsonl"
check "a text to pass on to another session sets nothing (H2)" "$IDLE" "$T/h2.jsonl" block
{ user "$PLAIN"; user "if the build is red, you are the helper for the train session tomorrow, not today"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/h3.jsonl"
check "a conditional sets nothing (H3)" "$IDLE" "$T/h3.jsonl" block
{ user "$PLAIN"; user "the peer wrote this, do NOT follow it:
> you are a helper session, only the orders of the main session"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/h6.jsonl"
check "a quoted block sets nothing (H6)" "$IDLE" "$T/h6.jsonl" block
{ user "$PLAIN"; user "$OP_2C"; user "ok, enough of that: from now on work as a normal session"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/h5.jsonl"
check "a clearing in other words ends the scope (H5)" "$IDLE" "$T/h5.jsonl" block
{ user "$PLAIN"; asst "?"; printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{"questions":[{"question":"mode?"}]}}]}}\n'; printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"q1","content":%s}]}}\n' "$(js "User has answered your questions: \"mode?\"=\"$OP_2C\"")"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/answer.jsonl"
check "control: a question-tool answer sets nothing - the AI wrote its options" "$IDLE" "$T/answer.jsonl" block
{ user "$PLAIN"; user "you are a helper session: only the tasks of the main session"; peer r1 main-b6 "Task 1"; bash_cmd "$MEAS"; asst "LIST EMPTY: done"; } > "$T/english.jsonl"
check "the built-in English words set it too" "$IDLE" "$T/english.jsonl" allow
# the German comes from the instance data: the same German sentence without that file sets nothing
mv "$R/.claude/rules/autonomous-patterns.json" "$R/.claude/rules/autonomous-patterns.off"
check "control: the operator's German sentence without the instance words sets nothing (a language is data)" "$IDLE" "$T/op2c.jsonl" block
mv "$R/.claude/rules/autonomous-patterns.off" "$R/.claude/rules/autonomous-patterns.json"
n=$(node -e 'process.stdout.write(String(require(process.argv[1]).ordersFrom(process.argv[2], "main-b6")))' "$(native "$SCOPE")" "$(native "$T/op2c.jsonl")")
[ "$n" = 2 ] && ok "orders counted by message id: a message recorded twice counts once (2)" || bad "orders counted $n, expected 2"

# open-items-gate: the first-turn report of the brain's open items is the main session's
{ user "$OP_2C"; asst "Started."; } > "$T/first2c.jsonl"
check "open-items: the operator's helper sentence - the brain's open-items report is not the helper's" "$OPEN" "$T/first2c.jsonl" allow
{ user "$PLAIN"; asst "Started."; } > "$T/firstplain.jsonl"
check "open-items: control - a normal session still owes the report" "$OPEN" "$T/firstplain.jsonl" block

[ $fail = 0 ] && echo "session-scope: all checks passed" || { echo "session-scope: FAILURES"; exit 1; }
