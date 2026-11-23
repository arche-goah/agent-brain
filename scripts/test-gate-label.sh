#!/usr/bin/env bash
# covers: gate-label
# Fixture for helpers/gate-label.cjs - one reader for the gate behind a hook refusal (2026-11-23: four parsers
# disagreed; a label with spaces was cut to its first word, an unlabelled refusal became "a hook").
# Usage: bash scripts/test-gate-label.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
L="$(native "$_D/../helpers/gate-label.cjs")"
fail=0
is() { # $1 label, $2 refusal text, $3 expected
  local got; got=$(node -e 'process.stdout.write(require(process.argv[1]).gateLabel(process.argv[2]))' "$L" "$2")
  [ "$got" = "$3" ] && echo "  OK  $1" || { echo "  FAIL $1: got '$got', want '$3'"; fail=1; }
}
is "a label with spaces is kept whole" 'PreToolUse:Bash hook error: SHARED WORKING COPY (/r): another session works here' 'SHARED WORKING COPY'
is "a label ends at ' ('" 'PreToolUse:Bash hook error: MECHANISM CHECK (agent-brain): a shell heredoc' 'MECHANISM CHECK'
is "a label ends at ':'" 'PreToolUse:AskUserQuestion hook error: MODE-QUESTION-ORDER: ask the mode last' 'MODE-QUESTION-ORDER'
is "BLOCKED (<gate>) names the gate" 'PreToolUse:Bash hook error: [node "$CLAUDE_PROJECT_DIR/core/helpers/content-review-gate.cjs"]: BLOCKED (content-review-gate): risk' 'content-review-gate'
is "an unlabelled refusal is named by its node hook" 'PreToolUse:Bash hook error: [node "$CLAUDE_PROJECT_DIR/core/helpers/slow-gate.cjs"]: timed out; blocking because onFailure is "block"' 'slow-gate'
is "an unlabelled refusal is named by its hook number" 'PreToolUse:Bash hook error: [command hook 29]: not here, use the target' 'command hook 29'
is "a label after the hook bracket wins over the hook" 'PreToolUse:Bash hook error: [node "x/core/helpers/x-gate.cjs"]: FACT-HOME: one place only' 'FACT-HOME'
is "lower-case text without a hook is 'a hook'" 'PreToolUse:Bash hook error: no.' 'a hook'
[ $fail = 0 ] && echo "gate-label: all checks passed" || { echo "gate-label: FAILURES"; exit 1; }
