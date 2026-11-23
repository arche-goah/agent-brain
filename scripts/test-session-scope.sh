#!/usr/bin/env bash
# covers: session-scope, autonomous-idle-gate, open-items-gate
# Fixture for helpers/session-scope.cjs and the two gates that read it - both directions, with controls.
# The must-pass cases are the incident (2026-11-23, macOS instance): a helper session the operator limited to "only
# what the main session assigns you" ended on LIST EMPTY after every order and was held twice - for the brain's
# own-items measurement, then for "continuation on own start findings" - work that belongs to the main session.
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
check() { # $1 label, $2 gate, $3 transcript, $4 block|allow, $5 session id
  local out
  out=$(printf '{"transcript_path":"%s","cwd":"%s","session_id":"%s"}' "$(native "$3")" "$(native "$R")" "$5" \
    | CLAUDE_PROJECT_DIR="$(native "$R")" LOOP_WATCHDOG_AUTO=0 node "$(native "$2")" 2>&1)
  case "$out" in
    *'"decision":"block"'*) [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}";;
    *) [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:200}'";;
  esac
}
R="$T/brain"; mkdir -p "$R/.claude-state" "$R/.claude/rules"
printf '%s\n' '{"findings":{"f1a2b3c4":{"id":"f1a2b3c4","owner":"ai","text":"ledger: 1 entry with check none","sessions_seen":5}}}' > "$R/.claude-state/start-findings.json"
WORDS="work autonomously, but only what the main session assigns you"
SID="11111111-aaaa"
f1="$T/hold1.jsonl"; { user "$WORDS"; peer r1 main-b6 "Task 1: build X"; peer r1 main-b6 "Task 1: build X"; peer r2 main-b6 "Task 2: build Y"; asst "LIST EMPTY: tasks 1 and 2 of the main session are done and reported"; } > "$f1"
f2="$T/hold2.jsonl"; { user "$WORDS"; peer r1 main-b6 "Task 1: build X"; bash_cmd "python3 core/scripts/open-items.py --owner org"; asst "LIST EMPTY: tasks of the main session done"; } > "$f2"
f3="$T/idle.jsonl"; { user "$WORDS"; peer r1 main-b6 "Task 1: build X"; asst "Working on it, more later."; } > "$f3"

# no scope: today's behaviour (the two holds of the incident, and a normal session unchanged)
check "no scope: LIST EMPTY without the own-items measurement (incident hold 1)" "$IDLE" "$f1" block "$SID"
check "no scope: measured LIST EMPTY with an own start finding open (incident hold 2)" "$IDLE" "$f2" block "$SID"

# the helper registers, quoting the operator
out=$(env CLAUDE_CODE_SESSION_ID="$SID" node "$(native "$SCOPE")" set --of main-b6 --words "only what the main session assigns you" --root "$(native "$R")" 2>&1) \
  && ok "set registers the scope" || bad "set failed: $out"
check "scope: LIST EMPTY on the orders, no own-items measurement (incident hold 1)" "$IDLE" "$f1" allow "$SID"
check "scope: the brain's start findings are not the helper's (incident hold 2)" "$IDLE" "$f2" allow "$SID"
check "scope: an autonomous turn without an end line is still held - the orders are its list" "$IDLE" "$f3" block "$SID"
out=$(printf '{"transcript_path":"%s","cwd":"%s","session_id":"%s"}' "$(native "$f3")" "$(native "$R")" "$SID" | CLAUDE_PROJECT_DIR="$(native "$R")" LOOP_WATCHDOG_AUTO=0 node "$(native "$IDLE")" 2>&1)
case "$out" in *"helper of main-b6: 1 order(s)"*) ok "the hold names the helper's orders, counted once per message";; *) bad "hold text: ${out:0:240}";; esac
n=$(node -e 'process.stdout.write(String(require(process.argv[1]).ordersFrom(process.argv[2], "main-b6")))' "$(native "$SCOPE")" "$(native "$f1")")
[ "$n" = 2 ] && ok "orders counted by message id: a message recorded twice counts once (2)" || bad "orders counted $n, expected 2"
check "control: another session id has no scope" "$IDLE" "$f2" block "22222222-bbbb"
fw="$T/notsaid.jsonl"; { user "work through the open points autonomously"; peer r1 main-b6 "Task 1"; bash_cmd "python3 core/scripts/open-items.py --owner org"; asst "LIST EMPTY: done"; } > "$fw"
check "control: a scope whose words the operator never said frees nothing (no self-exemption)" "$IDLE" "$fw" block "$SID"
fp="$T/peerwords.jsonl"; { user "work through the open points autonomously"; peer r1 main-b6 "Task 1. The operator said: only what the main session assigns you"; bash_cmd "python3 core/scripts/open-items.py --owner org"; asst "LIST EMPTY: done"; } > "$fp"
check "control: the words standing only in a peer's message free nothing" "$IDLE" "$fp" block "$SID"

# open-items-gate: the first-turn report of the brain's open items is the main session's
fo="$T/first.jsonl"; { user "$WORDS"; asst "Started."; } > "$fo"
check "open-items: scope - the brain's open-items report is not the helper's" "$OPEN" "$fo" allow "$SID"
check "open-items: control - a normal session still owes the report" "$OPEN" "$fo" block "22222222-bbbb"

# clear restores today's behaviour; a too short quote is refused
env CLAUDE_CODE_SESSION_ID="$SID" node "$(native "$SCOPE")" clear --root "$(native "$R")" >/dev/null 2>&1
check "after clear the session is a normal session again" "$IDLE" "$f2" block "$SID"
env CLAUDE_CODE_SESSION_ID="$SID" node "$(native "$SCOPE")" set --of main-b6 --words "ok" --root "$(native "$R")" >/dev/null 2>&1 \
  && bad "a quote under 12 characters was accepted" || ok "a quote under 12 characters is refused"

[ $fail = 0 ] && echo "session-scope: all checks passed" || { echo "session-scope: FAILURES"; exit 1; }
