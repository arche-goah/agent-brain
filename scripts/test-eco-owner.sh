#!/usr/bin/env bash
# Fixture for the ecosystem-owner read in helpers/session-bootup.sh (the owner whose PRs,
# code-scanning alerts and shared-memory repo a session start asks GitHub about).
# Incident 2026-10-21: the template marketplace "your-org" is a real GitHub organisation; a
# freshly bootstrapped brain listed 41 PRs of strangers as its own work. A placeholder owner
# must read as "no owner"; a real one must still come through.
# This runs the snippet AS SHIPPED, cut out of session-bootup.sh, so a change there is tested.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$HERE/../helpers/session-bootup.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — got '$2'"; fails=$((fails+1)); }

SNIP="$(sed -n "/^eco_owner=\$(\"\$PY\" -c '\$/,/^' 2>\/dev\/null)\$/p" "$BOOT" | sed '1d;$d')"
[ -n "$SNIP" ] || { echo "test-eco-owner: snippet not found in session-bootup.sh"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
owner() { # $1 = repo value in the project's extraKnownMarketplaces
  mkdir -p "$T/p/.claude" "$T/cfg"
  printf '{"extraKnownMarketplaces":{"m":{"source":{"source":"github","repo":"%s"}}}}' "$1" > "$T/p/.claude/settings.json"
  (cd "$T/p" && CLAUDE_CONFIG_DIR="$T/cfg" "$PY" -c "$SNIP" 2>/dev/null)
}

echo "ecosystem owner from the marketplace source"
o="$(owner some-team/claude-marketplace)"; [ "$o" = some-team ] && ok "real owner comes through (control)" || bad "real owner comes through (control)" "$o"
o="$(owner your-org/claude-marketplace)";  [ -z "$o" ] && ok "template placeholder your-org: no owner" || bad "template placeholder your-org: no owner" "$o"
o="$(owner '<owner>/claude-marketplace')"; [ -z "$o" ] && ok "<placeholder>: no owner" || bad "<placeholder>: no owner" "$o"

echo
if [ "$fails" -eq 0 ]; then echo "test-eco-owner: all checks passed"; exit 0; fi
echo "test-eco-owner: $fails check(s) FAILED"; exit 1
