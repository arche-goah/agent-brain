#!/usr/bin/env bash
# covers: workflows path args
# test-workflow-path-args.sh — every core workflow that reads `args` turns its path args to
# forward slashes before any agent sees them (slashPaths). Measured 2026-10-09 on the Windows
# instance: a brain-scan got `scratch` as a backslash path, the agents' Git Bash dropped every
# separator, and the run wrote into a junk folder in the brain root (os-traps shape A).
# Both directions: the helper turns nested backslash paths to slashes and leaves other args
# alone; a workflow that reads args without the helper is named (control: a planted one).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

missing() { # $1 = workflows dir -> names every workflow that reads args but never calls slashPaths(args)
  local f out=""
  for f in "$1"/*.js; do
    grep -q '\bargs\b' "$f" || continue
    grep -q 'slashPaths(args)' "$f" || out+="$(basename "$f") "
  done
  printf '%s' "$out"
}

m=$(missing "$ROOT/workflows")
[ -z "$m" ] && ok "every workflow that reads args normalises its paths" || bad "workflows without slashPaths(args): $m"

mkdir -p "$T/wf"; printf 'const REPO = args.repo || "."\n' > "$T/wf/planted.js"
[ "$(missing "$T/wf")" = "planted.js " ] && ok "control: a workflow without the helper is named" || bad "control: planted workflow not named"

# The helper itself, taken from one workflow and run on a sample.
helper=$(sed -n '/^const slashPaths = /,/^}/p' "$ROOT/workflows/brain-scan.js")
out=$(node -e "$helper
const a = { date: '2026-10-25', scratch: 'D:\\\\work\\\\x y\\\\scratch', reports: { brain: 'D:\\\\r\\\\b.md' }, n: 3 }
slashPaths(a); process.stdout.write(JSON.stringify(a))" 2>&1)
[ "$out" = '{"date":"2026-10-25","scratch":"D:/work/x y/scratch","reports":{"brain":"D:/r/b.md"},"n":3}' ] \
  && ok "nested backslash paths turn to slashes, other args untouched" || bad "helper output: $out"

[ "$fail" = 0 ] && echo "test-workflow-path-args: all checks passed" || { echo "test-workflow-path-args: FAILED"; exit 1; }
