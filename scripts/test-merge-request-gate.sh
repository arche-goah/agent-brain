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

# Second check (2026-10-26): in a suite or the core, every required OS says OK at the head, or the
# merge names itself a beta. Incident: two suite PRs merged with author and reviewer both on Windows.
spr() { node -e 'process.stdout.write(JSON.stringify({headRefOid: "abc1234def5678", body: process.argv[1], comments: JSON.parse(process.argv[2]).map((b) => ({body: b}))}))' "$1" "$2" > "$T/pr.json"; }
printf '{}\n' > "$T/deps.json"
printf '{"required_os": ["Windows"]}\n' > "$T/deps-win.json"
sprobe() { # same as probe, with the suite seam: $4 deps file or none, $5 OS
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac PR_JSON="$(native "$T/pr.json")" \
          MERGE_REQUEST_GATE_GH="$(native "$T/gh.js")" MERGE_REQUEST_GATE_OS="${5-win32}" MERGE_REQUEST_GATE_DEPS="$4" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
D="$(native "$T/deps.json")"
spr 'feat: x' '["**Review: OK at head `abc1234`** (the Windows instance) - Windows, CI green"]'
sprobe "suite, the incident: Windows OK only" "$M" block "$D"
sprobe "same PR merged as a declared beta" "$M # BETA-MERGE: Windows checked, macOS open" allow "$D"
sprobe "same PR, repo is not a suite (control)" "$M" allow none
sprobe "same PR, the suite requires Windows only" "$M" allow "$(native "$T/deps-win.json")"
spr 'feat: x' '["Windows OK at head `abc1234`", "macOS: ci-lint-local rc 0 at head `abc1234`"]'
sprobe "suite, both systems OK at the head" "$M" allow "$D"
spr 'feat: x' '["Windows OK at head `abc1234`", "macOS: tests pass at head `9999999`"]'
sprobe "suite, macOS OK only at an OLDER head" "$M" block "$D"
spr 'feat: x' '["Windows OK at head `abc1234`; macOS check wanted, macOS unchecked"]'
sprobe "suite, macOS named only as open" "$M" block "$D"

# 2026-10-28 (#156-#159): the negation of ANOTHER system's clause does not cancel this one's OK.
spr 'feat: x' '["macOS: OK at `abc1234` - lint rc 0 (the macOS instance). Windows check still open.", "Windows OK at head `abc1234`"]'
sprobe "macOS OK, Windows named open in the same line" "$M" allow "$D"
spr 'feat: x' '["Windows OK at head `abc1234`, macOS open"]'
sprobe "Windows OK, macOS open in the same line" "$M" block "$D"

# 2026-10-28 (#157): an earlier head separated only by "update branch" merges still counts.
cpr() { node -e 'process.stdout.write(JSON.stringify({headRefOid: "fff0000aaa", body: "feat: x", commits: JSON.parse(process.argv[2]), comments: JSON.parse(process.argv[1]).map((b) => ({body: b}))}))' "$1" "$2" > "$T/pr.json"; }
OKS='["macOS OK at `abc1234`", "Windows OK at `abc1234`"]'
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"fff0000aaa","messageHeadline":"Merge branch '"'"'main'"'"' into fix/x"}]'
sprobe "OKs at the head before an update-branch merge" "$M" allow "$D"
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"fff0000aaa","messageHeadline":"fix: second change"}]'
sprobe "OKs at an older head before a real commit" "$M" block "$D"
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"eee1111bbb","messageHeadline":"fix: y"},{"oid":"fff0000aaa","messageHeadline":"Merge branch '"'"'main'"'"' into fix/x"}]'
sprobe "update-branch merge after a real commit past the OK" "$M" block "$D"

echo
[ "$fail" -eq 0 ] && echo "test-merge-request-gate: all checks passed" || echo "test-merge-request-gate: FAILURES"
exit "$fail"
