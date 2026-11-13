#!/usr/bin/env bash
# covers: check-request-gate check-request-words
# test-check-request-gate.sh — a PR comment that asks another instance to act is posted only when an
# open shared-memory request names the PR (and the head it names), or the text carries
# `request: <id>`. No network: the gate reads the command, the handed file and a sandbox shared memory.
#
# WHY (operator 2026-11-12, translated: "of course she does not read a request in a PR automatically"):
# three comments on a train PR asked the Windows instance for its hand check at a new head; that
# instance reads its shared-memory inbox, not PR threads.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/check-request-gate.cjs"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

probe() { # $1 label, $2 shared-memory dir, $3 command, $4 block|allow, [$5 tool name]
  local out rc
  out=$(node -e '
    const [c, cwd, tool] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_name: tool, cwd, tool_input: { command: c } }));
  ' "$3" "$(native "$T")" "${5:-Bash}" | SHARED_MEMORY_REPO="$(native "$2")" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}"
  else [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
request() { # $1 dir, $2 stem, $3 status, $4 body
  mkdir -p "$1/core"
  printf -- '---\nname: %s\nmetadata:\n  von: a\n  audience: os:windows\n  topic: core\n  status: %s\n---\n\n%s\n' \
    "$2" "$3" "$4" > "$1/core/$2.md"
}

EMPTY="$T/sm-empty"; mkdir -p "$EMPTY/core"
OPEN="$T/sm-open";   request "$OPEN" request-windows-hand-check-510-2026-11-12 open "Hand check of agent-brain #510 at f24270f, please."
OLD="$T/sm-old";     request "$OLD" request-windows-hand-check-510-2026-11-11 open "Hand check of agent-brain #510 at 3f87f46."
DONE="$T/sm-done";   request "$DONE" request-windows-hand-check-510-2026-11-12 answered "Hand check of agent-brain #510 at f24270f."
OTHER="$T/sm-other"; request "$OTHER" request-windows-hand-check-5100-2026-11-12 open "Hand check of #5100 at f24270f."

printf 'macOS: lint all 12 steps at `f24270f`.\n\nPlease run the Windows hand check at `f24270f`.\n' > "$T/ask.md"
C_ASK="gh pr comment 510 -R o/r --body-file $(native "$T/ask.md")"

# Must hold: the incident, a request comment without a shared-memory request.
probe "the incident: ask without a shared-memory request" "$EMPTY" "$C_ASK" block
probe "an open request for an EARLIER head of the PR" "$OLD" "$C_ASK" block
probe "an answered request is no open one" "$DONE" "$C_ASK" block
probe "a request for #5100 is not #510" "$OTHER" "$C_ASK" block
probe "inline --body, another phrase" "$EMPTY" "gh pr comment 510 --body \"Also needed: content reviews for #454 and #511.\"" block
probe "re-run your probe" "$EMPTY" "gh pr review 473 --comment --body \"Please re-run your probe and both fixtures at the new head.\"" block
probe "passive form" "$EMPTY" "gh pr comment 445 --body \"The Windows hand check at this head is requested.\"" block
probe "PR named by URL" "$EMPTY" "gh pr comment https://github.com/o/r/pull/510 --body-file $(native "$T/ask.md")" block
probe "PowerShell" "$EMPTY" "gh pr comment 510 --body 'Please re-check at this head.'" block PowerShell
probe "request: names no existing file" "$EMPTY" "gh pr comment 510 --body \"Please re-check. request: core/request-missing-2026-11-12\"" block

# Must pass.
probe "an open request naming the PR and the head" "$OPEN" "$C_ASK" allow
probe "an open request naming the PR, the comment names no head" "$OPEN" "gh pr comment 510 --body \"Please re-run your probe.\"" allow
probe "request: <area>/<id> in the text" "$OPEN" "gh pr comment 99 --body \"Please run it at head abcdef1. request: core/request-windows-hand-check-510-2026-11-12\"" allow
probe "request: <bare stem> in the text" "$OPEN" "gh pr comment 99 --body \"Please run it. request: request-windows-hand-check-510-2026-11-12\"" allow
probe "a plain review verdict" "$EMPTY" "gh pr review 510 --approve --body \"macOS OK at head f24270f - lint all 12 steps.\"" allow
probe "a comment that answers a request" "$EMPTY" "gh pr comment 510 --body \"Windows OK at head f24270f, by hand (answers core/request-windows-hand-check-510).\"" allow
probe "a review finding for the author" "$EMPTY" "gh pr comment 510 --body \"Floor is high - please declare high and add the Risk line.\"" allow
probe "a quoted earlier request" "$EMPTY" "gh pr comment 509 --body 'Thanks for catching my \"The Windows OK stays with you\" on #473.'" allow
probe "a commit message quoting the ask is no post" "$EMPTY" "git commit -m \"Please run the Windows hand check\"" allow
probe "unreadable shared memory fails open" "$T/nowhere" "$C_ASK" allow

[ "$fail" -eq 0 ] && echo "check-request-gate: all cases pass" || { echo "check-request-gate: FAILURES"; exit 1; }
