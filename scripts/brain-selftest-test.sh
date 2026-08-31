#!/usr/bin/env bash
# covers: brain-selftest (the "executables nothing calls" detector)
#
# The detector decides whether a script is WIRED, and it decides it by looking for the
# script's name in a set of directories. Every bug it has had is a blind spot in that
# lookup: a directory it never walks, a line it counts that is only prose, a file whose
# own explanation names the thing it is judging. All three are invisible in the output —
# the report reads identically whether a script is genuinely unwired or merely unseen.
#
# So the fixture is built around one synthetic brain whose ANSWER IS KNOWN, and both
# directions are asserted: a script that IS invoked must disappear from the list, and a
# script that is only TALKED ABOUT must stay on it. The second half carries the weight;
# the first can be satisfied by a detector that reports nothing at all.
#
# Run: bash scripts/brain-selftest-test.sh    Exit 0 = all green.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fails=0
ok()  { echo "  OK   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }

# --- a synthetic brain with four executables and a known verdict ---------------
mkdir -p "$TMP/brain/scripts" "$TMP/brain/.github/workflows" "$TMP/brain/docs"
cd "$TMP/brain" || exit 1

for s in called-by-ci run-by-a-script only-documented named-in-a-comment; do
  printf '#!/usr/bin/env bash\necho %s\n' "$s" > "scripts/$s.sh"
done

# The wiring, one shape each.
cat > .github/workflows/ci.yml <<'YML'
name: ci
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      # this comment mentions scripts/named-in-a-comment.sh and must NOT count
      - run: bash scripts/called-by-ci.sh
YML

printf '#!/usr/bin/env bash\nbash scripts/run-by-a-script.sh\n' > scripts/caller.sh
printf 'The file scripts/only-documented.sh exists and is described here.\n' > docs/notes.md

# A hand tool wearing a fixture's name. The runner globs by name shape, so without a
# contract it EXECUTES this; on a real instance the equivalent script queried physical
# network hardware and the self-test looked hung rather than failed. The marker file is
# how we detect execution: if the guard fails, the script runs and writes it.
mkdir -p "$TMP/brain/.claude/rules"
printf '{ "manual": ["danger-test.sh"] }\n' > "$TMP/brain/.claude/rules/manual-tools.json"
printf '#!/usr/bin/env bash\ntouch "%s/EXECUTED"\nexit 0\n' "$TMP" \
  > "$TMP/brain/scripts/danger-test.sh"

report="$TMP/out.txt"
bash "$HERE/brain-selftest.sh" "$TMP/brain" > "$report" 2>&1

section=$(sed -n '/executables nothing calls/,/without a trigger;/p' "$report")
if [[ -z "$section" ]]; then
  bad "the detector printed no section at all — nothing below was measured"
  sed 's/^/       /' "$report"
  exit 1
fi
ok "detector ran and printed its section"

listed() { grep -q "scripts/$1.sh" <<<"$section"; }

# --- POSITIVE: real wiring must clear a script --------------------------------
if listed called-by-ci; then
  bad "a script invoked by a run: step in ci.yml is reported as untriggered"
else
  ok "a run: step in a workflow counts as wiring"
fi

if listed run-by-a-script; then
  bad "a script invoked from another script is reported as untriggered"
else
  ok "a call from another script counts as wiring"
fi

# --- NEGATIVE: the half that a silent detector would also pass ----------------
if listed only-documented; then
  ok "a script that is only described in docs stays on the list"
else
  bad "documentation alone cleared a script — a mention is not a call"
fi

if listed named-in-a-comment; then
  ok "a script named in a workflow COMMENT stays on the list"
else
  bad "a comment inside ci.yml cleared a script — a mention is not a call"
fi

# --- the runner honours the same list the detector honours ----------------------
# The decisive one: not "is it reported correctly" but "did it RUN". Everything else in
# this file is about a report; this is about a side effect on the world.
if [[ -e "$TMP/EXECUTED" ]]; then
  bad "a script declared in manual-tools.json was EXECUTED by the fixture runner"
else
  ok "a declared hand tool is not executed, even wearing a fixture's name"
fi
if grep -q 'danger-test — declared a hand tool' "$report"; then
  ok "and the skip is stated, not silent"
else
  bad "the hand tool was skipped without saying so — silence is not a report"
fi

# NOT asserted here, deliberately: "no comment in brain-selftest.sh names a script that
# it would thereby clear". I wrote that check and it fired on `brain-check.sh` (named in
# a comment that legitimately describes the relationship between the two) and on the
# naming SHAPES `-test.sh` / `-test.py`. It cannot separate "names a scanned script" from
# "names anything that looks like a filename", which makes it the very thing this file is
# about: a report whose two states share one symbol. The trap is real — it cost a fix in
# this same change — but a checker that cries wolf on every comment gets switched off and
# takes the four checks above with it. Left as a note until it can be stated precisely.

echo
if (( fails )); then echo "brain-selftest-test: $fails FAILURE(S)"; exit 1; fi
echo "brain-selftest-test: all 7 checks passed"
