#!/usr/bin/env bash
# covers: pre-commit
# Fixture for step 6 of helpers/git-hooks/pre-commit: a NEW site of a closed OS trap refuses the commit;
# the known baseline, an OPEN invariant (invariant-check exits 1 for it) and a repo without the register pass.
# Sandbox repos only, the real invariant-check.py, no network. Exit 0 = all pass.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
CHECK="$HERE/invariant-check.py"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false \
        -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
hook() { (cd "$1" && bash "$HOOK" 2>&1); }
native() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }   # OS-3: python on Windows
refuses() { local o; o=$(hook "$2"); [[ $? -ne 0 && "$o" == *"$3"* ]] && ok "$1" || bad "$1" "rc/out: $o"; }
passes()  { local o; o=$(hook "$2"); [[ $? -eq 0 ]] && ok "$1" || bad "$1" "refused: $o"; }

R="$T/repo"
mkdir -p "$R/docs" "$R/scripts"
cp "$CHECK" "$R/scripts/invariant-check.py"
printf '%s\n' 'root: ..' '' \
  '## OS-T — a test trap' 'invariant: no file says TRAPWORD' 'pattern:   TRAPWORD' 'paths:     --include=*.sh scripts' \
  'known:     scripts/old.sh=1' 'instances: 1' 'repeat:    no' 'status:    closed' > "$R/docs/os-traps.md"
printf '%s\n' '#!/bin/sh' 'echo TRAPWORD' > "$R/scripts/old.sh"
gq init -q "$R"; gq -C "$R" add -A; gq -C "$R" commit -qm seed

echo "OS traps in the pre-commit"
echo "x" > "$R/scripts/other.sh"; gq -C "$R" add -A
passes "the known baseline passes" "$R"

printf '%s\n' '' '## OS-U — an open class' 'invariant: no file says OPENWORD' 'pattern:   OPENWORD' \
  'paths:     --include=*.sh scripts' 'known:     scripts/old.sh=1' 'instances: 3' 'repeat:    yes' 'status:    open' >> "$R/docs/os-traps.md"
echo 'echo OPENWORD' >> "$R/scripts/old.sh"; gq -C "$R" add -A
passes "an OPEN invariant does not block" "$R"
printf '%s\n' '#!/bin/sh' 'echo OPENWORD' > "$R/scripts/grow.sh"; gq -C "$R" add -A
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # OS-17
o=$("$PY" "$(native "$R/scripts/invariant-check.py")" "$(native "$R/docs/os-traps.md")" 2>&1)
[[ "$o" == *"NEW site: scripts/grow.sh"* ]] && ok "  (control: invariant-check reports the open class's new site)" || bad "control" "$o"
passes "a NEW site of an OPEN class does not block" "$R"

printf '%s\n' '#!/bin/sh' 'echo TRAPWORD' > "$R/scripts/new.sh"; gq -C "$R" add -A
refuses "a NEW site of a closed trap is refused" "$R" "NEW site"
refuses "  ... and the file is named" "$R" "scripts/new.sh"
rm "$R/scripts/new.sh"; gq -C "$R" add -A
passes "  ... and passes again once it is gone" "$R"

P="$T/plain"; mkdir -p "$P"; gq init -q "$P"; echo a > "$P/a.txt"; gq -C "$P" add -A
passes "a repo without the register is not checked" "$P"

echo ""
[ "$fails" -eq 0 ] && echo "pre-commit os-traps: all $checks checks pass" || echo "pre-commit os-traps: $fails of $checks FAILED"
exit "$fails"
