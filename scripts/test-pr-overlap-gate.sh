#!/usr/bin/env bash
# covers: pr-overlap-gate
# Fixture for helpers/pr-overlap-gate.cjs - both directions, no network (PR_OVERLAP_FIXTURE).
# The must-block case is the incident (2026-10-28): a new core PR changed the three files an open PR of
# the parallel session already changed.
# Usage: bash scripts/test-pr-overlap-gate.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/pr-overlap-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
FIX='{"files":["scripts/pattern-cases.py","scripts/test-pattern-cases.sh"],"prs":[{"number":194,"title":"fix(pattern-cases)","headRefName":"fix/pattern-cases-answer","files":[{"path":"scripts/pattern-cases.py"}]},{"number":199,"title":"feat(device-status)","headRefName":"feat/device-status","files":[{"path":"scripts/device-status.py"}]}]}'
check() { # $1 label, $2 command, $3 block|allow, [$4 fixture]
  local out
  # hook input built by node from argv (2026-11-02, same class as core #337)
  out=$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]}}))' "$2" | PR_OVERLAP_FIXTURE="${4:-$FIX}" node "$G" 2>&1)
  case "$out" in
    *'"permissionDecision":"deny"'*) [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}";;
    *) [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:200}'";;
  esac
}
C="gh pr create -R arche-goah/agent-brain --head feat/pattern-cases-commitments --title x --body-file b.md"
check "the incident: an open PR changes the same file" "$C" block
check "a bare double quote in the command still blocks" "$C --label \"x\"" block
out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(js "$C")" | PR_OVERLAP_FIXTURE="$FIX" node "$G")
case "$out" in *"#194"*"scripts/pattern-cases.py"*) ok "the block names the PR and the shared file";; *) bad "PR or file not named: $out";; esac
case "$out" in *"#199"*) bad "a PR without shared files was named";; *) ok "a PR without shared files is not named";; esac
# Windows review 2026-11-17: the same call through the PowerShell tool is held too (Bash-only let it pass on Windows)
out=$(printf '{"tool_name":"PowerShell","tool_input":{"command":%s}}' "$(js "$C")" | PR_OVERLAP_FIXTURE="$FIX" node "$G")
case "$out" in *'"permissionDecision":"deny"'*) ok "the PowerShell tool is held as well";; *) bad "PowerShell passed: ${out:0:200}";; esac
grep -aq '"matcher": "Bash|PowerShell"' "$(dirname "$G")/../hooks/hooks.json" && node -e '
const d=require(process.argv[1]);process.exit(d.hooks.PreToolUse.some(g=>/PowerShell/.test(g.matcher)&&g.hooks.some(h=>/pr-overlap-gate/.test(h.command)))?0:1)' "$(cd "$(dirname "$G")/.." && pwd)/hooks/hooks.json" \
  && ok "hooks.json registers it for Bash and PowerShell" || bad "hooks.json: not registered for PowerShell"
# Short (2026-10-31): a stacked branch overlapped ~45 PRs and the block listed every file (~5000 characters).
BIG=$(node -e 'const f=["a","b","c","d","e"];const prs=[];for(let i=1;i<=8;i++)prs.push({number:i,title:"pr "+i,headRefName:"h"+i,files:f.slice(0,i>5?1:5).map(p=>({path:p}))});process.stdout.write(JSON.stringify({files:f,prs}))')
out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(js "$C")" | PR_OVERLAP_FIXTURE="$BIG" node "$G")
case "$out" in *"8 open PR(s)"*"+3 more PR(s)"*) ok "many overlapping PRs: count, top five, the rest as a number";; *) bad "no cap: ${out:0:300}";; esac
case "$out" in *'"#6 '*) bad "a PR outside the top five is listed: ${out:0:300}";; *) ok "the PRs with the most shared files come first";; esac
case "$out" in *"(a, b, c +2)"*) ok "at most three files per PR, the rest as a number";; *) bad "files not capped: ${out:0:300}";; esac
check "a marker with a reason passes" "$C # OVERLAP-OK: #194 lacks the instance case, agreed with the owner" allow
check "a marker without a reason does not pass" "$C # OVERLAP-OK:" block
check "no overlap passes" "$C" allow '{"files":["helpers/x.cjs"],"prs":[{"number":194,"title":"t","headRefName":"b","files":[{"path":"scripts/pattern-cases.py"}]}]}'
check "the branch's own PR (same head) does not count" "$C" allow '{"files":["a.py"],"prs":[{"number":9,"title":"t","headRefName":"feat/pattern-cases-commitments","files":[{"path":"a.py"}]}]}'
check "not a create call (gh pr list)" "gh pr list -R arche-goah/agent-brain" allow
check "create without --head or repo fails open" "gh pr create --title x" allow
check "unreadable data fails open" "$C" allow 'not json'
# branch start (2026-10-29): the incident - a worktree for a translation the same AI's open #232 already carried
SF='{"repo":"arche-goah/grandma3-suite","prs":[{"number":232,"title":"chore(docs): English sweep of mcp/REFERENCE.md","headRefName":"chore/english-sweep-reference"},{"number":231,"title":"chore(docs): English sweep of three tool files","headRefName":"chore/english-sweep-tool-files"}]}'
W="git -C /x/grandma3-suite worktree add -b chore/english-sweep-reference /tmp/w origin/main"
check "the incident: a worktree branch in a repo with open PRs" "$W" block "$SF"
out=$(printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(js "$W")" | PR_OVERLAP_FIXTURE="$SF" node "$G")
case "$out" in *"#232"*"already uses the branch name"*) ok "the block lists the PRs and the same branch name";; *) bad "list or name missing: ${out:0:300}";; esac
check "checkout -b is a branch start too" "git checkout -b feat/x" block "$SF"
check "switch -c is a branch start too" "git -C /x/r switch -c feat/x" block "$SF"
check "a PRS-READ marker with a reason passes" "$W # PRS-READ: #232 carries it - not built" allow "$SF"
check "a PRS-READ marker without a reason does not pass" "$W # PRS-READ:" block "$SF"
check "a repo without open PRs passes" "$W" allow '{"repo":"a/b","prs":[]}'
check "a worktree on an existing branch is no start" "git -C /x/r worktree add /tmp/w origin/main" allow "$SF"
check "git checkout of a file is no start" "git checkout -- a.py" allow "$SF"
echo
[ "$fail" -eq 0 ] && echo "pr-overlap-gate: all cases pass" || { echo "pr-overlap-gate: FAILURE"; exit 1; }
