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

# OS-3 (docs/os-traps.md): the config path reaches native git as DATA in an env var, so on
# Windows it is stated natively — a Git Bash /tmp path would not resolve, git would read no
# config, and the gh-helper case would pass for the wrong reason.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

run() {  # $1 = global config file
  PATH="$TMP/bin:$PATH" GIT_CONFIG_GLOBAL="$(native "$1")" GIT_CONFIG_NOSYSTEM=1 bash "$TMP/block.sh"
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

# The line `gh auth setup-git` writes on Windows (measured 2026-10-18 on the Windows
# instance): the full quoted program path, so "gh auth git-credential" never occurs in it.
printf '[credential "https://github.com"]\n\thelper =\n\thelper = !'"'"'C:\\\\Program Files\\\\GitHub CLI\\\\gh.exe'"'"' auth git-credential\n' > "$TMP/ghwin"
out=$(run "$TMP/ghwin")
[ -z "$out" ] && ok "gh helper, Windows form: silent" || bad "gh helper, Windows form: printed '$out'"

echo
if (( fails )); then echo "bootup-git-login: $fails FAILURE(S)"; exit 1; fi
echo "bootup-git-login: all 4 cases pass"
