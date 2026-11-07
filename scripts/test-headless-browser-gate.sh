#!/usr/bin/env bash
# covers: headless-browser-gate
# Fixture test for helpers/headless-browser-gate.cjs - both directions. Must block: a playwright or chrome-devtools
# tool call (also under a plugin prefix) while the brain's .mcp.json starts that server without --headless (the
# incident 2026-10-28: a check opened a visible Chrome on the operator's screen). Must allow: the same server WITH
# --headless, a server the brain's .mcp.json does not define, any other MCP tool, an unreadable .mcp.json (fail open).
# Usage: bash scripts/test-headless-browser-gate.sh (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
G="$(cd "$(dirname "$0")" && pwd)/../helpers/headless-browser-gate.cjs"
fail=0
# The project dir reaches node as DATA (env var): Git Bash /tmp/... does not resolve for a native process, and every
# block case would pass silently (docs/os-traps.md OS-3). cygpath states the path natively; elsewhere a no-op.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

probe() { # probe <label> <mcp.json content or -> <tool> <block|allow>
  local d="$T/p$RANDOM$RANDOM"; mkdir -p "$d"
  [ "$2" != "-" ] && printf '%s' "$2" > "$d/.mcp.json"
  local out
  out=$(printf '{"tool_name":"%s","tool_input":{}}' "$3" | CLAUDE_PROJECT_DIR="$(native "$d")" node "$G")
  if [ "$4" = block ]; then
    case "$out" in *'"deny"'*HEADLESS-BROWSER*) ok "$1 blocks" ;; *) bad "$1 should block (got: ${out:-nothing})" ;; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 should allow (got: $out)"
  fi
}

VISIBLE='{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest"]},"chrome-devtools":{"command":"npx","args":["chrome-devtools-mcp@latest"]}}}'
HEADLESS='{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--headless"]},"chrome-devtools":{"command":"npx","args":["chrome-devtools-mcp@latest","--headless"]}}}'

probe "playwright without --headless (the incident)" "$VISIBLE" mcp__playwright__browser_navigate block
probe "chrome-devtools without --headless" "$VISIBLE" mcp__chrome-devtools__new_page block
probe "a plugin-prefixed playwright tool without --headless" "$VISIBLE" mcp__plugin_web_playwright__browser_click block
probe "playwright with --headless (control)" "$HEADLESS" mcp__playwright__browser_navigate allow
probe "chrome-devtools with --headless (control)" "$HEADLESS" mcp__chrome-devtools__take_screenshot allow
probe "server not defined in .mcp.json (control)" '{"mcpServers":{}}' mcp__playwright__browser_navigate allow
probe "another MCP tool (control)" "$VISIBLE" mcp__context7__query-docs allow
probe "no .mcp.json: fail open (control)" - mcp__playwright__browser_navigate allow
probe "unreadable .mcp.json: fail open (control)" '{not json' mcp__playwright__browser_navigate allow

[ "$fail" = 0 ] && echo "test-headless-browser-gate: all checks passed" || echo "test-headless-browser-gate: FAILED"
exit "$fail"
