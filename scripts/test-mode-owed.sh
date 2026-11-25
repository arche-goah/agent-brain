#!/usr/bin/env bash
# covers: mode-owed autonomous-gate
# Fixture for helpers/mode-owed.cjs (2026-11-23: an operator asked what was open in an autonomous run; three question
# rounds, about 40 work calls between them, the mode question never asked).
# Must hold: after an answered round in a dialog the operator opened, the 4th non-reading call is held once (through
# autonomous-gate, no extra process); a turn end with the mode question owed is held once.
# Must pass: the question tool and reads, the first 3 calls, the re-issue, a mode question clears the debt, a round
# answered in a dialog the operator did NOT open (no "what is open" prompt) owes nothing.
# Usage: bash scripts/test-mode-owed.sh   (exit 0 = pass)
set -u
# The mode is set by its words here (the latch before the mode-confirm answer); the confirmation: test-mode-confirm.sh.
export MODE_READING=words
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
MO="$(native "$_D/../helpers/mode-owed.cjs")"
AG="$(native "$_D/../helpers/autonomous-gate.cjs")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":%s}}\n' "$2" "$(js "$1")"; }
B="$(native "$T/brain")"; mkdir -p "$T/brain/.claude"
export CLAUDE_PROJECT_DIR="$B" HOME="$(native "$T/home")" USERPROFILE="$(native "$T/home")"
TP="$(native "$T/t.jsonl")"
{ user "work through them on your own, autonomously" 2026-11-23T10:00:00Z; user "what is open for me?" 2026-11-23T10:05:00Z; } > "$T/t.jsonl"
ev() { # $1 tool, $2 extra json fields -> hook input on stdin of $3 (script) with arg $4
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s","tool_name":"%s"%s}' "$TP" "$B" "$1" "${2:-}"; }
Q='"tool_use_id":"q1","tool_input":{"questions":[{"question":"Which shop for the filament?","options":[]}]}'
QM='"tool_use_id":"q2","tool_input":{"questions":[{"question":"Continue autonomously?","options":[]}]}'

ev AskUserQuestion ",$Q" | node "$MO" post
grep -q '"owed":true' "$T/brain/.claude-state/mode-owed.json" 2>/dev/null && ok "an answered round in a dialog the operator opened owes the mode question" || bad "debt not recorded"
held=0; for t in Read Grep Bash Edit Bash Write; do out=$(ev "$t" ',"tool_input":{"command":"x","file_path":"/x"}' | node "$AG"); case "$out" in *MODE-OWED*) held=$((held+1)); echo "    held at $t";; esac; done
[ "$held" = 1 ] && ok "reads pass uncounted, the 4th other call is held once" || bad "holds: $held"
out=$(ev Bash ',"tool_input":{"command":"y"}' | node "$AG"); case "$out" in *MODE-OWED*) bad "held twice in one round";; *) ok "the re-issue passes";; esac
out=$(ev AskUserQuestion ",$Q" | node "$AG"); case "$out" in *MODE-OWED*) bad "the question tool was held";; *) ok "the question tool passes";; esac
out=$(printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s","stop_hook_active":false}' "$TP" "$B" | node "$MO" stop)
case "$out" in *MODE-OWED*) ok "a turn end with the mode question owed is held";; *) bad "turn end not held: '$out'";; esac
out=$(printf '{"session_id":"s1","transcript_path":"%s","cwd":"%s","stop_hook_active":false}' "$TP" "$B" | node "$MO" stop)
[ -z "$out" ] && ok "the turn end is held once per round" || bad "turn end held twice"
ev AskUserQuestion ",$QM" | node "$MO" post
grep -q '"s1"' "$T/brain/.claude-state/mode-owed.json" && bad "the mode question did not clear the debt" || ok "asking the mode question clears the debt"
# a dialog the operator did not open: no "what is open" prompt
user "fix the readme" 2026-11-23T11:00:00Z > "$T/t2.jsonl"
printf '{"session_id":"s2","transcript_path":"%s","cwd":"%s","tool_name":"AskUserQuestion",%s}' "$(native "$T/t2.jsonl")" "$B" "$Q" | node "$MO" post
grep -q '"s2"' "$T/brain/.claude-state/mode-owed.json" && bad "a round outside an opened dialog owed the mode question" || ok "no opened dialog, nothing owed"
# Negative control: autonomous-gate without the mode-owed call does not hold (the incident: 40 work calls ran on)
sed '/mode-owed.cjs/d' "$_D/../helpers/autonomous-gate.cjs" > "$T/brain/ag-mutant.cjs"; cp "$_D/../helpers/"*.cjs "$T/brain/" 2>/dev/null; cp "$T/brain/ag-mutant.cjs" "$T/brain/autonomous-gate.cjs"
cp "$_D/../session-areas.json" "$T/" 2>/dev/null || true
ev AskUserQuestion ",$Q" | node "$MO" post
held=0; for t in Bash Bash Bash Bash Bash; do out=$(ev "$t" ',"tool_input":{"command":"x"}' | node "$(native "$T/brain/autonomous-gate.cjs")"); case "$out" in *MODE-OWED*) held=$((held+1));; esac; done
[ "$held" = 0 ] && ok "control: without the call the work runs on unheld (the incident)" || bad "control held $held"
[ "$fail" = 0 ] && echo "test-mode-owed: all checks passed" || { echo "test-mode-owed: FAILED"; exit 1; }
