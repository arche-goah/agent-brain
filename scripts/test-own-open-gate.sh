#!/usr/bin/env bash
# covers: own-open-gate
# test-own-open-gate.sh — a reply that ends on the AI's own open items holds the INTERACTIVE turn once; the
# named ends (question tool, BLOCKED / POOL EMPTY / LIST EMPTY / HAND STEP lines, a hand step, a waiter for the
# item's own sentence) and a negated hit pass, and the autonomous mode is left to autonomous-idle-gate.
# Both directions, English only (other languages are instance data, `own_open_patterns`).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
G="$ROOT/helpers/own-open-gate.cjs"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
CWD="$T/brain"; mkdir -p "$CWD/.claude/rules"
printf '%s\n' '{"own_open_patterns": ["\\bqqq open here\\b"], "own_open_negation_patterns": ["^\\W{0,4}zilch\\b"]}' > "$CWD/.claude/rules/stop-patterns.json"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }

# $1 name · $2 final text · $3 block|allow · $4 extra assistant blocks (JSON, optional) · $5 first user prompt (optional)
# · $6 "after" = the extra blocks follow the text (a question that ENDS the turn comes after it)
run_case() {
  local tr="$T/$1.jsonl"
  printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "${5:-what is the state?}")" > "$tr"
  if [ -n "${4:-}" ]; then
    if [ "${6:-}" = after ]; then
      printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s},%s]}}\n' "$(js "$2")" "$4" >> "$tr"
    else
      printf '{"type":"assistant","message":{"role":"assistant","content":[%s,{"type":"text","text":%s}]}}\n' "$4" "$(js "$2")" >> "$tr"
    fi
  else
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$2")" >> "$tr"
  fi
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$tr")" "$(native "$CWD")" | node "$(native "$G")" 2>&1)"
  if [ "$3" = block ]; then
    case "$out" in *OWN-OPEN-GATE*) ok "$1 blocks";; *) bad "$1 did not block: '${out:0:160}'";; esac
  else
    case "$out" in *OWN-OPEN-GATE*) bad "$1 blocked wrongly: '${out:0:160}'";; *) ok "$1 allows";; esac
  fi
}

INCIDENT='Still open on my side: reset Art-Net, remove the TD helper entry, a correction PR. I need nothing from you for it.'
run_case incident "$INCIDENT" block
run_case i-still-need 'Done with the bench. I still need to update the ledger and post the note.' block
run_case too-late-for-train 'Merge after the Windows check. #414 is too late for the train, it goes with the next pin.' block
run_case data-pack-pattern 'Bench done. qqq open here: the ledger.' block
run_case clean 'PR #38 merged, working copy pulled, ledger entry closed.' allow
run_case quoted 'The rule says a turn that ends with "still open on my side" is held. Built and tested.' allow
# the three changes from the alpha evaluation (2026-11-10, 44 real blocks: 17 right, 25 noise)
run_case blocked-line $'Still open on my side: the ledger line.\nBLOCKED: ledger-line — the peer\'s merge of the carrier' allow
run_case blocked-line-bold $'Still open on my side: the export.\n- **BLOCKED:** export — the operator\'s word on the deploy' allow
run_case hand-step-line $'Still open on my side: the bench run.\nHAND STEP: plug the controller into port 4' allow
run_case hand-step-free-words 'Still open on my side: the flash. Next step for you: press the boot button.' allow
run_case negated 'My open items: none. Everything is merged.' allow
run_case negated-data-pack 'qqq open here: zilch.' allow
run_case autonomous-mode "$INCIDENT" allow "" 'work on autonomously for the next hour'
# a waiter excuses only the item whose own sentence names the condition
run_case waiter-for-its-item 'Still open on my side: the merge, once CI is green.' allow '{"type":"tool_use","id":"toolu_b1","name":"Bash","input":{"command":"sleep 1","run_in_background":true}}'
run_case waiter-does-not-excuse-other "$INCIDENT" block '{"type":"tool_use","id":"toolu_b2","name":"Bash","input":{"command":"sleep 1","run_in_background":true}}'
run_case question-tool "$INCIDENT" allow '{"type":"tool_use","id":"q1","name":"AskUserQuestion","input":{"questions":[{"question":"Go?"}]}}' "" after

[ "$fail" -eq 0 ] && echo "own-open-gate fixtures: ALL passed" || { echo "own-open-gate fixtures: FAILURES"; exit 1; }
