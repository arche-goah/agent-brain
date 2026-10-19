#!/usr/bin/env bash
# Class check: no arm example in the core still passes the Monitor flag `persistent: true`.
# The Monitor tool dropped it (Claude Code 2.1.303, measured 2026-10-19: `timeout_ms` is
# required, default 5 min, cap 30 min); an example with the old flag is invalid on the
# running harness, and seven places carried it (coherence register 2026-10-19).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

scan() { grep -arnE 'persistent: *true' "$@" 2>/dev/null; }

# negative control: a planted arm example must be found
printf 'Monitor({ command: "x", persistent: true })\n' > "$T/planted.md"
if scan "$T" >/dev/null; then ok "planted persistent:true is found"; else bad "planted persistent:true not found"; fi
printf 'Monitor({ command: "x", timeout_ms: 1800000 })\n' > "$T/planted.md"
if scan "$T" >/dev/null; then bad "timeout_ms example flagged"; else ok "timeout_ms example passes"; fi

hits="$(scan "$ROOT/skills" "$ROOT/scripts" "$ROOT/helpers" "$ROOT/rules" "$ROOT/templates" | grep -av 'test-monitor-arm-shape.sh')"
if [ -z "$hits" ]; then ok "no persistent:true in skills/scripts/helpers/rules/templates"
else bad "persistent:true still present:"; printf '%s\n' "$hits"; fi

exit "$fail"
