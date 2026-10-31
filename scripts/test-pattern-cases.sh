#!/usr/bin/env bash
# covers: pattern-cases
# Fixture for scripts/pattern-cases.py — a brain's own pattern data run through the core reader.
# Both directions: a case that passes, a case that fails, a known file without `_cases` (a finding,
# not a failure), an unknown pattern file (listed, not failed), a broken file (a failure), and the
# 2026-10-28 regression: an on-pattern with a lookahead that skips an on-word inside a question
# makes the question-tool "yes" set nothing — the expected-autonomous case must FAIL with that data
# and pass once the data is fixed. Last: a failing case reaches the brain-check brief, the
# session-start report.
# Usage: bash scripts/test-pattern-cases.sh   (exit 0 = pass)
set -u
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/pattern-cases.py"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK  $1"; }
bad() { echo "  FAIL $1"; fail=1; }
# OS-3: python and node open these paths; a Git-Bash /tmp path would not resolve on Windows.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
brain() { mkdir -p "$T/$1/.claude/rules"; printf %s "$T/$1"; }
put() { printf '%s\n' "$3" > "$T/$1/.claude/rules/$2"; }

run() { # $1 brain -> sets OUT and RC
  OUT="$("$PY" "$R" "$(native "$T/$1")" 2>&1)"; RC=$?
}
has() { case "$OUT" in *"$2"*) ok "$1";; *) bad "$1: '$2' not in output:"; printf '%s\n' "$OUT" | sed 's/^/       /';; esac; }
rc() { [ "$RC" = "$2" ] && ok "$1 (exit $2)" || bad "$1: expected exit $2, got $RC"; }

# --- a case that passes, both verdicts, on an instance word the built-ins do not know
brain pass >/dev/null
put pass condition-patterns.json '{"condition_patterns": ["\\bthereupon\\b"],
 "_cases": [{"text": "merge it, thereupon tag the release", "expect": "block"},
            {"text": "merge it now", "expect": "allow"}]}'
run pass
has "passing cases are reported" "ok  condition-patterns.json: 2 case(s) pass"
rc "passing cases" 0

# --- a case that fails: the instance word is missing from the data
brain miss >/dev/null
put miss condition-patterns.json '{"condition_patterns": [],
 "_cases": [{"text": "merge it, thereupon tag the release", "expect": "block"}]}'
run miss
has "a failing case names expected and measured verdict" "case 1: expected block, conditional-order-gate.cjs says allow"
rc "a failing case" 1

# --- a known file without _cases: a finding, never a failure; an unknown file: listed
brain nocases >/dev/null
put nocases premise-patterns.json '{"generalisation_patterns": []}'
put nocases own-hook-patterns.json '{"patterns": []}'
run nocases
has "a known file without _cases is a finding" "--  premise-patterns.json: no _cases"
has "an unknown pattern file is listed" "..  own-hook-patterns.json: no core reader known"
rc "a file without _cases does not fail" 0

# --- a known file that is not JSON: the reader would fall back to its built-ins in silence
brain broken >/dev/null
put broken stop-patterns.json '{"patterns": [,]}'
run broken
has "broken JSON is named" "stop-patterns.json: not valid JSON"
rc "broken JSON fails" 1

# --- a malformed case is a failure, not a silent skip
brain form >/dev/null
put form promise-patterns.json '{"_cases": [{"text": "I will not push until you are back."}]}'
run form
has "a case without expect is malformed" "case 1: malformed"
rc "a malformed case fails" 1

# --- every reader in the table runs (English built-ins, empty instance lists)
brain all >/dev/null
put all root-cause-patterns.json '{"_cases": [{"text": "why did you ask that again?", "expect": "block"},
 {"text": "why did you ask that again?", "reply": "Cause: the record was stale.", "expect": "block"},
 {"text": "how is the show going?", "expect": "allow"}]}'
put all premise-patterns.json '{"_cases": [{"text": "The last one always wins.", "expect": "block"},
 {"text": "The last one always wins.", "writes": false, "expect": "allow"}]}'
put all promise-patterns.json '{"_cases": [{"text": "I will not push until you are back.", "expect": "block"},
 {"text": "I will not push.", "expect": "allow"}]}'
put all stop-patterns.json '{"_cases": [{"text": "The fix is ready. Shall I merge it?", "expect": "block"},
 {"text": "The fix is merged.", "expect": "allow"}]}'
put all secret-patterns.json '{"files": [{"id": "probe", "regex": "(?:^|/)probe\\.txt$"}],
 "_cases": [{"text": "cat .env", "expect": "block"}, {"text": "data/probe.txt", "tool": "Read", "expect": "block"},
            {"text": "ls data", "expect": "allow"}]}'
run all
for f in root-cause premise promise stop secret; do has "$f reader runs" "ok  $f-patterns.json"; done
rc "all readers" 0

# --- the shipped templates: a new brain starts with cases that pass against the core's readers
brain tpl >/dev/null
for f in "$HERE"/../templates/rules-instance/*-patterns.json; do cp "$f" "$T/tpl/.claude/rules/"; done
run tpl
has "template cases pass (all three templates carry cases)" "in 3 file(s), 0 failed; 0 known file(s) without _cases"
rc "templates" 0

# --- the 2026-10-28 regression: the answer path of the autonomous latch
SEQ='"_cases": [{"steps": ["work through the list solo"], "expect": "autonomous"},
 {"steps": ["work through the list solo", "anything open for me?",
            {"q": "Continue solo?", "a": "Yes, continue"}], "expect": "autonomous"},
 {"steps": ["work through the list solo", "anything open for me?"], "expect": "interactive"}]'
brain lookahead >/dev/null
put lookahead autonomous-patterns.json "{\"on_patterns\": [\"\\\\bsolo\\\\b(?![^.!?]{0,30}\\\\?)\"], $SEQ}"
run lookahead
has "lookahead data: the question-tool yes sets nothing" "case 2: expected autonomous, autonomous-mode.cjs says interactive"
case "$OUT" in *"case 1:"*|*"case 3:"*) bad "lookahead data: only the answer path may fail";; *) ok "lookahead data: the prompt path still works";; esac
rc "lookahead data fails" 1
brain fixed >/dev/null
put fixed autonomous-patterns.json "{\"on_patterns\": [\"\\\\bsolo\\\\b\"], $SEQ}"
run fixed
has "fixed data: all three cases pass" "ok  autonomous-patterns.json: 3 case(s) pass"
rc "fixed data passes" 0

# --- the session-start report: a failing case reaches the brain-check brief
B="$T/lookahead"
BRIEF="$(CLAUDE_PROJECT_DIR="$B" CACHED_VERDICT_STATE="$T/verdict" BRAIN_SELFTEST_BG= bash "$HERE/brain-check.sh" --brief 2>&1)"
case "$BRIEF" in
  *"!!  pattern-cases"*"case 2: expected autonomous"*) ok "the brief names the failing case";;
  *) bad "the brief does not carry the failing case:"; printf '%s\n' "$BRIEF" | sed 's/^/       /';;
esac

echo
[ "$fail" -eq 0 ] && echo "pattern-cases fixtures: ALL passed" || { echo "pattern-cases fixtures: FAILURE"; exit 1; }
