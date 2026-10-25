#!/usr/bin/env bash
# covers: merge-request-gate
# test-merge-request-gate.sh — `gh pr merge` waits while the PR body asks THIS machine for a check
# that no comment of this instance answered. Both directions, no network: a fake gh answers.
#
# WHY (2026-10-24): three "please counter-check on macOS" requests were merged unanswered.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/merge-request-gate.cjs"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain/.claude"
KEY="$(node -e 'console.log(require(process.argv[1]).keyFor("mac"))' "$(native "$ROOT/helpers/instance-key-gate.cjs")")"
printf 'process.stdout.write(require("fs").readFileSync(process.env.PR_JSON, "utf8"))\n' > "$T/gh.js"

pr() { node -e 'process.stdout.write(JSON.stringify({body: process.argv[1], comments: JSON.parse(process.argv[2]).map((b) => ({body: b}))}))' "$1" "$2" > "$T/pr.json"; }
probe() { # $1 label, $2 command, $3 block|allow, [$4 OS, default darwin]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac PR_JSON="$(native "$T/pr.json")" \
          MERGE_REQUEST_GATE_GH="$(native "$T/gh.js")" MERGE_REQUEST_GATE_OS="${4-darwin}" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
M="gh pr merge 67 -R o/r --merge"

pr $'## Tests\nWindows green.\n**Please counter-check on macOS** at the head.' '[]'
probe "unanswered macOS request" "$M" block
probe "same request, this machine is Windows" "$M" allow win32
probe "URL form" "gh pr merge https://github.com/o/r/pull/67 --squash" block
probe "marker names where it was answered" "$M # REQUEST-ANSWERED: shared-memory reply 2026-10-24" allow
probe "not a merge" "gh pr view 67 -R o/r" allow
pr $'Please counter-check on macOS.' "[\"macOS: tests pass at abc <!-- instance-key: $KEY -->\"]"
probe "answered by this instance, naming the OS" "$M" allow
pr $'Please counter-check on macOS.' '["macOS: tests pass <!-- instance-key: 0123456789 -->"]'
probe "answered only by ANOTHER instance" "$M" block
pr $'Please counter-check on macOS.' "[\"merging <!-- instance-key: $KEY -->\"]"
probe "own comment that does not name the OS" "$M" block
pr $"Please counter-check on Windows.
<!-- instance-key: $KEY -->" '[]'
probe "own PR (body carries own key)" "$M" allow
pr $'Tested on macOS and Windows, all green.' '[]'
probe "a statement, no request" "$M" allow

echo
[ "$fail" -eq 0 ] && echo "test-merge-request-gate: all checks passed" || echo "test-merge-request-gate: FAILURES"
exit "$fail"
