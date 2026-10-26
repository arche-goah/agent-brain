#!/usr/bin/env bash
# covers: decision-presentation-gate
# Fixture for helpers/decision-presentation-gate.cjs - both directions.
# The must-block case is the incident (2026-10-26, Windows instance): asked "is anything open for
# me?", the reply listed four operator decisions in prose without a question mark.
# Usage: bash scripts/test-decision-presentation-gate.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/decision-presentation-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
ask()  { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[]}}]}}\n'; }

B="$T/brain"; mkdir -p "$B/.claude/rules" "$B/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$B/.claude/rules/ledgers.json"
printf '%s\n' '# Questions' '' '- [ ] Remove 29 old worktrees' '  - class: decision' '' '- [ ] Write the docs' '  - class: todo' > "$B/docs/questions.md"
N="$T/none"; mkdir -p "$N/.claude/rules" "$N/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$N/.claude/rules/ledgers.json"
printf '%s\n' '- [ ] Write the docs' '  - class: todo' '- [x] Old decision' '  - class: decision' > "$N/docs/questions.md"

check() { # $1 label, $2 transcript, $3 brain dir, $4 block|allow
  local out
  out=$(printf '{"transcript_path":"%s","cwd":"%s"}' "$(native "$2")" "$(native "$3")" | CLAUDE_PROJECT_DIR="$(native "$3")" node "$(native "$G")" 2>&1)
  case "$out" in
    *'"decision":"block"'*) [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}";;
    *) [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block: '${out:0:160}'";;
  esac
}

f="$T/1.jsonl"; { user "fix the parser"; asst "done"; user "anything open for me?"; asst "Four points: remove the worktrees (recommendation: yes) ..."; } > "$f"
check "the incident: asked what is open, decisions answered in prose" "$f" "$B" block
f="$T/2.jsonl"; { user "anything open for me?"; asst "Two decisions:"; ask; } > "$f"
check "same question, answered through the question tool" "$f" "$B" allow
f="$T/3.jsonl"; { user "work through everything autonomously"; asst "on it"; user "how did it go?"; asst "All done. Remove the worktrees? I recommend yes."; } > "$f"
check "first turn after an autonomous run, prose" "$f" "$B" block
f="$T/4.jsonl"; { user "work through everything autonomously"; asst "filed the question in the ledger"; } > "$f"
check "inside the autonomous run (never ask there)" "$f" "$B" allow
f="$T/5.jsonl"; { user "anything open for me?"; asst "Nothing open."; } > "$f"
check "asked, but no open decision (control)" "$f" "$N" allow
f="$T/6.jsonl"; { user "fix the parser"; asst "done"; user "now the tests"; asst "done"; } > "$f"
check "an ordinary turn, not after autonomy, no ask (control)" "$f" "$B" allow
mkdir -p "$N/.claude-state"
printf '%s\n' '{"a1b2c3d4":{"q":"Release now?","status":"deferred"}}' > "$N/.claude-state/open-questions.json"
f="$T/7.jsonl"; { user "anything open for me?"; asst "Nothing in the ledger."; } > "$f"
check "a deferred register question counts" "$f" "$N" block
# The operator's own language arrives as instance data (the real incident was worded in German).
printf '%s\n' '{"ask_patterns":["\\bmy queue\\b"]}' > "$B/.claude/rules/open-items.json"
f="$T/8.jsonl"; { user "what is in my queue?"; asst "Four points, recommendation yes each."; } > "$f"
check "an instance ask wording through instance data" "$f" "$B" block
rm "$B/.claude/rules/open-items.json"
check "the same wording without instance data (control)" "$f" "$B" allow

[ "$fail" = 0 ] && echo "decision-presentation-gate: all cases pass" || { echo "decision-presentation-gate: FAILURES"; exit 1; }
