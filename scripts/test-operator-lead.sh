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

echo
[ "$fail" -eq 0 ] && echo "operator-lead fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
