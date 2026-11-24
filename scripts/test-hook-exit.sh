#!/usr/bin/env bash
# covers: hook-exit hook-exit-lint
# Fixture for helpers/hook-exit.cjs and scripts/hook-exit-lint.py (2026-11-23: process.exit hung at Node shutdown
# after a large transcript read; a transcript-reading hook ends through hook-exit.cjs).
# Must hold: exit(n) ends with code n and runs nothing after it; the lint refuses a transcript reader that calls
# process.exit and is clean on this repo. Must pass: process.exit outside a transcript reader, the call in a comment.
# Usage: bash scripts/test-hook-exit.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python   # Windows: python3 can be the Store stub (OS-17)
HX="$(native "$_D/../helpers/hook-exit.cjs")"
LINT="$_D/hook-exit-lint.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }

node -e 'require(process.argv[1]).exit(2); console.log("after")' "$HX" > "$T/o1" 2>&1; rc=$?
[ "$rc" = 2 ] && ok "exit(2) ends with code 2" || bad "exit(2) gave rc=$rc"
grep -aq after "$T/o1" && bad "code after exit() still ran" || ok "nothing runs after exit()"
node -e 'require(process.argv[1]).exit()' "$HX"; rc=$?
[ "$rc" = 0 ] && ok "exit() without a code ends with 0" || bad "exit() gave rc=$rc"
node -e 'process.stdin.on("end", () => { console.log("{\"decision\":\"block\"}"); require(process.argv[1]).exit(2); }); process.stdin.resume()' "$HX" < /dev/null | cat > "$T/o2"; rc=${PIPESTATUS[0]}
[ "$rc" = 2 ] && grep -aq '"decision":"block"' "$T/o2" && ok "a hook's output before exit(2) arrives" || bad "hook output or code lost (rc=$rc)"

mkdir -p "$T/r/helpers"
printf 'const t = input.transcript_path;\nprocess.exit(0);\n' > "$T/r/helpers/a-gate.cjs"
out=$("$PY" "$LINT" --root "$(native "$T/r")"); rc=$?
[ "$rc" = 1 ] && [[ "$out" == *"a-gate.cjs"* ]] && ok "lint refuses a transcript reader that calls process.exit" || bad "lint missed it (rc=$rc)"
printf 'const t = input.transcript_path;\n// process.exit(0) would hang here\nhookExit(0);\n' > "$T/r/helpers/a-gate.cjs"
printf 'process.exit(0);\n' > "$T/r/helpers/b-tool.cjs"
"$PY" "$LINT" --root "$(native "$T/r")" >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "lint passes hookExit, a comment, and process.exit outside a transcript reader" || bad "lint false hit (rc=$rc)"
"$PY" "$LINT" >/dev/null; rc=$?
[ "$rc" = 0 ] && ok "this repo's helpers are clean" || bad "this repo's helpers: rc=$rc"

[ "$fail" = 0 ] && echo "test-hook-exit: all checks passed" || { echo "test-hook-exit: FAILED"; exit 1; }
