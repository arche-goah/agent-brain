#!/usr/bin/env bash
# Fixture for scripts/autonomy-diagnose.py: a planted brain (every section has something to
# find) and a clean one (negative control). Paths reach python only as ARGUMENTS, which Git Bash
# converts; the memory dir is derived from the path python sees, so the fixture builds the slug
# from the same native form (OS-3, docs/os-traps.md).
# Usage: bash scripts/test-autonomy-diagnose.sh   (exit 0 = all pass)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
D="$here/autonomy-diagnose.py"
PY="$(command -v python3 || command -v python)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
slug() { native "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
expect() { # $1 name, $2 file, $3 must|mustnot, $4 fixed string
  if grep -qF -- "$4" "$2"; then found=1; else found=0; fi
  if { [ "$3" = must ] && [ $found = 1 ]; } || { [ "$3" = mustnot ] && [ $found = 0 ]; }; then
    echo "  OK   $1"
  else
    echo "  FAIL $1: expected $3 '$4'"; fail=1
  fi
}

# --- planted brain
B="$T/brain"; H="$T/home"
mkdir -p "$B/.claude/rules" "$B/core/rules" "$H/.claude"
M="$H/.claude/projects/$(slug "$B")/memory"; mkdir -p "$M"
printf '# Brain\n\n- Kommentare und Push muessen immer Nutzer-Eingabe sein.\n\n@core/rules/working-rules.md\n' > "$B/CLAUDE.md"
printf 'The comparative test lives here.\n' > "$B/core/rules/intelligence.md"
printf '## Regeln\n\nVor jedem Schritt immer den Nutzer fragen.\nPush nur nach explizitem OK.\n' > "$B/.claude/rules/feedback.md"
printf 'One ordered procedure: ASK OR ACT.\n' > "$B/core/rules/working-rules.md"
for i in $(seq 1 210); do echo "- [m$i](m$i.md) — entry $i"; done > "$M/MEMORY.md"
printf 'Message Center was tested on 2026-10-10.\n' > "$M/desk.md"
printf '## Push\n\nNie selbst pushen, token: ghp_abcdefghijklmnopqrstuvwxyz0123456789 steht hier.\n' > "$B/.claude/rules/secret.md"
cat > "$B/.claude/settings.json" <<'JSON'
{"permissions": {"allow": ["Bash(git push:*)", "Bash(node core/helpers/*)"], "ask": ["Bash(gh pr merge:*)"], "deny": ["Bash(gh pr review *)"]},
 "hooks": {"Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "node \"$CLAUDE_PROJECT_DIR/core/helpers/stop-dispatcher.cjs\""}]}],
           "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "node scripts/my-guard.cjs"}]}]}}
JSON
mkdir -p "$B/core/templates"
printf '{"permissions": {"ask": ["Bash(git push*)"], "allow": ["Bash(node core/helpers/*)"]}}\n' > "$B/core/templates/settings.json"
R="$T/planted.md"
env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$B" --home "$H" > "$R"
expect "core marker present"            "$R" must '- present: "ASK OR ACT"'
expect "core marker on disk, not loaded" "$R" must '- on disk but NOT LOADED: "comparative test"'
expect "core marker missing"            "$R" must '- MISSING: "Presenting to the Operator"'
expect "rule file not imported"         "$R" must 'NOT LOADED: `core/rules/intelligence.md`'
expect "imported file counted"          "$R" must '2 on disk, 1 imported by CLAUDE.md'
expect "no core plugin"                 "$R" must "no enabled plugin with 'core' in its name"
expect "memory index over its limit"    "$R" must '210 lines'
expect "memory over flagged"            "$R" must 'OVER, entries past the cut'
expect "brake: user input (CLAUDE.md)"  "$R" must '`CLAUDE.md:3` [push, comment]'
expect "brake: always ask (rules)"      "$R" must '`.claude/rules/feedback.md:3` [nothing named'
expect "brake: explicit OK, push"       "$R" must '`.claude/rules/feedback.md:4` [push]'
expect "permission: push allowed"       "$R" must '→ ALLOW by `Bash(git push:*)` (project)'
expect "permission: merge asks"         "$R" must '→ ASK by `Bash(gh pr merge:*)` (project)'
expect "permission: review denied"      "$R" must '→ DENY by `Bash(gh pr review *)` (project)'
expect "permission: comment no rule"    "$R" must 'PR comment: `gh pr comment 1 -R owner/repo --body-file note.md` → no rule'
expect "permission: helper allowed"     "$R" must '→ ALLOW by `Bash(node core/helpers/*)` (project)'
expect "template: push asks there"      "$R" must '(project) [template: ASK `Bash(git push*)`]'
expect "template: comment no rule"      "$R" must 'note.md` → no rule'
expect "template: no rule shown"        "$R" must '[template: no rule]'
expect "clean has no template column"   "$R" must 'core template `core/templates/settings.json`: 1 allow, 1 ask, 0 deny'
expect "hook: core stop dispatcher"     "$R" must 'Stop [*] (project, core)'
expect "hook: instance guard"           "$R" must 'PreToolUse [Bash] (project, instance)'
expect "recall: topic found in memory"  "$R" must 'desk.md (1)'
expect "recall: no recall hook"         "$R" must 'none — memory reaches the AI only through the index'
# recall through the live-read gate (2026-10-16, Windows brain: section 6 said "none" while live-read.json made
# the desk's lessons mandatory reading before every desk call) — and an inert gate (no domains) stays "none"
LB="$T/lrbrain"; cp -R "$B" "$LB"; LM="$H/.claude/projects/$(slug "$LB")/memory"; mkdir -p "$LM"; cp "$M/desk.md" "$LM/"
printf '{"hooks": {"PreToolUse": [{"matcher": "Bash|mcp__.*", "hooks": [{"type": "command", "command": "node \\"$CLAUDE_PROJECT_DIR/core/helpers/live-read-gate.cjs\\""}]}]}}\n' > "$LB/.claude/settings.json"
printf '{"domains": [{"name": "desk", "tools": ["^mcp__desk__"], "required": [{"path": "%s", "label": "desk lessons"}, {"path": "docs/desk.md", "label": "ledger"}]}]}\n' "$(native "$LM/desk.md")" > "$LB/.claude/rules/live-read.json"
LR="$T/lr.md"; env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$LB" --home "$H" > "$LR"
expect "recall: live-read gate hands memory" "$LR" must 'live-read-gate: 1 live domain(s), 2 mandatory reading(s) before the first live call, 1 of them mention the topic'
printf '{"domains": []}\n' > "$LB/.claude/rules/live-read.json"
env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$LB" --home "$H" > "$LR"
expect "recall: inert live-read gate is none" "$LR" must 'none — memory reaches the AI only through the index'
expect "secret line still found"        "$R" must '`.claude/rules/secret.md:3` [push]'
expect "secret redacted"                "$R" must '[REDACTED]'
expect "secret not in the report"       "$R" mustnot 'ghp_abcdefghij'

# --- clean brain: negative control
C="$T/clean"; mkdir -p "$C/.claude/rules"; HC="$T/home2"; mkdir -p "$HC/.claude"
printf '# Brain\n\nAct within the order; report afterwards.\n' > "$C/CLAUDE.md"
R2="$T/clean.md"
env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$C" --home "$HC" > "$R2"
expect "clean: no brake phrase"         "$R2" must '- none found'
expect "clean: no hooks"                "$R2" must '- none wired'
expect "clean: no core dir"             "$R2" must 'no `core/` directory in the brain'
expect "clean: topic nowhere"           "$R2" must 'nowhere local'
expect "clean: no memory index"         "$R2" must '- memory index: none at'
expect "clean: no OVER line"            "$R2" mustnot 'OVER'

# --- messy brain: the report still runs through, and every mess is named in section 0
X="$T/messy"; HX="$T/home3"; mkdir -p "$X/.claude/rules" "$X/core" "$HX/.claude"
printf '\xef\xbb\xbf# Brain\r\n\r\n@core/rules/working-rules.md\r\nNie selbst pushen.\r\n' > "$X/CLAUDE.md"
printf '{"permissions": {"allow": ["Bash(git push:*)",]}' > "$X/.claude/settings.json"
printf '["not", "an", "object"]' > "$X/.claude/settings.local.json"
printf '{"permissions": {"allow": "Bash(gh pr comment:*)"}, "enabledPlugins": ["x"], "hooks": {"Stop": ["oops", {"hooks": [{"command": "node a.cjs"}]}]}}' > "$HX/.claude/settings.json"
printf 'Immer den Nutzer fragen, gr\xfc\xdf.\n' > "$X/.claude/rules/latin1.md"
R3="$T/messy.md"
env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$X" --home "$HX" > "$R3"; rc=$?
[ $rc -eq 0 ] && echo "  OK   messy: exit 0" || { echo "  FAIL messy: exit $rc"; fail=1; }
for s in "## 0 Problems" "## 1 Core state" "## 2 Context" "## 3 Brake" "## 4 Permissions" "## 5 Hooks" "## 6 Recall"; do
  expect "messy: section '$s' present" "$R3" must "$s"
done
expect "messy: invalid JSON named"      "$R3" must 'settings.json` is not valid JSON'
expect "messy: list instead of object"  "$R3" must 'holds a list, expected a dict'
expect "messy: allow as string named"   "$R3" must '`permissions.allow` is a str, not a list'
expect "messy: enabledPlugins wrong"    "$R3" must '`enabledPlugins` is a list, not an object'
expect "messy: missing import named"    "$R3" must 'imports `@core/rules/working-rules.md`, which does not exist'
expect "messy: empty core named"        "$R3" must '`core/` exists but is EMPTY'
expect "messy: non-UTF-8 named"         "$R3" must 'latin1.md` is not UTF-8'
expect "messy: BOM/CRLF brake found"    "$R3" must '`CLAUDE.md:4` [push]'
expect "messy: latin-1 brake found"     "$R3" must '`.claude/rules/latin1.md:1`'
expect "messy: odd hook entry survives" "$R3" must '`node a.cjs`'
expect "messy: no section crashed"      "$R3" mustnot 'SECTION FAILED'
N="$T/nobrain"; mkdir -p "$N"
R4="$T/nobrain.md"
env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$N" --home "$HX" > "$R4"; rc=$?
[ $rc -eq 0 ] && echo "  OK   not a brain: exit 0" || { echo "  FAIL not a brain: exit $rc"; fail=1; }
expect "not a brain: named"             "$R4" must 'no `CLAUDE.md` in'
expect "clean: section 0 says none"     "$R2" must "## 0 Problems found while reading"

# --- --memory-dir prints the folder the memory index was read from, and nothing else
md="$(env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$B" --home "$H" --memory-dir)"
case "$md" in *"/projects/$(slug "$B")/memory") echo "  OK   --memory-dir names the memory folder";; *) echo "  FAIL --memory-dir: '$md'"; fail=1;; esac

# --- --out writes the same report and says so on stdout
O="$T/out.md"
msg="$(env -u CLAUDE_CONFIG_DIR "$PY" "$D" --repo "$C" --home "$HC" --out "$(native "$O")")"
case "$msg" in *"report written to"*) echo "  OK   --out names the file";; *) echo "  FAIL --out: '$msg'"; fail=1;; esac
cmp -s "$O" "$R2" && echo "  OK   --out content equals stdout" || { echo "  FAIL --out content differs"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "test-autonomy-diagnose: all checks passed" || echo "test-autonomy-diagnose: FAILURES"
exit "$fail"
