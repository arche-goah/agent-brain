#!/usr/bin/env bash
# covers: absence-gate
#
# Fixture test for the absence-gate — both directions. The gate fires only on the
# COMBINATION (absence claim + a registered source root no search of the turn covered),
# so each half is tested alone as a negative control.
#   1. incident shape: claim after searching one root only        -> block, names the rest
#   2. same claim after a search over every root (Grep/Bash/Glob)  -> allow
#   3. one search on a parent of all roots                         -> allow
#   4. no absence claim, narrow search                             -> allow
#   5. --record mode on case 1                                     -> record, never blocks
#   6. narrow search with a visible "⚙ scope:" line                -> allow
#   7. the claim only quoted                                       -> allow
#   8. no instance roots file                                      -> allow (inert)
#   9. own echo in the last turn                                   -> allow (cooldown)
#  10. instance claim_patterns extend the built-ins                -> block
#  11. Read of a file inside each root counts as touching it       -> allow
# Usage: bash scripts/test-absence-gate.sh   (exit 0 = all fixtures pass)
set -u

# Paths travel INSIDE data here (the transcript JSON, the cwd field, the tool inputs
# the gate resolves). Git Bash /tmp/... does not resolve for node — every must-block
# case would read nothing and every must-allow case would pass for the wrong reason
# (docs/os-traps.md OS-3). cygpath states the path natively; elsewhere a no-op.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
resolve() { for c in "core/$1" "$1"; do [ -f "$ROOT/$c" ] && { printf '%s' "$ROOT/$c"; return 0; }; done; return 1; }
G=$(resolve helpers/absence-gate.cjs) || { echo "  --  absence-gate not in this layout"; exit 0; }

# A brain with three registered roots: one relative to the project, two absolute.
P="$T/brain"; S="$T/suite"; M="$T/shared"
mkdir -p "$P/.claude/rules" "$P/docs" "$S" "$M"
NP=$(native "$P"); NS=$(native "$S"); NM=$(native "$M")
printf '{"roots":["docs/","%s","%s"]}\n' "$NS" "$NM" > "$P/.claude/rules/absence-sources.json"
# Same roots, plus an extra claim pattern — the language-as-data contract, shown with a
# neutral token so the fixture itself stays inside the English-only ratchet.
mkdir -p "$T/ext/.claude/rules" "$T/ext/docs"
printf '{"roots":["docs/","%s","%s"],"claim_patterns":["\\\\bzzabsentzz\\\\b"]}\n' "$NS" "$NM" \
  > "$T/ext/.claude/rules/absence-sources.json"
mkdir -p "$T/bare"

U='{"message":{"role":"user","content":"question"}}'
ECHO='{"message":{"role":"user","content":"Stop hook feedback:\nABSENCE-GATE — ... [ABSENCE-GATE]"}}'
say()  { printf '{"message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$1"; }
tool() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"%s","id":"t","input":%s}]}}\n' "$1" "$2"; }

CLAIM='The send rate of the desk is documented nowhere, so it has to be measured.'
NARROW=$(tool Grep "{\"pattern\":\"send rate\",\"path\":\"$NM\"}")

# $1 name, $2 transcript, $3 block|allow|record, $4 cwd, $5.. extra args
run_hook() {
  local name="$1" tr="$2" want="$3" cwd="$4"; shift 4
  local out
  out=$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' "$(native "$tr")" "$(native "$cwd")" \
        | CLAUDE_PROJECT_DIR="$(native "$cwd")" node "$G" "$@" 2>&1)
  case "$want" in
    block)  case "$out" in *ABSENCE-GATE*'Unsearched roots: docs/'*) ok "$name blocks";;
              *) bad "$name did not block: ${out:0:160}";; esac ;;
    record) case "$out" in *'"record"'*'"would_block":true'*) ok "$name records";;
              *) bad "$name no record: ${out:0:160}";; esac
            case "$out" in *'"decision"'*) bad "$name blocked in record mode";; esac ;;
    *)      [ -z "$out" ] && ok "$name allows" || bad "$name blocked wrongly: ${out:0:160}" ;;
  esac
}

echo "absence-gate:"
{ echo "$U"; echo "$NARROW"; say "$CLAIM"; } > "$T/c1.jsonl"
run_hook "1 incident: one root searched" "$T/c1.jsonl" block "$P"

{ echo "$U"; echo "$NARROW"
  tool Grep '{"pattern":"send rate","path":"docs"}'
  tool Bash "{\"command\":\"cd $NS && rg -n 'send rate' .\"}"
  say "$CLAIM"; } > "$T/c2.jsonl"
run_hook "2 every root searched" "$T/c2.jsonl" allow "$P"

{ echo "$U"; tool Bash "{\"command\":\"grep -rn 'send rate' $(native "$T")\"}"; tool Grep '{"pattern":"send rate"}'
  say "$CLAIM"; } > "$T/c3.jsonl"
run_hook "3 parent of all roots searched" "$T/c3.jsonl" allow "$P"

{ echo "$U"; echo "$NARROW"; say 'Found it in the shared memory: 30 packets per second.'; } > "$T/c4.jsonl"
run_hook "4 no absence claim" "$T/c4.jsonl" allow "$P"

run_hook "5 record mode" "$T/c1.jsonl" record "$P" --record

{ echo "$U"; echo "$NARROW"; say "$CLAIM"; say '⚙ scope: only the shared memory, the question was what the collaborators were told.'; } > "$T/c6.jsonl"
run_hook "6 visible scope marker" "$T/c6.jsonl" allow "$P"

{ echo "$U"; echo "$NARROW"; say 'The ledger asks whether \"documented nowhere\" was checked.'; } > "$T/c7.jsonl"
run_hook "7 claim only quoted" "$T/c7.jsonl" allow "$P"

run_hook "8 no roots file" "$T/c1.jsonl" allow "$T/bare"

{ echo "$U"; echo "$NARROW"; say "$CLAIM"; echo "$ECHO"; echo "$NARROW"; say "$CLAIM"; } > "$T/c9.jsonl"
run_hook "9 own echo, cooldown" "$T/c9.jsonl" allow "$P"

{ echo "$U"; echo "$NARROW"; say 'The send rate is zzabsentzz.'; } > "$T/c10.jsonl"
run_hook "10 instance claim pattern" "$T/c10.jsonl" block "$T/ext"

{ echo "$U"; tool Read "{\"file_path\":\"$NP/docs/notes.md\"}"; tool Read "{\"file_path\":\"$NS/README.md\"}"
  tool Read "{\"file_path\":\"$NM/ops/LOG.md\"}"; say "$CLAIM"; } > "$T/c11.jsonl"
run_hook "11 Read inside every root" "$T/c11.jsonl" allow "$P"

echo
[ "$fail" -eq 0 ] && echo "absence-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
