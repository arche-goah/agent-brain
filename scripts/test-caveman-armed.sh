#!/usr/bin/env bash
# Fixture for scripts/caveman-armed.py — armed only through a real carrier (enabled plugin with a
# forced style at the recorded installPath, or a local style file); the bare setting arms nothing.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# installPath inside installed_plugins.json is DATA for a native python (os-traps OS-3)
nat() { cygpath -m "$1" 2>/dev/null || printf '%s' "$1"; }

# $1 enabled value (true|false), $2 plugin.json version, $3 force line, $4 project outputStyle
mk() {
  rm -rf "$T/b" "$T/cfg"; mkdir -p "$T/b/.claude" "$T/cfg/plugins" "$T/p/output-styles" "$T/p/.claude-plugin"
  printf '{"enabledPlugins":{"brain-core@m":%s}%s}' "$1" "${4:+,\"outputStyle\":\"$4\"}" > "$T/b/.claude/settings.json"
  printf '{"plugins":{"brain-core@m":[{"installPath":"%s","version":"1.0.0"}]}}' "$(nat "$T/p")" > "$T/cfg/plugins/installed_plugins.json"
  printf '{"version":"%s"}' "$2" > "$T/p/.claude-plugin/plugin.json"
  printf -- '---\nname: caveman\n%s\n---\nrules\n' "$3" > "$T/p/output-styles/caveman.md"
}
run() { (cd "$T/b" && CLAUDE_CONFIG_DIR="$(nat "$T/cfg")" "$PY" "$HERE/caveman-armed.py"); }

mk true 1.0.0 'force-for-plugin: true' ''
out=$(run); grep -q '^plugin brain-core@m 1.0.0$' <<< "$out" && ok "enabled-forced-plugin-armed" || bad "enabled-forced-plugin-armed: $out"

mk false 1.0.0 'force-for-plugin: true' ''
out=$(run); [[ -z "$out" ]] && ok "disabled-plugin-not-armed" || bad "disabled-plugin-not-armed: $out"

mk true 0.9.0 'force-for-plugin: true' ''
out=$(run); [[ -z "$out" ]] && ok "stale-cache-not-armed" || bad "stale-cache-not-armed: $out"

mk true 1.0.0 'description: no flag' ''
out=$(run); [[ -z "$out" ]] && ok "unforced-style-not-armed" || bad "unforced-style-not-armed: $out"

mk false 1.0.0 'force-for-plugin: true' 'caveman'
out=$(run); [[ -z "$out" ]] && ok "bare-setting-not-armed" || bad "bare-setting-not-armed: $out"

mk false 1.0.0 'force-for-plugin: true' 'caveman'
mkdir -p "$T/b/.claude/output-styles"; printf 'x\n' > "$T/b/.claude/output-styles/caveman.md"
out=$(run); grep -q '^local style caveman$' <<< "$out" && ok "setting-with-local-style-armed" || bad "setting-with-local-style-armed: $out"

(( fail )) && { echo "test-caveman-armed: FAILED"; exit 1; }
echo "test-caveman-armed: all checks passed"
