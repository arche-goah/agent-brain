#!/usr/bin/env bash
# covers: session-areas
# Fixture for helpers/session-areas.cjs — both directions.
# Must speak: two live sessions editing the same project folder (the incident 2026-11-08) get an
# OVERLAP line, once; a write into a peer's claim is named; the operator's prompt about other
# sessions injects the map; a commit with a pathspec records its folder.
# Must stay silent: different folders, a commit without paths (repo root — every session commits
# in the brain), a prompt about something else, a peer whose pid is gone (its record is deleted).
# Negative control: the session list without this helper (pid + cwd only) names no area at all.
# Usage: bash scripts/test-session-areas.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
G="$(native "$_D/../helpers/session-areas.cjs")"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
has() { case "$2" in *"$3"*) ok "$1";; *) bad "$1: '${2:0:240}'";; esac; }
lacks() { case "$2" in *"$3"*) bad "$1: '${2:0:240}'";; *) ok "$1";; esac; }

B="$(native "$T/brain")"; P="$(native "$T/proj")"; CFG="$(native "$T/cfg")"
mkdir -p "$T/brain/.git" "$T/proj/.git" "$T/proj/hardware/node-board" "$T/proj/firmware" "$T/cfg/sessions"
printf '{"pid":101,"sessionId":"s-a","cwd":"%s","name":"brain-aa","status":"busy"}' "$B" > "$T/cfg/sessions/101.json"
printf '{"pid":102,"sessionId":"s-b","cwd":"%s","name":"brain-bb","status":"idle"}' "$B" > "$T/cfg/sessions/102.json"
export CLAUDE_CONFIG_DIR="$CFG" CLAUDE_PROJECT_DIR="$B" SESSION_AREAS_ALIVE="101,102"

edit() { # $1 session, $2 file -> hook stdout
  printf '{"session_id":"%s","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$B" "$2" | node "$G" record 2>&1
}
bashc() { # $1 session, $2 command
  node -e 'process.stdout.write(JSON.stringify({session_id:process.argv[1],cwd:process.argv[2],tool_name:"Bash",tool_input:{command:process.argv[3]}}))' "$1" "$B" "$2" | node "$G" record 2>&1
}
ask() { # $1 session, $2 prompt
  node -e 'process.stdout.write(JSON.stringify({session_id:process.argv[1],cwd:process.argv[2],prompt:process.argv[3]}))' "$1" "$B" "$2" | node "$G" prompt 2>&1
}

out=$(edit s-a "$P/firmware/main.c"); [ -z "$out" ] && ok "a first write alone is silent" || bad "first write: '$out'"
out=$(edit s-b "$P/hardware/node-board/board.kicad_pcb"); [ -z "$out" ] && ok "a write in another folder is silent" || bad "other folder: '$out'"
out=$(edit s-a "$P/hardware/node-board/board.kicad_sch")
has "the incident: both sessions in the same project folder -> OVERLAP" "$out" "OVERLAP: brain-aa and brain-bb"
has "the overlap names the folder" "$out" "hardware/node-board"
has "the overlap says how to coordinate" "$out" "SendMessage to brain-bb"
has "the overlap names the claim command where this file sits" "$out" "session-areas.cjs claim <path>"
has "the hook answers as PostToolUse additionalContext" "$out" '"hookEventName":"PostToolUse"'
out=$(edit s-a "$P/hardware/node-board/board.kicad_sch"); [ -z "$out" ] && ok "the same overlap is told once" || bad "told twice: '$out'"

out=$(bashc s-b "git -C $P commit -m x")
has "the other session hears the same overlap at its next write" "$out" "OVERLAP: brain-bb and brain-aa"
lacks "a commit without paths (repo root) is itself no overlap" "$out" "$(basename "$P")."
out=$(bashc s-a "git -C $P commit -m z"); [ -z "$out" ] && ok "two commits without paths in one repo stay silent" || bad "repo root: '$out'"
out=$(CLAUDE_CODE_SESSION_ID= node "$G" overlaps)
has "without a session of its own (a watch) every pair's overlap is listed" "$out" "hardware/node-board"
[ "$(grep -c '^OVERLAP:' <<<"$out")" = 1 ] && ok "each pair's overlap once" || bad "pair count: '$out'"
out=$(CLAUDE_CODE_SESSION_ID= node "$G" show)
lacks "without a session of its own there is no phantom row" "$out" "(this session)"
out=$(node "$G" show --session s-b)
has "the map lists every live session with its areas" "$out" "brain-aa pid 101 busy: writes"
has "the map marks this session" "$out" "brain-bb (this session)"
has "a commit without paths shows as repo-level area" "$out" "$(basename "$P") ("

out=$(node "$G" claim "$P/firmware" --note "firmware rework" --session s-b)
has "a claim is written and shown" "$out" '"firmware rework"'
out=$(edit s-a "$P/firmware/main.c")
has "a write into a peer's claim is named" "$out" "claimed by brain-bb (firmware rework)"
out=$(node "$G" release --session s-b)
lacks "release drops the claim" "$out" "firmware rework"

bashc s-b "git add -A && git -C $P commit -m y -- firmware/main.c" >/dev/null
out=$(node "$G" show --session s-b)
has "a commit with a pathspec records its folder" "$out" "proj/firmware ("

out=$(ask s-b "check what the other session is doing")
has "the operator's prompt about other sessions injects the map" "$out" "<session-map>"
has "the injected map names the peer" "$out" "brain-aa"
out=$(ask s-b "fix the readme"); [ -z "$out" ] && ok "a prompt about something else stays silent" || bad "silent prompt: '${out:0:120}'"
mkdir -p "$T/brain/.claude/rules"
printf '{"triggers":["andere session"]}' > "$T/brain/.claude/rules/session-areas.json"
out=$(ask s-b "was macht die andere session?"); has "the instance adds its own language" "$out" "<session-map>"

SESSION_AREAS_ALIVE="102" node "$G" show --session s-b >/dev/null
[ ! -f "$T/brain/.claude-state/session-areas/s-a.json" ] && ok "a dead peer's record is deleted" || bad "dead record kept"
out=$(SESSION_AREAS_ALIVE="102" node "$G" show --session s-b --peers-only); [ -z "$out" ] && ok "no live peer: --peers-only is silent" || bad "peers-only: '$out'"

# Negative control: what the session list knew before this helper — pid and cwd per session, never an area.
ctl=$(for f in "$T"/cfg/sessions/*.json; do node -e 'const r=require(process.argv[1]);console.log(`claude-session pid=${r.pid} cwd=${r.cwd}`)' "$(native "$f")"; done)
lacks "control: pid + cwd lines name no area — the incident stays invisible without the helper" "$ctl" "node-board"
# Control: the same two sessions without the PostToolUse record — the map knows them, but no area and no overlap.
B2="$(native "$T/brain2")"; mkdir -p "$T/brain2/.git"
printf '{"pid":201,"sessionId":"s-c","cwd":"%s","name":"brain-cc","status":"busy"}' "$B2" > "$T/cfg/sessions/201.json"
out=$(CLAUDE_PROJECT_DIR="$B2" SESSION_AREAS_ALIVE="201" node "$G" show --session s-x)
has "control: without recorded writes the map says so" "$out" "nothing recorded yet"
lacks "control: without recorded writes there is no OVERLAP" "$out" "OVERLAP"

[ "$fail" = 0 ] && echo "test-session-areas: all checks passed" || { echo "test-session-areas: FAILED"; exit 1; }
