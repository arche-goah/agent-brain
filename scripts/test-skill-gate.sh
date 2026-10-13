#!/usr/bin/env bash
# covers: skill-gate
#
# Fixture test for helpers/skill-gate.cjs — both directions. Every must-block case is also
# run against an always-allow stub and must come back "allow" there (negative control: the
# case discriminates instead of passing for an unrelated reason).
#
# Usage: bash scripts/test-skill-gate.sh [gate.cjs]   (exit 0 = all fixtures pass)
set -u

native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
if [ $# -ge 1 ]; then GATE="$1"; else
  GATE=$(resolve helpers/skill-gate.cjs) || { echo "  --  skill-gate not in this layout"; exit 0; }
fi
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
NT=$(native "$T")
fail=0
must_block=0
flipped=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

STUB="$T/always-allow.cjs"
printf '%s\n' "process.stdin.resume(); process.stdin.on('end', () => process.exit(0));" > "$STUB"

# --- layout: a project, a fake HOME with one enabled and one disabled plugin ---
P="$T/proj"; H="$T/fakehome"
mkdir -p "$P/.claude/skills/local-skill" "$P/.claude/rules" "$P/.claude-state" \
         "$H/.claude/plugins/cache/mk/tdp/1.0/skills/td-core" \
         "$H/.claude/plugins/cache/mk/tdp/1.0/skills/td-plain" \
         "$H/.claude/plugins/cache/mk/offp/1.0/skills/off-skill"
cat > "$H/.claude/plugins/cache/mk/tdp/1.0/skills/td-core/SKILL.md" <<'EOF'
---
name: td-core
description: Core rules for the td tool.
metadata:
  load-before-tools: "^mcp__td(-\\d+)?__"
---
body
EOF
printf -- '---\nname: td-plain\ndescription: no gate here\n---\nbody\n' > "$H/.claude/plugins/cache/mk/tdp/1.0/skills/td-plain/SKILL.md"
printf -- '---\nname: off-skill\ndescription: x\nmetadata:\n  load-before-tools: "^Bash$"\n---\n' > "$H/.claude/plugins/cache/mk/offp/1.0/skills/off-skill/SKILL.md"
cat > "$P/.claude/skills/local-skill/SKILL.md" <<'EOF'
---
name: local-skill
description: local, gated on python edits
metadata:
  load-before-tools: '^(Edit|Write)$'
  load-before-paths: '\.py$'
---
EOF
cat > "$H/.claude/plugins/installed_plugins.json" <<EOF
{"version":2,"plugins":{
 "tdp@mk":[{"scope":"project","projectPath":"$NT/proj","installPath":"$NT/fakehome/.claude/plugins/cache/mk/tdp/1.0"}],
 "offp@mk":[{"scope":"user","installPath":"$NT/fakehome/.claude/plugins/cache/mk/offp/1.0"}]}}
EOF
printf '{"enabledPlugins":{"tdp@mk":true,"offp@mk":true}}\n' > "$P/.claude/settings.json"
printf '{"enabledPlugins":{"offp@mk":false}}\n' > "$P/.claude/settings.local.json"
printf '{"rules":[{"skills":["core:lazy"],"tools":"^NotebookEdit$"}]}\n' > "$P/.claude/rules/skill-gate.json"

# --- transcripts ---
skillcall() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}\n' "$1"; }
readcall()  { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s"}}]}}\n' "$1"; }
: > "$T/empty.jsonl"
skillcall "tdp:td-core" > "$T/loaded-qualified.jsonl"
skillcall "td-core" > "$T/loaded-bare.jsonl"
printf '{"type":"user","message":{"role":"user","content":"<command-name>/tdp:td-core</command-name>"}}\n' > "$T/loaded-slash.jsonl"
readcall "$NT/fakehome/.claude/plugins/cache/mk/tdp/1.0/skills/td-core/SKILL.md" > "$T/loaded-read.jsonl"
skillcall "tdp:td-plain" > "$T/loaded-other.jsonl"
skillcall "local-skill" > "$T/loaded-local.jsonl"

run() { # engine tool transcript [file_path]
  local inp
  inp=$(printf '{"tool_name":"%s","tool_input":{"file_path":"%s"},"transcript_path":"%s"}' "$2" "${4:-}" "$(native "$T/$3")")
  printf '%s' "$inp" | CLAUDE_PROJECT_DIR="$NT/proj" SKILL_GATE_HOME="$NT/fakehome" node "$1" 2>/dev/null \
    | grep -aq '"permissionDecision":"deny"' && echo block || echo allow
}
expect() { # want tool transcript [file_path] -- label
  local want=$1 tool=$2 tr=$3 fp=$4 label=$5 got
  got=$(run "$GATE" "$tool" "$tr" "$fp")
  [ "$got" = "$want" ] && ok "$label" || bad "$label (want $want, got $got)"
  if [ "$want" = block ]; then
    must_block=$((must_block + 1))
    [ "$(run "$STUB" "$tool" "$tr" "$fp")" = allow ] && flipped=$((flipped + 1))
  fi
}

expect block mcp__td__create_node   empty.jsonl            "" "frontmatter gate: TD tool before the skill is loaded"
expect block mcp__td-2__get_info    empty.jsonl            "" "regex covers the second instance"
expect block mcp__td__create_node   loaded-other.jsonl     "" "a different skill of the same plugin does not count"
expect allow mcp__td__create_node   loaded-qualified.jsonl "" "Skill call, qualified name"
expect allow mcp__td__create_node   loaded-bare.jsonl      "" "Skill call, bare name"
expect allow mcp__td__create_node   loaded-slash.jsonl     "" "slash command"
expect allow mcp__td__create_node   loaded-read.jsonl      "" "Read of the SKILL.md (agent without Skill tool)"
expect allow mcp__other__x          empty.jsonl            "" "undeclared tool stays silent"
expect allow Bash                   empty.jsonl            "" "plugin disabled in a higher settings layer is not read"
expect block Edit                   empty.jsonl "$NT/proj/a.py" "project skill with a path filter: .py edit blocks"
expect allow Edit                   empty.jsonl "$NT/proj/a.md" "path filter: .md edit stays silent"
expect allow Edit                   loaded-local.jsonl "$NT/proj/a.py" "project skill loaded"
expect block NotebookEdit           empty.jsonl            "" "instance rule from skill-gate.json"
expect allow Skill                  empty.jsonl            "" "the Skill tool itself is never gated"
# fail-open: no transcript on disk
got=$(printf '{"tool_name":"mcp__td__x","tool_input":{},"transcript_path":"%s"}' "$NT/missing.jsonl" \
  | CLAUDE_PROJECT_DIR="$NT/proj" SKILL_GATE_HOME="$NT/fakehome" node "$GATE" | grep -ac deny)
[ "$got" = 0 ] && ok "fail-open without a transcript" || bad "fail-open without a transcript"

[ "$flipped" = "$must_block" ] && ok "negative control: all $must_block blocking cases allow under the stub" \
  || bad "negative control: only $flipped of $must_block blocking cases flip under the stub"
[ $fail = 0 ] && echo "skill-gate: all fixtures pass" || echo "skill-gate: FAILURES"
exit $fail
