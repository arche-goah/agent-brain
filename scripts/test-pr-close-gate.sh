#!/usr/bin/env bash
# covers: pr-close-gate
# test-pr-close-gate.sh — `gh pr close` passes on a PR whose body carries this instance's key, and is held on any other
# PR (operator decision 2026-11-04: allow closing own PRs only). Both directions, no network: gh is a stub.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/pr-close-gate.cjs"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain/.claude"
KEY="$(node -e 'console.log(require(process.argv[1]).keyFor("mac"))' "$(native "$ROOT/helpers/instance-key-gate.cjs")")"

# gh stub: PR 1 carries our key, PR 2 another instance's, PR 3 none; PR 9 fails like a network error
cat > "$T/gh.js" <<EOF
const n = process.argv[2 + 2];
if (n === '9') process.exit(1);
const b = { '1': 'train member <!-- instance-key: $KEY -->', '2': 'x <!-- instance-key: 0123456789 -->', '3': 'no key' }[n] || '';
process.stdout.write(b + '\n');
EOF

probe() { # $1 label, $2 command, $3 block|allow, [$4 SELF value]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF="${4-mac}" PR_CLOSE_GATE_GH="$(native "$T/gh.js")" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}

probe "close own PR" "gh pr close 1 -R o/r --delete-branch" allow
probe "close own PR, repo flag first" "gh pr close -R o/r 1" allow
probe "close another instance's PR" "gh pr close 2 -R o/r" block
probe "close a PR without any key" "gh pr close 3 -R o/r" block
probe "body unreadable = hold" "gh pr close 9 -R o/r" block
probe "no instance id = hold" "gh pr close 1 -R o/r" block ""
probe "another party's PR with the operator's word" "gh pr close 2 -R o/r # PR-CLOSE-OK: \"ja schliessen\" 2026-11-05" allow
probe "a read of the close command is no close" "grep -n 'gh pr close' templates/settings.json" allow
probe "gh pr view is no close" "gh pr view 2 -R o/r" allow

[ "$fail" -eq 0 ] && echo "test-pr-close-gate: all green" || echo "test-pr-close-gate: FAILED"
exit "$fail"
