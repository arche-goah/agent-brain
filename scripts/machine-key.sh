#!/usr/bin/env bash
# machine-key.sh — the one name of THIS machine that per-machine instance data is filed
# under (config/machines/<key>.md). Sourced for the function, or run to print the key.
#
# Why not plain `hostname`: on macOS it follows the network (a DHCP or VPN name, or
# `<name>.local` on one network and something else on the next), so the same laptop would
# look for a different profile per network. `scutil --get LocalHostName` is the name the
# operator set in the sharing settings and does not move. Linux and Windows Git Bash keep
# `hostname`, which is stable there.
#
# Normalised: short form (up to the first dot), lowercase, anything outside [a-z0-9_-]
# becomes '-', so the key is a safe file name on every OS.
#
# Used by: scripts/machine-profile.sh (session start line) and helpers/session-pull.sh
# (per-machine opt-out). One function, so both parts always agree on the machine.

machine_key() {
  local k=""
  if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && command -v scutil >/dev/null 2>&1; then
    k=$(scutil --get LocalHostName 2>/dev/null) || k=""
  fi
  [ -n "$k" ] || k=$(hostname 2>/dev/null) || k=""
  k=${k%%.*}
  printf '%s' "$k" | tr -d '\r\n' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g'
}

# Run directly: print the key. Sourced: only define the function.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  machine_key
  echo
fi
