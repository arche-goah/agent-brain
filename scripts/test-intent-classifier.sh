#!/usr/bin/env bash
# covers: intent-classifier
# Fixture for helpers/intent-classifier.cjs. No model call: a node stub answers. Cases: a disagreement between words
# and model is reported, an unreadable answer fails open, the child guard stops recursion, a hook run logs one line,
# a question-tool answer is logged with its question and note, a background notice is not classified, and the line
# written is the one autonomous-mode.cjs modelSays reads back. Usage: bash scripts/test-intent-classifier.sh (rc 0 = pass)
set -u
here=$(cd "$(dirname "$0")" && pwd)
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
H="$(native "$here/../helpers/intent-classifier.cjs")"
AM="$(native "$here/../helpers/autonomous-mode.cjs")"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
B="$(native "$T/brain")"; mkdir -p "$T/brain/.claude-state"
LOG="$B/.claude-state/intent-classifier.jsonl"; : > "$LOG"
export CLAUDE_PROJECT_DIR="$B"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
lines() { node -e 'const fs=require("fs");process.stdout.write(String(fs.readFileSync(process.argv[1],"utf8").split("\n").filter(Boolean).length))' "$LOG"; }

# stub: asks_open true for any message, everything else false; and a broken one
printf '%s\n' 'process.stdin.resume();process.stdin.on("end",()=>{console.log(JSON.stringify({asks_open:true,mode_on:false,mode_off:false,correction:false,condition:false,orders_task:false}))});' > "$T/stub.cjs"
printf '%s\n' 'process.stdin.resume();process.stdin.on("end",()=>{console.log("no json here")});' > "$T/broken.cjs"
S="$(native "$T/stub.cjs")"; BR="$(native "$T/broken.cjs")"

out=$(INTENT_CLASSIFIER_BIN="$S" node -e '
const c = require(process.argv[1]);
const t = "is there something you need me for?";
const w = c.wordVerdict(t), m = c.modelVerdict(t);
process.stdout.write(JSON.stringify({d: c.differ(w, m)}));' "$H")
case "$out" in *'"d":["asks_open"]'*) ok "a phrasing the words miss and the model reads is reported as a disagreement";; *) bad "disagreement: $out";; esac

out=$(INTENT_CLASSIFIER_BIN="$BR" node -e 'process.stdout.write(String(require(process.argv[1]).modelVerdict("x")))' "$H")
[ "$out" = "null" ] && ok "an unreadable model answer is null (fails open)" || bad "broken answer: $out"

printf '{"prompt":"what is up?","session_id":"t"}' | INTENT_CLASSIFIER_CHILD=1 INTENT_CLASSIFIER_BIN="$S" node "$H"
[ "$(lines)" = 0 ] && ok "inside the nested call (child guard) the hook does nothing" || bad "child guard wrote a line"

printf '{"prompt":"is there something you need me for?","session_id":"sess-x"}' | INTENT_CLASSIFIER_BIN="$S" node "$H"; rc=$?
[ "$rc" = 0 ] && [ "$(lines)" = 1 ] && ok "a hook run exits 0 and logs one line" || bad "hook run rc=$rc lines $(lines)"

# the record round trip: what the hook wrote is what the gates read (same session, prompt in the window, same text)
at=$(node -e 'const l=require("fs").readFileSync(process.argv[1],"utf8").trim().split("\n");process.stdout.write(JSON.parse(l[0]).at)' "$LOG")
got=$(node -e '
const am = require(process.argv[1]);
const ts = new Date(Date.parse(process.argv[2]) - 2000).toISOString();
const tp = "/x/sess-x.jsonl";
process.stdout.write([am.modelSays("asks_open", tp, process.argv[3], ts, "is there something you need me for?"),
  am.modelSays("asks_open", "/x/other.jsonl", process.argv[3], ts, "is there something you need me for?"),
  am.modelSays("asks_open", tp, process.argv[3], ts, "a different prompt")].map(String).join(","));' "$AM" "$at" "$B")
[ "$got" = "true,null,null" ] && ok "modelSays reads the record back; another session or prompt is no record" || bad "round trip: $got"

printf '{"prompt":"x","session_id":"sess-f"}' | INTENT_CLASSIFIER_BIN="$BR" node "$H"
case "$(tail -n 1 "$LOG")" in *'"model":null'*) ok "a failed call is logged with model null (readers fall back to the words)";; *) bad "failed call line: $(tail -n 1 "$LOG")";; esac

printf '{"tool_name":"AskUserQuestion","session_id":"sess-a","tool_input":{"questions":[]},"tool_response":{"answers":{"Tag now?":"After the two PRs"},"annotations":{"Tag now?":{"notes":"only then"}}}}' \
  | INTENT_CLASSIFIER_BIN="$S" node "$H"
case "$(tail -n 1 "$LOG")" in *'"mode":"answer"'*'Answer: After the two PRs'*'Note: only then'*) ok "a question-tool answer is logged as mode answer, with its question and note";; *) bad "answer line: $(tail -n 1 "$LOG")";; esac
n1=$(lines)
printf '{"tool_name":"AskUserQuestion","session_id":"sess-a","tool_input":{"questions":[]},"tool_response":{"answers":{}}}' | INTENT_CLASSIFIER_BIN="$S" node "$H"
[ "$n1" = "$(lines)" ] && ok "a question-tool call without answers logs nothing" || bad "empty answers wrote a line"

for p in '<task-notification>\n<task-id>x</task-id> done</task-notification>' '<cross-session-message from=\"peer\">do it</cross-session-message>'; do
  printf '{"prompt":"%s","session_id":"sess-n"}' "$p" | INTENT_CLASSIFIER_BIN="$S" node "$H"
done
[ "$n1" = "$(lines)" ] && ok "a background notice and a peer message are not classified" || bad "a notice wrote a line"

# Windows review of #594 (2026-11-18): an npm install leaves claude.cmd, which spawnSync cannot start without a shell
WB="$T/winbin"; mkdir -p "$WB/node_modules/@anthropic-ai/claude-code"; : > "$WB/claude.cmd"; : > "$WB/node_modules/@anthropic-ai/claude-code/cli.js"
r="$(node -e 'const {resolveBin}=require(process.argv[1]);const [c,a]=resolveBin("claude","win32",process.argv[2]);process.stdout.write((c===process.execPath?"node":c)+" "+a.join(" "))' "$H" "$WB")"
case "$r" in "node "*cli.js) ok "win32 npm shim: node runs the cli.js next to claude.cmd";; *) bad "win32 npm shim resolved to: $r";; esac
# Windows re-review (2026-11-18): current npm installs ship bin/claude.exe in the package, no cli.js
WB2="$T/winbin2"; mkdir -p "$WB2/node_modules/@anthropic-ai/claude-code/bin"; : > "$WB2/claude.cmd"; : > "$WB2/node_modules/@anthropic-ai/claude-code/bin/claude.exe"
r="$(node -e 'const {resolveBin}=require(process.argv[1]);process.stdout.write(String(resolveBin("claude","win32",process.argv[2])[0]))' "$H" "$WB2")"
case "$r" in *bin*claude.exe) ok "win32 npm shim: the package's native bin/claude.exe";; *) bad "win32 native shim resolved to: $r";; esac
r="$(node -e 'const {resolveBin}=require(process.argv[1]);process.stdout.write(String(resolveBin("claude","win32",process.argv[2])[0]))' "$H" "$T/empty-nowhere")"
[ "$r" = null ] && ok "win32, nothing found: null, not the bare name" || bad "win32 nothing found resolved to: $r"
: > "$WB/claude.exe"
r="$(node -e 'const {resolveBin}=require(process.argv[1]);process.stdout.write(resolveBin("claude","win32",process.argv[2])[0])' "$H" "$WB")"
case "$r" in *claude.exe) ok "win32: claude.exe on PATH wins";; *) bad "win32 exe resolved to: $r";; esac
r="$(node -e 'const {resolveBin}=require(process.argv[1]);process.stdout.write(resolveBin("claude","darwin","/nowhere")[0])' "$H")"
[ "$r" = claude ] && ok "other OS: the bare name" || bad "darwin resolved to: $r"

[ $fail -eq 0 ] && echo "intent-classifier: all passed" || echo "intent-classifier: FAILED"
exit $fail
