#!/usr/bin/env bash
# covers: operator-lead
# Fixture for helpers/operator-lead.cjs (2026-11-26: the operator sees about two lines of a hold, and they were
# written for the agent). Must hold: a deny reason and a block reason whose marker is in the brain's
# operator-lines.json get that sentence in front, the agent's text after it unchanged; console.log is reached too.
# Must pass unchanged: no data file, a marker not in the table, a non-JSON write, a JSON write without a reason,
# a reason that already starts with the sentence.
# Usage: bash scripts/test-operator-lead.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
OL="$(native "$_D/../hooks/operator-lead.cjs")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

mkdir -p "$T/b/.claude/rules"
printf '{"lines":{"MECHANISM CHECK":"Stopped: there is a defined path for this. Nothing for you to do.","STOPPEN-GATE":"Stopped: a question to you belongs in the question tool."}}\n' \
  > "$T/b/.claude/rules/operator-lines.json"
DENY='process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"MECHANISM CHECK (core): a heredoc"}}))'
BLOCK='console.log(JSON.stringify({decision:"block",reason:"STOPPEN-GATE (stopping is the exception)"}))'

run() { # $1 project dir, $2 js
  CLAUDE_PROJECT_DIR="$(native "$1")" node -r "$OL" -e "$2" 2>&1
}

out="$(run "$T/b" "$DENY")"
r="$(node -e 'const o=JSON.parse(process.argv[1]);process.stdout.write(o.hookSpecificOutput.permissionDecisionReason)' "$out")"
[ "$r" = "$(printf 'Stopped: there is a defined path for this. Nothing for you to do.\nMECHANISM CHECK (core): a heredoc')" ] \
  && ok "deny reason gets the sentence in front, agent text unchanged" || bad "deny: '$r'"

out="$(run "$T/b" "$BLOCK")"
r="$(node -e 'const o=JSON.parse(process.argv[1]);process.stdout.write(o.reason)' "$out")"
case "$r" in "Stopped: a question to you belongs in the question tool."$'\n'"STOPPEN-GATE (stopping"*) ok "block reason via console.log gets the sentence";;
  *) bad "block: '$r'";; esac

mkdir -p "$T/none"
out="$(run "$T/none" "$DENY")"
[[ "$out" == *'"permissionDecisionReason":"MECHANISM CHECK (core): a heredoc"'* ]] && ok "no data file: unchanged" || bad "no data: '$out'"

out="$(run "$T/b" 'console.log(JSON.stringify({decision:"block",reason:"OTHER-GATE: x"}))')"
[ "$out" = '{"decision":"block","reason":"OTHER-GATE: x"}' ] && ok "marker not in the table: byte for byte" || bad "other marker: '$out'"

out="$(run "$T/b" 'process.stdout.write("MECHANISM CHECK plain text\n")')"
[ "$out" = "MECHANISM CHECK plain text" ] && ok "non-JSON write passes" || bad "plain: '$out'"

out="$(run "$T/b" 'console.log(JSON.stringify({systemMessage:"MECHANISM CHECK note"}))')"
[ "$out" = '{"systemMessage":"MECHANISM CHECK note"}' ] && ok "JSON without a hold reason passes" || bad "no reason: '$out'"

out="$(run "$T/b" 'console.log(JSON.stringify({decision:"block",reason:"Stopped: a question to you belongs in the question tool.\nSTOPPEN-GATE x"}))')"
n="$(printf %s "$out" | grep -ao 'Stopped: a question' | wc -l | tr -d ' ')"
[ "$n" = 1 ] && ok "a reason that already leads with the sentence is not doubled" || bad "doubled ($n)"

out="$(run "$T/b" 'console.log(JSON.stringify({decision:"block",reason:"STOPPEN-GATE first; then MECHANISM CHECK second"}))')"
r="$(node -e 'const o=JSON.parse(process.argv[1]);process.stdout.write(o.reason.split("\n")[0])' "$out")"
[ "$r" = "Stopped: a question to you belongs in the question tool." ] && ok "the marker named first wins" || bad "first marker: '$r'"

printf '{broken' >"$T/b/.claude/rules/operator-lines.json"
out="$(run "$T/b" "$DENY")"
[[ "$out" == *'"permissionDecisionReason":"MECHANISM CHECK (core): a heredoc"'* ]] && ok "broken data file: fails open, unchanged" || bad "broken: '$out'"

# Every node hook of the shipped hooks.json carries the preload (2026-11-26: #653 adds an Agent hook written before
# this preload existed - whichever of the two merges second must fail here until its new line carries it).
gone="$(node -e '
const h=require(process.argv[1]).hooks, out=[];
for (const ev of Object.values(h)) for (const m of ev) for (const k of m.hooks||[])
  if (/^node\s/.test(k.command||"") && !/operator-lead\.cjs/.test(k.command)) out.push(k.command);
process.stdout.write(out.join("\n"));' "$(native "$_D/../hooks/hooks.json")")"
[ -z "$gone" ] && ok "every node hook in hooks/hooks.json carries the operator-lead preload" || bad "node hooks without the preload: $gone"

# --- Windows review of #683 (2026-11-26), the four before-merge points ---------------------------------------------
LEAD="$(native "$_D/../hooks/operator-lead.cjs")"
GL="$(native "$_D/../helpers/gate-label.cjs")"
GH="$(native "$_D/gate-health.py")"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
S1="Stopped: there is a defined path for this. Nothing for you to do."
S2="Stopped: a question to you belongs in the question tool."
# a fresh brain: the case above left $T/b with a broken data file on purpose
mkdir -p "$T/w/.claude/rules"
printf '{"lines":{"MECHANISM CHECK":"%s","STOPPEN-GATE":"%s"}}\n' "$S1" "$S2" > "$T/w/.claude/rules/operator-lines.json"
lead() { CLAUDE_PROJECT_DIR="$(native "$1")" node -e 'process.stdout.write(require(process.argv[1]).lead(process.argv[2]))' "$LEAD" "$2"; }
# (3) the Stop dispatcher's form: LABEL - long text - trailing [MARKER]; two findings -> both sentences, in order
LONG="$(printf 'x%.0s' $(seq 1 140))"
r="$(lead "$T/w" "CLOSING QUESTION — $LONG   [STOPPEN-GATE]")"
case "$r" in "$S2"$'\n'"CLOSING QUESTION"*) ok "(3) a trailing [MARKER] behind a long text gets its sentence";; *) bad "(3) trailing tag: '${r:0:120}'";; esac
r="$(lead "$T/w" "$(printf 'CLOSING QUESTION — a   [STOPPEN-GATE]\nPATH — b   [MECHANISM CHECK]')")"
[ "$r" = "$(printf '%s\n%s\nCLOSING QUESTION — a   [STOPPEN-GATE]\nPATH — b   [MECHANISM CHECK]' "$S2" "$S1")" ] \
  && ok "(3) two findings: both sentences, in the order of the text" || bad "(3) two findings: '$r'"
r="$(lead "$T/w" "FOREIGN-ENTRY: the MECHANISM CHECK path names an id")"
[ "$r" = "FOREIGN-ENTRY: the MECHANISM CHECK path names an id" ] && ok "(3) a marker only MENTIONED in another gate's text gets no sentence" || bad "(3) mention: '$r'"
# (4) a UTF-8 BOM in front of the data file (PowerShell 5.1 Set-Content -Encoding utf8)
mkdir -p "$T/bom/.claude/rules"; printf '\357\273\277' > "$T/bom/.claude/rules/operator-lines.json"; cat "$T/w/.claude/rules/operator-lines.json" >> "$T/bom/.claude/rules/operator-lines.json"
r="$(lead "$T/bom" "MECHANISM CHECK (core): a heredoc")"
case "$r" in "$S1"$'\n'*) ok "(4) a data file with a BOM is read";; *) bad "(4) BOM: '$r'";; esac
# (1) the refusal readers take the sentence off again - both ways, node and python
RAW="PreToolUse:Bash hook error: $(lead "$T/w" "MECHANISM CHECK (agent-brain): a heredoc")"
gl() { node -e 'process.stdout.write(require(process.argv[1]).gateLabel(process.argv[2], process.argv[3]))' "$GL" "$1" "$(native "$2")"; }
[ "$(gl "$RAW" "$T/w")" = "MECHANISM CHECK" ] && ok "(1) gate-label: the label behind the sentence" || bad "(1) gate-label with sentence: '$(gl "$RAW" "$T/w")'"
[ "$(gl "$RAW" "$T/none")" = "a hook" ] && ok "(1) control: without the brain's sentences the first line stays (one source)" || bad "(1) gate-label control: '$(gl "$RAW" "$T/none")'"
RAWB="PreToolUse:Bash hook error: [node \"x/content-review-gate.cjs\"]: $(printf '%s\nBLOCKED (content-review-gate): risk' "$S1")"
[ "$(gl "$RAWB" "$T/w")" = "content-review-gate" ] && ok "(1) gate-label: the guard form behind a [node] tag and the sentence" || bad "(1) guard form: '$(gl "$RAWB" "$T/w")'"
ghl() { "$PY" -c 'import importlib.util,sys
s=importlib.util.spec_from_file_location("gh",sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
m.SENTENCES=m.operator_sentences(sys.argv[3]);print(m.label_of(sys.argv[2]))' "$GH" "$1" "$(native "$2")"; }
[ "$(ghl "$RAW" "$T/w")" = "MECHANISM CHECK" ] && ok "(1) gate-health: the label behind the sentence" || bad "(1) gate-health with sentence: '$(ghl "$RAW" "$T/w")'"
[ "$(ghl "$RAW" "$T/none")" = "a hook" ] && ok "(1) control: gate-health without the brain's sentences" || bad "(1) gate-health control: '$(ghl "$RAW" "$T/none")'"
[ "$(ghl "$RAW" "$T/bom")" = "MECHANISM CHECK" ] && ok "(1)+(4) gate-health reads the BOM file too" || bad "(1) gate-health BOM: '$(ghl "$RAW" "$T/bom")'"
# (5) the table was edited or translated after the hold was written (Windows re-review of #683, 2026-11-27): the old
# sentence no longer matches the table; the readers strip it structurally, both ways, also for two leading sentences
mkdir -p "$T/ed/.claude/rules"
printf '{"lines":{"MECHANISM CHECK":"Held: this step has a set way, reworded.","STOPPEN-GATE":"Held: ask through the question tool, reworded."}}\n' > "$T/ed/.claude/rules/operator-lines.json"
[ "$(gl "$RAW" "$T/ed")" = "MECHANISM CHECK" ] && ok "(5) gate-label: an old sentence after a table edit is still taken off" || bad "(5) gate-label edited table: '$(gl "$RAW" "$T/ed")'"
[ "$(ghl "$RAW" "$T/ed")" = "MECHANISM CHECK" ] && ok "(5) gate-health: an old sentence after a table edit is still taken off" || bad "(5) gate-health edited table: '$(ghl "$RAW" "$T/ed")'"
RAW2="PreToolUse:Bash hook error: $(printf '%s\n%s\r\nMECHANISM CHECK (agent-brain): a heredoc' "$S2" "$S1")"
[ "$(gl "$RAW2" "$T/ed")" = "MECHANISM CHECK" ] && ok "(5) gate-label: two old sentences (CRLF) are taken off" || bad "(5) gate-label two old: '$(gl "$RAW2" "$T/ed")'"
[ "$(ghl "$RAW2" "$T/ed")" = "MECHANISM CHECK" ] && ok "(5) gate-health: two old sentences (CRLF) are taken off" || bad "(5) gate-health two old: '$(ghl "$RAW2" "$T/ed")'"
RAWT="PreToolUse:Bash hook error: [node \"x/content-review-gate.cjs\"]: $(printf '%s\nBLOCKED (content-review-gate): risk' "$S1")"
[ "$(gl "$RAWT" "$T/ed")" = "content-review-gate" ] && ok "(5) gate-label: the guard form behind a [node] tag and an old sentence" || bad "(5) guard form edited: '$(gl "$RAWT" "$T/ed")'"
# controls: a refusal with no label anywhere stays 'a hook'; a label deeper than three lines is not reached
NOL="PreToolUse:Bash hook error: $(printf '%s\nno label here\nnor here' "$S1")"
[ "$(gl "$NOL" "$T/ed")" = "a hook" ] && ok "(5) control: no label in any line stays 'a hook'" || bad "(5) control no label: '$(gl "$NOL" "$T/ed")'"
[ "$(ghl "$NOL" "$T/ed")" = "a hook" ] && ok "(5) control: gate-health, no label in any line" || bad "(5) gate-health control no label: '$(ghl "$NOL" "$T/ed")'"
DEEP="PreToolUse:Bash hook error: $(printf 'a\nb\nc\nd\nMECHANISM CHECK (agent-brain): x')"
[ "$(gl "$DEEP" "$T/ed")" = "a hook" ] && ok "(5) control: a label below three leading lines is not taken" || bad "(5) control deep: '$(gl "$DEEP" "$T/ed")'"

echo
[ "$fail" -eq 0 ] && echo "operator-lead fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
