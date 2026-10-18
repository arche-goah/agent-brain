#!/usr/bin/env bash
# Fixture: the session start names a brain whose git login for github.com does not go
# through gh, and stays silent when it does. Runs the REAL block cut out of
# session-bootup.sh against a throwaway global git config — the user's config is never read.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
ok()  { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

sed -n '/^# Git over HTTPS to github.com authenticates through gh/,/^fi$/p' "$HERE/../helpers/session-bootup.sh" > "$TMP/block.sh"
[ -s "$TMP/block.sh" ] || { echo "  FAIL git-login block not found in session-bootup.sh"; exit 1; }

# gh must resolve for the block to run; a stub is enough (the block never calls it).
mkdir -p "$TMP/bin"; printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/gh"; chmod +x "$TMP/bin/gh"

run() {  # $1 = global config file
  PATH="$TMP/bin:$PATH" GIT_CONFIG_GLOBAL="$1" GIT_CONFIG_NOSYSTEM=1 bash "$TMP/block.sh"
}

: > "$TMP/none"
out=$(run "$TMP/none")
case "$out" in *"does not go through gh"*) ok "no helper: named" ;; *) bad "no helper: silent ('$out')" ;; esac

printf '[credential]\n\thelper = osxkeychain\n' > "$TMP/keychain"
out=$(run "$TMP/keychain")
case "$out" in *"does not go through gh"*) ok "keychain only: named" ;; *) bad "keychain only: silent ('$out')" ;; esac

printf '[credential "https://github.com"]\n\thelper =\n\thelper = !/usr/bin/gh auth git-credential\n' > "$TMP/gh"
out=$(run "$TMP/gh")
[ -z "$out" ] && ok "gh helper: silent" || bad "gh helper: printed '$out'"

echo
if (( fails )); then echo "bootup-git-login: $fails FAILURE(S)"; exit 1; fi
echo "bootup-git-login: all 3 cases pass"
