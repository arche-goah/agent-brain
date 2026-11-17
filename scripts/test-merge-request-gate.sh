#!/usr/bin/env bash
# covers: merge-request-gate os-review
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
# 2026-11-13 (grandma3-suite #253): an OS named in the evidence of ANOTHER system's OK is no verdict for it.
spr 'feat: x' '["Windows OK at head `abc1234` - npm test rc 0 (257 tests, 256 pass - the same totals as macOS); CI green at this head."]'
sprobe "the incident: a Windows OK naming macOS in its evidence is no macOS OK" "$M" block "$D"
spr 'feat: x' '["Windows OK at head `abc1234` - npm test rc 0.", "macOS: tests pass at head `abc1234`"]'
sprobe "control: the same Windows OK plus a macOS line of its own" "$M" allow "$D"
spr 'feat: x' '["Windows OK at head `abc1234`, macOS: all 256 pass at head `abc1234`"]'
sprobe "a labelled second verdict in the same line (macOS:) stays a macOS OK" "$M" allow "$D"

# 2026-11-06 (operator, question tool: "Ja, auf solche Suiten ausweiten"): for a repo the instance lists in
# .claude/rules/os-proof.json, a green CI job named for the OS counts as that OS's check at the head.
cipr() { node -e 'process.stdout.write(JSON.stringify({headRefOid: "abc1234def5678", body: "feat: x", comments: [{body: "macOS OK at head `abc1234`"}], statusCheckRollup: [{name: "check (ubuntu-latest)", conclusion: "SUCCESS"}, {name: "check (windows-latest)", conclusion: process.argv[1]}]}))' "$1" > "$T/pr.json"; }
cipr SUCCESS
sprobe "suite, macOS OK + green windows-latest, repo NOT listed (control: old rule)" "$M" block "$D"
printf '{"ci_counts_as_os_check": {"o/r": ["Windows"]}}\n' > "$T/brain/.claude/rules/os-proof.json" 2>/dev/null || { mkdir -p "$T/brain/.claude/rules"; printf '{"ci_counts_as_os_check": {"o/r": ["Windows"]}}\n' > "$T/brain/.claude/rules/os-proof.json"; }
sprobe "suite listed, macOS OK + green windows-latest job covers Windows" "$M" allow "$D"
cipr FAILURE
sprobe "negative control: the same listed suite with a red windows job blocks" "$M" block "$D"
printf '{"ci_counts_as_os_check": {"o/r": ["Linux"]}}\n' > "$T/brain/.claude/rules/os-proof.json"
cipr SUCCESS
sprobe "negative control: the listed OS is not Windows, Windows still needs its check" "$M" block "$D"
rm -f "$T/brain/.claude/rules/os-proof.json"

# 2026-10-28 (#156-#159): the negation of ANOTHER system's clause does not cancel this one's OK.
spr 'feat: x' '["macOS: OK at `abc1234` - lint rc 0 (the macOS instance). Windows check still open.", "Windows OK at head `abc1234`"]'
sprobe "macOS OK, Windows named open in the same line" "$M" allow "$D"
spr 'feat: x' '["Windows OK at head `abc1234`, macOS open"]'
sprobe "Windows OK, macOS open in the same line" "$M" block "$D"
# 2026-10-28 (#164): a file name in a code span is no verdict; the same word outside one still is.
spr 'feat: x' '["**macOS OK at head `abc1234`**: `test-open-items.sh` all cases pass", "Windows OK at head `abc1234`"]'
sprobe "a code span naming a file with a negation word" "$M" allow "$D"
spr 'feat: x' '["**macOS OK at head `abc1234`**: test-open-items.sh red", "Windows OK at head `abc1234`"]'
sprobe "the same word outside a code span (control)" "$M" block "$D"
# 2026-11-02 (mikrotik-suite #44): a file name without backticks and the fixture phrase "red against the old code" are no
# verdict either; a real "red against main" still is.
spr 'feat: x' '["macOS: OK at `abc1234` (scripts/test-fail-fast.py, 7/7).", "Windows OK at head `abc1234`"]'
sprobe "a bare file name with a negation word" "$M" allow "$D"
spr 'feat: x' '["macOS OK at `abc1234`: all 7 cases pass (the new case red against the old code)", "Windows OK at head `abc1234`"]'
sprobe "the fixture phrase red against the old code" "$M" allow "$D"
spr 'feat: x' '["macOS OK at `abc1234`, but lint red against main", "Windows OK at head `abc1234`"]'
sprobe "red against main stays a negation (control)" "$M" block "$D"

# 2026-11-06 (agent-brain #414, #332; the reader is helpers/os-review.cjs, shared with release-preflight check 8): a
# compound word is no fail word, and a word in the evidence after "<OS> OK at head" does not cancel the verdict.
spr 'feat: x' '["**macOS OK at head `abc1234`** (the macOS instance): fixture 14/14 (new case 8 red-free both directions in one tree)", "Windows OK at head `abc1234`"]'
sprobe "a compound word (red-free) after the OK" "$M" allow "$D"
spr 'feat: x' '["macOS OK at head abc1234 — read the diff: prompt text only — read the open entries first, a matching one gets a seen-again line", "Windows OK at head `abc1234`"]'
sprobe "a word in the evidence after the verdict" "$M" allow "$D"
spr 'feat: x' '["**macOS OK at head `abc1234`** - the fixture is red", "Windows OK at head `abc1234`"]'
sprobe "a whole fail word in the verdict clause still cancels it (control)" "$M" block "$D"

# 2026-11-12 (agent-brain #473, measured on the Windows instance): an OK named as a thing or promised is no verdict.
# The reviewer's "No Windows OK yet: one finding" and the author's "The Windows OK stays with you" both counted as a
# Windows hand review at the head. Both block cases are red against the reader before this fix.
spr 'feat: x' '["macOS OK at head `abc1234`", "No Windows OK yet: one finding, builder = author side. Head abc1234."]'
sprobe "No Windows OK yet (a finding, not a verdict)" "$M" block "$D"
spr 'feat: x' '["macOS OK at head `abc1234`", "Windows finding fixed, head `abc1234`. Please re-run your probe. The Windows OK stays with you."]'
sprobe "the author asking for the Windows OK" "$M" block "$D"
spr 'feat: x' '["macOS OK at head `abc1234`", "Windows OK once the path is translated (head abc1234)"]'
sprobe "an OK promised on a condition" "$M" block "$D"
spr 'feat: x' '["macOS OK at head `abc1234`", "**Windows OK at head `abc1234`** (the Windows instance, measured once)"]'
sprobe "a real Windows OK with the instance named after it (control)" "$M" allow "$D"
# A finding comment whose evidence carries pass words is no OK: the explicit no is its verdict (13 drafts, 2026-11-12).
spr 'feat: x' '["macOS OK at head `abc1234`", "Windows check (head abc1234)\nNo Windows OK yet: 1 finding, builder = author side.\n- **Windows, measured:** 17/17 passed rc=0"]'
sprobe "a finding comment with passing suites" "$M" block "$D"
spr 'feat: x' '["macOS OK at head `abc1234`", "Windows FAIL at head abc1234: test-x.sh red; the other suites pass on Windows"]'
sprobe "Windows FAIL with pass words after it (control, blocked before too)" "$M" block "$D"

# 2026-10-28 (#157): an earlier head separated only by "update branch" merges still counts.
cpr() { node -e 'process.stdout.write(JSON.stringify({headRefOid: "fff0000aaa", body: "feat: x", commits: JSON.parse(process.argv[2]), comments: JSON.parse(process.argv[1]).map((b) => ({body: b}))}))' "$1" "$2" > "$T/pr.json"; }
OKS='["macOS OK at `abc1234`", "Windows OK at `abc1234`"]'
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"fff0000aaa","messageHeadline":"Merge branch '"'"'main'"'"' into fix/x"}]'
sprobe "OKs at the head before an update-branch merge" "$M" allow "$D"
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"fff0000aaa","messageHeadline":"fix: second change"}]'
sprobe "OKs at an older head before a real commit" "$M" block "$D"
cpr "$OKS" '[{"oid":"abc1234def","messageHeadline":"fix: x"},{"oid":"eee1111bbb","messageHeadline":"fix: y"},{"oid":"fff0000aaa","messageHeadline":"Merge branch '"'"'main'"'"' into fix/x"}]'
sprobe "update-branch merge after a real commit past the OK" "$M" block "$D"

# Third + fourth check (2026-10-26, merge table conditions "CI green" and "open own findings"):
# gh merges on red CI where no branch protection asks, and nothing read an open own finding.
rpr() { node -e 'process.stdout.write(JSON.stringify({body: "feat: x", statusCheckRollup: JSON.parse(process.argv[1]), comments: JSON.parse(process.argv[2]).map((b) => ({body: b}))}))' "$1" "$2" > "$T/pr.json"; }
rpr '[{"name":"lint","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"tag","status":"COMPLETED","conclusion":"SKIPPED"}]' '[]'
probe "CI green, skipped check (control)" "$M" allow
rpr '[]' '[]'
probe "no CI at all (control)" "$M" allow
rpr '[{"name":"lint","status":"COMPLETED","conclusion":"FAILURE"}]' '[]'
probe "CI red" "$M" block
probe "CI red, marker says why" "$M # CI-RED-OK: flaky runner, rerun green on main" allow
rpr '[{"name":"lint","status":"IN_PROGRESS","conclusion":""}]' '[]'
probe "CI still running" "$M" block
rpr '[{"context":"ci/legacy","state":"FAILURE"}]' '[]'
probe "a failed commit status" "$M" block
rpr '[]' "[\"**Finding:** the guard misses \`x\` <!-- instance-key: $KEY -->\"]"
probe "own finding open" "$M" block
probe "own finding, marker names where it closed" "$M # FINDING-CLOSED: follow-up PR #9" allow
rpr '[]' "[\"Finding: x <!-- instance-key: $KEY -->\", \"Fixed at head, OK <!-- instance-key: $KEY -->\"]"
probe "own finding, later own OK" "$M" allow
rpr '[]' '["Finding: x <!-- instance-key: 0123456789 -->"]'
probe "another instance's finding (not this gate's)" "$M" allow
rpr '[]' "[\"Windows OK; leak-scan 0 findings, the old pattern fails both cases <!-- instance-key: $KEY -->\"]"
probe "an OK that mentions findings and fails in prose (control)" "$M" allow

echo
[ "$fail" -eq 0 ] && echo "test-merge-request-gate: all checks passed" || echo "test-merge-request-gate: FAILURES"
exit "$fail"
