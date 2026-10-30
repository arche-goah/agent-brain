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
write() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":%s}}]}}\n' "$(js "$1")"; }
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

# --- the class: a correction, a fix on the spot, no cause named
{ user "check the PRs"; asst "Done."; user "that is already active! something went wrong"; asst "Closed the question in the register."; } > "$T/t1.jsonl"
check "correction answered without a cause" "$T/t1.jsonl" block "$CWD"
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
{ user "go"; asst "ok"; user "something went wrong"; asst "Cause unknown — the transcript of that session is gone; what is missing: the register's state of that day.
Carrier: none — the cause is unknown, nothing to build until it is measured"; write "$CWD/$REG"; } > "$T/t6.jsonl"
check "cause unknown, carrier none with a reason, registered" "$T/t6.jsonl" allow "$CWD"
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
check "carrier none with a reason, registered" "$T/t24.jsonl" allow "$CWD"
# --- must allow: no correction
{ user "go"; asst "ok"; user "and the show?"; asst "Fixed."; } > "$T/t7.jsonl"
check "no correction in the prompt" "$T/t7.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user 'he wrote "something went wrong" in the ticket, please read it'; asst "Read it."; } > "$T/t8.jsonl"
check "a correction only quoted" "$T/t8.jsonl" allow "$CWD"
{ user "go"; asst "ok"; user "why is the fan loud?"; asst "The fan curve."; } > "$T/t9.jsonl"
check "a why-question about the work, not about the agent" "$T/t9.jsonl" allow "$CWD"
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
unset WHEN

[ "$fail" = 0 ] && echo "root-cause-gate: all checks passed" || echo "root-cause-gate: FAILURES"
exit "$fail"
