#!/usr/bin/env bash
# Fixture test for helpers/question-gate.cjs — both directions, plus the CLI.
# The must-block case is the incident (2026-10-09): a proposal ended as a question, the
# operator's next prompt was about something else, and the question scrolled away.
# Must allow: a question the operator has not seen yet (the reply being ended), a settled
# question (answered/dropped/deferred), a question inside code or quotes, a plain "why?",
# a re-issue, a second stop in the same turn. German grips only as instance data.
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

check() { # $1 name, $2 transcript, $3 block|allow, $4 root, [$5 stop_hook_active]
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s}' "$(native "$2")" "${5:-false}" \
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

for st in answered dropped deferred; do
  R="$T/r-$st"; fresh "$R"
  check "first run records the question ($st case)" "$T/t1.jsonl" block "$R" >/dev/null
  id="$(cli "$R" list | sed -n 's/^- \[open\] [0-9-]* \([0-9a-f]\{8\}\) .*/\1/p')"
  cli "$R" resolve "$id=$st:fixture" >/dev/null
  check "question settled as $st" "$T/t1.jsonl" allow "$R"
done
R="$T/r-deferred"
case "$(cli "$R" list)" in *'[deferred]'*) ok "deferred question is listed for the session start";; *) bad "deferred not listed";; esac
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

# --- German only as instance data
R="$T/r7"; fresh "$R"
{ user "los"; asst "Fertig. Soll ich den Uhr-Check als PR bauen?"; user "laufen die watches?"; asst "ja"; } > "$T/t7.jsonl"
check "German question without instance data" "$T/t7.jsonl" allow "$R"
fresh "$R"; mkdir -p "$R/.claude/rules"; printf '{"question_patterns":["\\\\bsoll ich\\\\b"]}\n' > "$R/.claude/rules/open-questions.json"
check "German question with instance data" "$T/t7.jsonl" block "$R"

# --- negative control
printf 'process.stdin.resume();process.stdin.on("end",()=>process.exit(0));\n' > "$T/stub.cjs"
before=$fail; fail=0
for c in t1 t2; do R="$T/stub-$c"; fresh "$R"; GATE="$T/stub.cjs" check "stub on $c" "$T/$c.jsonl" block "$R" >/dev/null; done
caught=$fail; fail=$before
[ "$caught" = 1 ] && ok "always-allow stub fails the must-block cases" || bad "negative control: stub passed"

[ "$fail" = 0 ] && echo "question-gate: all checks passed" || echo "question-gate: FAILURES"
exit "$fail"
