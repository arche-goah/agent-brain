# OS trap register — agent-brain

> **Why this file exists.** CI runs on Linux. macOS is where most of this repo is
> written. Windows is where it breaks — and the breakage is silent, because the same
> code path that misbehaves there produces nothing at all to look at here: a path
> comparison that always misses reports "everything is missing", a fixture whose
> transcript cannot be read reports "the gate stayed silent", a generator that writes
> CRLF reports success. Every one of those looks like a clean run on the OS that
> cannot reproduce it.
>
> Four of these classes have now come back after being fixed once (2026-08-10,
> 2026-08-13, 2026-08-31 twice) — above the build threshold, so they get a mechanism
> rather than another single fix. This register is that mechanism: each class stated as an
> INVARIANT plus the search that spans its space, re-run automatically.
>
> **Checked by:** `python3 scripts/invariant-check.py docs/os-traps.md` — wired into
> CI (`.github/workflows/ci.yml`) and into `scripts/portability-smoke.sh`, so it runs
> on every OS the repo is used on, not only the one that can reproduce the defect.
>
> **`known` is a baseline of SITES, not of defects.** OS-2 and OS-3 count places that
> are currently correct: the point is that a NEW site appears as drift and gets read
> before it ships. Whoever adds one updates the number and says why under `note`.
> OS-1 is baselined at zero — there the pattern itself is the defect.
>
> **Adding a class:** a Windows/macOS divergence that cost a debugging session belongs
> here the moment it is understood, at instance 1 — registering is not the build
> threshold (only building a mechanism is). If no grep spans the space, say so with
> `mechanizable: no — <why>` instead of leaving the field off.

root: ..

## The three shapes behind all of these (operator order 2026-08-31)

Six entries in one day is not six unrelated bugs; it is three shapes, and naming them is
what lets a NEW instance look in the right place instead of rediscovering each one at the
cost of a session. Every entry above is an instance of exactly one:

**A · The platform reshapes a string in transit.** The value is right when written and
wrong when read, because something between the two applied a platform convention.
Members: OS-1 (path separator), OS-2 (line ending). Older, same shape: the cp1252 finding
of 2026-08-04 (encoding), the MSYS argument rewriting of `git show a:b`.
*Where to look first on a new platform:* every place a path or text crosses a boundary —
written to a file another tool reads, compared against text somebody else wrote, printed
into a report a fixture greps. The test is never "does it look right in the terminal" but
"is it byte-identical to what the other platform produces".

**B · The same command name is a different program.** Nothing is reshaped; the tool
itself behaves differently, and usually only in one branch. Members: OS-5 (`grep` decides
per stream whether it is text), OS-6 (`python3` is an install manager that honours a
shebang in an argument, while `python` on the same machine does not). Older, same shape:
`stat -c` vs `-f`, `lsof` absent, the Microsoft Store python3 stub.
*Where to look first:* every tool invoked by bare name in a REPORTING or GUARDING path.
An interpreter probe that runs `-c 'import sys'` proves the binary starts, never that it
behaves — and a guard that fails open looks exactly like a guard with nothing to say.

**C · The gate does not run where the defect lives.** Not a divergence at all: a coverage
hole that makes A and B invisible. Member: OS-4 (the OS gate carried a hand-written suite
list). *Where to look first:* anything that ENUMERATES what to check — a list of suites, a
list of directories to walk, a list of steps in CI. Every hand-kept enumeration is a second
copy of a directory and drifts silently toward "we checked everything".

**How this register is kept** — the part that has to survive this session:

1. A Mac/Windows divergence that cost a debugging session gets a block here **at instance
   1**, before it is fixed. Registering is not the build threshold; only building a
   mechanism is.
2. It is stated as an INVARIANT plus a search, never as an anecdote — and the search runs
   in CI and in `portability-smoke.sh`, so it executes on the platform that cannot
   reproduce the defect.
3. It says which of A/B/C it belongs to. If it fits none, that is the interesting case:
   name the fourth shape here rather than filing it as a one-off.
4. Baselines hold the sites that are CORRECT. The point is not a clean list, it is that a
   new site surfaces and gets read.
5. This file lives in the CORE, not in an instance register, because a platform is not a
   property of one brain. An instance's own register keeps its instance-specific classes
   and points here for platform ones.

## OS-1 — a repo-relative path leaves the program as text with the platform separator

shape: A

invariant: A path that is compared against, or written into, forward-slashed text —
markdown links, git output, a baseline file, JSON another instance reads — is stated
with `.as_posix()`. `str(p.relative_to(root))` yields backslashes on Windows, so every
such comparison misses and every such link is unfollowable.
pattern:   str\([A-Za-z_.]+\.relative_to\(|os\.path\.join\(
paths:     --include=*.py --include=*.sh scripts helpers
known:     scripts/brain-friction.py=1 scripts/brain-selftest.sh=3 scripts/brain-update.sh=7 scripts/freshness-gate-test.py=9 scripts/gate-precision.py=3 scripts/hook-coverage.py=6 scripts/memory-lint-test.py=3 scripts/shared-memory-lint.py=1 scripts/test-suite-plugin-linkage.sh=2 scripts/transcript-recall-test.py=5 helpers/session-bootup.sh=8
instances: 5
repeat:    yes
status:    closed
note:      2026-08-13 english-only.py — 100 findings on a clean tree. 2026-08-31, same
class in three more places: shared-memory-lint.py reported 143 of 143 files as missing
from the index AND every index line as pointing at a missing file; shared-memory-index.py
matched nothing against the old index and carried every existing entry into the root page
(83,205 chars instead of 1,651), writing backslashed links; leak-scan.py in its report
only. Baseline zero on purpose — after the fix there is no legitimate site, so any hit is
a new one. A PROSE mention counts as a hit — measured the same day, when a fixture
docstring describing this very defect tripped it. That is the honest trade for a grep: it
cannot tell code from a sentence about code, and weakening the pattern to spare the
sentence would spare a real site in a fixture too. Write about the class without writing
the call. Second constructor added the same day: `os.path.join()` produces the
identical defect and the first pattern could not see it — found only because the
other instance's new fixture greps a REPORT for `scripts/<name>.sh` and the detector
printed `scripts\<name>.sh`, so both its negative cases read as passes. A class is
the invariant, not the one spelling that produced it; the baseline below is now the
join sites that legitimately build a filesystem path — the baseline is no longer zero,
and the review question for a new hit is one sentence: does this string get REPORTED,
or matched against forward-slashed text? If it only ever reaches the filesystem, it is
fine and gets counted; if it reaches a reader or a comparison, it needs `as_posix()` or
a literal `/`. `.sh` is in the search because the defect was found inside a python
block embedded in a shell script, where a `*.py` search could not see it.

## OS-2 — a generator writes a git-tracked text file without pinning the line ending

shape: A

invariant: Every write of a file that git tracks pins `newline="\n"`. Python text mode
translates `\n` to the platform separator, so the same generator emits LF on macOS and
CRLF on Windows — against a `.gitattributes` that says LF the whole file reads as
changed, or git rewrites it behind the run.
pattern:   \.write_text\(
paths:     --include=*.py --exclude=*-test.py scripts helpers
known:     scripts/ecosystem-sync.py=1 scripts/english-only.py=1 scripts/os-traps-export.py=1 scripts/regen-skill-registry.py=1 scripts/shared-memory-index.py=2 scripts/shared-memory-lint.py=1
instances: 3
repeat:    yes
status:    closed
note:      Closed means no known open site, not that the class is over: the mechanism IS
this entry, and the baseline is what makes a seventh site visible. All six baselined sites
are currently CORRECT — this baseline exists so that a
seventh shows up and gets read. History: 2026-08-10 regen-skill-registry.py (12 CR lines
in a fresh REGISTRY.md) and ecosystem-sync.py (65 CR lines in a fresh ecosystem.json),
both fixed then; 2026-08-31 shared-memory-index.py shipped the same defect again (17 of 17
lines CRLF in the generated root index of the shared-memory repo) and english-only.py's
baseline writer carried it unnoticed. The pattern deliberately matches correct sites too:
"is there a new place that writes a tracked file" is the question a grep can answer, "did
the author think about line endings" is not. Proven in use the same day: the seventh site
(os-traps-export.py, which generates this register's own signpost) surfaced as drift on the
first run after it was written, was read, and was correct.

## OS-3 — a fixture hands a shell path to a native process

shape: A

invariant: A fixture that creates a temp dir and passes it into node or python as DATA
(a JSON field, an env var) states it natively via `cygpath -m`. Git Bash `/tmp/...` does
not resolve for a native process — the process reads nothing, and a gate that should
BLOCK stays silent, which the fixture cannot distinguish from a gate working correctly.
pattern:   mktemp -d
paths:     --include=test-*.sh scripts
known:     scripts/test-stoppen-gate.sh=1 scripts/test-guards.sh=2 scripts/test-premise-gate.sh=1 scripts/test-recall-gate.sh=1 scripts/test-session-helpers.sh=1 scripts/test-stop-checks.sh=1 scripts/test-stop-dispatcher.sh=2 scripts/test-suite-plugin-linkage.sh=1
instances: 3
repeat:    yes
status:    closed
note:      Closed on the same terms as OS-2 — every baselined fixture is correct today and
the baseline is the gate against the next one. test-stop-dispatcher.sh and test-premise-gate.sh carry the `native()` helper
and the comment explaining it; test-recall-gate.sh was written afterwards without it and
failed 4 of 13 cases on Windows on 2026-08-31 — the other 9 were green for the wrong
reason, which is the worse half. A new fixture appears here as drift; the review question
is whether any path in it crosses into a native process.

## OS-5 — grep swallows a report line by calling the stream binary

shape: B

invariant: A grep that renders a REPORT line — a FAIL, a verdict, a count somebody acts
on — passes `-a`. Git Bash decides per stream whether it is text, and on a decision of
"binary" grep prints `Binary file (standard input) matches` INSTEAD of the matching line:
the diagnostic replaces exactly the output it was asked to produce, and only in the
failure path, where nobody has a second copy.
pattern:   \| *grep -[b-zA-Z]
paths:     --include=*.sh scripts helpers
known:     helpers/session-closing.sh=1 helpers/shared-memory-check.sh=1 scripts/brain-update.sh=2 scripts/ci-watch.sh=1 scripts/lint-placeholders.sh=1 scripts/onboarding-verify.sh=5 scripts/parallel-sessions.sh=1 scripts/portability-smoke.sh=2 scripts/preflight.sh=1 scripts/shared-memory-watch.sh=1 scripts/test-guards.sh=2 scripts/test-stop-dispatcher.sh=1 scripts/test-suite-plugin-linkage.sh=1
instances: 3
repeat:    yes
status:    closed
note:      Measured 2026-08-31, three sites in one afternoon: session-bootup printed
"Binary file (standard input) matches" in place of the AHEAD line it had just computed;
portability-smoke did the same for the FAIL detail of a failing suite AND for the
os-trap register's own drift lines — a gate reporting a failure it then made unreadable.
Report paths in brain-selftest, brain-check, effect-check and portability-smoke were
swept in the same pass (14 greps). The baseline is what is LEFT: predicates (`grep -q`,
whose exit status is unaffected) are in it too, because a pattern cannot tell them
apart from the rest, and the rest are greps whose output
nobody reads as a verdict. They stay listed rather than changed, because `-a` on a line
that never renders anything is noise — but a NEW pipe-grep must be looked at, and the
question is one word long: does this line end up in front of a human?

## OS-6 — `python -` runs the file you passed as an argument

shape: B

invariant: A path is never handed to `"$PY" - "<path>"` as argv when that file may carry a
shebang. Python 3.14's install manager — the `python3` on PATH on a Windows workstation —
honours the shebang of a file argument even though the program was given on stdin: the
stdin program never runs, and the argument is EXECUTED instead. Pass such a value in the
environment.
pattern:   "\$PY" - "
paths:     --include=*.sh scripts helpers
known:     scripts/brain-selftest.sh=2 scripts/suite-install.sh=2
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-08-31 on the workstation. Exactly one of the five sites was
affected, and it was the hand-tool guard — the check whose entire purpose is that a
declared script does NOT run. It returned "not a hand tool" and launched bash on the very
file it was protecting. Isolated: only a shebang-carrying FILE triggers it; a directory, a
.json and a shebang-less .sh are passed through as argv correctly, which is why the other
four sites are fine and why nothing else in the repo showed a symptom. Invisible to the
interpreter probe at the top of those scripts (`python3 -c 'import sys'` succeeds) and
invisible to python.org's `python` 3.11 on the same machine, which behaves correctly — two
interpreters under two names, one of them wrong only for this construct. The baseline
counts the remaining `$PY - "<arg>"` sites; a new one is read with one question: can this
argument ever be a file with a shebang?

## OS-4 — a fixture suite exists but no OS gate runs it

shape: C

invariant: The set of fixture suites that `portability-smoke.sh` runs is DISCOVERED, not
listed. A hand-kept list is a second copy of the directory and drifts the moment somebody
adds a suite — and what it silently drops is exactly the OS coverage the suite was written
for.
check:     the three fixture runners glob instead of listing — scripts/portability-smoke.sh,
scripts/brain-selftest.sh and the CI step "fixture suites (discovered)"; each fails loudly
if discovery yields nothing
mechanizable: tool — a pattern cannot state "this list equals that directory" without
becoming the list again. What is checkable is the opposite: no runner may carry a literal
suite list, and each reports the count it discovered.
instances: 1
repeat:    no
status:    closed
note:      2026-08-31: portability-smoke named five suites literally. The five newest
suites (test-recall-gate.sh plus four `*-test.py`) were never run on Windows, which is how
OS-1, OS-2 and OS-3 all shipped unnoticed — CI ran them on Linux, where none of the three
can reproduce. CI carried the same list a second time, one step per suite. Fixed by
globbing in all three runners: the OS gate went from 5 suites to 12, brain-selftest from 8
to 15.
