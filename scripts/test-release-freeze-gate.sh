#!/usr/bin/env bash
# covers: release-freeze-gate
# test-release-freeze-gate.sh — while a release scope is open, a command that starts a NEW branch on the release's repo
# is held unless the branch is in the scope or the operator's quoted word stands in the command (operator 2026-11-06).
# Both directions, no network: the "core" is a throwaway repo whose origin URL ends in agent-brain.git.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/release-freeze-gate.cjs"
. "$(dirname "$0")/git-sandbox.sh"
fail=0; n=0
ok()  { n=$((n+1)); echo "  OK   $1"; }
bad() { n=$((n+1)); echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain/.claude-state"
git init -q -b main "$T/core"
git -C "$T/core" remote add origin https://example.invalid/o/agent-brain.git
git -C "$T/core" commit -q --allow-empty -m init
git init -q -b main "$T/suite"
git -C "$T/suite" remote add origin https://example.invalid/o/some-suite.git
CORE="$(native "$T/core")"; SUITE="$(native "$T/suite")"

WORD='"\"cut the beta now\" 2026-11-12"'   # operator_word as a JSON string
scope() { # $1 status, $2 JSON list of items, [$3 operator_word JSON string; default $WORD]
  printf '{"version": "2.1.4", "repo": "agent-brain", "status": "%s", "operator_word": %s, "items": %s, "excluded": {"feat/out": "later"}}\n' \
    "$1" "${3:-$WORD}" "$2" > "$T/brain/.claude-state/release-scope.json"
}

probe() { # $1 label, $2 command, $3 block|allow, [$4 cwd]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"${4:-$CORE}\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:200}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}

scope open '["feat/listed", "agent-brain#5"]'
probe "worktree add -b, branch not in the scope" "git -C $CORE worktree add ../wt -b feat/new" block
probe "worktree add -b, branch in the scope" "git -C $CORE worktree add ../wt -b feat/listed" allow
probe "checkout -b in the core's working dir, not listed" "git checkout -b feat/new" block
probe "switch -c after another command, not listed" "git status && git switch -c feat/new" block
probe "switch --create=, not listed" "git switch --create=feat/new" block
probe "an excluded branch is named in the scope" "git switch -c feat/out" allow
probe "gh pr create --head, not listed" "gh pr create --head feat/new --title x --body y" block
probe "gh pr create --repo of the release, listed head" "gh pr create -R o/agent-brain -H feat/listed -t x -b y" allow
probe "gh pr create on the current branch (main), not listed" "gh pr create --title x --body y" block
probe "a new branch in another repo" "git -C $SUITE checkout -b feat/new" allow "$SUITE"
probe "gh pr create for another repo" "gh pr create --repo o/some-suite --head feat/new -t x -b y" allow
probe "plain checkout of an existing branch is no new work" "git checkout main" allow
probe "a commit message naming the command is no command" "git commit -m 'git checkout -b feat/new'" allow
probe "marker with the operator's quoted word and date" "git checkout -b feat/new # SCOPE-OK: \"start it now\" 2026-11-06" allow
probe "marker without a quotation" "git checkout -b feat/new # SCOPE-OK: the operator agreed" block
git -C "$T/core" tag v2.1.4
probe "open scope whose tag v2.1.4 already stands reads as closed" "git checkout -b feat/new" allow
git -C "$T/core" tag -d v2.1.4 >/dev/null
probe "tag removed again: the open scope holds" "git checkout -b feat/new" block
# No scope before a pin is due (operator 2026-11-12): an open scope without the operator's word was opened while the
# train still collected - it holds nothing.
scope open '["feat/listed"]' '""'
probe "open scope without the operator's word holds nothing" "git checkout -b feat/new" allow
scope closed '[]'
probe "closed scope" "git checkout -b feat/new" allow
rm -f "$T/brain/.claude-state/release-scope.json"
probe "no scope file" "git checkout -b feat/new" allow
printf 'not json' > "$T/brain/.claude-state/release-scope.json"
probe "unreadable scope file fails open" "git checkout -b feat/new" allow

[ "$fail" -eq 0 ] && echo "test-release-freeze-gate: all $n green" || echo "test-release-freeze-gate: FAILED"
exit "$fail"
