#!/usr/bin/env bash
# covers: decision-register
# Fixture test for helpers/decision-register.cjs — both directions.
# The incident (2026-11-11): two questions the operator had answered one and two days earlier (a tool
# set, an industrial PoE splitter) were put to them again in other words, and a rejected 19-inch case
# was proposed again; the answers lived only in transcripts and one project ledger.
# Must: PostToolUse writes each answered question (object and text form); PreToolUse denies a question
# the model judges the same matter as an earlier answer of ANOTHER session, ONCE (re-issue passes);
# allows with context when the model rejects the candidates; allows a fresh question; fails open when
# the model is unreadable; --backfill reads transcripts and dedupes. The model is a stub (.cjs).
# Usage: bash scripts/test-decision-register.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
H="$(cd "$(dirname "$0")" && pwd)/../helpers/decision-register.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$H" ] || { echo "  FAIL helper missing: $H"; exit 1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }

P="$T/brain"; mkdir -p "$P/.claude/rules"
printf '{"register":"reg.jsonl"}' > "$P/.claude/rules/decision-register.json"
# model stub: prints $STUB_OUT, ignores its input
printf 'process.stdin.resume();process.stdin.on("end",()=>{process.stdout.write(process.env.STUB_OUT||"")});\n' > "$T/stub.cjs"
export CLAUDE_PROJECT_DIR="$(native "$P")" DECISION_REGISTER_BIN="$(native "$T/stub.cjs")"
run() { node "$H"; }

Q1='Tools for the field node: which do you have already? Ticked = present, not ordered.'
A1='Step drill 4-20 mm'
Q2='PoE splitter: on 8 Nov you chose an industrial PoE splitter as the show unit. Shall it go into the last big order?'

# 1. PostToolUse, answers as object
printf '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","session_id":"s-old","cwd":"/x","tool_input":{"questions":[{"question":"%s"}]},"tool_response":{"answers":{"%s":"%s"}}}' "$Q1" "$Q1" "$A1" | run
grep -q 'Step drill' "$P/reg.jsonl" && ok "post writes the object answer" || bad "post did not write the object answer"
# 2. PostToolUse, answers as result text
printf '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","session_id":"s-old","tool_input":{"questions":[{"question":"%s"}]},"tool_response":"User has answered your questions: \\"%s\\"=\\"Yes, order it too (Recommended)\\". You can now continue."}' "$Q2" "$Q2" | run
grep -q '"answer":"Yes, order it too (Recommended)"' "$P/reg.jsonl" && ok "post writes the text answer, cut at the quote" || bad "post text answer wrong: $(tail -1 "$P/reg.jsonl")"
# 3. a question without an answer is no decision
printf '{"hook_event_name":"PostToolUse","tool_name":"AskUserQuestion","session_id":"s-old","tool_input":{"questions":[{"question":"Unanswered thing?"}]},"tool_response":{"answers":{}}}' | run
grep -q 'Unanswered thing' "$P/reg.jsonl" && bad "an unanswered question was written" || ok "unanswered question not written"

pre() { printf '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","session_id":"%s","tool_input":{"questions":[{"question":"%s"}]}}' "$1" "$2" | run; }
NEWQ='Tools for the field nodes: which of these do you have already? (Selected = present, drops from the order.)'
# 4. same matter (model says 1) -> deny once
out="$(STUB_OUT='{"same":[1]}' pre s-new "$NEWQ")"
case "$out" in *'"permissionDecision":"deny"'*"Step drill"*) ok "re-ask denied with the earlier answer";; *) bad "re-ask not denied: $out";; esac
# 5. the same question re-issued passes
out="$(STUB_OUT='{"same":[1]}' pre s-new "$NEWQ")"
case "$out" in *'"deny"'*) bad "re-issue denied again";; *) ok "re-issue passes";; esac
# 6. model rejects -> allow with context
out="$(STUB_OUT='{"same":[]}' pre s-other "$NEWQ")"
case "$out" in *'"deny"'*) bad "rejected candidate denied";; *additionalContext*"Step drill"*) ok "rejected candidate allowed with context";; *) bad "no context: $out";; esac
# 7. fresh question, no candidate -> silent
out="$(STUB_OUT='{"same":[1]}' pre s-new2 'DMX termination at the end of the chain: standard terminator or self-built?')"
[ -z "$out" ] && ok "fresh question passes silently" || bad "fresh question touched: $out"
# 8. model unreadable -> fail open (no deny)
out="$(STUB_OUT='garbage' pre s-new3 "$NEWQ")"
case "$out" in *'"deny"'*) bad "unreadable model denied";; *) ok "unreadable model fails open";; esac
# 9. own session's answer of today does not deny (the operator just answered it here)
out="$(STUB_OUT='{"same":[1]}' pre s-old "$NEWQ")"
case "$out" in *'"deny"'*) bad "own fresh answer denied";; *) ok "own session today not matched";; esac
# 10. other tool -> ignored
out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"x","tool_input":{}}' | run)"
[ -z "$out" ] && ok "other tool ignored" || bad "other tool touched: $out"

# 11. backfill from a transcript, dedupe on the second run
D="$T/proj"; mkdir -p "$D"
printf '%s\n' '{"timestamp":"2026-11-01T10:00:00Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{"questions":[{"question":"Case: 19 inch or small?"}]}}]}}' \
  '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"User has answered your questions: \"Case: 19 inch or small?\"=\"small, into the desk\". You can now continue."}]}}' > "$D/abc.jsonl"
o1="$(node "$H" --backfill "$(native "$D")")"; o2="$(node "$H" --backfill "$(native "$D")")"
case "$o1$o2" in *"1 answers added"*"0 answers added"*) ok "backfill adds once";; *) bad "backfill: $o1 / $o2";; esac
grep -q '"answer":"small, into the desk"' "$P/reg.jsonl" && ok "backfill reads the answer" || bad "backfill answer missing"

[ "$fail" = 0 ] && echo "test-decision-register: all passed" || echo "test-decision-register: FAILURES"
exit "$fail"
