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
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new "$NEWQ")"
case "$out" in *'"permissionDecision":"deny"'*"Step drill"*) ok "re-ask denied with the earlier answer";; *) bad "re-ask not denied: $out";; esac
# 5. the same question re-issued passes
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new "$NEWQ")"
case "$out" in *'"deny"'*) bad "re-issue denied again";; *) ok "re-issue passes";; esac
# 5b. re-asked in other words, saying what changed: the same earlier answer is not denied twice (Windows review of #490)
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new "$NEWQ What changed: a third node joined.")"
case "$out" in *'"deny"'*) bad "reworded re-ask denied a second time";; *) ok "reworded re-ask passes (once per earlier answer)";; esac
# 6. model rejects -> allow with context
out="$(STUB_OUT='{"same":[]}' pre s-other "$NEWQ")"
case "$out" in *'"deny"'*) bad "rejected candidate denied";; *additionalContext*"Step drill"*) ok "rejected candidate allowed with context";; *) bad "no context: $out";; esac
# 7. fresh question, no candidate -> silent
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new2 'DMX termination at the end of the chain: standard terminator or self-built?')"
[ -z "$out" ] && ok "fresh question passes silently" || bad "fresh question touched: $out"
# 8. model unreadable -> fail open (no deny)
out="$(STUB_OUT='garbage' pre s-new3 "$NEWQ")"
case "$out" in *'"deny"'*) bad "unreadable model denied";; *) ok "unreadable model fails open";; esac
# 9. own session's answer of today does not deny (the operator just answered it here)
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-old "$NEWQ")"
case "$out" in *'"deny"'*) bad "own fresh answer denied";; *) ok "own session today not matched";; esac
# 10. other tool -> ignored
out="$(printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","session_id":"x","tool_input":{}}' | run)"
[ -z "$out" ] && ok "other tool ignored" || bad "other tool touched: $out"

# 10b. a recurring check-in is never matched (asked every session by design)
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new4 'Tools done. I can handle 5 open items myself — shall I go ahead?')"
case "$out" in *'"deny"'*) bad "recurring check-in denied";; *) ok "recurring check-in passes";; esac
# 10c. instance recurring_patterns (operator's language) count too
printf '{"register":"reg.jsonl","recurring_patterns":["\\\\bcarry on alone\\\\b"]}' > "$P/.claude/rules/decision-register.json"
out="$(STUB_OUT='{"same":[{"n":1,"object":"tools","choice":"step drill present"}]}' pre s-new5 'Tools for the field nodes: carry on alone?')"
case "$out" in *'"deny"'*) bad "instance recurring pattern ignored";; *) ok "instance recurring pattern passes";; esac
printf '{"register":"reg.jsonl"}' > "$P/.claude/rules/decision-register.json"
# 10d. the model names an object that does not stand in both questions -> no deny
out="$(STUB_OUT='{"same":[{"n":1,"object":"budget"}]}' pre s-new6 "$NEWQ")"
case "$out" in *'"deny"'*) bad "unanchored object denied";; *) ok "unanchored object passes";; esac
# 10e. a bare number (old answer form) has no object -> no deny
out="$(STUB_OUT='{"same":[1]}' pre s-new7 "$NEWQ")"
case "$out" in *'"deny"'*) bad "objectless verdict denied";; *) ok "objectless verdict passes";; esac

# 11. backfill from a transcript, dedupe on the second run
D="$T/proj"; mkdir -p "$D"
printf '%s\n' '{"timestamp":"2026-11-01T10:00:00Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{"questions":[{"question":"Case: 19 inch or small?"}]}}]}}' \
  '{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"User has answered your questions: \"Case: 19 inch or small?\"=\"small, into the desk\". You can now continue."}]}}' > "$D/abc.jsonl"
o1="$(node "$H" --backfill "$(native "$D")")"; o2="$(node "$H" --backfill "$(native "$D")")"
case "$o1$o2" in *"1 answers added"*"0 answers added"*) ok "backfill adds once";; *) bad "backfill: $o1 / $o2";; esac
grep -q '"answer":"small, into the desk"' "$P/reg.jsonl" && ok "backfill reads the answer" || bad "backfill answer missing"

# 12. default transcript dir for a project path with a space (Windows review of #490): Claude Code turns EVERY
#     non-alphanumeric character into '-'; the old slug kept the space and --backfill died on ENOENT
SP="$T/My Brain"; mkdir -p "$SP/.claude/rules"; printf '{"register":"reg2.jsonl"}' > "$SP/.claude/rules/decision-register.json"
FH="$T/home"; SLUG="$(native "$SP" | sed 's/[^A-Za-z0-9]/-/g')"; mkdir -p "$FH/.claude/projects/$SLUG"; cp "$D/abc.jsonl" "$FH/.claude/projects/$SLUG/"
o3="$(HOME="$(native "$FH")" USERPROFILE="$(native "$FH")" CLAUDE_PROJECT_DIR="$(native "$SP")" node "$H" --backfill 2>&1)"; rc3=$?
case "$rc3 $o3" in "0 "*"1 answers added"*) ok "default dir found for a path with a space";; *) bad "default dir with a space: rc=$rc3 $o3";; esac
o4="$(HOME="$(native "$T/nohome")" USERPROFILE="$(native "$T/nohome")" CLAUDE_PROJECT_DIR="$(native "$SP")" node "$H" --backfill 2>&1)"; rc4=$?
case "$rc4" in 0) ok "missing transcript dir is no crash";; *) bad "missing transcript dir crashed: rc=$rc4 $o4";; esac

[ "$fail" = 0 ] && echo "test-decision-register: all passed" || echo "test-decision-register: FAILURES"
exit "$fail"
