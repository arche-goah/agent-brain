#!/usr/bin/env bash
# Fixture test for the stoppen-gate — both directions, plus the language-as-data
# contract (T3, operator order 2026-08-19): engine built-ins are English, and EVERY
# other language grips only via the instance file .claude/rules/stop-patterns.json —
# German (the full pack, written below; this file is its reference copy) and Czech
# prove it in temp cwds, and German without the file must pass, which is what shows the
# engine carries no language of its own. Negative control discipline: run after every
# stoppen-gate or pattern-data change. Usage: bash scripts/test-stoppen-gate.sh
# (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
# In the core the helpers live one level up in helpers/; an instance that still carries
# its own copy under scripts/hooks/ keeps working, because the fallback is checked.
_D="$(cd "$(dirname "$0")" && pwd)"
G="$_D/../helpers/stoppen-gate.cjs"
[ -f "$G" ] || G="$_D/hooks/stoppen-gate.cjs"
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }

# OS-3: the transcript and cwd below go into a JSON field that NODE opens. A Git-Bash
# `/tmp/...` path does not resolve for a native process, so the hook would read an empty
# transcript and every must-block case would pass for the wrong reason — green, and
# measuring nothing. Same helper the other fixtures carry.
native() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi
}

run_case() { # $1 name, $2 assistant text (JSON string), $3 expect: block|allow, $4 cwd
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$2" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
          "$(native "$tr")" "$(native "$4")" | node "$G" 2>&1)"
  if [ "$3" = "block" ]; then
    case "$out" in *"STOPPEN-GATE"*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}

# A cwd with NO instance pattern file: these cases must be carried by the built-ins
# alone, which is the whole point of moving the class fix into the core. (It used to be
# a hard-coded home path — instance data in a core fixture, and a leak-scan finding.)
CWD="$T/cwd-builtins"
mkdir -p "$CWD"

# The German pack as an instance would carry it. Moved verbatim out of the engine's
# former inline LANGUAGE_PACK_DE; an instance that relied on the inline pack copies this
# JSON to its .claude/rules/stop-patterns.json.
DE="$T/cwd-de"
mkdir -p "$DE/.claude/rules"
printf '%s\n' '{"patterns": [
  "\\bsoll ich\\b[^?\\n]{0,140}\\?",
  "\\bsollen wir\\b[^?\\n]{0,140}\\?",
  "\\bm(ö|oe)chtest du,? dass ich\\b[^?\\n]{0,140}\\?",
  "\\bwillst du,? dass ich\\b[^?\\n]{0,140}\\?",
  "\\bdarf ich\\b[^?\\n]{0,140}\\?",
  "\\bwomit (soll ich )?(weitermachen|starten|anfangen|beginnen)\\b[^?\\n]{0,60}\\?",
  "\\b(weitermachen|fortfahren)\\?",
  "\\bsag (mir )?(bitte )?bescheid\\b[^.\\n]{0,80}[.!]",
  "\\bgib (mir )?(bitte )?bescheid\\b[^.\\n]{0,80}[.!]",
  "\\bmelde dich\\b[^.\\n]{0,80}[.!]",
  "\\b(liegt|liegen) (jetzt |damit |weiterhin )?(bei|beim) (dir|euch|ihm|ihr|kollegen|dem kollegen|der workstation|workstation)\\b",
  "\\bwenn du (willst|magst|moechtest|möchtest),? (dann )?(mache|baue|nehme|schreibe) ich\\b",
  "\\bzwei wege\\b[^.\\n]{0,120}\\boder\\b[^.\\n]{0,120}[.!]"
], "announce_patterns": [
  "\\b(mache|baue|pruefe|prüfe|schreibe|lese|teste|starte) (ich )?(das |es |sie |ihn |den |die )?(jetzt|gleich|als n(ä|ae)chstes)\\b",
  "\\b(arbeite|mache) (ich )?weiter\\b",
  "\\bweiter (laut|mit|am|an der)\\b",
  "\\bals n(ä|ae)chstes (kommt|mache|baue|pruefe|prüfe|gehe)\\b"
], "announce_condition_patterns": [
  "\\b(sobald|wenn|nachdem|bis|falls)\\b"
]}' > "$DE/.claude/rules/stop-patterns.json"

# Like run_case, with JSONL records of the running turn BEFORE the final text ($5).
run_case_turn() { # $1 name, $2 final text (JSON string), $3 expect, $4 cwd, $5 records
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$tr"
  printf '%s\n' "$5" >> "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$2" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":false,"cwd":"%s"}' \
          "$(native "$tr")" "$(native "$4")" | node "$G" 2>&1)"
  if [ "$3" = "block" ]; then
    case "$out" in *"STOPPEN-GATE"*) ok "$1 blocks";; *) bad "$1 did not block: '$out'";; esac
  else
    [ -z "$out" ] && ok "$1 allows" || bad "$1 blocked wrongly: '$out'"
  fi
}

# German via the instance file
run_case de-soll-ich '"Bericht fertig. Soll ich das jetzt umsetzen?"' block "$DE"
run_case de-womit '"Alles erledigt. Womit weitermachen?"' block "$DE"
run_case de-darf-ich '"Der Plan steht. Darf ich die Datei anlegen?"' block "$DE"
# The engine carries no German: the same sentence WITHOUT the instance file passes. This
# is the direction that fails if a language pack creeps back into the built-ins.
run_case de-no-pack '"Bericht fertig. Soll ich das jetzt umsetzen?"' allow "$CWD"
# English engine built-ins
run_case en-proceed '"The fix is ready. Should I proceed with the merge?"' block "$CWD"
run_case en-want-me '"Tests are green. Do you want me to tag the release?"' block "$CWD"
# English built-ins still grip with a language file present (merge, not replace)
run_case en-with-pack '"Tests are green. Do you want me to tag the release?"' block "$DE"
# Negative direction
run_case clean '"Erledigt und verifiziert, Messwert im Log. Bericht folgt unten."' allow "$DE"
run_case quoted '"Die Regel verbietet Schlussfragen wie \"soll ich weitermachen?\" am Turn-Ende."' allow "$DE"
run_case option-q '"Offene Frage an Alex: welcher Kanal ist gemeint?"' allow "$DE"

# Language-as-data contract: a Czech pattern in the instance file must grip
# identically — no code change, same key (T3: examples are EXAMPLES).
mkdir -p "$T/cwd-cs/.claude/rules"
printf '%s\n' '{"patterns": ["\\bm(á|a)m\\b[^?\\n]{0,140}\\?"]}' > "$T/cwd-cs/.claude/rules/stop-patterns.json"
# --- the HANDOFF shape: a stop that never asks a question ------------------------
# Measured 2026-08-31, four times in one day. Every deferral ended in a STATEMENT, so
# every question-shaped pattern above missed it, while the three-condition test said the
# work was mine. The sentences below are verbatim from that day, not invented.
run_case handoff-bescheid \
  '"Nehme ich mir; sag Bescheid, falls du schon dran bist."' block "$DE"
run_case handoff-liegt-bei \
  '"Die Klasse bleibt offen. Der Fix liegt beim Kollegen."' block "$DE"
run_case handoff-zwei-wege \
  '"Zwei Wege: umbenennen und die Gefahr ist weg, oder warten auf den Kern-Fix."' block "$DE"
run_case handoff-yours \
  '"portability-smoke green, leak-scan 0. Yours to merge or to shred."' block "$CWD"
run_case handoff-tell-me \
  '"The negative control is measured. Tell me which side takes it."' block "$CWD"
# NEGATIVE: a real operator gate, correctly STATED rather than asked, must pass. This is
# the sentence the rule wants — naming a boundary is not handing work over.
run_case gate-stated \
  '"Release bleibt gesperrt. Pin auf v1.3.25, Bedingung ist deine Unterschrift."' allow "$DE"
run_case report-plain \
  '"brain-check: 22 Fixtures gruen, 0 ohne Wirkungsnachweis, 0 ohne Ausloeser."' allow "$DE"

# --- the ANNOUNCEMENT shape: the turn ends on "doing it now" and nothing runs ---------
# Measured 2026-10-11, the German sentences are verbatim from that session.
BG='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_bg1","name":"Bash","input":{"command":"x","run_in_background":true}}]}}'
END='{"message":{"role":"user","content":"<task-notification>\n<task-id>b1</task-id>\n<tool-use-id>toolu_bg1</tool-use-id>\n<status>completed</status>\n</task-notification>"}}'
MON='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_m1","name":"Monitor","input":{"command":"x"}}]}}'
WAKE='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_w1","name":"ScheduleWakeup","input":{"delaySeconds":600}}]}}'
FG='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_f1","name":"Bash","input":{"command":"x"}}]}}'
run_case en-announce '"Tests are green. Next, I will write the Windows request."' block "$CWD"
run_case en-announce-now '"The fixture passes. Doing that now."' block "$CWD"
run_case de-announce-mache '"Gate gefixt. Mache das jetzt, dann die Windows-Pruefbitte."' block "$DE"
run_case de-announce-weiter '"Beide Hinweise geklaert. Arbeite weiter am Handoff."' block "$DE"
run_case de-announce-laut '"Bis dahin weiter laut Handoff: Gate-Test und Guard-Check."' block "$DE"
run_case de-announce-no-pack '"Beide Hinweise geklaert. Arbeite weiter am Handoff."' allow "$CWD"
# A foreground tool call earlier in the turn does not make the closing announcement true.
run_case_turn de-announce-after-fg '"Gemessen. Als Naechstes kommt die Memory-Sicherung."' block "$DE" "$FG"
# NEGATIVE: a running waiter is what the announcement waits for.
run_case_turn waiter-bash-live '"CI laeuft. Mache das jetzt, sobald sie gruen ist."' allow "$DE" "$BG"
run_case_turn waiter-monitor-live '"Watcher scharf. Once it reports, I will read the answer."' allow "$CWD" "$MON"
run_case_turn waiter-wakeup '"Wakeup gesetzt. Arbeite weiter, sobald er feuert."' allow "$DE" "$WAKE"
# A Workflow always runs in the background; an Agent counts only when started in the
# background (review finding from the Windows instance).
WF='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_wf1","name":"Workflow","input":{"name":"x"}}]}}'
AGBG='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a1","name":"Agent","input":{"prompt":"x","run_in_background":true}}]}}'
AGFG='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a2","name":"Agent","input":{"prompt":"x"}}]}}'
run_case_turn waiter-workflow-live '"Scan laeuft. Once it is done, I will read its report."' allow "$CWD" "$WF"
run_case_turn waiter-agent-bg-live '"Agent laeuft. Once it is done, I will read its report."' allow "$CWD" "$AGBG"
run_case_turn agent-fg-no-waiter '"Agent fertig. Next, I will read its report."' block "$CWD" "$AGFG"
# The real flag arrives as the STRING "true" on 2.1.295 (measured, 5 of 6 Agent calls) ...
AGSTR='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a3","name":"Agent","input":{"prompt":"x","run_in_background":"true"}}]}}'
run_case_turn waiter-agent-bg-string-live '"Agent laeuft. Once it is done, I will read its report."' allow "$CWD" "$AGSTR"
# ... and since 2.1.296 there is no flag at all: the launch RESULT says the agent runs async.
AGASYNC="$AGFG
"'{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a2","content":[{"type":"text","text":"Async agent launched successfully. The agent is working in the background."}]}]}}'
run_case_turn waiter-agent-async-result-live '"Agent laeuft. Once it is done, I will read its report."' allow "$CWD" "$AGASYNC"
# NEGATIVE: a sync Agent returns its report as the tool result — foreground, no waiter.
AGSYNC="$AGFG
"'{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a2","content":[{"type":"text","text":"Report: three files checked, all clean."}]}]}}'
run_case_turn agent-sync-result-no-waiter '"Agent fertig. Next, I will read its report."' block "$CWD" "$AGSYNC"
# A running waiter excuses only an announcement that says it waits for it (measured
# 2026-10-18: "the review — I do that next" passed because unrelated watchers were running).
run_case_turn waiter-unrelated-de '"Fuer #6 bittet er um ein Review, das mache ich als Naechstes."' block "$DE" "$MON"
run_case_turn waiter-unrelated-en '"Watcher armed. Next, I will review PR 6."' block "$CWD" "$MON"
run_case_turn waiter-unrelated-wakeup '"Wakeup gesetzt. Arbeite weiter in zehn Minuten."' block "$DE" "$WAKE"
# ...but a waiter that already reported its end waits for nothing.
run_case_turn waiter-ended '"CI gruen. Arbeite weiter am Handoff."' block "$DE" "$BG
$END"
run_case de-done '"Erledigt und committet, Test gruen."' allow "$DE"
run_case announce-quoted '"Die Regel trifft Saetze wie \"arbeite weiter am Handoff\" am Zugende."' allow "$DE"

run_case cs-mam '"Hotovo. Mám to teď nasadit?"' block "$T/cwd-cs"
run_case cs-clean '"Hotovo a ověřeno, výsledek je v logu."' allow "$T/cwd-cs"

# --- an operator DECISION goes through the question tool, not closing prose ---------------
# Operator order 2026-10-15 (Windows instance): after a report ended on a prose list of things
# that needed his word, he asked for "a clean question"; once three decisions came to him
# through AskUserQuestion he ordered that form for every operator decision. A re-issue of the
# prose question no longer passes by repetition; after two blocks in one turn it is let
# through LOUDLY (systemMessage), so a stuck session is never locked.
run_gate() { # $1 name, $2 final text (JSON), $3 block|allow|loud, $4 cwd, $5 records, $6 stop_hook_active, $7 must appear
  local tr="$T/$1.jsonl"
  printf '%s\n' '{"message":{"role":"user","content":"frage"}}' > "$tr"
  [ -n "$5" ] && printf '%s\n' "$5" >> "$tr"
  printf '{"message":{"role":"assistant","content":[{"type":"text","text":%s}]}}\n' "$2" >> "$tr"
  local out
  out="$(printf '{"transcript_path":"%s","stop_hook_active":%s,"cwd":"%s"}' \
          "$(native "$tr")" "$6" "$(native "$4")" | node "$G" 2>&1)"
  case "$3" in
    block) case "$out" in *'"decision":"block"'*STOPPEN-GATE*) ;; *) bad "$1 did not block: '$out'"; return;; esac ;;
    loud)  case "$out" in *'"decision"'*|'') bad "$1 not a loud let-through: '$out'"; return;; *systemMessage*) ;; *) bad "$1 no systemMessage: '$out'"; return;; esac ;;
    allow) [ -z "$out" ] || { bad "$1 blocked wrongly: '$out'"; return; } ;;
  esac
  if [ -n "${7:-}" ]; then
    case "$out" in *"$7"*) ;; *) bad "$1: output lacks '$7': '$out'"; return;; esac
  fi
  case "$3" in block) ok "$1 blocks";; loud) ok "$1 lets through loudly";; allow) ok "$1 allows";; esac
}
DQ='"The fix is ready. Should I proceed with the merge?"'
ASKQ='{"message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_q1","name":"AskUserQuestion","input":{"questions":[{"question":"Merge the fix now?","options":[{"label":"Merge now (Recommended)"},{"label":"Wait"}]}]}}]}}
{"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_q1","content":"User answered: Merge now"}]}}'
PRIOR='{"message":{"role":"assistant","content":[{"type":"text","text":"The fix is ready. Should I proceed with the merge?"}]}}'
ECHO_OWN='{"message":{"role":"user","content":"Stop hook feedback:\nCLOSING QUESTION — Closing question \"Should I proceed with the merge?\" - if only the operator can decide it, ask it through the question tool   [STOPPEN-GATE]"}}'
ECHO_OTHER='{"message":{"role":"user","content":"Stop hook feedback:\nCLASS — gate.cjs changed - does the same defect exist anywhere else?   [CLASS-GATE]"}}'
ONE_BLOCK="$PRIOR
$ECHO_OWN"
TWO_BLOCKS="$PRIOR
$ECHO_OWN
$PRIOR
$ECHO_OWN"
# planted: the prose decision question blocks and names the tool
run_gate ask-prose-no-tool "$DQ" block "$CWD" "" false "question tool (AskUserQuestion)"
# the same closing prose in a turn that DID call the tool passes
run_gate ask-through-tool "$DQ" allow "$CWD" "$ASKQ" false
# the tool is missing here and the reply says so in its one line
run_gate ask-no-tool-line '"⚙ no question tool: this run is headless.\nThe fix is ready. Should I proceed with the merge?"' allow "$CWD" "" false
# re-issue without tool and without the line: still blocks, in full (no dispatcher compression line)
run_gate ask-reissue-blocks "$DQ" block "$CWD" "$ONE_BLOCK" true "re-issuing it unchanged does not pass"
# third issue in the same turn: let through, loudly
run_gate ask-third-issue-loud "$DQ" loud "$CWD" "$TWO_BLOCKS" true "without AskUserQuestion"
# the re-issue that called the tool, or carries the line, passes
run_gate ask-reissue-with-tool "$DQ" allow "$CWD" "$ONE_BLOCK
$ASKQ" true
run_gate ask-reissue-no-tool-line '"⚙ no question tool: scheduled run.\nShould I proceed with the merge?"' allow "$CWD" "$ONE_BLOCK" true
# unchanged: a re-issue after ANOTHER gate's block passes as it always did
run_gate reissue-after-other-gate "$DQ" allow "$CWD" "$PRIOR
$ECHO_OTHER" true
# unchanged: a clarification that is no permission handback is not judged
run_gate clarification-question '"Two log files match. Which of them did you mean, the old or the new one?"' allow "$CWD" "" false
# unchanged: the German pack grips the same way through the instance file
run_gate de-ask-reissue-blocks '"Bericht fertig. Soll ich das jetzt umsetzen?"' block "$DE" '{"message":{"role":"assistant","content":[{"type":"text","text":"Bericht fertig. Soll ich das jetzt umsetzen?"}]}}
'"$ECHO_OWN" true "question tool"
# NEGATIVE CONTROL: a turn with the tool call and an unrelated prose question still passes
run_gate tool-plus-unrelated-question '"Merged as chosen. Do you want me to tidy the old branch as well?"' allow "$CWD" "$ASKQ" false
# ... but asking is not doing: an announcement after the tool call is still judged
run_gate tool-then-announcement '"Merge chosen. Doing that now."' block "$CWD" "$ASKQ" false

echo
[ "$fail" -eq 0 ] && echo "stoppen-gate fixtures (incl. language-as-data): ALL passed" || echo "FAILURE"
exit "$fail"
