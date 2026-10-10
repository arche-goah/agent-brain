#!/usr/bin/env bash
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
case "$OUT" in *'[PREMISE-GATE]'*) ok "keeps PREMISE-GATE cooldown marker";; *) bad "PREMISE-GATE marker lost";; esac
case "$OUT" in *'[CLASS-GATE]'*) ok "keeps CLASS-GATE cooldown marker";; *) bad "CLASS-GATE marker lost";; esac
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

echo
[ "$fail" -eq 0 ] && echo "stop-dispatcher fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
