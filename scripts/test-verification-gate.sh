#!/usr/bin/env bash
# Fixture for helpers/verification-gate.cjs — both directions. The gate fires only when THREE
# things meet in the turn: code was edited, the last reply declares the work finished, and skill
# verification-before-completion was never loaded in the session. Each leg alone is a control.
# Usage: bash scripts/test-verification-gate.sh   (exit 0 = all fixtures pass)
set -u

# Paths inside JSON read by node are stated natively (OS-3, docs/os-traps.md).
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT/helpers/verification-gate.cjs"
[ -f "$G" ] || G="$ROOT/core/helpers/verification-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# Instance language for the done claim lives in watch-gate.json (one place, done-claim.cjs).
mkdir -p "$T/de/.claude/rules" "$T/empty"
printf '%s\n' '{"done_claim_patterns":["\\balles\\s+erledigt\\b"]}' > "$T/de/.claude/rules/watch-gate.json"

op()    { printf '{"message":{"role":"user","content":%s}}\n' "$1"; }
say()   { printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$1"; }
edit()  { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":%s,"old_string":"a","new_string":"b"}}]}}\n' "$1"; }
skill() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Skill","input":{"skill":"brain-core:verification-before-completion"}}]}}\n'; }
readf() { printf '{"message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"C:\\\\x\\\\skills\\\\verification-before-completion\\\\SKILL.md"}}]}}\n'; }
meta()  { printf '{"isMeta":true,"sourceToolUseID":"toolu_x","message":{"role":"user","content":[{"type":"text","text":"Base directory for this skill: x"}]}}\n'; }

# $1 name, $2 block|allow, $3 cwd, $4 extra payload fields (json, optional)
run_case() {
  local name="$1" want="$2" cwd="${3:-$T/empty}" extra="${4:-}"
  local out
  out="$(printf '{"transcript_path":"%s","cwd":"%s"%s}' "$(native "$T/$name.jsonl")" "$(native "$cwd")" "$extra" | node "$G" 2>&1)"
  if [ "$want" = block ]; then
    case "$out" in *VERIFICATION-GATE*) ok "$name blocks";; *) bad "$name did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$name allows" || bad "$name blocked wrongly: '$out'"
  fi
}

# --- the case: code edited, "all done", skill never loaded
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"Fixed. All done."'; } > "$T/claim.jsonl"
run_case claim block
# --- loaded earlier in the SESSION (another turn) counts
{ op '"start"'; skill; say '"ok"'; op '"fix the parser"'; edit '"src/parse.py"'; say '"Fixed. All done."'; } > "$T/loaded.jsonl"
run_case loaded allow
{ op '"fix the parser"'; readf; edit '"src/parse.py"'; say '"Fixed. All done."'; } > "$T/read-skill.jsonl"
run_case read-skill allow
# --- controls: each leg alone
{ op '"update the notes"'; edit '"docs/notes.md"'; say '"Updated. All done."'; } > "$T/prose.jsonl"
run_case prose allow
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"Fixed; the CI run is still going."'; } > "$T/no-claim.jsonl"
run_case no-claim allow
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"He wrote \"all done\" in the log; the run is still going."'; } > "$T/quoted.jsonl"
run_case quoted allow
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"ok"'; op '"thanks, anything left?"'; say '"All done."'; } > "$T/old-turn.jsonl"
run_case old-turn allow
# --- re-issue and own echo pass
run_case claim allow "$T/empty" ',"stop_hook_active":true'
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"Fixed. All done."'; op '"Stop hook feedback: VERIFICATION-GATE: x"'; say '"All done."'; } > "$T/echo.jsonl"
run_case echo allow
# --- a loaded skill's own text is no turn boundary: the edit before it still counts
{ op '"fix the parser"'; edit '"src/parse.py"'; meta; say '"All done."'; } > "$T/skill-text.jsonl"
run_case skill-text block
# --- instance language from the data, with a discriminator
{ op '"fix the parser"'; edit '"src/parse.py"'; say '"Behoben, alles erledigt."'; } > "$T/de.jsonl"
run_case de block "$T/de"
run_case de allow "$T/empty"
# --- fail-open: no transcript
out="$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$T/missing.jsonl")" "$(native "$T")" | node "$G" 2>&1)"
[ -z "$out" ] && ok "missing transcript allows (fail-open)" || bad "missing transcript: '$out'"

echo
[ "$fail" -eq 0 ] && echo "verification-gate fixtures: ALL passed" || echo "FAILURE"
exit "$fail"
