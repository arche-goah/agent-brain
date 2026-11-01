#!/usr/bin/env bash
# covers: basics-hint
# Fixture for helpers/basics-hint.cjs - both directions.
# Must speak: a new brain, a prompt that matches a basic's trigger, the basic not used yet.
# Must stay silent: a second basic in the same session, a learned basic (its proof in the transcript),
# a prompt that matches nothing, a brain with history, a proof that only NAMES the command in text.
# Usage: bash scripts/test-basics-hint.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/basics-hint.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
user() { printf '{"type":"user","message":{"role":"user","content":%s}}\n' "$(js "$1")"; }
asst() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$(js "$1")"; }
skill() { printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"s1","name":"Skill","input":{"skill":"%s"}}]}}\n' "$1"; }
run() { # $1 brain root, $2 transcript, $3 session id, $4 prompt -> stdout of the hook
  printf '{"transcript_path":"%s","cwd":"%s","session_id":"%s","prompt":%s}' \
    "$(native "$2")" "$(native "$1")" "$3" "$(js "$4")" | CLAUDE_PROJECT_DIR="$(native "$1")" node "$(native "$G")" 2>&1
}
says() { case "$2" in *"<basics-hint id=\"$3\""*) ok "$1";; *) bad "$1: '${2:0:160}'";; esac; }
quiet() { [ -z "$2" ] && ok "$1" || bad "$1: '${2:0:160}'"; }

# A new brain: its transcript folder holds only the running session.
B="$T/new"; P="$T/p-new"; mkdir -p "$B" "$P"
f="$P/s1.jsonl"; user "fix the readme" > "$f"
out=$(run "$B" "$f" s1 "ok, I'm done for today"); says "a new operator about to stop hears how to close" "$out" session-close
out=$(run "$B" "$f" s1 "keep an eye on the PRs please"); quiet "a second basic in the same session stays silent" "$out"
out=$(run "$B" "$f" s2 "keep an eye on the PRs please"); says "the next session may teach the next basic" "$out" watch
out=$(run "$B" "$f" s3 "rename the file"); quiet "a prompt that matches no trigger stays silent" "$out"
out=$(run "$B" "$f" s3 "done for today"); says "an unlearned basic comes back in a later session" "$out" session-close

# Proof: the operator used the session close once - silent for good.
{ user "close the session"; skill "brain-core:session-close"; } >> "$f"
out=$(run "$B" "$f" s4 "done for today"); quiet "a basic whose proof is in the transcript is learned and silent" "$out"
grep -q '"session-close": "20' "$B/.claude-state/basics.json" && ok "the learned date is written to the brain's state" \
  || bad "learned date missing: $(cat "$B/.claude-state/basics.json")"

# A close typed as a slash command (Windows review of #257, 2026-11-01): recorded as a prompt, not a tool call.
B7="$T/typed"; P7="$T/p-typed"; mkdir -p "$B7" "$P7"
f7="$P7/s1.jsonl"; { user "fix it"; user "<command-message>brain-core:session-close</command-message>
<command-name>/brain-core:session-close</command-name>"; } > "$f7"
out=$(run "$B7" "$f7" s2 "ok done for today"); quiet "a close typed as a slash command is learned too" "$out"
B8="$T/typed-no"; P8="$T/p-typed-no"; mkdir -p "$B8" "$P8"
f8="$P8/s1.jsonl"; { user "<command-message>loop</command-message>
<command-name>/loop</command-name>"; } > "$f8"
out=$(run "$B8" "$f8" s2 "ok done for today"); says "another typed command is no proof of the close (control)" "$out" session-close
B9="$T/said"; P9="$T/p-said"; mkdir -p "$B9" "$P9"
f9="$P9/s1.jsonl"; user "how does session-close work?" > "$f9"
out=$(run "$B9" "$f9" s2 "done for today"); says "the word session-close in a question is no proof (control)" "$out" session-close

# A proof that only NAMES the command (start report, skill text) is no use of it.
B2="$T/named"; P2="$T/p-named"; mkdir -p "$B2" "$P2"
f2="$P2/s1.jsonl"; { user "hi"; asst "arm it with bash core/scripts/collab-watch.sh"; } > "$f2"
out=$(run "$B2" "$f2" s1 "a PR is coming from them soon"); says "a command named in text is no proof - the basic is still taught" "$out" watch

# The prompt-proof: saying the word once is using it.
B3="$T/prompt"; P3="$T/p-prompt"; mkdir -p "$B3" "$P3"
f3="$P3/s1.jsonl"; user "work through the list autonomously" > "$f3"
out=$(run "$B3" "$f3" s1 "handle everything on your own"); quiet "the operator already said the word: autonomous counts as learned" "$out"

# A brain with history starts with every basic learned.
B4="$T/old"; P4="$T/p-old"; mkdir -p "$B4" "$P4"
for i in 1 2 3 4 5; do user "old $i" > "$P4/old$i.jsonl"; done
f4="$P4/now.jsonl"; user "x" > "$f4"
out=$(run "$B4" "$f4" s1 "done for today"); quiet "a brain with past sessions is not taught what its operator knows" "$out"

# The instance's language: triggers added as data.
B5="$T/lang"; P5="$T/p-lang"; mkdir -p "$B5/.claude/rules" "$P5"
printf '{"triggers":{"session-close":["\\\\bfeierabend\\\\b"]}}\n' > "$B5/.claude/rules/basics.json"
f5="$P5/s1.jsonl"; user "x" > "$f5"
out=$(run "$B5" "$f5" s1 "so, feierabend"); says "an instance trigger in its own language fires" "$out" session-close

# Fail open: no transcript, unreadable state.
B6="$T/broken"; mkdir -p "$B6/.claude-state"; printf 'not json' > "$B6/.claude-state/basics.json"
out=$(run "$B6" "$T/none.jsonl" s1 "rename it"); quiet "broken state and no transcript: silent, no error" "$out"

[ "$fail" = 0 ] && echo "test-basics-hint: all checks passed" || { echo "test-basics-hint: FAILED"; exit 1; }
