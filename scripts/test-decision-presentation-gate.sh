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
ask()  { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Remove the worktrees?"}]}}]}}\n'; }
# The closing question after an autonomous run (operator 2026-10-26: "the last question is always: continue autonomously?").
askc() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Remove the worktrees?"},{"question":"Continue autonomously?"}]}}]}}\n'; }
answer() { printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t9","content":%s}]}}\n' "$(js "Your questions have been answered: $1. You can now continue")"; }
qcmd() { printf '{"type":"attachment","attachment":{"type":"queued_command","prompt":%s,"origin":{"kind":"human"}}}\n' "$(js "$1")"; }

B="$T/brain"; mkdir -p "$B/.claude/rules" "$B/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$B/.claude/rules/ledgers.json"
printf '%s\n' '# Questions' '' '- [ ] Remove 29 old worktrees' '  - class: decision' '' '- [ ] Write the docs' '  - class: todo' > "$B/docs/questions.md"
N="$T/none"; mkdir -p "$N/.claude/rules" "$N/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$N/.claude/rules/ledgers.json"
# Decisions that are not the operator's (circle A, C, D) never count (macOS finding on #143).
printf '%s\n' '- [ ] Write the docs' '  - class: todo' '- [x] Old decision' '  - class: decision' \
  '- [ ] Fixture id scheme' '  - class: decision' '  - circle: C' '- [ ] Their desk layout' '  - class: decision' '  - circle: D' > "$N/docs/questions.md"
O="$T/circle"; mkdir -p "$O/.claude/rules" "$O/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$O/.claude/rules/ledgers.json"
printf '%s\n' '- [ ] Fixture id scheme' '  - class: decision' '  - circle: C' '- [ ] Release now' '  - class: decision' '  - circle: B' > "$O/docs/questions.md"

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
# Typed mid-turn (queued_command, turn-kind #139): the operator's word, and an AskUserQuestion of an
# EARLIER turn does not count for it.
f="$T/2q.jsonl"; { user "anything open for me?"; ask; user "now fix the parser"; asst "working"; qcmd "anything open for me?"; asst "Four points, recommendation yes each."; } > "$f"
check "the question typed mid-turn, answered in prose (an earlier turn asked)" "$f" "$B" block
f="$T/2r.jsonl"; { user "work through everything autonomously"; asst "on it"; qcmd "anything open for me?"; asst "Two decisions:"; askc; } > "$f"
check "asked mid-run: through the tool, last question continue autonomously" "$f" "$B" allow
f="$T/2s.jsonl"; { user "work through everything autonomously"; asst "on it"; user "anything open for me?"; asst "Two decisions:"; ask; } > "$f"
check "asked mid-run: through the tool, but no continue question" "$f" "$B" block
f="$T/2t.jsonl"; { user "work through everything autonomously"; asst "on it"; user "anything open for me?"; asst "Nothing open."; } > "$f"
check "asked mid-run, nothing open, prose: the continue question is still due" "$f" "$N" block
f="$T/2u.jsonl"; { user "work through everything autonomously"; user "anything open for me?"; askc; answer '"Remove the worktrees?"="Yes", "Continue autonomously?"="Yes, continue"'; asst "continuing"; } > "$f"
check "after yes to continue: back in the run" "$f" "$B" allow
f="$T/2v.jsonl"; { user "work through everything autonomously"; user "anything open for me?"; askc; answer '"Remove the worktrees?"="Yes", "Continue autonomously?"="No, interactive"'; asst "ok, interactive"; } > "$f"
check "after no to continue: the questions were asked this turn" "$f" "$B" allow
f="$T/3.jsonl"; { user "work through everything autonomously"; asst "on it"; user "normal mode again - how did it go?"; asst "All done. Remove the worktrees? I recommend yes."; } > "$f"
check "first turn after an autonomous run (the off word), prose" "$f" "$B" block
f="$T/4.jsonl"; { user "work through everything autonomously"; asst "filed the question in the ledger"; } > "$f"
check "inside the autonomous run (never ask there)" "$f" "$B" allow
# The two macOS probes (#143 at 9c1515c): a status question or a mid-turn remark does not end the run.
f="$T/4s.jsonl"; { user "work through everything autonomously"; asst "on it"; user "status?"; asst "PR merged, CI running."; } > "$f"
check "a status question mid-run is not the end of the run" "$f" "$B" allow
f="$T/4r.jsonl"; { user "work through everything autonomously"; asst "on it"; qcmd "the desk is running, if you need it"; asst "noted, continuing"; } > "$f"
check "a remark typed mid-run is not the end of the run" "$f" "$B" allow
f="$T/4o.jsonl"; { user "work through everything autonomously"; asst "on it"; user "status?"; asst "x"; user "back to normal mode"; asst "All done. Release now? I recommend yes."; } > "$f"
check "the off word after a status question: first turn after the run, prose" "$f" "$B" block
f="$T/4n.jsonl"; { user "work through everything autonomously"; user "do not stop everything interactively, collect the questions"; asst "collecting"; } > "$f"
check "a negated interactive is no end of the run (macOS finding on #142)" "$f" "$B" allow
f="$T/4c.jsonl"; { user "anything open for me?"; asst "Two points, recommendation yes each."; } > "$f"
check "an operator circle next to a circle C entry" "$f" "$O" block
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

# A hand step counts like a decision (operator 2026-10-26, macOS instance, clarified through the question
# tool: at the end of a run every hand step and decision goes through the tool, never prose).
H="$T/hand"; mkdir -p "$H/.claude/rules" "$H/docs"
printf '%s\n' '{"ledgers":["docs/questions.md"]}' > "$H/.claude/rules/ledgers.json"
printf '%s\n' '- [ ] Update the office router tonight' '  - class: hand-step' '  - circle: B' > "$H/docs/questions.md"
f="$T/h1.jsonl"; { user "anything open for me?"; asst "One thing: update the router tonight."; } > "$f"
check "an open hand step answered in prose" "$f" "$H" block
f="$T/h2.jsonl"; { user "anything open for me?"; asst "One hand step:"; ask; } > "$f"
check "the same hand step through the question tool" "$f" "$H" allow
[ "$fail" = 0 ] && echo "decision-presentation-gate: all cases pass" || { echo "decision-presentation-gate: FAILURES"; exit 1; }
