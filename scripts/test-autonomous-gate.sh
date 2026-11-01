#!/usr/bin/env bash
# covers: autonomous-gate
# Fixture for helpers/autonomous-gate.cjs - both directions.
# The must-block case is the incident (2026-10-26, Windows instance): in an autonomous run an edit
# of .claude/settings.json (an ask rule) raised a dialog, and the operator had to answer it.
# Usage: bash scripts/test-autonomous-gate.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/autonomous-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }

B="$T/brain"; mkdir -p "$B/.claude" "$T/userdir"
printf '%s\n' '{"permissions":{"ask":["Edit(.claude/settings.json)","Bash(git -C * push * main*)","Bash(gh pr close*)"]}}' > "$B/.claude/settings.json"
printf '%s\n' '{"permissions":{"ask":["WebFetch"]}}' > "$T/userdir/settings.json"
AUTO="$T/auto.jsonl"; user "work through the open points autonomously" > "$AUTO"
INTER="$T/inter.jsonl"; { user "work through the open points autonomously"; user "back to normal mode"; } > "$INTER"
STAT="$T/stat.jsonl"; { user "work through the open points autonomously"; user "status?"; } > "$STAT"
# A message typed mid-turn is a queued_command attachment, not a user record (macOS finding on #142).
queued() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"%s"}}}\n' "$(js "$1")" "${2-human}"; }
MID="$T/mid.jsonl"; { user "work through the open points autonomously"; queued "put the open decisions to me now"; } > "$MID"
PEER="$T/peer.jsonl"; { user "work through the open points autonomously"; queued "a note from another session" peer; } > "$PEER"

probe() { # $1 label, $2 tool, $3 tool_input JSON, $4 transcript, $5 block|allow
  local out
  out=$(printf '{"tool_name":"%s","tool_input":%s,"transcript_path":"%s","cwd":"%s"}' "$2" "$3" "$(native "$4")" "$(native "$B")" \
        | CLAUDE_PROJECT_DIR="$(native "$B")" CLAUDE_CONFIG_DIR="$(native "$T/userdir")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"permissionDecision":"deny"'*) [ "$5" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$5" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}
SET="$(js "$(native "$B")/.claude/settings.json")"

probe "the incident: settings edit in an autonomous run" Edit "{\"file_path\":$SET}" "$AUTO" block
probe "same edit, relative path" Edit '{"file_path":".claude/settings.json"}' "$AUTO" block
probe "same edit, not autonomous (the operator is there)" Edit "{\"file_path\":$SET}" "$INTER" allow
probe "question tool in an autonomous run" AskUserQuestion '{"questions":[]}' "$AUTO" block
probe "question tool, not autonomous" AskUserQuestion '{"questions":[]}' "$INTER" allow
# The gate's own words are locked inside the run (2026-10-28: a refused question was made to pass by widening them).
probe "edit of the ask patterns in an autonomous run" Edit '{"file_path":".claude/rules/open-items.json"}' "$AUTO" block
probe "write of the on/off words in an autonomous run" Write '{"file_path":".claude/rules/autonomous-patterns.json"}' "$AUTO" block
probe "edit of the ask patterns in the conversation" Edit '{"file_path":".claude/rules/open-items.json"}' "$INTER" allow
probe "edit of another rules file in an autonomous run" Edit '{"file_path":".claude/rules/ledgers.json"}' "$AUTO" allow
probe "a status question mid-run keeps the mode: no question tool" AskUserQuestion '{"questions":[]}' "$STAT" block
probe "push naming main (ask glob)" Bash '{"command":"git -C /r push -q origin main"}' "$AUTO" block
probe "branch-less push (no ask rule)" Bash '{"command":"git -C /r push"}' "$AUTO" allow
probe "gh pr close (ask prefix)" Bash '{"command":"gh pr close 5 -R o/r"}' "$AUTO" block
probe "a plain edit outside every ask rule" Edit '{"file_path":"docs/notes.md"}' "$AUTO" allow
# Hook data the classifier holds without an ask rule (macOS measurement 2026-10-26).
probe "stop-checks.json, no ask rule, autonomous" Edit '{"file_path":".claude/rules/stop-checks.json"}' "$AUTO" block
probe "plugin hooks.json, autonomous" Write '{"file_path":"hooks/hooks.json"}' "$AUTO" block
probe "stop-checks.json outside the mode" Edit '{"file_path":".claude/rules/stop-checks.json"}' "$INTER" allow
probe "local-machinery.json is not held (control)" Edit '{"file_path":".claude/rules/local-machinery.json"}' "$AUTO" allow
probe "a bare tool rule from the user settings" WebFetch '{"url":"https://example.com"}' "$AUTO" block
probe "a tool no rule names" Read '{"file_path":"README.md"}' "$AUTO" allow
probe "a mid-turn operator message ends the mode: the asked-for question passes" AskUserQuestion '{"questions":[]}' "$MID" allow
probe "a queued message from another origin keeps the mode (control)" AskUserQuestion '{"questions":[]}' "$PEER" block
# The way out stays open (2026-11-01, macOS instance): the operator's "continue interactively" matched no
# off-pattern and the lock refused the edit that would have taught it. An added pattern passes only when it
# matches an operator prompt of this session and nothing else changes.
mkdir -p "$B/.claude/rules"
printf '%s\n' '{"_note":"x","on_patterns":[],"off_patterns":["\\bbye\\b"]}' > "$B/.claude/rules/autonomous-patterns.json"
printf '%s\n' '{"ask_patterns":[]}' > "$B/.claude/rules/open-items.json"
STUCK="$T/stuck.jsonl"; { user "work through the open points autonomously"; user "carry on interactively, if you need anything"; } > "$STUCK"
probe "the stuck run is still autonomous (precondition)" AskUserQuestion '{"questions":[]}' "$STUCK" block
AP='.claude/rules/autonomous-patterns.json'
probe "adding the operator's own off-words passes" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"carry on interactively\\\"]\"}" "$STUCK" allow
probe "an off-word that also matches the order which switched the run on stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"\\\\\\\\bpoints\\\\\\\\b\\\"]\"}" "$STUCK" block
probe "an off-word plus a changed on-list stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"on_patterns\\\":[],\\\"off_patterns\\\":[\\\"\\\\\\\\bbye\\\\\\\\b\\\"]\",\"new_string\":\"\\\"on_patterns\\\":[\\\"go\\\"],\\\"off_patterns\\\":[\\\"\\\\\\\\bbye\\\\\\\\b\\\",\\\"carry on interactively\\\"]\"}" "$STUCK" block
probe "removing an off-word stays held" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"\\\\\\\\bbye\\\\\\\\b\\\"\",\"new_string\":\"\\\"carry on interactively\\\"\"}" "$STUCK" block
probe "the 2026-10-28 incident: an ask-pattern no prompt carries stays held" Edit '{"file_path":".claude/rules/open-items.json","old_string":"[]","new_string":"[\"\\\\bzebra\\\\b\"]"}' "$STUCK" block
probe "a note-only edit is no way out (held)" Edit "{\"file_path\":\"$AP\",\"old_string\":\"\\\"x\\\"\",\"new_string\":\"\\\"y\\\"\"}" "$STUCK" block

[ "$fail" = 0 ] && echo "autonomous-gate: all cases pass" || { echo "autonomous-gate: FAILURES"; exit 1; }
