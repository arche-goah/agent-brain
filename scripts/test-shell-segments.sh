#!/usr/bin/env bash
# covers: shell-segments
# Fixture for helpers/shell-segments.cjs - separators split only outside quotes, both directions.
# Usage: bash scripts/test-shell-segments.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
S="$_D/../helpers/shell-segments.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
seg() { node -e 'const {segments}=require(process.argv[1]);process.stdout.write(JSON.stringify(segments(process.argv[2]).map((s)=>s.trim()).filter(Boolean)))' "$S" "$1"; }
eq() { local got; got="$(seg "$2")"; [ "$got" = "$3" ] && ok "$1" || bad "$1: got $got, wanted $3"; }
eq "a ( and ; inside double quotes do not split" 'git commit -m "gate (alpha; yes)" -- a.txt' '["git commit -m \"gate (alpha; yes)\" -- a.txt"]'
eq "a | inside a grep pattern does not split" "grep -E 'a|b' dir" "[\"grep -E 'a|b' dir\"]"
eq "an escaped quote stays inside the string" 'echo "x \" ; y" ; ls' '["echo \"x \\\" ; y\"","ls"]'
eq "real separators split (control)" 'cd x && grep -r foo . ; ls | wc -l' '["cd x","grep -r foo .","ls","wc -l"]'
eq "a subshell splits (control)" 'echo $(git log) (cd x)' '["echo","git log)","cd x)"]'
echo
[ "$fail" -eq 0 ] && echo "shell-segments: all cases pass" || { echo "shell-segments: FAILURE"; exit 1; }
