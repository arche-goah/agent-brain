#!/usr/bin/env bash
# covers: recall-gate
#
# Both directions. The "must stay silent" half carries the weight: this gate ends a
# finished turn, so a false positive costs a re-issue. Cases:
#   1. research above threshold, nothing persisted           -> block
#   2. research above threshold, memory file written after   -> allow
#   3. research below threshold                              -> allow
#   4. memory written BEFORE the research began (not a carrier for what was read) -> block
#   5. own echo in the last turn, no new research since      -> allow (cooldown, no wallpaper)
#   6. --record mode on case 1                                -> prints record, never blocks
#   7. instance config raises the threshold                   -> allow
# Second trigger (verification claims, T5 — a claim needs verb AND object):
#   8. two verification claims, nothing persisted            -> block
#   9. two verification claims, memory written after         -> allow
#  10. verification VERB alone, no discovery object          -> allow (the AND is the filter)
#  11. discovery OBJECT alone, no verification verb          -> allow
#  12. one claim only (below verifyThreshold)                -> allow
#  13. instance empties the word lists                       -> allow (data, not code)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# A path that travels INSIDE data (a JSON field, an env var read by a native process) is
# not translated by the shell — on Git Bash node would receive /tmp/... and resolve nothing,
# so every must-block case read an empty transcript and "passed" by staying silent. Measured
# 2026-08-31 on Windows: 4 of 13 cases FAIL, the other 9 green for the wrong reason. Same
# helper test-stop-dispatcher.sh and test-premise-gate.sh already carry.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}
resolve() { for c in "core/$1" "$1"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
HOOK=$(resolve helpers/recall-gate.cjs) || { echo "  --  recall-gate not in this layout"; exit 0; }

# $1 name, $2 transcript, $3 block|allow, $4 cwd (config root), $5.. extra args
run_hook() {
  local name="$1" tr="$2" want="$3" cwd="$4"; shift 4
  local out
  out=$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$tr")" "$(native "$cwd")" \
        | CLAUDE_PROJECT_DIR="$(native "$cwd")" node "$HOOK" "$@" 2>&1)
  if [ "$want" = "block" ]; then
    case "$out" in *RECALL-GATE*) ok "$name blocks";; *) bad "$name did not block: ${out:0:140}";; esac
  elif [ "$want" = "record" ]; then
    case "$out" in *'"record"'*'"would_block":true'*) ok "$name records";; *) bad "$name no record: ${out:0:140}";; esac
  else
    [ -z "$out" ] && ok "$name allows" || bad "$name blocked wrongly: ${out:0:140}"
  fi
}

U='{"message":{"role":"user","content":"frage"}}'
research() { # $1 count
  local i; for ((i=0;i<$1;i++)); do
    printf '%s\n' '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"mcp__grandma3__gma3_object_children","id":"r'"$i"'","input":{"path":"Page 1"}}]}}'
  done
}
MEMWRITE='{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Write","id":"w1","input":{"file_path":"brain/memory/phaser-mechanik.md","content":"lesson"}}]}}'
ECHO='{"message":{"role":"user","content":"Stop hook feedback:\nRECALL-GATE — routine … [RECALL-GATE]"}}'

echo "recall-gate:"
{ echo "$U"; research 9; } > "$T/c1.jsonl"
run_hook "1 research>=8, nothing persisted" "$T/c1.jsonl" block "$T"

{ echo "$U"; research 9; echo "$MEMWRITE"; } > "$T/c2.jsonl"
run_hook "2 memory written after research" "$T/c2.jsonl" allow "$T"

{ echo "$U"; research 3; } > "$T/c3.jsonl"
run_hook "3 research below threshold" "$T/c3.jsonl" allow "$T"

{ echo "$U"; echo "$MEMWRITE"; research 9; } > "$T/c4.jsonl"
run_hook "4 memory written BEFORE research" "$T/c4.jsonl" block "$T"

{ echo "$U"; research 9; echo "$ECHO"; echo "$U"; } > "$T/c5.jsonl"
run_hook "5 own echo, no new research" "$T/c5.jsonl" allow "$T"

run_hook "6 record mode" "$T/c1.jsonl" record "$T" --record

mkdir -p "$T/cfg/.claude/rules"
printf '{"threshold": 50}\n' > "$T/cfg/.claude/rules/recall-tools.json"
run_hook "7 instance threshold 50" "$T/c1.jsonl" allow "$T/cfg"

# ── second trigger: verification claims ───────────────────────────────────────
# The real incident's shape: one command establishes a mechanism, far below the
# research threshold, and nothing is written down.
say() { # $1 text -> one assistant text block
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"
}
CLAIM1='Two-level nesting verified live at the desk - the mechanism holds.'
CLAIM2='Reproduced three times, root cause confirmed.'
VERB_ONLY='CI is green, all checks verified, PR merged and pushed.'
OBJ_ONLY='I will look into the nesting syntax and the mechanism behind it tomorrow.'

{ echo "$U"; say "$CLAIM1"; say "$CLAIM2"; } > "$T/c8.jsonl"
run_hook "8 two claims, nothing persisted" "$T/c8.jsonl" block "$T"

{ echo "$U"; say "$CLAIM1"; say "$CLAIM2"; echo "$MEMWRITE"; } > "$T/c9.jsonl"
run_hook "9 two claims, memory written after" "$T/c9.jsonl" allow "$T"

{ echo "$U"; say "$VERB_ONLY"; say "$VERB_ONLY"; say "$VERB_ONLY"; } > "$T/c10.jsonl"
run_hook "10 verification verb without object" "$T/c10.jsonl" allow "$T"

{ echo "$U"; say "$OBJ_ONLY"; say "$OBJ_ONLY"; say "$OBJ_ONLY"; } > "$T/c11.jsonl"
run_hook "11 discovery object without verb" "$T/c11.jsonl" allow "$T"

{ echo "$U"; say "$CLAIM1"; } > "$T/c12.jsonl"
run_hook "12 single claim below threshold" "$T/c12.jsonl" allow "$T"

mkdir -p "$T/cfg2/.claude/rules"
printf '{"verifyVerbs": ["zzzz-no-such-word"]}\n' > "$T/cfg2/.claude/rules/recall-tools.json"
run_hook "13 instance replaces the word list" "$T/c8.jsonl" allow "$T/cfg2"

exit $fail
