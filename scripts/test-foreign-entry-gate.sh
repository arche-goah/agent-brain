#!/usr/bin/env bash
# covers: foreign-entry-gate
# Fixture for helpers/foreign-entry-gate.cjs - both directions, plus inert without data.
# Usage: bash scripts/test-foreign-entry-gate.sh   (exit 0 = all pass)
set -u
G="$(cd "$(dirname "$0")/../helpers" && pwd)/foreign-entry-gate.cjs"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# OS-3/OS-19: node opens these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }

R="$T/repo"
mkdir -p "$R/docs/maintenance" "$R/.claude/rules"
printf '%s\n' '{"files": ["docs/maintenance/carrier-register.md", "docs/maintenance/session-log.md"], "id_pattern": "^id:\\s*(\\S+)", "file_patterns": {"docs/maintenance/session-log.md": "\\b(?:[Ss]ession|[Mm]ain session \\S+) \\(?([0-9a-f]{8})\\b"}}' > "$R/.claude/rules/foreign-entry.json"
git -C "$R" init -q
git -C "$R" config user.name t
git -C "$R" config user.email t@t
printf '# register\n\n## old\nid: old-entry\n' > "$R/docs/maintenance/carrier-register.md"
git -C "$R" add -A
git -C "$R" commit -q -m init
printf '\n## mine\nid: my-entry\n\n## theirs\nid: their-entry\n' >> "$R/docs/maintenance/carrier-register.md"

OWN="$T/own.jsonl"; ALL="$T/all.jsonl"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"printf id: my-entry >> docs/maintenance/carrier-register.md"}}]}}' > "$OWN"
cp "$OWN" "$ALL"
printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"text","text":"their-entry seen"}]}}' >> "$ALL"

run() { # $1 transcript $2 command
  printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"transcript_path":"%s","cwd":"%s"}' "$2" "$(native "$1")" "$(native "$R")" | CLAUDE_PROJECT_DIR="$(native "$R")" node "$G"
}
C='git commit -F msg -- docs/maintenance/carrier-register.md'

out="$(run "$OWN" "$C")"
case "$out" in *"FOREIGN-ENTRY"*"their-entry"*) ok "a foreign id blocks and is named";; *) bad "foreign id not blocked: '$out'";; esac
case "$out" in *"my-entry"*) bad "own id named as foreign";; *) ok "the own id is not named";; esac

out="$(run "$ALL" "$C")"
[ -z "$out" ] && ok "every added id seen in the transcript passes" || bad "seen ids blocked: '$out'"

out="$(run "$OWN" "$C # FOREIGN-ENTRY-OK: owner asked")"
[ -z "$out" ] && ok "the escape passes" || bad "escape blocked: '$out'"

out="$(run "$OWN" "git commit -F msg -- docs/other.md")"
[ -z "$out" ] && ok "a commit not naming the watched file passes" || bad "unrelated commit blocked: '$out'"

# session log: a line naming another session's id is foreign (2026-11-05: a close commit carried the main session's lines)
printf '# log\n' > "$R/docs/maintenance/session-log.md"
git -C "$R" add docs/maintenance/session-log.md; git -C "$R" commit -q -m log -- docs/maintenance/session-log.md
printf '  Session aaaa1111 (mine): done\n  Main session brain-ef (bbbb2222, other): done\n' >> "$R/docs/maintenance/session-log.md"
LOGOWN="$T/logown.jsonl"
printf '%s\n' '{"sessionId":"aaaa1111-x","message":{"role":"assistant","content":[{"type":"text","text":"x"}]}}' > "$LOGOWN"
out="$(run "$LOGOWN" 'git commit -m close -- docs/maintenance/session-log.md')"
case "$out" in *"bbbb2222"*) ok "a session-log line of another session blocks and is named";; *) bad "foreign session line not blocked: '$out'";; esac
case "$out" in *"aaaa1111"*) bad "own session id named as foreign";; *) ok "the own session's line is not named";; esac

# no data file: inert (a brain that has not named its append files)
rm -f "$R/.claude/rules/foreign-entry.json"
out="$(run "$OWN" "$C")"
[ -z "$out" ] && ok "without foreign-entry.json the gate is inert" || bad "inert case blocked: '$out'"

[ "$fail" -eq 0 ] && echo "foreign-entry-gate: all fixtures pass" || { echo "foreign-entry-gate: FAILURES"; exit 1; }
