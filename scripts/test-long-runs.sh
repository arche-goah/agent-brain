#!/usr/bin/env bash
# Fixture for helpers/long-runs.cjs through the real helpers/mechanism-guard.cjs (2026-10-31).
# covers: long-runs, mechanism-guard
# A long run the rule list does not name is held in the foreground when the script declares
# `long-run: detached`, or when the operator once had to background it by hand (transcript).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$ROOT/helpers/mechanism-guard.cjs"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/.claude/rules" "$T/.claude-state" "$T/scripts"
echo '[]' > "$T/.claude/rules/mechanism-rules.json"
printf '#!/usr/bin/env bash\n# long-run: detached\nsleep 1\n' > "$T/scripts/slow-lint.sh"
printf '#!/usr/bin/env bash\necho quick\n' > "$T/scripts/quick.sh"
printf '#!/usr/bin/env bash\necho wrapper\n' > "$T/scripts/wrapper.sh"
fail=0

# $1 label, $2 expected block|pass, $3 command, $4 background true|false, $5 transcript
verdict() {
  local out got
  out="$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",transcript_path:process.argv[3],tool_input:{command:process.argv[1],run_in_background:process.argv[2]==="true"}}))' "$3" "$4" "${5:-}" \
        | HOME="$T" CLAUDE_PROJECT_DIR="$T" node "$GUARD")"
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then got=block; else got=pass; fi
  if [ "$got" = "$2" ]; then echo "  OK   $1"; else echo "  FAIL $1 (expected $2, got $got)"; fail=1; fi
}

verdict "a declared long run in the foreground is held" block 'bash scripts/slow-lint.sh 217' false
verdict "the same run detached passes" pass 'bash scripts/slow-lint.sh 217' true
verdict "a declared script behind an env assignment is held" block 'X=1 bash scripts/slow-lint.sh' false
verdict "a grep naming the declared script passes" pass 'grep -n slow-lint.sh scripts/quick.sh' false
verdict "a commit message naming it passes" pass 'git commit -m "run bash scripts/slow-lint.sh detached"' false
verdict "an undeclared script passes" pass 'bash scripts/quick.sh' false
verdict "a marker opens it" pass 'bash scripts/slow-lint.sh # MECHANISM-OK: measured short today' false

# a script relative to the call's working directory (a worktree outside the project)
W="$T/worktree"; mkdir -p "$W/scripts"; cp "$T/scripts/slow-lint.sh" "$W/scripts/wt-lint.sh"
out="$(node -e 'process.stdout.write(JSON.stringify({tool_name:"Bash",cwd:process.argv[2],tool_input:{command:process.argv[1]}}))' 'bash scripts/wt-lint.sh' "$W" \
      | HOME="$T" CLAUDE_PROJECT_DIR="$T" node "$GUARD")"
printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && echo "  OK   a declared script in the call's cwd is held" || { echo "  FAIL cwd-relative declared script passed"; fail=1; }

# learned: the transcript shows the operator backgrounded wrapper.sh by hand
TR="$T/session.jsonl"
printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"tu1","name":"Bash","input":{"command":"bash scripts/wrapper.sh 5"}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tu1","content":"Command was manually backgrounded by user"}]},"toolUseResult":{"backgroundTaskId":"b1","backgroundedByUser":true}}' > "$TR"
verdict "without the transcript the wrapper passes (control)" pass 'bash scripts/wrapper.sh 6' false
verdict "a run the operator backgrounded by hand is held next time" block 'bash scripts/wrapper.sh 6' false "$TR"
grep -q '"wrapper.sh"' "$T/.claude-state/long-runs.json" 2>/dev/null && echo "  OK   the lesson is stored for later sessions" || { echo "  FAIL store not written"; fail=1; }
verdict "a later session without that transcript still holds it" block 'bash scripts/wrapper.sh 7' false
verdict "detached it passes" pass 'bash scripts/wrapper.sh 7' true

[ "$fail" -eq 0 ] && echo "long-runs: all cases pass" || { echo "long-runs: FAILURE"; exit 1; }
