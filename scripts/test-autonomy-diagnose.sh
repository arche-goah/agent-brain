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
printf '# Brain\n\n- Kommentare und Push muessen immer Nutzer-Eingabe sein.\n' > "$B/CLAUDE.md"
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
expect "core marker missing"            "$R" must '- MISSING: "comparative test"'
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
