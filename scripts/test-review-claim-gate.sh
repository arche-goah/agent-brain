#!/usr/bin/env bash
# covers: review-claim-gate
# test-review-claim-gate.sh — a review comment that says it read the diff is posted only after a
# diff was read since the session's previous post. No network: the gate reads the command, the
# handed file and a fixture transcript.
#
# WHY (operator 2026-11-03): a review comment claimed "read the diff of scripts/open-items.py"
# before that diff was read.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/review-claim-gate.cjs"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# One transcript line per tool use: assistant record with a tool_use block.
use() { # $1 tool name, $2 command or file path
  node -e '
    const [name, arg] = process.argv.slice(1);
    const input = name === "Bash" ? { command: arg } : { file_path: arg };
    console.log(JSON.stringify({ type: "assistant", message: { role: "assistant", content: [{ type: "tool_use", name, input }] } }));
  ' "$1" "$2"
}
probe() { # $1 label, $2 transcript file, $3 command, $4 block|allow
  local out rc
  out=$(node -e '
    const [t, c, cwd] = process.argv.slice(1);
    process.stdout.write(JSON.stringify({ tool_name: "Bash", cwd, transcript_path: t, tool_input: { command: c } }));
  ' "$(native "$2")" "$3" "$(native "$T")" | node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}"
  else [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}

printf 'macOS OK at head 4d04c34 - ran the tests and read the diff of x.py\n' > "$T/claim.md"
printf 'macOS OK at head abc - ran the tests, all pass\n' > "$T/plain.md"
C_CLAIM="gh pr comment 5 -R o/r --body-file $(native "$T/claim.md")"

# The incident: the diff read before the claim was ANOTHER PR's (same file), this PR's diff never opened.
{ use Bash "gh pr diff 4 -R o/r"; use Bash "git -C /x diff origin/main...pr-4 -- x.py"; use Bash "gh pr comment 4 -R o/r --body ok"; use Bash "bash scripts/test-x.sh"; } > "$T/t1.jsonl"
probe "claim with only another PR's diff read" "$T/t1.jsonl" "$C_CLAIM" block
# Negative controls: this PR's diff, read before (also in an earlier turn, before another post).
{ use Bash "git -C /x diff origin/main...pr-5 -- x.py"; use Bash "gh pr comment 4 -R o/r --body ok"; } > "$T/t2.jsonl"
probe "claim after git diff naming pr-5, another post in between" "$T/t2.jsonl" "$C_CLAIM" allow
{ use Bash "gh pr diff 5 -R o/r"; } > "$T/t3.jsonl"
probe "claim after gh pr diff 5" "$T/t3.jsonl" "$C_CLAIM" allow
{ use Bash "git -C /x show 4d04c34 -- x.py"; } > "$T/t6.jsonl"
probe "claim after a diff of the head the comment names" "$T/t6.jsonl" "$C_CLAIM" allow
{ use Bash "gh pr diff 55 -R o/r"; } > "$T/t7.jsonl"
probe "gh pr diff 55 is not PR 5" "$T/t7.jsonl" "$C_CLAIM" block
# A diff in a checkout of the PR (`...HEAD -- <file>`) counts when the comment names that file and it ran
# after the previous post; the same diff before the previous post (read for the PR posted then) does not.
printf 'macOS OK at head 4d04c34 - read the diff of `helpers/x.cjs`\n' > "$T/named.md"
C_NAMED="gh pr comment 5 -R o/r --body-file $(native "$T/named.md")"
{ use Bash "gh pr comment 4 -R o/r --body ok"; use Bash "git diff origin/main...HEAD -- helpers/x.cjs"; } > "$T/t8.jsonl"
probe "diff of the named file in a checkout, after the previous post" "$T/t8.jsonl" "$C_NAMED" allow
{ use Bash "git diff origin/main...HEAD -- helpers/x.cjs"; use Bash "gh pr comment 4 -R o/r --body ok"; } > "$T/t9.jsonl"
probe "the same diff, but before the previous post" "$T/t9.jsonl" "$C_NAMED" block
{ use Read "/x/helpers/x.cjs"; } > "$T/t4.jsonl"
probe "a Read of a file is no read of this PR's diff" "$T/t4.jsonl" "$C_CLAIM" block
printf 'read the diff, no finding\n' > "$T/bare.md"
probe "no PR number, no head: a Read since the previous post counts" "$T/t4.jsonl" "gh pr comment --body-file $(native "$T/bare.md")" allow
probe "comment without a diff claim" "$T/t1.jsonl" "gh pr comment 5 -R o/r --body-file $(native "$T/plain.md")" allow
probe "claim inline in --body" "$T/t1.jsonl" "gh pr comment 5 -R o/r --body \"reviewed the code, no finding\"" block
probe "escape marker names where it was read" "$T/t1.jsonl" "$C_CLAIM # DIFF-READ: read by the subagent, transcript 12" allow
probe "a commit message quoting the claim is no post" "$T/t1.jsonl" "git commit -m \"read the diff\"" allow
# The asking command already stands in the transcript (PreToolUse after the record was written).
{ use Bash "gh pr comment 4 -R o/r --body ok"; use Bash "$C_CLAIM"; } > "$T/t5.jsonl"
probe "the asking call itself is not counted as the previous post" "$T/t5.jsonl" "$C_CLAIM" block

[ "$fail" -eq 0 ] && echo "review-claim-gate: all cases pass" || { echo "review-claim-gate: FAILURES"; exit 1; }
