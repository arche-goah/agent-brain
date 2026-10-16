#!/usr/bin/env bash
# Fixture for scripts/decision-review.py: planted transcripts, one per case, plus the guards of the co-sign
# (a correction about a question is never an overreach; without the action's word it is only "unclear"; a
# compaction summary and a notification are no prompts) and a German pattern from the instance file.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/decision-review.py"
PY="$(command -v python3 || command -v python)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
# Paths that reach python as DATA are stated natively (Git Bash rewrites env/args, not file contents; OS-3).
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
ROOT="$T/brain"; TX="$T/tx"; EMPTY="$T/empty"
mkdir -p "$ROOT/.claude-state" "$ROOT/.claude/rules" "$TX" "$EMPTY"
fail=0

# gen <file> <record>... : record = p:<prompt> | q:<queued prompt> | r:<assistant text> | b:<bash command>
#                          | m:<mcp tool name> | c:<compaction summary> | n:<notification>
gen() { "$PY" -c '
import json, sys
out = open(sys.argv[1], "w", encoding="utf-8")
for a in sys.argv[2:]:
    k, v = a[:1], a[2:]
    if k == "p": r = {"type": "user", "message": {"role": "user", "content": v}}
    elif k == "q": r = {"type": "attachment", "attachment": {"type": "queued_command", "prompt": v}}
    elif k == "n": r = {"type": "user", "message": {"role": "user", "content": "<task-notification>" + v + "</task-notification>"}}
    elif k == "c": r = {"type": "user", "isCompactSummary": True, "message": {"role": "user", "content": "This session is being continued from a previous conversation. " + v}}
    elif k == "r": r = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": v}]}}
    elif k == "b": r = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Bash", "input": {"command": v}}]}}
    elif k == "m": r = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": v, "input": {}}]}}
    out.write(json.dumps(r) + "\n")
' "$@"; }

gen "$TX/s-needed.jsonl"    "p:build it" "r:Done. Shall I tag the release now or wait for the review?" "p:wait for the review"
gen "$TX/s-unneeded.jsonl"  "p:fix it" "r:Fixed. Shall I commit the fix?" "p:just do it, why do you ask"
gen "$TX/s-overreach.jsonl" "p:look at the branch" "b:git push origin main" "r:Pushed." "p:why did you not ask before the push?"
gen "$TX/s-unclear.jsonl"   "p:check the PR" "b:gh pr merge 5 --squash" "r:Done." "p:why did you not ask me?"
gen "$TX/s-qguard.jsonl"    "p:prepare it" "b:git push origin feat/x" "r:Pushed the branch. Shall I open the PR?" "p:why do you ask, just do it - why did you not ask is not the point"
gen "$TX/s-noaction.jsonl"  "p:what is the state" "r:All green." "p:why did you not ask the workstation first?"
gen "$TX/s-referral.jsonl"  "p:settle it with the other AI" "r:This needs the operator's word, so I stop here." "p:needless, the two of you could have settled it"
gen "$TX/s-german.jsonl"    "p:mach weiter" "r:Fertig. Soll ich den Commit pushen?" "p:mach einfach"
gen "$TX/s-compact.jsonl"   "p:go" "b:git push" "c:the operator asked why did you not ask before the push" "r:Continuing." "p:fine"
gen "$TX/s-notify.jsonl"    "p:go" "m:mcp__mikrotik__mikrotik_config_write" "n:done without asking, push complete" "r:Written." "q:looks good"
# Windows co-sign finding 2: the correction comes four prompts later, queued mid-turn, and names the referral
gen "$TX/s-late.jsonl"      "p:settle the settings with the other AI" "r:A human has to enter the settings change." \
                            "p:next" "r:ok" "p:next" "r:ok" "p:next" "r:ok" \
                            "q:you recommended asking the human although communication was possible - needless"
# a correction that names the referral right after it: counted once, never twice
gen "$TX/s-once.jsonl"      "p:clear it" "r:This needs the operator's word." "r:Earlier: a human must decide this." \
                            "p:needless - you recommended asking the human, communication was possible"
"$PY" -c '
import json, sys
json.dump({"a1": {"q": "Shall I tag the release now or wait for the review?", "session": "s-needed", "status": "answered"},
           "a2": {"q": "Shall I commit the fix?", "session": "s-unneeded", "status": "answered"},
           "a3": {"q": "Shall I open the PR?", "session": "s-qguard", "status": "answered"},
           "a4": {"q": "Soll ich den Commit pushen?", "session": "s-german", "status": "answered"}},
          open(sys.argv[1], "w"))' "$ROOT/.claude-state/open-questions.json"
printf '{"unneeded": ["mach (es |das )?einfach"]}\n' > "$ROOT/.claude/rules/decision-review.json"

NR="$(native "$ROOT")"; NTX="$(native "$TX")"
OUT="$("$PY" "$S" --root "$NR" --dir "$NTX" --json)"
check() { # $1 name, $2 python expression over d (the --json result)
  if printf '%s' "$OUT" | "$PY" -c "import json,sys; d=json.load(sys.stdin); n=d['numbers']; c=d['candidates']; sys.exit(0 if ($2) else 1)"; then
    echo "  OK   $1"; else echo "  FAIL $1"; fail=1; fi
}
case_of() { printf "[x['case'] for x in c if x['transcript']=='%s.jsonl']" "$1"; }
check "twelve sessions read"                       "n['sessions'] == 12"
check "needed question counted"                    "n['questions'] == 4"
check "needless question (English)"                "'unneeded' in $(case_of s-unneeded)"
check "needless question (German, instance data)"  "'unneeded' in $(case_of s-german)"
check "overreach names the action"                 "$(case_of s-overreach) == ['overreach']"
check "correction without the action word: unclear" "$(case_of s-unclear) == ['unclear']"
check "correction about a question: no overreach"  "'overreach' not in $(case_of s-qguard) and 'unclear' not in $(case_of s-qguard)"
check "correction without an action: nothing"      "$(case_of s-noaction) == []"
check "needless referral (case 3b)"                "$(case_of s-referral) == ['referral']"
check "compaction summary is no prompt"            "$(case_of s-compact) == []"
check "notification is no prompt, queued prompt is" "$(case_of s-notify) == []"
check "late referral found four prompts later"     "$(case_of s-late) == ['referral'] and any('3 prompt(s) later' in x['reply'] for x in c if x['transcript']=='s-late.jsonl')"
check "referral named right away: counted once"    "$(case_of s-once) == ['referral']"
check "totals"                                   "n['unneeded'] == 3 and n['overreach'] == 1 and n['unclear'] == 1 and n['referral'] == 3"
check "MCP write tool counts as an action"         "n['self'] >= 3"

# Windows co-sign finding 1: the cache holds verdicts, so a pattern change must reach transcripts already seen
printf '{"unneeded": ["mach (es |das )?einfach", "^wait for the review$"]}\n' > "$ROOT/.claude/rules/decision-review.json"
U="$("$PY" "$S" --root "$NR" --dir "$NTX" --numbers | "$PY" -c "import json,sys; print(json.load(sys.stdin)['unneeded'])")"
[ "$U" = "4" ] && echo "  OK   a pattern change reaches cached transcripts" || { echo "  FAIL cached verdict survived a pattern change (unneeded=$U)"; fail=1; }
printf '{"unneeded": ["mach (es |das )?einfach"]}\n' > "$ROOT/.claude/rules/decision-review.json"

# corrections: the share of prompts that correct the AI (built-in English + instance words), in its own window
TC="$T/txc"; mkdir -p "$TC"
gen "$TC/s-corr.jsonl" "p:build the window" "r:Built." "p:that's not what I asked" "r:Rebuilt." "p:schon wieder falsch" "r:Fixed." "p:fine, thanks" \
    "p:<cross-session-message from=\"x\">why did you push again?</cross-session-message>" "p:<bash-stdout>that's wrong</bash-stdout>"
printf '{"unneeded": ["mach (es |das )?einfach"], "correction": ["schon wieder"]}\n' > "$ROOT/.claude/rules/decision-review.json"
CR="$("$PY" "$S" --root "$NR" --dir "$(native "$TC")" --numbers | "$PY" -c "import json,sys; n=json.load(sys.stdin); print(n['corrections'], n['prompts'], n['correction_rate'])")"
[ "$CR" = "2 4 0.5" ] && echo "  OK   corrections counted per prompt (built-in + instance word)" || { echo "  FAIL corrections: '$CR'"; fail=1; }
printf '{"unneeded": ["mach (es |das )?einfach"]}\n' > "$ROOT/.claude/rules/decision-review.json"

# --numbers carries counts only, never a sentence
NUM="$("$PY" "$S" --root "$NR" --dir "$NTX" --numbers)"
if printf '%s' "$NUM" | grep -q "push\|Shall"; then echo "  FAIL --numbers leaks text"; fail=1; else echo "  OK   --numbers carries counts only"; fi

# verdicts: two confirmed overreach of one group make a proposal, one does not
ID="$(printf '%s' "$OUT" | "$PY" -c "import json,sys; print([x['id'] for x in json.load(sys.stdin)['candidates'] if x['case']=='overreach'][0])")"
"$PY" "$S" --root "$NR" --confirm "$ID" >/dev/null
P1="$("$PY" "$S" --root "$NR" --dir "$NTX" --json | "$PY" -c "import json,sys; print(len(json.load(sys.stdin)['proposals']))")"
[ "$P1" = "0" ] && echo "  OK   one confirmed candidate is no proposal" || { echo "  FAIL one confirmed made a proposal"; fail=1; }
gen "$TX/s-overreach2.jsonl" "p:look" "b:git -C /x push" "r:Pushed." "p:why did you not ask before you push?"
ID2="$("$PY" "$S" --root "$NR" --dir "$NTX" --json | "$PY" -c "import json,sys; print([x['id'] for x in json.load(sys.stdin)['candidates'] if x['case']=='overreach' and x['transcript']=='s-overreach2.jsonl'][0])")"
"$PY" "$S" --root "$NR" --confirm "$ID2" >/dev/null
P2="$("$PY" "$S" --root "$NR" --dir "$NTX" --json | "$PY" -c "import json,sys; p=json.load(sys.stdin)['proposals']; print(p[0]['group'] if p else '')")"
[ "$P2" = "git push" ] && echo "  OK   two confirmed of one group make a proposal" || { echo "  FAIL proposal: '$P2'"; fail=1; }

# empty window and a missing directory: a report, exit 0
"$PY" "$S" --root "$NR" --dir "$(native "$EMPTY")" | grep -q "no transcripts" && echo "  OK   empty directory reported" || { echo "  FAIL empty directory"; fail=1; }
"$PY" "$S" --root "$NR" --dir "$(native "$T/missing")" >/dev/null; [ $? -eq 0 ] && echo "  OK   missing directory exits 0" || { echo "  FAIL missing directory"; fail=1; }

echo
[ "$fail" -eq 0 ] && echo "decision-review: all checks passed" || echo "decision-review: FAILURES"
exit "$fail"
