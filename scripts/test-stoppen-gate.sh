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
]}' > "$DE/.claude/rules/stop-patterns.json"

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

run_case cs-mam '"Hotovo. Mám to teď nasadit?"' block "$T/cwd-cs"
run_case cs-clean '"Hotovo a ověřeno, výsledek je v logu."' allow "$T/cwd-cs"

echo
[ "$fail" -eq 0 ] && echo "stoppen-gate fixtures (incl. language-as-data): ALL passed" || echo "FAILURE"
exit "$fail"
