#!/usr/bin/env bash
# covers: start-report-gate
# Fixtures for helpers/start-report-gate.cjs: no outward call in the first turn before the start report, unless
# the first message orders work. English patterns from the template; rc 0 = all pass.
cd "$(dirname "$0")/.." || exit 1
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export START_REPORT_GATE_LOG="$T/log.jsonl"
mkdir -p "$T/brain/.claude/rules"
cp templates/rules-instance/start-report-patterns.json "$T/brain/.claude/rules/"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export CLAUDE_PROJECT_DIR="$(native "$T/brain")"
fail=0
rec() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$1"; }
run() { # name transcript command expect(deny|allow)
  # hook input built by node from argv (2026-11-02, same class as core #337: a printf template broke on a double quote)
  out=$(node -e 'const a=process.argv;process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:JSON.parse(a[1])},transcript_path:a[2],session_id:"t"}))' "$3" "$(native "$2")" | node helpers/start-report-gate.cjs)
  got=allow; [[ "$out" == *'"deny"'* ]] && got=deny
  if [ "$got" = "$4" ]; then echo "ok   $1"; else echo "FAIL $1 (got $got)"; fail=1; fi
}
rec '"status?"' > "$T/q.jsonl"
rec '"please merge PR 54"' > "$T/o.jsonl"
{ rec '"status?"'; printf '{"type":"assistant","message":{"content":[{"type":"text","text":"Status: ..."}]}}\n'; rec '"ok"'; } > "$T/two.jsonl"
{ rec '"status?"'; rec '[{"type":"tool_result","tool_use_id":"x","content":"done"}]'; } > "$T/tr.jsonl"
run "question, merge denied"            "$T/q.jsonl"   '"gh pr merge 54 --squash"' deny
run "question, push denied"             "$T/q.jsonl"   '"git -C /x push"' deny
run "question, merge with a double quote denied" "$T/q.jsonl" '"gh pr merge 54 --subject \"x\""' deny
run "question, read allowed"            "$T/q.jsonl"   '"gh pr view 54"' allow
run "question, local commit allowed"    "$T/q.jsonl"   '"git commit -q -m x"' allow
run "question, help allowed"            "$T/q.jsonl"   '"python3 x/shared-memory-post.py --help"' allow
run "order, merge allowed"              "$T/o.jsonl"   '"gh pr merge 54 --squash"' allow
run "second turn, merge allowed"        "$T/two.jsonl" '"gh pr merge 54 --squash"' allow
run "tool result is no prompt"          "$T/tr.jsonl"  '"gh pr merge 54 --squash"' deny
ask='{"type":"assistant","message":{"content":[{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{}}]}}'
{ rec '"status?"'; printf '%s\n' "$ask"; rec '[{"type":"tool_result","tool_use_id":"q1","content":"Yes"}]'; } > "$T/qa.jsonl"
{ rec '"status?"'; printf '%s\n' "$ask"; rec '[{"type":"tool_result","tool_use_id":"q1","content":"rejected","is_error":true}]'; } > "$T/qx.jsonl"
run "question-tool answer opens a turn" "$T/qa.jsonl"  '"gh pr merge 54 --squash"' allow
run "rejected question is no answer"    "$T/qx.jsonl"  '"gh pr merge 54 --squash"' deny
run "escape with quoted order"         "$T/q.jsonl"   '"gh pr merge 54 # START-REPORT-OK: \"merge 54\""' allow
# 2026-11-06: the effect word only inside a search pattern is data, not a command
run "grep for the effect words allowed" "$T/q.jsonl"  '"grep -n \"gh pr close\" settings.json"' allow
run "git log -S effect words allowed"  "$T/q.jsonl"   '"git -C /x log --oneline -S\"gh pr close\" -- t.json"' allow
run "bash -c keeps its quoted command" "$T/q.jsonl"   '"bash -c \"gh pr merge 54\""' deny
run "merge after a quoted grep denied" "$T/q.jsonl"   '"grep -q \"x\" f && gh pr merge 54"' deny
# 2026-11-06: an order typed mid-turn (queued command, human origin) is an order
qc() { printf '{"type":"attachment","attachment":{"type":"queued_command","origin":{"kind":"human"},"prompt":%s}}\n' "$1"; }
{ rec '"status?"'; qc '"work through it autonomously"'; } > "$T/qo.jsonl"
{ rec '"status?"'; qc '"what time is it?"'; } > "$T/qn.jsonl"
run "queued order allows"              "$T/qo.jsonl"  '"gh pr merge 54 --squash"' allow
run "queued question still denies"     "$T/qn.jsonl"  '"gh pr merge 54 --squash"' deny
# --replay: a question-tool answer ends the first turn (evaluation 2026-11-10: 8 of 10 replay hits were such turns)
{ rec '"status?"'; printf '%s\n' "$ask"; rec '[{"type":"tool_result","tool_use_id":"q1","content":"Yes"}]'; printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"gh pr merge 54"}}]}}\n'; } > "$T/rq.jsonl"
{ rec '"status?"'; printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"gh pr merge 54"}}]}}\n'; } > "$T/rd.jsonl"
rp=$(node helpers/start-report-gate.cjs --replay "$(native "$T/rq.jsonl")" "$(native "$T/rd.jsonl")")
case "$rp" in *rq.jsonl*) echo "FAIL replay counts a merge after a question-tool answer"; fail=1;; *) echo "ok   replay: a question-tool answer ends the first turn";; esac
case "$rp" in *rd.jsonl*) echo "ok   replay: a first-turn merge is named";; *) echo "FAIL replay misses a first-turn merge"; fail=1;; esac
exit $fail
