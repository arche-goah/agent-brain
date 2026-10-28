#!/usr/bin/env bash
# covers: dead-carriers
# Fixture for scripts/dead-carriers.py — a carrier a rule names but that does not exist is reported;
# a present one, a glob, an absence note and a path in a named sibling repo are not.
# Usage: bash scripts/test-dead-carriers.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PY="${PYTHON:-python3}"; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
S="$(cd "$(dirname "$0")" && pwd)/dead-carriers.py"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
B="$T/brain"; mkdir -p "$B/.claude/rules" "$B/scripts" "$B/core/skills/present-skill"
touch "$B/scripts/here.sh"
printf '%s\n' 'Run `scripts/here.sh` and `scripts/missing.sh`.' 'Skill `brain-core:present-skill`, skill brain-core:gone-skill.' > "$B/CLAUDE.md"
printf '%s\n' 'Glob `docs/*.md` is no carrier.' 'The symlink `scripts/old.sh` was removed.' 'Line `docs/x.md:12` points into a file.' > "$B/.claude/rules/a.md"
out=$("$PY" "$(native "$S")" --repo "$(native "$B")" 2>&1); rc=$?
case "$out" in *"dead carrier: CLAUDE.md:1 names scripts/missing.sh"*) ok "a missing script is named";; *) bad "missing script: $out";; esac
case "$out" in *"names brain-core:gone-skill"*) ok "a missing core skill is named";; *) bad "missing skill: $out";; esac
case "$out" in *"scripts/here.sh"*|*"present-skill"*) bad "a present carrier was reported: $out";; *) ok "present carriers are silent";; esac
case "$out" in *"docs/*"*|*"old.sh"*) bad "a glob or an absence note was reported: $out";; *) ok "globs and absence notes are skipped";; esac
case "$out" in *"names docs/x.md"*) ok "a file:line reference is checked as its file";; *) bad "file:line: $out";; esac
case "$out" in *"dead-carriers summary: 5 named, 3 missing"*) ok "the summary counts named and missing";; *) bad "summary: $out";; esac
[ "$rc" -eq 0 ] && ok "a report, exit 0" || bad "rc=$rc"
echo
[ "$fail" -eq 0 ] && echo "dead-carriers: all cases pass" || echo "dead-carriers: FAILURES"
exit "$fail"
