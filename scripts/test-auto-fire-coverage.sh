#!/usr/bin/env bash
# covers: auto-fire-coverage
#
# Fixture for scripts/auto-fire-coverage.py — both directions of the table check: a skill a plugin ships
# that the table omits (missing), and a row naming a skill the plugin no longer ships (stale). A plugin
# enabled only in the project's settings.local.json is checked too (measured 2026-10-29: it was not).
# Usage: bash scripts/test-auto-fire-coverage.sh   (exit 0 = all pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

CFG="$T/cfg"; B="$T/brain"; P="$T/plug"
mkdir -p "$CFG/plugins" "$B/.claude/rules" "$P/.claude-plugin" "$P/skills/alpha" "$P/skills/beta"
printf '{"name":"suite"}' > "$P/.claude-plugin/plugin.json"
printf -- '---\nname: alpha\ndescription: a\n---\n' > "$P/skills/alpha/SKILL.md"
printf -- '---\nname: beta\ndescription: b\n---\n' > "$P/skills/beta/SKILL.md"
printf '{"version":2,"plugins":{"suite@m":[{"installPath":"%s"}]}}' "$(native "$P")" > "$CFG/plugins/installed_plugins.json"
printf '{}' > "$CFG/settings.json"
run() { CLAUDE_CONFIG_DIR="$(native "$CFG")" "$PY" "$HERE/auto-fire-coverage.py" "$(native "$B")"; }
table() { printf '%s\n' "$1" > "$B/.claude/rules/intelligence-instance.md"; }

# enabled only in settings.local.json: before 2026-10-29 the plugin was never read
printf '{"enabledPlugins":{"suite@m":true}}' > "$B/.claude/settings.local.json"
table '| x | `suite:alpha` |'
out=$(run); [[ "$out" == "suite:beta" ]] && ok "plugin enabled in settings.local.json is checked (missing beta)" || bad "local-enabled: '$out'"

table '| x | `suite:alpha` · `suite:beta` |'
out=$(run); rc=$?; [[ -z "$out" && $rc -eq 0 ]] && ok "fully covered table is silent" || bad "covered: rc=$rc '$out'"

table '| x | `suite:alpha` · `suite:beta` · `suite:gone` |'
out=$(run); grep -qx 'stale row: suite:gone (the plugin ships no such skill)' <<< "$out" && ok "row naming a skill the plugin no longer ships is stale" || bad "stale: '$out'"

table '| x | `suite:alpha` · `suite:beta` · `harness-family:docx` |'
out=$(run); [[ -z "$out" ]] && ok "a prefix this machine does not know is no finding" || bad "unknown prefix: '$out'"

table '| x | `suite:alpha` · `suite:beta` · `suite:gone` |
<!-- auto-fire-ignore: suite:gone -->'
out=$(run); [[ -z "$out" ]] && ok "an ignored id is neither missing nor stale" || bad "ignored: '$out'"

(( fail )) && { echo "test-auto-fire-coverage: FAILED"; exit 1; }
echo "test-auto-fire-coverage: all checks passed"
