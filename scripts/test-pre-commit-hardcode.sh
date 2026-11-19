#!/usr/bin/env bash
# covers: pre-commit
# pre-commit: covers
# Fixture for step 3 of helpers/git-hooks/pre-commit: a repo without its own scripts/hardcode-lint.py runs the lint an
# installed plugin ships (tools/hardcode-lint.py, the newest one) over its code directories, against $SHOW_NETWORK_CONFIG;
# without that variable nothing runs; a repo copy wins over the plugin. Operator decision 2026-11-19 (macOS instance):
# a brain kept a hand copy of the suite's lint only because this step read nothing else.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../helpers/git-hooks/pre-commit"
native() { command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || printf '%s' "$1"; }   # OS-3: the paths reach python
T="$(native "$(mktemp -d)")"
trap 'rm -rf "$T"' EXIT
fails=0; checks=0
ok()  { checks=$((checks + 1)); echo "  ok   $1"; }
bad() { checks=$((checks + 1)); fails=$((fails + 1)); echo "  FAIL $1 — $2"; }
mkdir -p "$T/nohooks"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c core.autocrlf=false -c core.hooksPath="$T/nohooks" "$@"; }
gq() { g "$@" >/dev/null 2>&1; }
py=python3; "$py" -c 'import sys' >/dev/null 2>&1 || py=python

# A stand-in for the plugin's lint: it fails on the documentation address 192.0.2.7 in any file under the paths given
# and prints the config it was handed. An OLD version that always fails sits next to it, older on disk.
CC="$T/cc"; NEW="$CC/plugins/cache/org/suite-next/2.0.0/tools"; OLD="$CC/plugins/cache/org/suite-next/1.0.0/tools"
mkdir -p "$NEW" "$OLD"
printf '%s\n' 'import sys, pathlib' \
  'a = sys.argv[1:]; cfg = a[a.index("--config") + 1]; paths = a[:a.index("--config")]' \
  'hits = [str(f) for p in paths for f in pathlib.Path(p).rglob("*") if f.is_file() and "192.0.2.7" in f.read_text()]' \
  'print("lint-new config=" + pathlib.Path(cfg).name + " hits=" + str(len(hits))); sys.exit(1 if hits else 0)' > "$NEW/hardcode-lint.py"
printf '%s\n' 'import sys' 'print("lint-old ran"); sys.exit(1)' > "$OLD/hardcode-lint.py"
touch -t 202601010000 "$OLD/hardcode-lint.py"
echo '{"subnet": "192.0.2.0/24"}' > "$T/net.json"

R="$T/repo"; mkdir -p "$R/scripts"
gq init -q "$R"; echo a > "$R/a.txt"; gq -C "$R" add -A; gq -C "$R" commit -qm seed
hook() { (cd "$R" && env "$@" CLAUDE_CONFIG_DIR="$CC" bash "$HOOK" 2>&1); }

echo "hardcode lint from an installed plugin in the pre-commit"
echo 'host = "192.0.2.7"' > "$R/scripts/x.py"; gq -C "$R" add -A
o=$(hook -u SHOW_NETWORK_CONFIG); [ $? -eq 0 ] && ok "without SHOW_NETWORK_CONFIG nothing is checked" || bad "no config" "$o"
o=$(hook SHOW_NETWORK_CONFIG="$T/missing.json"); [ $? -eq 0 ] && ok "a SHOW_NETWORK_CONFIG that names no file checks nothing" || bad "missing config" "$o"
o=$(hook SHOW_NETWORK_CONFIG="$T/net.json"); [[ $? -ne 0 && "$o" == *"hardcode-lint (plugin)"* && "$o" == *"lint-new config=net.json hits=1"* ]] \
  && ok "a hardcoded address is refused by the newest plugin lint, handed the config" || bad "plugin lint" "$o"
[[ "$o" != *"lint-old"* ]] && ok "  ... and the older installed version does not run" || bad "old version ran" "$o"
echo 'host = cfg["subnet"]' > "$R/scripts/x.py"; gq -C "$R" add -A
o=$(hook SHOW_NETWORK_CONFIG="$T/net.json"); [ $? -eq 0 ] && ok "clean code passes" || bad "clean" "$o"

# A repo copy wins: it runs, the plugin's does not (the stand-in would refuse the address).
printf '%s\n' 'print("repo copy ran")' > "$R/scripts/hardcode-lint.py"
echo 'host = "192.0.2.7"' > "$R/scripts/x.py"; gq -C "$R" add -A
o=$(hook SHOW_NETWORK_CONFIG="$T/net.json"); [[ $? -eq 0 && "$o" != *"lint-new"* ]] && ok "a repo's own hardcode-lint.py wins over the plugin's" || bad "repo copy" "$o"

echo "$checks checks, $fails failed"
[ "$fails" -eq 0 ]
