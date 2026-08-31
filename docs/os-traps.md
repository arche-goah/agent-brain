# OS trap register — agent-brain

> **Why this file exists.** CI runs on Linux. macOS is where most of this repo is
> written. Windows is where it breaks — and the breakage is silent, because the same
> code path that misbehaves there produces nothing at all to look at here: a path
> comparison that always misses reports "everything is missing", a fixture whose
> transcript cannot be read reports "the gate stayed silent", a generator that writes
> CRLF reports success. Every one of those looks like a clean run on the OS that
> cannot reproduce it.
>
> Three of these classes have now come back after being fixed once (2026-08-13,
> 2026-08-10, 2026-08-31) — above the build threshold, so they get a mechanism rather
> than a fourth single fix. This register is that mechanism: each class stated as an
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

## OS-1 — a repo-relative path leaves the program as text with the platform separator

invariant: A path that is compared against, or written into, forward-slashed text —
markdown links, git output, a baseline file, JSON another instance reads — is stated
with `.as_posix()`. `str(p.relative_to(root))` yields backslashes on Windows, so every
such comparison misses and every such link is unfollowable.
pattern:   str\([A-Za-z_.]+\.relative_to\(
paths:     --include=*.py scripts helpers
known:
instances: 4
repeat:    yes
status:    closed
note:      2026-08-13 english-only.py — 100 findings on a clean tree. 2026-08-31, same
class in three more places: shared-memory-lint.py reported 143 of 143 files as missing
from the index AND every index line as pointing at a missing file; shared-memory-index.py
matched nothing against the old index and carried every existing entry into the root page
(83,205 chars instead of 1,651), writing backslashed links; leak-scan.py in its report
only. Baseline zero on purpose — after the fix there is no legitimate site, so any hit is
a new one.

## OS-2 — a generator writes a git-tracked text file without pinning the line ending

invariant: Every write of a file that git tracks pins `newline="\n"`. Python text mode
translates `\n` to the platform separator, so the same generator emits LF on macOS and
CRLF on Windows — against a `.gitattributes` that says LF the whole file reads as
changed, or git rewrites it behind the run.
pattern:   \.write_text\(
paths:     --include=*.py --exclude=*-test.py scripts helpers
known:     scripts/ecosystem-sync.py=1 scripts/english-only.py=1 scripts/regen-skill-registry.py=1 scripts/shared-memory-index.py=2 scripts/shared-memory-lint.py=1
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
the author think about line endings" is not.

## OS-3 — a fixture hands a shell path to a native process

invariant: A fixture that creates a temp dir and passes it into node or python as DATA
(a JSON field, an env var) states it natively via `cygpath -m`. Git Bash `/tmp/...` does
not resolve for a native process — the process reads nothing, and a gate that should
BLOCK stays silent, which the fixture cannot distinguish from a gate working correctly.
pattern:   mktemp -d
paths:     --include=test-*.sh scripts
known:     scripts/test-guards.sh=2 scripts/test-premise-gate.sh=1 scripts/test-recall-gate.sh=1 scripts/test-session-helpers.sh=1 scripts/test-stop-checks.sh=1 scripts/test-stop-dispatcher.sh=2 scripts/test-suite-plugin-linkage.sh=1
instances: 3
repeat:    yes
status:    closed
note:      Closed on the same terms as OS-2 — every baselined fixture is correct today and
the baseline is the gate against the next one. test-stop-dispatcher.sh and test-premise-gate.sh carry the `native()` helper
and the comment explaining it; test-recall-gate.sh was written afterwards without it and
failed 4 of 13 cases on Windows on 2026-08-31 — the other 9 were green for the wrong
reason, which is the worse half. A new fixture appears here as drift; the review question
is whether any path in it crosses into a native process.

## OS-4 — a fixture suite exists but no OS gate runs it

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
