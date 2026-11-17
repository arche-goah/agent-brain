#!/usr/bin/env bash
# Fixture for effect-check.sh E3 (hook targets): an env prefix `VAR="$CLAUDE_PROJECT_DIR/<dir>"` is no hook target;
# a present script passes, a missing script is named, also when passed as a `--flag=` argument.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude" "$T/scripts/envdir"
: > "$T/scripts/present.cjs"
cat > "$T/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"hooks":[
 {"type":"command","command":"CLAUDE_PROJECT_DIR=\"$CLAUDE_PROJECT_DIR/scripts/envdir\" node \"$CLAUDE_PROJECT_DIR/scripts/present.cjs\""},
 {"type":"command","command":"node --require=$CLAUDE_PROJECT_DIR/scripts/gone-require.cjs \"$CLAUDE_PROJECT_DIR/scripts/present.cjs\""},
 {"type":"command","command":"node \"$CLAUDE_PROJECT_DIR/scripts/gone.cjs\""}]}]}}
JSON
out="$(bash "$HERE/effect-check.sh" "$T" 2>&1 | grep -a ' E3 ')"
fail=0
case "$out" in *"3 declared, missing:"*" scripts/gone.cjs"*) echo "OK  env prefix skipped, missing target named";;
  *) echo "FAIL E3: $out"; fail=1;; esac
case "$out" in *"scripts/gone-require.cjs"*) echo "OK  missing --require= target named";;
  *) echo "FAIL --require= target not checked: $out"; fail=1;; esac
case "$out" in *envdir*) echo "FAIL env prefix read as a hook target"; fail=1;; esac
[ "$fail" -eq 0 ] && echo "effect-check E3 fixture: all passed"
exit "$fail"
