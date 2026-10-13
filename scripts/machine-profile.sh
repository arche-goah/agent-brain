#!/usr/bin/env bash
# machine-profile.sh — ONE session-start line about the machine this session runs on.
#
# A brain that runs on several machines needs to know which one it is on: the alias the
# operator uses for it, its role, the sender id its shared-memory entries carry, paths
# nothing can discover. That is IDENTITY and lives in config/machines/<key>.md (template:
# core/templates/machine-profile.md, key: scripts/machine-key.sh).
#
# What a tool can read live is never written there (core rule "identity is written, state
# is read", rules/working-rules.md): which programs this machine has is MEASURED here, on
# every start, with `command -v` over the instance's list config/machines/probe-tools.txt
# (one command name per line, # comments). "on PATH" is what is measured — not that the
# program works (a Windows python3 store stub is on PATH). No list = "not measured", a
# state of its own, never "no".
#
# Opt-in: without a config/machines/ directory this prints nothing. Read-only, exit 0.
# Usage: bash scripts/machine-profile.sh [brain-dir]   (default $CLAUDE_PROJECT_DIR or cwd)
set -u
BRAIN="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DIR="$BRAIN/config/machines"
[ -d "$DIR" ] || exit 0
# shellcheck source=machine-key.sh
. "$HERE/machine-key.sh"
key=$(machine_key)
[ -n "$key" ] || { echo "machine: key not measurable (no hostname) — profile not checked"; exit 0; }

# Tools: measured live, never read from the profile.
probe="$DIR/probe-tools.txt"
if [ -f "$probe" ]; then
  have=""; miss=""
  while IFS= read -r t || [ -n "$t" ]; do
    t=${t%%#*}; t=$(printf '%s' "$t" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -n "$t" ] || continue
    case "$t" in *[!A-Za-z0-9._+-]*) miss="$miss $t(unreadable name)"; continue ;; esac
    if command -v "$t" >/dev/null 2>&1; then have="$have $t"; else miss="$miss $t"; fi
  done < "$probe"
  tools="tools on PATH:${have:- none}"
  [ -n "$miss" ] && tools="$tools · missing:$miss"
else
  tools="tools: not measured (no config/machines/probe-tools.txt)"
fi

f="$DIR/$key.md"
if [ -f "$f" ]; then
  field() { sed -n "s/^- $1:[[:space:]]*//p" "$f" | head -1 | tr -d '\r'; }
  alias=$(field "Alias"); sender=$(field "Sender id")
  echo "machine: $key — profile config/machines/$key.md (alias ${alias:-not set}, sender id ${sender:-not set}) · $tools"
else
  echo "!! machine: $key — no profile yet; create it: cp core/templates/machine-profile.md config/machines/$key.md and fill in alias, role, sender id · $tools"
fi
exit 0
