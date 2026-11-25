#!/usr/bin/env bash
# Fixture for the mode-confirm question (operator order 2026-11-25): a mode word never switches by itself - it waits for
# the answer to a question-tool question with header "mode-confirm" (helpers/autonomous-mode.cjs), the work is held until
# that question is asked (helpers/mode-confirm.cjs pre, via autonomous-gate.cjs), and a turn end with it unasked is held
# once (mode-confirm.cjs stop). Each case has its control.
# Usage: bash scripts/test-mode-confirm.sh   (exit 0 = pass)
set -u
unset MODE_READING
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
M="$_D/../helpers/autonomous-mode.cjs"
C="$_D/../helpers/mode-confirm.cjs"
AG="$_D/../helpers/autonomous-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
# confirm <id> <header> <answer> <opt1> <opt2> [opt3]: a question-tool call with the options and its answered result
confirm() {
  local id="$1" hdr="$2" ans="$3"; shift 3
  local opts=""; for o in "$@"; do opts="$opts${opts:+,}{\"label\":$(js "$o"),\"description\":\"x\"}"; done
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"AskUserQuestion","input":{"questions":[{"question":"Mode?","header":"%s","multiSelect":false,"options":[%s]}]}}]}}\n' "$id" "$hdr" "$opts"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","content":%s}]}}\n' "$id" "$(js "Your questions have been answered: \"Mode?\"=\"$ans\". You can now continue")"
}
rejected() {
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"%s","name":"AskUserQuestion","input":{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"a"},{"label":"b"}]}]}}]}}\n' "$1"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"%s","is_error":true,"content":"The user doesn'"'"'t want to proceed with this tool use."}]}}\n' "$1"
}
EN="$T/en"; mkdir -p "$EN"
mode() { local got; got="$(node "$M" "$(native "$2")" "$(native "$EN")")"; [ "$got" = "$3" ] && ok "$1: $3" || bad "$1: expected $3, got $got"; }
pend() { local got; got="$(node -e 'const p=require(process.argv[1]).confirmPending(process.argv[2],process.argv[3]);process.stdout.write(p?p.direction:"none")' "$(native "$M")" "$(native "$2")" "$(native "$EN")")"
  [ "$got" = "$3" ] && ok "$1: pending $3" || bad "$1: expected pending $3, got $got"; }

f="$T/1.jsonl"; { user "work through the list autonomously"; asst "x"; } > "$f"
mode "an on-word alone switches nothing" "$f" interactive
pend "an on-word alone leaves the question pending" "$f" autonomous
[ "$(MODE_READING=words node "$M" "$(native "$f")" "$(native "$EN")")" = autonomous ] && ok "control: the words read it as an order" || bad "control: the words no longer read the order"
f="$T/2.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "The open list" "This prompt's work" "The open list" "Stay interactive"; } > "$f"
mode "the answer naming a scope switches it on" "$f" autonomous
pend "the answer ends the wait" "$f" none
f="$T/3.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "Stay interactive" "The open list" "Stay interactive"; } > "$f"
mode "the last option (stay interactive) keeps it interactive" "$f" interactive
f="$T/4.jsonl"; { user "work through the list autonomously"; confirm c1 other "The open list" "The open list" "Stay interactive"; } > "$f"
mode "control: the same answer under another header is no mode-confirm answer" "$f" interactive
f="$T/5.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "hm, not sure" "The open list" "Stay interactive"; } > "$f"
mode "a free-text answer that orders nothing stays interactive" "$f" interactive
f="$T/6.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "The open list" "The open list" "Stay interactive"; asst "x"; user "back to normal mode"; } > "$f"
mode "an off-word in a run switches nothing by itself" "$f" autonomous
pend "the off-word leaves 'continue interactively?' pending" "$f" interactive
f="$T/7.jsonl"; { cat "$T/6.jsonl"; confirm c2 mode-confirm "Continue interactively" "Stay autonomous" "Continue interactively"; } > "$f"
mode "the answer to 'continue interactively?' ends the run" "$f" interactive
f="$T/8.jsonl"; { cat "$T/6.jsonl"; confirm c2 mode-confirm "Stay autonomous" "Stay autonomous" "Continue interactively"; } > "$f"
mode "'stay autonomous' keeps the run" "$f" autonomous
f="$T/9.jsonl"; { user "work through the list autonomously"; rejected c1; } > "$f"
mode "a rejected mode-confirm question switches nothing" "$f" interactive
pend "a rejected mode-confirm question ends the wait" "$f" none
f="$T/10.jsonl"; { user "work through the list autonomously"; asst "x"; user "no wait - normal mode"; } > "$f"
pend "naming the mode in force cancels the wait" "$f" none
f="$T/11.jsonl"; { user "work through the list autonomously"; asst "x"; user "and also check the build"; } > "$f"
pend "a later prompt without a mode word keeps the wait" "$f" autonomous

# pre / stop (state file under the fixture's .claude-state)
hook() { # $1 tool, $2 transcript, $3 session, [$4 tool_input json]
  local ti="${4:-}"; [ -n "$ti" ] || ti='{}'
  printf '{"tool_name":"%s","transcript_path":%s,"session_id":"%s","cwd":%s,"tool_input":%s}' "$1" "$(js "$(native "$2")")" "$3" "$(js "$(native "$EN")")" "$ti"
}
pre() { CLAUDE_PROJECT_DIR="$(native "$EN")" node -e 'let r="";process.stdin.on("data",c=>r+=c).on("end",()=>{const x=require(process.argv[1]).pre(JSON.parse(r));process.stdout.write(x?"held":"pass")})' "$(native "$C")"; }
f="$T/1.jsonl"
[ "$(hook Edit "$f" s1 | pre)" = held ] && ok "pre: an edit is held while the question is pending" || bad "pre: the edit passed"
[ "$(hook Edit "$f" s1 | pre)" = held ] && ok "pre: and held again (no free pass)" || bad "pre: the second edit passed"
[ "$(hook Read "$f" s1 | pre)" = pass ] && ok "pre: a read passes" || bad "pre: a read was held"
Q='{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"a"},{"label":"Stay interactive"}]}]}'
[ "$(hook AskUserQuestion "$f" s1 "$Q" | pre)" = pass ] && ok "pre: the mode-confirm question passes" || bad "pre: the question was held"
Q1='{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"a"}]}]}'
[ "$(hook AskUserQuestion "$f" s1 "$Q1" | pre)" = held ] && ok "pre: a mode-confirm question with one option is held" || bad "pre: one option passed"
# every mode switch takes the mode-confirm form, also "continue autonomously?" at the end of a dialog (2026-11-25)
QL='{"questions":[{"question":"Continue autonomously?","header":"Mode","options":[{"label":"Yes"},{"label":"No"}]}]}'
[ "$(hook AskUserQuestion "$T/2.jsonl" s9 "$QL" | pre)" = held ] && ok "pre: the old-form mode question is held" || bad "pre: the old-form mode question passed"
QH='{"questions":[{"question":"Continue autonomously?","header":"mode-confirm","options":[{"label":"Yes, the open list"},{"label":"Continue interactively"}]}]}'
[ "$(hook AskUserQuestion "$T/2.jsonl" s9 "$QH" | pre)" = pass ] && ok "pre: control - the same question as mode-confirm passes" || bad "pre: the mode-confirm form was held"
QO='{"questions":[{"question":"Release now?","header":"release","options":[{"label":"Yes"},{"label":"No"}]}]}'
[ "$(hook AskUserQuestion "$T/2.jsonl" s9 "$QO" | pre)" = pass ] && ok "pre: control - a question that is no mode question passes" || bad "pre: another question was held"
# The dialog (operator 2026-11-25): all questions and dialogs come, the mode stands, the closing mode-confirm decides.
wmode() { local got; got="$(node "$M" "$(native "$2")" "$(native "$EN")" --window)"; [ "$got" = "$3" ] && ok "$1: $3" || bad "$1: expected $3, got $got"; }
f="$T/12a.jsonl"; { cat "$T/2.jsonl"; asst "x"; user "anything open for me?"; confirm q1 release "Yes" "Yes" "No"; confirm q2 budget "No" "Yes" "No"; confirm q3 device "Later" "Now" "Later"; } > "$f"
wmode "a dialog: three answered questions leave the run and its window standing" "$f" window
f="$T/12.jsonl"; { cat "$T/12a.jsonl"; confirm c3 mode-confirm "Yes, the open list" "Yes, the open list" "Continue interactively"; } > "$f"
wmode "the closing mode-confirm answer 'autonomous' keeps the run, the window ends" "$f" autonomous
f="$T/12b.jsonl"; { cat "$T/12a.jsonl"; confirm c3 mode-confirm "Continue interactively" "Yes, the open list" "Continue interactively"; } > "$f"
wmode "the closing mode-confirm answer 'interactive' ends the run" "$f" interactive
f="$T/12c.jsonl"; { cat "$T/12a.jsonl"; asst "done"; peer() { printf '{"type":"user","origin":{"kind":"peer"},"message":{"role":"user","content":%s}}\n' "$(js "$1")"; }; peer "the build is done"; } > "$f"
wmode "control: a turn the operator did not open closes the window, the run stays" "$f" autonomous
grep -q 'mode-confirm' "$_D/../helpers/mode-owed.cjs" && ok "mode-owed: its holds name the mode-confirm form" || bad "mode-owed: no mode-confirm in its holds"
f="$T/2.jsonl"
[ "$(hook Edit "$f" s2 | pre)" = pass ] && ok "pre: control - after the answer the edit passes" || bad "pre: held after the answer"
# the cache: the transcript grows by an assistant record only - the pending state is reused; an answer moves it
g="$T/grow.jsonl"; cp "$T/1.jsonl" "$g"
hook Edit "$g" s3 | pre >/dev/null; asst "more work" >> "$g"
[ "$(hook Edit "$g" s3 | pre)" = held ] && ok "pre: cache - an assistant record keeps the hold" || bad "pre: cache lost the hold"
confirm c1 mode-confirm "The open list" "The open list" "Stay interactive" >> "$g"
[ "$(hook Edit "$g" s3 | pre)" = pass ] && ok "pre: cache - an appended answer releases it" || bad "pre: cache kept a stale hold"
# Windows review of #672 (2026-11-25), finding 1: a half-written answer line must not leave a stale hold
g="$T/half.jsonl"; cp "$T/1.jsonl" "$g"; confirm c1 mode-confirm "The open list" "The open list" "Stay interactive" > "$T/ans.txt"
hook Edit "$g" s11 | pre >/dev/null
head -n 1 "$T/ans.txt" >> "$g"; tail -n 1 "$T/ans.txt" | head -c 60 | tr -d '\n' >> "$g"
[ "$(hook Edit "$g" s11 | pre)" = held ] && ok "pre: a half-written answer line holds (not yet an answer)" || bad "pre: passed on half a line"
tail -n 1 "$T/ans.txt" | tail -c +61 >> "$g"
[ "$(hook Edit "$g" s11 | pre)" = pass ] && ok "pre: once the line is complete the hold is gone (no stale hold)" || bad "pre: stale hold after the line completed"
# finding 2: a free-text yes is no order
f="$T/13.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "yes, stay interactive" "The open list" "Continue interactively"; } > "$f"
mode "free text 'yes, stay interactive' stays interactive" "$f" interactive
f="$T/13b.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "Stay interactive please" "The open list" "Stay interactive"; } > "$f"
mode "free text naming the last option stays interactive" "$f" interactive
f="$T/13c.jsonl"; { user "work through the list autonomously"; confirm c1 mode-confirm "only the list, work through it autonomously" "The open list" "Continue interactively"; } > "$f"
mode "control: a free-text order switches on" "$f" autonomous
# finding 3: a misordered option list is held at ask time
QM='{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"Stay interactive"},{"label":"The open list"}]}]}'
[ "$(hook AskUserQuestion "$T/1.jsonl" s12 "$QM" | pre)" = held ] && ok "pre: the interactive option first is held" || bad "pre: a misordered list passed"
QM2='{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"Continue interactively"},{"label":"Stay autonomous"}]}]}'
[ "$(hook AskUserQuestion "$T/6.jsonl" s12 "$QM2" | pre)" = held ] && ok "pre: towards interactive, autonomous last is held" || bad "pre: autonomous last passed"
QM3='{"questions":[{"question":"Mode?","header":"mode-confirm","options":[{"label":"Stay autonomous"},{"label":"Continue interactively"}]}]}'
[ "$(hook AskUserQuestion "$T/6.jsonl" s12 "$QM3" | pre)" = pass ] && ok "pre: control - the right order passes" || bad "pre: the right order was held"
# through the gate itself
out="$(hook Edit "$T/1.jsonl" s4 | CLAUDE_PROJECT_DIR="$(native "$EN")" node "$AG")"
[[ "$out" == *MODE-CONFIRM* && "$out" == *"no extra rights"* ]] && ok "gate: the hold names the question and the explanation" || bad "gate: no MODE-CONFIRM hold: $out"
f="$T/6.jsonl"; out="$(hook AskUserQuestion "$f" s5 "$Q" | CLAUDE_PROJECT_DIR="$(native "$EN")" node "$AG")"
[ -z "$out" ] && ok "gate: in an autonomous run the mode-confirm question is not refused" || bad "gate: refused it: $out"
Q2='{"questions":[{"question":"Release now?","header":"release","options":[{"label":"a"},{"label":"b"}]}]}'
out="$(hook AskUserQuestion "$T/2.jsonl" s6 "$Q2" | CLAUDE_PROJECT_DIR="$(native "$EN")" node "$AG")"
[[ "$out" == *AUTONOMOUS-GATE* ]] && ok "gate: control - another question in the run is still refused" || bad "gate: another question passed: $out"
# stop
st() { printf '{"transcript_path":%s,"session_id":"%s","cwd":%s}' "$(js "$(native "$1")")" "$2" "$(js "$(native "$EN")")" | CLAUDE_PROJECT_DIR="$(native "$EN")" node "$C" stop; }
[ -n "$(st "$T/1.jsonl" s7)" ] && ok "stop: a turn end with the question unasked is held" || bad "stop: not held"
[ -z "$(st "$T/1.jsonl" s7)" ] && ok "stop: once per mode word" || bad "stop: held twice"
[ -z "$(st "$T/2.jsonl" s8)" ] && ok "stop: control - answered, no hold" || bad "stop: held after the answer"

echo
[ "$fail" -eq 0 ] && echo "mode-confirm fixtures: ALL passed" || { echo "mode-confirm fixtures: FAILURE"; exit 1; }
