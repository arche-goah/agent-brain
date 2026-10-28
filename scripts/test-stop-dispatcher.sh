#!/usr/bin/env bash
# covers: stop-dispatcher stop-echo
# Fixture test for the stop dispatcher: does it collect several gates into ONE block,
# keep every gate's cooldown marker, and stay silent when nothing fires?
# Usage: bash scripts/test-stop-dispatcher.sh   (exit 0 = all fixtures pass)
set -u

# A path that travels INSIDE data (a JSON string, an env var read by a native process)
# is not translated by the shell — on Git Bash node would receive /d/a/... or /tmp/...
# and resolve neither. cygpath states the same path natively; elsewhere it is a no-op.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Two layouts, one fixture: inside a brain the helpers live under core/helpers, inside
# the core repo itself under helpers. A fixture that only knows one of them silently
# tests nothing in the other — so resolution is explicit, and a missing subject is
# SKIPPED loudly rather than passing quietly.
resolve() {
  for cand in "core/$1" "$1"; do
    [ -f "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  return 1
}
skip() { echo "  --  $1 (not in this layout)"; }
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D=$(cd "$ROOT" && resolve helpers/stop-dispatcher.cjs || resolve scripts/hooks/stop-dispatcher.cjs)
D="$ROOT/$D"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }



# The check list is INSTANCE data. Outside a brain there is none, and a dispatcher
# with an empty config correctly does nothing — which would make this fixture pass by
# testing nothing. So it builds its own project root with a minimal config and points
# the dispatcher at that.
CFG="$(mktemp -d)"
mkdir -p "$CFG/.claude/rules"
CG=$(cd "$ROOT" && resolve helpers/class-gate.cjs)
PG=$(cd "$ROOT" && resolve helpers/premise-gate.cjs || resolve scripts/hooks/premise-gate.cjs)
TG=$(cd "$ROOT" && resolve scripts/hooks/time-gate.cjs || true)
{
  printf '{"header":"STOP-CHECKS ({n})","checks":['
  printf '{"label":"CLASS","marker":"CLASS-GATE","cmd":"%s","mode":"block",' "$(native "$ROOT/$CG")"
  # ' *' instead of a backslash class: same match, no escape to survive two layers of
  # quoting. The heredoc that used to build this JSON was the only thing in the suite
  # that needed an interpreter, and the only thing that failed on Windows.
  printf '"extract":"Touched this turn: *(.+)","template":"{1} -> class?","basename":true}'
  printf ',{"label":"PREMISE","marker":"PREMISE-GATE","cmd":"%s","mode":"block",' "$(native "$ROOT/$PG")"
  printf '"extract":"Rule-shaped wording: *(.+)","template":"{1} carries an action"}'
  if [ -n "$TG" ]; then
    printf ',{"label":"TIME","marker":"TIME-GATE","cmd":"%s","mode":"record","args":["--record"]}' "$(native "$ROOT/$TG")"
  fi
  printf ']}'
} > "$CFG/.claude/rules/stop-checks.json"
trap 'rm -rf "$T" "$CFG"' EXIT

feed() { # $1 transcript -> dispatcher output
  printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
    "$(native "$1")" "$(native "$CFG")" \
    | CLAUDE_PROJECT_DIR="$(native "$CFG")" node "$D" 2>/dev/null
}

# --- a turn that trips THREE gates: time + premise + class -------------------
TR="$T/three.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$TR"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"That has been open since yesterday. In a conflict the one who lets go last always wins."},{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"scripts/hooks/probe-fixture.cjs","content":"x"}}]}}' >> "$TR"
OUT="$(feed "$TR")"

case "$OUT" in *'STOP-CHECKS'*) ok "emits one combined block";; *) bad "no combined block: $OUT";; esac
n=$(printf '%s' "$OUT" | grep -o '·' | wc -l | tr -d ' ')
[ "$n" -ge 2 ] && ok "collects $n findings in one message" || bad "only $n findings"
# ZEIT is a RECORDING check since 2026-08-20: it must NOT appear in the block, and its
# findings must land in the log instead. Both halves are asserted — a recorder that
# silently records nothing looks exactly like one that had nothing to record.
case "$OUT" in *'[TIME-GATE]'*) bad "TIME-GATE blocked although it only records";; *) ok "TIME-GATE does not block";; esac
if [ -n "$TG" ]; then
  LOG="$CFG/.claude-state/time-gate.jsonl"
  grep -q '"phrase"' "$LOG" 2>/dev/null && ok "recording check wrote to its log" \
    || bad "recorder registered but nothing landed in $LOG"
else
  skip "recording check (no recorder in this layout)"
fi
# Operator 2026-10-10: no codes in the lines. A gate that finds its echo by its label
# (premise-gate) declares it and its line goes out without a token; a gate that does not
# declare it (class-gate, not converted yet) keeps its token, or its cooldown would die.
case "$OUT" in *'[PREMISE-GATE]'*) bad "PREMISE line still carries its token: $OUT";;
  *'PREMISE '*) ok "PREMISE line without a token (gate reads its echo by label)";; *) bad "PREMISE finding lost: $OUT";; esac
case "$OUT" in *'[CLASS-GATE]'*) ok "keeps the CLASS-GATE token for a gate that still reads it";; *) bad "CLASS-GATE marker lost";; esac
lines=$(printf '%s' "$OUT" | "$PY" -c "import json,sys; print(len(json.load(sys.stdin)['reason'].splitlines()))")
[ "$lines" -le 6 ] && ok "compact ($lines lines)" || bad "not compact ($lines lines)"

# --- a clean turn: nothing fires --------------------------------------------
TR2="$T/clean.jsonl"
printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$TR2"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"Messwert 34 s steht im Log, sonst nichts offen."}]}}' >> "$TR2"
OUT2="$(feed "$TR2")"
[ -z "$OUT2" ] && ok "silent when no gate fires" || bad "fired on a clean turn: $OUT2"

# --- re-issue pass: stop_hook_active silences everything ---------------------
OUT3="$(printf '{"transcript_path":"%s","stop_hook_active":true,"cwd":"%s"}' \
  "$(native "$TR")" "$(native "$CFG")" \
  | CLAUDE_PROJECT_DIR="$(native "$CFG")" node "$D" 2>/dev/null)"
[ -z "$OUT3" ] && ok "silent on the re-issue pass" || bad "blocked twice: $OUT3"

# --- turn kind: a notification turn reaches every check as such; "skip" sits it out ---
# A probe check that always blocks and names the turn kind it was handed. Two entries:
# SKIPPER opts out of notification turns, PLAIN does not (the default).
PROBE="$T/probe.cjs"
printf '%s\n' "let d='';process.stdin.on('data',c=>d+=c);process.stdin.on('end',()=>{let k='none';try{k=JSON.parse(d).turn_kind||'none'}catch(e){}console.log(JSON.stringify({decision:'block',reason:'kind='+k}))});" > "$PROBE"
CFG2="$(mktemp -d)"
mkdir -p "$CFG2/.claude/rules"
printf '{"checks":[{"label":"SKIPPER","marker":"SKIP-PROBE","cmd":"%s","mode":"block","onNotification":"skip"},{"label":"PLAIN","marker":"PLAIN-PROBE","cmd":"%s","mode":"block"}]}' \
  "$(native "$PROBE")" "$(native "$PROBE")" > "$CFG2/.claude/rules/stop-checks.json"
trap 'rm -rf "$T" "$CFG" "$CFG2"' EXIT
feed2() {
  printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$1")" "$(native "$CFG2")" \
    | CLAUDE_PROJECT_DIR="$(native "$CFG2")" node "$D" 2>/dev/null
}
NOTE='<system-reminder>\n[SYSTEM NOTIFICATION - NOT USER INPUT]\n<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>\n</system-reminder>'
TN="$T/notif.jsonl"
{ printf '%s\n' '{"message":{"role":"user","content":"frage"}}' '{"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}'
  printf '{"message":{"role":"user","content":"%s"}}\n' "$NOTE"
  printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"CI green."}]}}'; } > "$TN"
OUT4="$(feed2 "$TN")"
case "$OUT4" in *'SKIP-PROBE'*) bad "skip check ran on a notification turn: $OUT4";; *) ok "onNotification:skip sits out a notification turn";; esac
case "$OUT4" in *'[PLAIN-PROBE]'*) ok "a check without the setting still runs";; *) bad "default check skipped: $OUT4";; esac
case "$OUT4" in *'kind=notification'*) ok "checks are told turn_kind=notification";; *) bad "turn_kind not handed over: $OUT4";; esac

TO="$T/oper.jsonl"
{ cat "$TN"; printf '%s\n' '{"message":{"role":"user","content":"next"}}' '{"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}'; } > "$TO"
OUT5="$(feed2 "$TO")"
case "$OUT5" in *'SKIP-PROBE'*'PLAIN-PROBE'*|*'PLAIN-PROBE'*'SKIP-PROBE'*) ok "both run on an operator turn";; *) bad "operator turn lost a check: $OUT5";; esac
case "$OUT5" in *'kind=operator'*) ok "checks are told turn_kind=operator";; *) bad "operator kind missing: $OUT5";; esac

# A frame plus the operator's own words is the operator — and hook feedback after a
# notification does not turn it into an operator turn.
TM="$T/mixed.jsonl"
{ printf '%s\n' '{"message":{"role":"user","content":"frage"}}'
  printf '{"message":{"role":"user","content":"%s and please go on"}}\n' "$NOTE"
  printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}'; } > "$TM"
case "$(feed2 "$TM")" in *'kind=operator'*) ok "frame + operator words = operator";; *) bad "mixed record read as notification";; esac
TF="$T/feedback.jsonl"
{ cat "$TN"; printf '%s\n' '{"message":{"role":"user","content":"Stop hook feedback:\nx"}}' '{"message":{"role":"assistant","content":[{"type":"text","text":"re"}]}}'; } > "$TF"
case "$(feed2 "$TF")" in *'kind=notification'*) ok "hook feedback keeps the notification kind";; *) bad "hook feedback flipped the kind";; esac

# --- recorder logs rotate by size, one generation (both ways) -----------------
# A probe recorder that always records one row. Limit 200 bytes: a log above it is
# moved to <name>.1.jsonl and the new row starts a fresh file; a log below it is
# appended to and no older generation appears.
REC="$T/rec.cjs"
printf '%s\n' "console.log(JSON.stringify({record:[{probe:'fresh-row'}]}))" > "$REC"
CFG3="$(mktemp -d)"
mkdir -p "$CFG3/.claude/rules" "$CFG3/.claude-state"
printf '{"checks":[{"label":"REC","marker":"REC-PROBE","cmd":"%s","mode":"record"}]}' \
  "$(native "$REC")" > "$CFG3/.claude/rules/stop-checks.json"
trap 'rm -rf "$T" "$CFG" "$CFG2" "$CFG3"' EXIT
RLOG="$CFG3/.claude-state/rec-probe.jsonl"
feed3() {
  printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$TR2")" "$(native "$CFG3")" \
    | STOP_RECORD_MAX_BYTES=200 CLAUDE_PROJECT_DIR="$(native "$CFG3")" node "$D" >/dev/null 2>&1
}
printf '{"probe":"small-old-row"}\n' > "$RLOG"
feed3
if [ ! -f "$CFG3/.claude-state/rec-probe.1.jsonl" ] && grep -q small-old-row "$RLOG" && grep -q fresh-row "$RLOG"; then
  ok "a log below the limit is appended to, not rotated"
else
  bad "a log below the limit was rotated or lost a row"
fi
rm -f "$RLOG"
for _ in 1 2 3 4 5 6 7 8 9 10; do printf '{"probe":"big-old-row-padding-padding"}\n' >> "$RLOG"; done
feed3
if grep -q big-old-row "$CFG3/.claude-state/rec-probe.1.jsonl" 2>/dev/null \
   && grep -q fresh-row "$RLOG" && ! grep -q big-old-row "$RLOG"; then
  ok "a log above the limit moves to .1.jsonl and the new row starts a fresh file"
else
  bad "a log above the limit was not rotated"
fi

# --- a gate without --record in a recorder slot: its block is recorded, never shown ---
# premise-gate has no record mode; until 2026-10-23 its block was dropped in a record slot
# and the log never came into being. Both halves: it lands in the log, and it does not block.
BLK="$T/blk.cjs"
printf '%s\n' "console.log(JSON.stringify({decision:'block',reason:'probe premise'}))" > "$BLK"
printf '{"checks":[{"label":"BLK","marker":"BLK-PROBE","cmd":"%s","mode":"record"}]}' \
  "$(native "$BLK")" > "$CFG3/.claude/rules/stop-checks.json"
BOUT="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$TR2")" "$(native "$CFG3")" \
  | CLAUDE_PROJECT_DIR="$(native "$CFG3")" node "$D" 2>/dev/null)"
case "$BOUT" in *'probe premise'*) bad "a block in a record slot reached the turn";; *) ok "a block in a record slot does not block";; esac
grep -q '"would_block":true' "$CFG3/.claude-state/blk-probe.jsonl" 2>/dev/null \
  && ok "a block in a record slot lands in the log as would_block" \
  || bad "a block in a record slot was dropped — the recorder records nothing"

# --- re-issue pass: only a check that opts in runs (onReissue), a loud let-through is forwarded ---
# stoppen-gate since 2026-10-15: an operator decision re-issued as closing prose instead of
# through the question tool must not pass by repetition — so the re-issue has to reach it.
CFG4="$(mktemp -d)"
mkdir -p "$CFG4/.claude/rules"
LOUD="$T/loud.cjs"
printf '%s\n' "console.log(JSON.stringify({systemMessage:'let through loudly'}))" > "$LOUD"
trap 'rm -rf "$T" "$CFG" "$CFG2" "$CFG3" "$CFG4"' EXIT
feed4() { # $1 transcript, $2 stop_hook_active
  printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' "$(native "$1")" "$2" "$(native "$CFG4")" \
    | CLAUDE_PROJECT_DIR="$(native "$CFG4")" node "$D" 2>/dev/null
}
printf '{"checks":[{"label":"REISSUE","marker":"REISSUE-PROBE","cmd":"%s","mode":"block","onReissue":"run"},{"label":"PLAIN","marker":"PLAIN-PROBE","cmd":"%s","mode":"block"}]}' \
  "$(native "$PROBE")" "$(native "$PROBE")" > "$CFG4/.claude/rules/stop-checks.json"
OUT6="$(feed4 "$TR2" true)"
case "$OUT6" in *'[REISSUE-PROBE]'*) ok "an opted-in check runs on the re-issue pass";; *) bad "opted-in check silent on re-issue: $OUT6";; esac
case "$OUT6" in *'PLAIN-PROBE'*) bad "a check without onReissue ran on the re-issue pass: $OUT6";; *) ok "a check without onReissue stays silent on the re-issue pass";; esac
printf '{"checks":[{"label":"LOUD","marker":"LOUD-PROBE","cmd":"%s","mode":"block"}]}' \
  "$(native "$LOUD")" > "$CFG4/.claude/rules/stop-checks.json"
OUT7="$(feed4 "$TR2" false)"
case "$OUT7" in *'"decision"'*) bad "a let-through turned into a block: $OUT7";;
  *'[LOUD-PROBE]'*) bad "a let-through carries a token: $OUT7";;
  *'LOUD — let through loudly'*) ok "a check's systemMessage reaches the operator without a block, named by its label";;
  *) bad "systemMessage swallowed: $OUT7";; esac
# End to end with the real stoppen-gate and the template's entry: the prose decision question
# re-issued after the gate's own block blocks again, in full; without onReissue it passes.
SG=$(cd "$ROOT" && resolve helpers/stoppen-gate.cjs || true)
if [ -n "$SG" ]; then
  TQ="$T/reissue.jsonl"
  { printf '%s\n' '{"message":{"role":"user","content":"frage"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"The fix is ready. Should I proceed with the merge?"}]}}'
    printf '%s\n' '{"message":{"role":"user","content":"Stop hook feedback:\nCLOSING QUESTION — Closing question - ask it through the question tool   [STOPPEN-GATE]"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"The fix is ready. Should I proceed with the merge?"}]}}'; } > "$TQ"
  sgcfg() { # $1 extra key ("" or ,"onReissue":"run")
    printf '{"checks":[{"label":"CLOSING QUESTION","marker":"STOPPEN-GATE","cmd":"%s","mode":"block","extract":"Closing question in this reply: *(.+)","template":"Closing question {1}"%s}]}' \
      "$(native "$ROOT/$SG")" "$1" > "$CFG4/.claude/rules/stop-checks.json"
  }
  sgcfg ',"onReissue":"run"'
  OUT8="$(feed4 "$TQ" true)"
  case "$OUT8" in *'[STOPPEN-GATE]'*) bad "stoppen line still carries its token: $OUT8";;
    *'"decision":"block"'*'question tool'*) ok "stoppen-gate judges its own re-issue behind the dispatcher, reason in full";;
    *) bad "stoppen-gate re-issue not judged: $OUT8";; esac
  # The same re-issue after an echo WITHOUT the token (the form the dispatcher writes now):
  # the gate has to recognise its own line by the label the dispatcher handed it.
  TQL="$T/reissue-label.jsonl"
  { printf '%s\n' '{"message":{"role":"user","content":"frage"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"The fix is ready. Should I proceed with the merge?"}]}}'
    printf '%s\n' '{"message":{"role":"user","content":"Stop hook feedback:\nCLOSING QUESTION — Closing question - ask it through the question tool"}}'
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"The fix is ready. Should I proceed with the merge?"}]}}'; } > "$TQL"
  sgcfg ',"onReissue":"run"'
  case "$(feed4 "$TQL" true)" in *'"decision":"block"'*'question tool'*) ok "stoppen-gate finds its token-free echo by the label it was handed";;
    *) bad "token-free echo not recognised: $(feed4 "$TQL" true)";; esac
  sgcfg ''
  OUT9="$(feed4 "$TQ" true)"
  [ -z "$OUT9" ] && ok "without onReissue the re-issue passes as before" || bad "re-issue judged without opt-in: $OUT9"
else
  skip "stoppen-gate end to end"
fi

# A template check marked required runs in a brain whose instance file lacks it (2026-10-26:
# a check added to the template later otherwise ships and runs nowhere).
if [ -f "$ROOT/helpers/commitment-carrier-gate.cjs" ] && [ -f "$ROOT/templates/rules-instance/stop-checks.json" ]; then
  P="$T/req-brain"; mkdir -p "$P/.claude/rules"; ln -s "$ROOT" "$P/core"
  printf '%s\n' '{"checks":[]}' > "$P/.claude/rules/stop-checks.json"
  TR="$T/req.jsonl"
  { printf '%s\n' '{"type":"user","message":{"role":"user","content":"why did you not restart it?"}}'
    printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"From now on I keep the watcher running while the desk runs."}]}}'; } > "$TR"
  feedreq() { printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$TR")" "$(native "$P")" | CLAUDE_PROJECT_DIR="$P" node "$D"; }
  case "$(feedreq)" in *'"decision":"block"'*) ok "a required template check runs although the instance file does not list it";;
    *) bad "required template check did not run: $(feedreq)";; esac
  printf '%s\n' '{"checks":[],"disabled":{"COMMITMENT-CARRIER-GATE":"test brain, operator 2026-10-26"}}' > "$P/.claude/rules/stop-checks.json"
  [ -z "$(feedreq)" ] && ok "disabled by name with a reason: the required check stays off" || bad "disabled check still ran: $(feedreq)"
  printf '%s\n' '{"checks":[],"disabled":{"COMMITMENT-CARRIER-GATE":""}}' > "$P/.claude/rules/stop-checks.json"
  case "$(feedreq)" in *'"decision":"block"'*) ok "disabled WITHOUT a reason does not switch it off";;
    *) bad "an empty reason switched the required check off";; esac
else
  skip "required template checks"
fi

# The template's open-items line names the branch that fired (2026-10-28: a fixed sentence read
# "missing from the first reply" for the close-report branch). A stand-in gate prints that reason.
if [ -f "$ROOT/templates/rules-instance/stop-checks.json" ]; then
  P="$T/oi-brain"; mkdir -p "$P/.claude/rules"
  printf '%s\n' "console.log(JSON.stringify({decision:'block',reason:'The close report leaves out what the session start lists as ours and is still open — the operator shuts down on this answer. Missing: core#7'}))" > "$T/oi-gate.cjs"
  node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync(process.argv[1],"utf8")).checks.find(x=>x.marker==="OPEN-ITEMS-GATE");c.cmd=process.argv[2];fs.writeFileSync(process.argv[3],JSON.stringify({checks:[c]}))' \
    "$(native "$ROOT/templates/rules-instance/stop-checks.json")" "$(native "$T/oi-gate.cjs")" "$(native "$P/.claude/rules/stop-checks.json")"
  TR="$T/oi.jsonl"; printf '%s\n' '{"type":"user","message":{"role":"user","content":"close"}}' > "$TR"
  OI=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$TR")" "$(native "$P")" | CLAUDE_PROJECT_DIR="$P" node "$D")
  case "$OI" in *"The close report leaves out"*"missing: core#7"*) ok "open-items line names the branch and what is missing";;
    *) bad "open-items line: $OI";; esac
  case "$OI" in *"first reply"*) bad "open-items line still says first reply: $OI";; *) ok "no first-reply wording on a close-report block";; esac
else
  skip "open-items template line"
fi

echo
[ "$fail" -eq 0 ] && echo "stop-dispatcher fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
