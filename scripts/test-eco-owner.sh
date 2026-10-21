#!/usr/bin/env bash
# Fixture for the ecosystem-owner read in helpers/session-bootup.sh (the owner whose PRs,
# code-scanning alerts and shared-memory repo a session start asks GitHub about).
# Incident 2026-10-21: the template marketplace "your-org" is a real GitHub organisation; a
# freshly bootstrapped brain listed 41 PRs of strangers as its own work. A placeholder owner
# must read as "no owner"; a real one must still come through; and a placeholder must not
# fall through to the next marketplace (a vendor's is no owner either).
# This runs the snippet AS SHIPPED, cut out of session-bootup.sh, so a change there is tested.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$HERE/../helpers/session-bootup.sh"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — got '$2'"; fails=$((fails+1)); }

SNIP="$(sed -n "/^eco_owner=\$(\"\$PY\" -c '\$/,/^' 2>\/dev\/null)\$/p" "$BOOT" | sed '1d;$d')"
# A moved end marker would let the range run to the end of the file; fail loudly then.
if [ -z "$SNIP" ] || ! printf '%s' "$SNIP" | "$PY" -c 'import sys; compile(sys.stdin.read(), "snip", "exec")' 2>/dev/null; then
  echo "test-eco-owner: snippet not found or broken in session-bootup.sh"; exit 1
fi

# OS-3: the dir reaches python as data (CLAUDE_CONFIG_DIR), so it is stated natively.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(native "$(mktemp -d)")"; trap 'rm -rf "$T"' EXIT
mk() { # $1 = file, rest = repo values, in order
  local f="$1"; shift; local body="" i=0
  for r in "$@"; do i=$((i+1)); body="$body${body:+,}\"m$i\":{\"source\":{\"source\":\"github\",\"repo\":\"$r\"}}"; done
  printf '{"extraKnownMarketplaces":{%s}}' "$body" > "$f"
}
owner() { # $1 = project repos (space-separated owner/name, no paths), $2 = user repos
  local pr ur
  read -ra pr <<< "$1"; read -ra ur <<< "${2:-}"
  rm -rf "$T/p" "$T/cfg"; mkdir -p "$T/p/.claude" "$T/cfg"
  [ "${#pr[@]}" -gt 0 ] && mk "$T/p/.claude/settings.json" "${pr[@]}"
  [ "${#ur[@]}" -gt 0 ] && mk "$T/cfg/settings.json" "${ur[@]}"
  (cd "$T/p" && CLAUDE_CONFIG_DIR="$T/cfg" "$PY" -c "$SNIP")
}
is() { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2"; }

echo "ecosystem owner from the marketplace source"
is "real owner comes through (control)"             "$(owner some-team/claude-marketplace)" some-team
is "template placeholder your-org: no owner"        "$(owner your-org/claude-marketplace)" ""
is "case does not matter (Your-Org): no owner"      "$(owner Your-Org/claude-marketplace)" ""
is "<placeholder>: no owner"                        "$(owner '<your-org>/claude-marketplace')" ""
is "a name that only contains it stays an owner"    "$(owner your-org-studio/claude-marketplace)" your-org-studio
is "placeholder first: no fall-through to the next" "$(owner 'your-org/a some-vendor/b')" ""
is "placeholder in project: no fall-through to user" "$(owner your-org/a some-vendor/b)" ""
is "project before user (control)"                  "$(owner proj-org/a user-org/b)" proj-org

echo
if [ "$fails" -eq 0 ]; then echo "test-eco-owner: all checks passed"; exit 0; fi
echo "test-eco-owner: $fails check(s) FAILED"; exit 1
