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
probe "a status question mid-run keeps the mode: no question tool" AskUserQuestion '{"questions":[]}' "$STAT" block
probe "push naming main (ask glob)" Bash '{"command":"git -C /r push -q origin main"}' "$AUTO" block
probe "branch-less push (no ask rule)" Bash '{"command":"git -C /r push"}' "$AUTO" allow
probe "gh pr close (ask prefix)" Bash '{"command":"gh pr close 5 -R o/r"}' "$AUTO" block
probe "a plain edit outside every ask rule" Edit '{"file_path":"docs/notes.md"}' "$AUTO" allow
probe "a bare tool rule from the user settings" WebFetch '{"url":"https://example.com"}' "$AUTO" block
probe "a tool no rule names" Read '{"file_path":"README.md"}' "$AUTO" allow
probe "a mid-turn operator message ends the mode: the asked-for question passes" AskUserQuestion '{"questions":[]}' "$MID" allow
probe "a queued message from another origin keeps the mode (control)" AskUserQuestion '{"questions":[]}' "$PEER" block

[ "$fail" = 0 ] && echo "autonomous-gate: all cases pass" || { echo "autonomous-gate: FAILURES"; exit 1; }
