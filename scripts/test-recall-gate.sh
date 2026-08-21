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
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
resolve() { for c in "core/$1" "$1"; do [ -f "$c" ] && { printf '%s' "$c"; return 0; }; done; return 1; }
HOOK=$(resolve helpers/recall-gate.cjs) || { echo "  --  recall-gate not in this layout"; exit 0; }

# $1 name, $2 transcript, $3 block|allow, $4 cwd (config root), $5.. extra args
run_hook() {
  local name="$1" tr="$2" want="$3" cwd="$4"; shift 4
  local out
  out=$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$tr" "$cwd" \
        | CLAUDE_PROJECT_DIR="$cwd" node "$HOOK" "$@" 2>&1)
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

exit $fail
