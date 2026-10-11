#!/usr/bin/env bash
# The session start names its own duration once it uses two thirds of its hook timeout
# (class carrier, 2026-10-11: the bootup grew from 9 s to past its 30 s limit and was killed,
# which swallows every line it would have printed). Runs the real helpers/session-bootup.sh
# on a throwaway brain and checks both directions:
#   positive  — a limit of 0 s is always exceeded: the line appears, with the slowest parts
#   negative  — a limit far above any run: no line
#   settings  — no override: the limit comes from the brain's own SessionStart hook entry
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BOOT="$HERE/../helpers/session-bootup.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bootup-budget.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
git -C "$TMP" init -q
mkdir -p "$TMP/.claude"
fail=0
check() { # name, output, expect: line|no-line, [extra text that must appear]
  local got=no-line; [[ "$2" == *"session start took "* ]] && got=line
  if [ "$got" != "$3" ]; then echo "FAIL $1 (want $3, got $got)"; fail=1; return; fi
  if [ -n "${4:-}" ] && [[ "$2" != *"$4"* ]]; then echo "FAIL $1 (missing: $4)"; fail=1; return; fi
  echo "ok   $1"
}
run() { CLAUDE_PROJECT_DIR="$TMP" SHARED_MEMORY_REPO="$TMP/no-shared-memory" bash "$BOOT" < /dev/null 2>/dev/null; }

out="$(BOOTUP_TIMEOUT_S=0 run)"
check "limit exceeded: line appears"            "$out" line "of its 0 s limit"
check "limit exceeded: slowest parts named"     "$out" line "slowest: "
out="$(BOOTUP_TIMEOUT_S=100000 run)"
check "far below limit: no line"                "$out" no-line
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash core/helpers/session-bootup.sh","timeout":0}]}]}}' > "$TMP/.claude/settings.json"
out="$(run)"
check "limit read from the brain's settings"    "$out" line "of its 0 s limit"
printf '%s\n' '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash core/helpers/session-bootup.sh","timeout":100000}]}]}}' > "$TMP/.claude/settings.json"
out="$(run)"
check "settings limit far above: no line"       "$out" no-line
[ "$fail" = 0 ] && echo "bootup-time-budget: all cases pass" || { echo "bootup-time-budget: FAILURES"; exit 1; }
