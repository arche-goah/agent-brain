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
shebang in an argument, while `python` on the same machine does not), OS-13 (`python3` is
3.9 on stock macOS and 3.12+ elsewhere), OS-17 (the Microsoft Store `python3` stub exists but
runs nothing). Older, same shape: `stat -c` vs `-f`, `lsof` absent.
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
known:     helpers/session-bootup.sh=4
known:     scripts/always-loaded.py=4
known:     scripts/autonomy-diagnose.py=26
known:     scripts/backprop-report.py=5
known:     scripts/brain-friction.py=1
known:     scripts/brain-selftest.sh=3
known:     scripts/brain-update.sh=7
known:     scripts/carrier-audit-test.py=22
known:     scripts/carrier-audit.py=12
known:     scripts/caveman-armed.py=6
known:     scripts/commitments.py=5
known:     scripts/device-status.py=19
known:     scripts/freshness-gate-test.py=9
known:     scripts/gate-precision.py=4
known:     scripts/hook-coverage.py=20
known:     scripts/lesson-carriers.py=5
known:     scripts/live-doc-lint-test.py=2
known:     scripts/live-doc-lint.py=3
known:     scripts/local-machinery.py=1
known:     scripts/memory-lint-test.py=6
known:     scripts/orphan-check-test.py=7
known:     scripts/orphan-check.py=1
known:     scripts/plugin-records-test.py=1
known:     scripts/recorder-report.py=3
known:     scripts/shared-memory-lint.py=1
known:     scripts/shared-reach-check.py=8
known:     scripts/test-open-items.sh=1
known:     scripts/test-suite-plugin-linkage.sh=2
known:     scripts/transcript-recall-test.py=5
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
2026-10-09, local-machinery.py rework (carrier inventory): one join is left — the default
path of the declarations file, which is only opened. Every path the script REPORTS or
matches against a declaration key is built with `pathlib` and leaves as `.as_posix()` (item
ids, `rel_id`) or with backslashes replaced; the scheduled-job search compares the brain path
in both separator forms, lowercased. Before the rework: all five joins build the path
of a file the script opens (settings, stop-checks, declarations, the core checkout and its
`.git`); none is printed or compared. The paths it REPORTS come from git porcelain
(already forward-slashed) and from hook command strings.
2026-10-09: the caveman check moved out of session-bootup.sh into caveman-armed.py
(bootup 8 -> 4, new file 6). Same review: every join builds a path the script opens;
it prints only plugin id, version and style name.
2026-10-09, always-loaded.py baselined after that review: the four joins build paths it
only sizes or writes (rule globs, the state file); it reports byte counts, never a path.
2026-10-09, commitments.py baselined after that review: the five joins build the transcript
dir, a session file and the instance data path it opens; it reports session ids, never a path.
2026-10-11, hook-coverage.py 6 -> 9 after that review: the three new joins only feed
`os.path.isfile` (is the wired helper / the registered stop check in the consumed core?); the
lines it prints name the helper's FILE NAME, never a joined path.
2026-10-16, scripts/autonomy-diagnose.py baselined after review: its `os.path.join` results are
compared only with each other after `normcase(normpath())` on both sides, and every path that
leaves the program as text goes through `rel()` / `--memory-dir`, which turn `os.sep` into `/`.
Green on Windows (Git Bash) the same day, report paths forward-slashed.
2026-10-20, hook-coverage.py 11 -> 14 after that review: the three new joins build the paths of
live-watchdog.cjs, live-read.json and live-watchdog.json, which are only tested or opened; the line
it prints names the live-read domain and the fixed text `.claude/rules/live-watchdog.json`.
2026-10-23, scripts/recorder-report.py baselined after review: its three joins build the paths of
stop-checks.json, the gate's source and the recorder logs, which are only opened or tested for
existence; what it prints is the check's label and the log's bare file name, never a joined path.
2026-10-25, scripts/live-doc-lint.py (3) and its fixture (2) baselined after review: the lint's
joins build the paths of dependencies.json, the glob root and the file it opens; every path it
REPORTS or hands to `git diff` is `relpath(...).replace(os.sep, "/")`. The fixture's joins build
files it writes into its throwaway repo and never prints.

2026-10-25, lesson-carriers.py baselined after the review: both joins only OPEN a file (the instance
data file, the protocol); neither path is compared against text or written into a link, the one that
reaches stdout is the unreadable-protocol notice for a human.
2026-10-25, scripts/shared-reach-check.py baselined after that review (8): every join builds a path the
script opens, stats or hands to `git -C` (the instance data file, the ledgers, a private document, the
shared file); every path it REPORTS comes from git porcelain (forward-slashed) or from the pointer text
inside a document, never from a join.
2026-10-31: the ecosystem-owner snippet moved out of session-bootup.sh into scripts/eco_owner.py
(bootup 5 -> 4); the new file builds its paths with pathlib and prints only the owner's name.

## OS-2 — a generator writes a git-tracked text file without pinning the line ending

shape: A

invariant: Every write of a file that git tracks pins `newline="\n"`. Python text mode
translates `\n` to the platform separator, so the same generator emits LF on macOS and
CRLF on Windows — against a `.gitattributes` that says LF the whole file reads as
changed, or git rewrites it behind the run.
pattern:   \.write_text\(|\bopen\(.*["']w["']
paths:     --include=*.py --exclude=*-test.py scripts helpers
known:     scripts/always-loaded.py=1
known:     scripts/autonomy-diagnose.py=1
known:     scripts/brain-scan-prep.py=3
known:     scripts/changelog-assemble.py=1
known:     scripts/ci-lint-local-parse.py=1
known:     scripts/decision-review.py=1
known:     scripts/device-status.py=1
known:     scripts/eco_owner.py=1
known:     scripts/ecosystem-sync.py=1
known:     scripts/english-only.py=1
known:     scripts/invariant-index.py=1
known:     scripts/ledger-reconcile.py=4
known:     scripts/open-items.py=1
known:     scripts/os-traps-export.py=1
known:     scripts/regen-skill-registry.py=1
known:     scripts/session-audit.py=1
known:     scripts/shared-memory-index.py=3
known:     scripts/shared-memory-lint.py=1
known:     scripts/shared-memory-log-rotate.py=1
known:     scripts/shared-memory-post.py=2
known:     scripts/template-drift.py=1
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
first run after it was written, was read, and was correct. 2026-10-09: invariant-index.py read the same way — it pins newline="\n", and its fixture asserts LF bytes.
first run after it was written, was read, and was correct. 2026-10-09: brain-scan-prep.py
(three writes into the scan's scratch dir; one of them, the report head, is concatenated
into a tracked report) surfaced on its first run and was pinned before it shipped.
2026-10-10: every pinned write moved from `Path.write_text(..., newline="\n")` to
`with open(path, "w", encoding="utf-8", newline="\n")` — `write_text` takes `newline` only
from Python 3.10, and stock macOS python3 is 3.9 (OS-13). The pattern grew the `open(…"w"`
form so the same writes stay visible; the two `open` sites that already pinned
(always-loaded.py, open-items.py) joined the baseline after the same read. Bytes unchanged:
`open(newline="\n")` and `write_text(newline="\n")` hand the same argument to the same
TextIOWrapper.
2026-10-16, scripts/autonomy-diagnose.py baselined: its one write (`--out`) opens with
`newline="\n"`; the report is not git-tracked anyway (it goes to the person who asked).
2026-10-31, scripts/eco_owner.py baselined: its one write (the per-machine answer cache under
`.claude-state/`, not git-tracked) opens with `newline="\n"`.

## OS-3 — a fixture hands a shell path to a native process

shape: A

invariant: A fixture that creates a temp dir and passes it into node or python as DATA
(a JSON field, an env var) states it natively via `cygpath -m`. Git Bash `/tmp/...` does
not resolve for a native process — the process reads nothing, and a gate that should
BLOCK stays silent, which the fixture cannot distinguish from a gate working correctly.
pattern:   mktemp -d
paths:     --include=test-*.sh scripts
known:     scripts/test-absence-gate.sh=1
known:     scripts/test-always-loaded.sh=1
known:     scripts/test-auto-fire-coverage.sh=1
known:     scripts/test-autonomous-gate.sh=1
known:     scripts/test-autonomous-idle-gate.sh=1
known:     scripts/test-autonomous-mode.sh=1
known:     scripts/test-autonomy-diagnose-run.sh=1
known:     scripts/test-autonomy-diagnose.sh=1
known:     scripts/test-bootup-declared-alpha.sh=1
known:     scripts/test-bootup-git-login.sh=1
known:     scripts/test-bootup-time-budget.sh=1
known:     scripts/test-brain-check-brief.sh=1
known:     scripts/test-brain-scan-files.sh=1
known:     scripts/test-caveman-armed.sh=1
known:     scripts/test-change-level.sh=1
known:     scripts/test-ci-lint-local.sh=1
known:     scripts/test-close-loss-gate.sh=1
known:     scripts/test-code-scanning-alerts.sh=1
known:     scripts/test-coherence-scan-files.sh=1
known:     scripts/test-collab-watch-plan.sh=1
known:     scripts/test-commitment-carrier-gate.sh=1
known:     scripts/test-conditional-order-gate.sh=1
known:     scripts/test-dead-carriers.sh=1
known:     scripts/test-decision-presentation-gate.sh=1
known:     scripts/test-decision-readiness.sh=1
known:     scripts/test-decision-review.sh=1
known:     scripts/test-delivered-read-gate.sh=1
known:     scripts/test-eco-owner.sh=1
known:     scripts/test-ecosystem-sync.sh=1
known:     scripts/test-full-audit-synthesis-files.sh=1
known:     scripts/test-git-hooks.sh=1
known:     scripts/test-git-sandbox.sh=1
known:     scripts/test-guards.sh=4
known:     scripts/test-hook-coverage.sh=1
known:     scripts/test-install-git-hooks.sh=1
known:     scripts/test-instance-key-gate.sh=1
known:     scripts/test-instrument-watch.sh=1
known:     scripts/test-leak-scan.sh=1
known:     scripts/test-live-read-gate.sh=1
known:     scripts/test-live-watchdog.sh=1
known:     scripts/test-local-machinery.sh=1
known:     scripts/test-memory-dream-files.sh=1
known:     scripts/test-merge-request-gate.sh=1
known:     scripts/test-merge-train.sh=1
known:     scripts/test-monitor-arm-shape.sh=1
known:     scripts/test-no-input-control.sh=1
known:     scripts/test-onboarding-leak-check.sh=1
known:     scripts/test-open-items-gate.sh=1
known:     scripts/test-open-items-wake.sh=1
known:     scripts/test-open-items.sh=1
known:     scripts/test-order-list-reader.sh=1
known:     scripts/test-parallel-sessions.sh=1
known:     scripts/test-pattern-cases.sh=1
known:     scripts/test-pr-ball.sh=1
known:     scripts/test-pre-commit-behind.sh=1
known:     scripts/test-pre-commit-os-traps.sh=1
known:     scripts/test-premise-gate.sh=1
known:     scripts/test-promise-gate.sh=1
known:     scripts/test-public-text-guard.sh=1
known:     scripts/test-python-probe.sh=1
known:     scripts/test-question-gate.sh=1
known:     scripts/test-recall-gate.sh=1
known:     scripts/test-repo-activity-watch.sh=1
known:     scripts/test-root-cause-gate.sh=1
known:     scripts/test-session-closing.sh=1
known:     scripts/test-session-helpers.sh=1
known:     scripts/test-session-pull.sh=1
known:     scripts/test-setup-shell-start.sh=1
known:     scripts/test-shared-memory-channels.sh=1
known:     scripts/test-shared-memory-check.sh=1
known:     scripts/test-shared-working-copy-guard.sh=1
known:     scripts/test-skill-gate.sh=1
known:     scripts/test-stop-checks.sh=1
known:     scripts/test-stop-dispatcher.sh=5
known:     scripts/test-stoppen-gate.sh=1
known:     scripts/test-suite-plugin-linkage.sh=3
known:     scripts/test-template-drift.sh=1
known:     scripts/test-text-leaks-notice.sh=1
known:     scripts/test-transcript-archive.sh=1
known:     scripts/test-turn-kind.sh=1
known:     scripts/test-verification-gate.sh=1
known:     scripts/test-wait-mcp-reconnect.sh=1
known:     scripts/test-watch-gate.sh=1
known:     scripts/test-watch-pr.sh=1
known:     scripts/test-watch-readiness.sh=1
known:     scripts/test-watch-supervisor.sh=1
known:     scripts/test-workflow-path-args.sh=1
known:     scripts/test-loop-watchdog-alarm.sh=1
instances: 3
repeat:    yes
status:    closed
note:      Closed on the same terms as OS-2 — every baselined fixture is correct today and
the baseline is the gate against the next one. test-stop-dispatcher.sh and test-premise-gate.sh carry the `native()` helper
and the comment explaining it; test-recall-gate.sh was written afterwards without it and
failed 4 of 13 cases on Windows on 2026-08-31 — the other 9 were green for the wrong
reason, which is the worse half. A new fixture appears here as drift; the review question
is whether any path in it crosses into a native process.
2026-09-12, test-promise-gate.sh baselined after exactly that review: three paths cross
into node — the transcript, the cwd carrying the pattern data, and the cwd of the
discriminator case — and all three go through `native()`. The discriminator is the reason
it matters here more than usual: it asserts SILENCE, and an unresolvable path produces
silence too, so without `native()` that case would pass on Windows for the wrong reason
and certify a fixture that sees only one world state.
2026-10-28, test-suite-plugin-linkage.sh 1 -> 3 after the review: `mkremote`/`mkcheckout` named their repos
`$T/…-$RANDOM` and now take them from `mktemp -d "$T/…-XXXXXX"` (two calls could draw the same
number and share a repo). Same parent `$T`, and the paths still go only to git through `git_`, as
before — no new crossing into node or python.
2026-09-13, test-coherence-scan-files.sh baselined after the same review: the temp dir
never crosses into node as data — node receives the harness file as an ARGUMENT (Git Bash
converts argv) and the lens files by NAME through env, which is the comparison the helper
under test makes (names, not directories). No path is opened by the native process.
2026-10-18, test-leak-scan.sh baselined after the same review: every temp path reaches python
as an ARGUMENT (`--root`, `--text`), which Git Bash converts; the watch list travels through
env as JSON text, not as a path.
2026-10-18, test-delivered-read-gate.sh baselined after the same review: the transcript path
crosses into node as DATA (a JSON field of the hook payload) and goes through `native()`.
2026-10-18, test-bootup-git-login.sh baselined after the same review: the throwaway config
path reaches native git as DATA (`GIT_CONFIG_GLOBAL`) and goes through `native()`; the
gh-helper case asserts SILENCE, so without it an unread config would pass for the wrong reason.
2026-10-18, test-git-hooks.sh baselined after the same review: `GIT_CONFIG_GLOBAL` (a path as env
DATA for the native git) goes through `native()`; every other temp path is an argument or the cwd.
2026-10-25, test-text-leaks-notice.sh baselined after the same review: the temp dir never crosses
into a native process — the script under test is bash, every path reaches it as an ARGUMENT, and
nothing is handed to node or python.
2026-10-20, test-live-watchdog.sh baselined after the same review: the project dir crosses into
node as DATA (`CLAUDE_PROJECT_DIR`, the cwd field) and the check path as DATA inside the instance
file; both go through `native()`.
2026-10-21, test-ci-lint-local.sh baselined after the same review: the temp repo reaches only
bash (`CI_LINT_ROOT` for ci-lint-local.sh, which runs the steps with bash); the one crossing into
python — the workflow path and the output dir for the parser — is made native with `cygpath -m`
inside ci-lint-local.sh itself, so every caller, not only the fixture, is covered.
2026-09-30, test-setup-shell-start.sh baselined after the same review: the temp dir only
reaches bash — the fake `powershell.exe`/`pwsh` are bash scripts, the profile path they
return goes back through `cygpath -u` in the script under test. No native process opens it.
2026-09-30, test-code-scanning-alerts.sh baselined after the same review: the temp dir only
reaches bash — the fake `gh` is a bash script that reads its answers from `FAKE_DIR`, and
the script under test is bash. No native process opens it; green on Windows (Git Bash) the
same day.
2026-10-05, test-absence-gate.sh baselined after the same review: paths cross into node in
four places — the transcript, the cwd, the roots inside the instance file, and the paths
inside the recorded tool inputs (the gate resolves those to decide coverage). All four go
through `native()`. Here it matters in BOTH directions: an unresolvable root is never
covered (a must-allow case would block), an unresolvable transcript reads empty (a
must-block case would pass silently). Windows run still owed at baseline time.
2026-10-11, test-pr-ball.sh baselined after the same review: the temp dir crosses into python
in one place — `SHARED_MEMORY_REPO` (env), the throwaway shared memory `shared_answers.py`
reads — and goes through `cygpath -m`. It matters for the discriminator: the own-answer case
asserts SILENCE, and an unresolvable path would read no answer and fire the line instead, so
the case would fail loudly rather than pass for the wrong reason; the foreign-text control
asserts a line and would pass either way. Green on Windows (Git Bash) the same day.
2026-10-28, test-pattern-cases.sh baselined after the same review: every synthetic brain reaches
python as an ARGUMENT through `native()`; pattern-cases.py makes its own temp brain with
`tempfile`, so every path it hands to node (the transcript, the cwd field, CLAUDE_PROJECT_DIR) is
native by construction. The brief case hands the brain to brain-check.sh (bash) through
CLAUDE_PROJECT_DIR; bash passes it on to python as an argument. Windows run owed at baseline time.
2026-10-09, test-live-read-gate.sh baselined after the same review: paths cross into node in
five places — the transcript, the project dir (env), the absolute required path inside the
instance file, the `filePath` of each delivered-Read record, and the path inside each `cat`
command the gate resolves. All five go through `native()` (one `$NT` for the temp dir). Both
directions matter here too: an unresolvable delivered record never covers the file (a
must-allow case would block), an unresolvable transcript reads empty (a must-block case would
still block, but for the wrong reason — which is why the fixture also runs every must-block
case against an always-allow stub). The stub and the padding script take their paths as
ARGUMENTS, which Git Bash converts. Windows run owed at baseline time.
2026-10-09, test-transcript-archive.sh baselined after the same review: the temp dir
reaches the script under test through CLAUDE_CONFIG_DIR and argv, and inside it only bash,
`find`, `du` and `tar` (all MSYS) open it; the script converts both paths with `cygpath -u`
where it exists, because GNU tar reads the colon of `C:\...` as host:path. The one native
program, `git -C <dir>` (the refusal check), receives the dir as an ARGUMENT, which Git Bash
converts. Windows run still owed at baseline time.
2026-10-09, test-wait-mcp-reconnect.sh baselined after the same review: the temp dir holds
the stamp files, written and read by bash (`echo`, `cat`) only; the process cases start
bash children and never hand a path to a native process. Windows run still owed at
baseline time (the process cases are designed to SKIP there and to check the refusal).
2026-10-10, test-stop-dispatcher.sh 3 -> 4 after the same review: the recorder-rotation
cases add one config dir; it reaches node as the cwd field, as CLAUDE_PROJECT_DIR and (the
probe's path) inside the config, all three through `native()`. The log files are read back
by bash `grep` only. Windows run still owed at baseline time.
2026-10-15, test-stop-dispatcher.sh 4 -> 5 after the same review: the re-issue cases add one
config dir; it reaches node as the cwd field and as CLAUDE_PROJECT_DIR, and the check paths
inside its config (two probes, the real stoppen-gate) and the transcripts — all through
`native()`. Green on Windows (Git Bash) the same day.
2026-10-10, test-session-pull.sh baselined after the same review: the temp paths reach node
only as ARGUMENTS (the two config files, which Git Bash converts); the paths INSIDE those JSON
files are printed back by node unchanged and used by bash and as `git` argv, never opened by a
native process. The one path that does travel as data — the hang script inside
`GIT_SSH_COMMAND`, which native git hands to its shell — goes through `native()`. Windows run
still owed at baseline time.
2026-10-11, test-open-items-wake.sh baselined after the same review: paths cross into python
as data in three places — `--repo`, `--root` and `OPEN_ITEMS_PR_FIXTURE` — all through
`native()`; the script path is an argument and goes through it too. The fixture's own `git -C`
calls are bash argv (converted). Python then runs `git -C <repo>` with the native path it was
given. Windows run still owed at baseline time.
2026-10-12, test-guards.sh 3 -> 4 after the same review: the operator-word cases add one
project dir; it reaches node as CLAUDE_PROJECT_DIR and as the cwd field, and the guard
resolves the pointer probes' record files under it — all through `native()`. Both
directions matter: an unresolvable dir loads no rules (every must-block case would pass
silently) and finds no record file (the must-allow pointer case would block). Windows run
still owed at baseline time.

2026-09-13, test-brain-scan-files.sh, test-memory-dream-files.sh and
test-full-audit-synthesis-files.sh baselined on the same review and the same construction
— they are the per-workflow siblings of the coherence fixture: harness file as an
argument, data file names through env, nothing that the native process has to open by
path. The three arrived together because the producer-writes fix covered the remaining
three workflows at once; the review is per file regardless, and the shared construction
is what makes it short.

2026-09-13, test-onboarding-leak-check.sh: the temp dir is a BRAIN handed to a bash
script (BRAIN_DIR and the argument), never a path a native process has to open; the
report goes to --out inside the same temp dir. Its one pipe-grep carries -a, because the
line it extracts is the verdict the fixture judges (OS-5).

2026-10-09, test-local-machinery.sh: the temp dir reaches python only as the `--repo`
ARGUMENT (Git Bash converts argv) and git as `-C` arguments; the hook commands inside the
fixture JSON name `$CLAUDE_PROJECT_DIR` or a fictitious `/elsewhere/...` prefix that is
compared as text, never opened. No native process opens a temp path from data.
Rework 2026-10-09 (carrier coverage): now four temp paths DO travel as data — the suite path
in `.mcp.json` and in an alpha key, the plugin install path in `installed_plugins.json`, the
brain path inside a planted LaunchAgents plist, and the global hooks dir in the git config
named by `GIT_CONFIG_GLOBAL` (itself an env value a native git reads). Every one goes through
`nat()` (cygpath -m). `--home` and `--repo` stay argv.
2026-10-09, test-caveman-armed.sh: the installPath written into installed_plugins.json is
data a native python opens, so it goes through `nat()` (cygpath -m), and so does
CLAUDE_CONFIG_DIR; the brain dir reaches python only as its working directory.
2026-10-09, test-always-loaded.sh: the temp dir reaches python only as the `--repo` and
`--memory` ARGUMENTS (Git Bash converts argv); no path travels inside data.
2026-10-09, the three collab-watch fixtures, after the review question: test-watch-supervisor.sh
hands its temp dir only to bash. test-collab-watch-plan.sh hands the config path to python
as an ARGUMENT only — directly, and through `COLLAB_WATCH_CONFIG`, which the bash arm script
reads and passes on as argv (Git Bash converts argv). test-repo-activity-watch.sh: `FAKE_DIR`
and the state dir are read by bash only (the fake `gh` is bash); the clone root reaches the
native `git` only as a `-C` argument; the python filter gets JSON on stdin, never a path. No
native process opens a temp path from data. Windows run owed by the workstation check.
2026-10-09, test-parallel-sessions.sh baselined after the same review: the temp dir reaches
only bash — the command-line list is read by the script under test through a bash redirect,
and the repo argument goes to `cd` in bash. No native process opens it; green on Windows the
same day.
2026-10-14, test-git-sandbox.sh baselined after the same review: the temp dir crosses into a
native process as DATA in two places — the global gitconfig path in `GIT_CONFIG_GLOBAL`
(env, read by git) and the hooks dir written INTO that config file (`core.hooksPath`, read
by git) — and both go through `nat()`. The repo dirs reach python and git as ARGUMENTS
(`-C`, argv; Git Bash converts); the hook scripts are sh. It matters in the unsafe
direction: the negative control asserts that the host hook BLOCKS a plain commit, and an
unresolvable hooksPath runs no hook, so the control would fail loudly, not pass for the
wrong reason. Windows run owed at baseline time.
2026-10-16, test-autonomy-diagnose.sh and test-autonomy-diagnose-run.sh baselined after the same
review: every temp path reaches python as an ARGUMENT (`--repo`, `--home`, `--out`), which Git Bash
converts; the one place python derives a path itself (the memory folder slug) is matched in the
fixture against `cygpath -m` of the same dir (`native()`). The runner fixture's env seams
(`DIAG_OUT_ROOT`, `DIAG_CLAUDE`) are read by bash only. Both green on Windows (Git Bash).
2026-10-16, test-conditional-order-gate.sh baselined after the same review: two paths cross into
node as data — the transcript and the cwd that holds the instance pattern file — both through
`native()`. Both directions matter: an unresolvable transcript makes the gate fail OPEN (every
must-block case would pass silently), and an unresolvable cwd drops the German data file, so the
incident case would pass for the wrong reason while the discriminator would still look right.
Green on Windows (Git Bash) the same day.
2026-10-24, test-merge-request-gate.sh baselined after the same review: four paths cross into node
as data — the brain dir (`CLAUDE_PROJECT_DIR`), the cwd, the fake gh (`MERGE_REQUEST_GATE_GH`) and the
PR fixture (`PR_JSON`, read by the fake) — all through `native()`. An unresolvable fake gh makes the
gate fail OPEN (PR unreadable = allow), so every must-block case would pass silently.

## OS-5 — grep swallows a report line by calling the stream binary

shape: B

invariant: A grep that renders a REPORT line — a FAIL, a verdict, a count somebody acts
on — passes `-a`. Git Bash decides per stream whether it is text, and on a decision of
"binary" grep prints `Binary file (standard input) matches` INSTEAD of the matching line:
the diagnostic replaces exactly the output it was asked to produce, and only in the
failure path, where nobody has a second copy.
pattern:   \| *grep -[b-zA-Z]
paths:     --include=*.sh scripts helpers
known:     helpers/session-closing.sh=1
known:     helpers/shared-memory-check.sh=1
known:     scripts/brain-update.sh=1
known:     scripts/ci-watch.sh=1
known:     scripts/lint-placeholders.sh=1
known:     scripts/onboarding-verify.sh=4
known:     scripts/parallel-sessions.sh=1
known:     scripts/portability-smoke.sh=2
known:     scripts/preflight.sh=1
known:     scripts/release-preflight.sh=3
known:     scripts/shared-memory-watch.sh=1
known:     scripts/test-decision-review.sh=2
known:     scripts/test-guards.sh=2
known:     scripts/test-live-read-gate.sh=2
known:     scripts/test-live-watchdog.sh=3
known:     scripts/test-shared-working-copy-guard.sh=1
known:     scripts/test-stop-dispatcher.sh=1
known:     scripts/test-suite-plugin-linkage.sh=1
known:     scripts/test-text-leaks-notice.sh=12
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
2026-10-09, test-live-read-gate.sh baselined after that question: both pipe-greps are
`grep -q` predicates on the hook's JSON (the deny decision, the continuation offset); their
output is never printed, only the exit status decides the case.
2026-10-13, test-shared-working-copy-guard.sh baselined after that question: one pipe-grep, a
`grep -q` predicate on the hook's JSON deny decision; nothing of it is printed, the exit status
decides the case.
2026-10-20, test-live-watchdog.sh baselined after that question: three pipe-greps, all `grep -q`
predicates on the hook's JSON (the deny/block decision, the check output in the refusal, the
could-not-measure note); nothing of them is printed, the exit status decides the case.
2026-10-25, test-text-leaks-notice.sh baselined after that question: twelve pipe-greps, all `grep -q`
predicates on the notice body the script under test printed (a mention, a class-and-line line, the
absence of the matched text); nothing of them is printed, the exit status decides the case.

2026-10-25, release-preflight.sh baselined after that question: five pipe-greps — the quotation test
on RELEASE_EARLY_OK, the OS words per PR text and the PR-number extraction are `grep -q`/`grep -o`
whose output is never printed; the three greps whose words DO reach a FAIL line (the open
shared-memory entries) carry `-a`.
## OS-6 — `python -` runs the file you passed as an argument

shape: B

invariant: A path is never handed to `"$PY" - "<path>"` as argv when that file may carry a
shebang. Python 3.14's install manager — the `python3` on PATH on a Windows workstation —
honours the shebang of a file argument even though the program was given on stdin: the
stdin program never runs, and the argument is EXECUTED instead. Pass such a value in the
environment.
pattern:   "\$PY" - "
paths:     --include=*.sh scripts helpers
known:     scripts/brain-selftest.sh=2
known:     scripts/suite-install.sh=2
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

2026-10-13, test-shared-working-copy-guard.sh baselined after the same review: three paths cross
into node as data — the repo in the JSON command (`git -C …`), the cwd, and `CLAUDE_PROJECT_DIR`
(the guard's log dir) — all through `native()`. It matters in the blocking direction: an
unresolvable repo makes the guard skip the call (fail-open), so every must-block case would
pass silently. Windows run owed at baseline time (request in the shared memory).
2026-10-16, a second spelling of the same class, outside this repo (an instance hook's fixture,
`test-network-drive-gate.sh`): no temp dir at all, but a LITERAL POSIX path in an env var
(`export NDG_EXTRA_MOUNTS="/Volumes/<share>|…"`) read by node. Here the path is not left
unresolved — Git Bash REWRITES an env value that starts with `/` before the native process sees
it (`C:/Program Files/Git/Volumes/<share>|…`; a leading `|` was rewritten too, a leading `x|`
was not). Four must-block cases passed silently on Windows. `native()`/`cygpath -m` do not fit
a fake path that must stay POSIX; `export MSYS2_ENV_CONV_EXCL=<VAR>` exempts that one variable
and is inert on macOS/Linux. The `mktemp -d` pattern cannot see this spelling; a search for
`[A-Z_]="/` assignments over core scripts, helpers and one instance brain found no other site.

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

## OS-7 — a GNU-only regex extension in a portable script matches nothing on BSD and says nothing

shape: B

invariant: `sed` alternation written as `\|` (and its relatives `\+`, `\?`) is a GNU
extension. BSD sed on macOS treats it as a literal and the pattern matches NOTHING —
silently, exit 0, an empty range. A reader built on it reports "no open orders" on a list
that has them. Alternation in sed is written with `-E` and a bare `|`, which both
implementations share; the same holds for grep (`-E` over `\|`).
pattern:   sed[^#]*\\\|
paths:     --include=*.sh scripts helpers
known:
instances: 1
repeat:    no
status:    closed
note:      2026-09-13: the session-bootup order-list reader gained a second heading language
and was written with `\|`. Measured on macOS: 0 lines for the German AND the English list,
where 1 was expected in each — the fixture written for the heading change caught the sed
change instead. GNU CI would have been green. Fixed with `-E`; class searched across core and
the proving instance (scripts, helpers, hooks): no other site.

## OS-8 — one identity, two platform spellings: the own user profile as long name and as 8.3 short name

shape: A (borderline — see note)

invariant: Code that decides "is this path MINE" never derives the answer from a single
spelling of the username. On Windows the same profile has a long name and an 8.3 short
name (six characters plus tilde-digit), both produced by the platform and both appearing
in real paths; `id -un` and the basename of $HOME return only the long one. A comparison
built on that alone answers "foreign" for the machine it is running on.
pattern:   \$\(id -un\)
paths:     --include=*.sh scripts helpers
known:     scripts/onboarding-verify.sh=1
known:     scripts/test-onboarding-leak-check.sh=1
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-09-15 on the second Windows machine (alex-workstation), in check 8
of onboarding-verify.sh. The Claude Code harness hands its scratchpad root out in the SHORT
spelling; a local guard log had recorded it, and the leak check reported the brain's own home
path as a foreign leak — the exact failure the surrounding fix set out to remove, one spelling
further on. Teaching the strip the short name would not have been enough on its own: the tilde
is outside the extraction charset `[A-Za-z0-9._-]+`, so the token is cut there before any
comparison happens. Closed by scope instead: the scan now reads only git-TRACKED files when the
brain is a repo, and an untracked or ignored file cannot reach a remote, so the short spelling
stops being reachable at all. Measured after the change on that machine: no tracked file
contains the short form, and the own-path hit is gone while both genuine foreign hits remain.
The baseline counts the sites that ask "who am I" from `id -un`; a new one is read with one
question: can this identity appear under a second spelling on the platform it runs on?
Shape is filed as A because the platform supplies a second form of a value the program did not
control — but it is a borderline case: nothing is reshaped IN TRANSIT here, both spellings are
valid at the same time and the program simply knows one of them. If the maintainers read that
as a fourth shape rather than a variant of A, this entry is the place to name it.

## OS-9 — a Python script whose stdout another program parses leaves it to the platform

shape: A

invariant: A Python script whose output is READ by another program pins its stdout —
`sys.stdout.reconfigure(encoding="utf-8", newline="\n")`. Unpinned, Python on Windows
gives a redirected stdout the ANSI codepage and CRLF line endings, so the same program
emits different bytes per platform. The consumer never learns this: a shell regex `.*`
stops at the first invalid byte instead of failing, and a trailing CR turns an extracted
number into a string. Both end as a WRONG VALUE, not as an error.
pattern:   print\(.*[^\x00-\x7F]
paths:     --include=*.py scripts helpers
known:     scripts/backprop-report.py=4
known:     scripts/brain-friction.py=3
known:     scripts/carrier-audit.py=1
known:     scripts/changelog-assemble.py=1
known:     scripts/check-table.py=1
known:     scripts/clock-skew.py=1
known:     scripts/commitments.py=1
known:     scripts/dep-install.py=2
known:     scripts/ecosystem-sync.py=1
known:     scripts/english-only.py=1
known:     scripts/fork-drift.py=2
known:     scripts/instrument-watch.py=3
known:     scripts/invariant-check.py=3
known:     scripts/lesson-carriers.py=4
known:     scripts/live-doc-lint.py=2
known:     scripts/memory-lint-test.py=1
known:     scripts/memory-lint.py=1
known:     scripts/open-items.py=9
known:     scripts/orphan-check.py=2
known:     scripts/os-traps-export.py=3
known:     scripts/pending-clauses.py=3
known:     scripts/plugin-scope-check-test.py=1
known:     scripts/regen-skill-registry.py=1
known:     scripts/session-audit.py=3
known:     scripts/shared-memory-index.py=4
known:     scripts/shared-memory-lint.py=1
known:     scripts/shared-reach-check.py=4
known:     scripts/transcript-recall.py=1
instances: 1
repeat:    no
status:    open
note:      Measured 2026-09-24 on alex-workstation (Windows 11, Git Bash, Python 3.14),
core v1.3.38. `brain-check.sh --brief` — the form the session-start hook runs — printed
`[: 1<0x97> decide each, none of them is a verdict.: integer expression expected` and then
took its "needs a look" branch, while a hand-run `brain-check.sh` was green. Cause:
`brain-friction.py` wrote its headline em dash as the single cp1252 byte 0x97 and ended
its lines CRLF; the `sed` that lifts the candidate count out could consume neither. So the
brain raised a permanent false alarm at every session start, and the operator had to be
told "needs a look" about a machine that was fine. Fixed at the PRODUCER — a consumer
cannot repair bytes that already left wrong.
The FORM of the measurement matters and cost a wrong check first: through a plain `>` file
redirect the same script ended LF, through a PIPE it ended CRLF. brain-check.sh reads it in
a command substitution, i.e. a pipe, so the gate in `scripts/portability-smoke.sh` pipes too
— written with `>` it would have been green against exactly this defect. The CR half of that
gate reads bytes in Python rather than `grep "$(printf '\r')"`: the substitution hands grep
an EMPTY pattern, which matches every file and reports LF for a file full of CRLF.
`known` is a baseline of SITES (like OS-2), not of defects: 13 files print non-ASCII today
and only `brain-friction.py` is parsed by another program, so the rest are correct as they
stand. The baseline exists so a NEW site is read with one question before it ships: does
anything PARSE this output? 2026-10-09 commitments.py: yes — effect-check E6 reads its summary line — and it pins stdout like brain-friction.py. 2026-10-09 local-machinery.py: yes — the session start reads
it — so it pins stdout like brain-friction.py (the pin stays). Its sites left the baseline in
the carrier rework of the same day: the em-dash lines now live in a MESSAGES table and reach
`print()` through `format()`, which this pattern cannot see — the pin, not the count, is what
carries this file. 2026-10-15, open-items.py 7 -> 8 after the same question: the new site is
the heading of the standing-approval group (`- standing approval — handle these …`); the
bootup and open-items-gate.cjs parse this output, and the script pins stdout (`OS-9` comment in
`main()`), so the em dash leaves as UTF-8 on every platform. 2026-10-19, shared-memory-lint.py
(count unchanged, 1): the same question answered yes — `shared-memory-dream` redirects `--inventory`
into a JSON file its agents read, and on a Windows brain that file held a description's `·` as the
cp1252 byte 0xb7 (measured at core #24 on 2026-10-18; a planted accented letter reproduced it). Pinned in
`main()`; `portability-smoke.sh` asserts the piped `--inventory` parses as UTF-8 JSON. Left `open` deliberately — the 12 unpinned sites are fine only
as long as that answer stays no. 2026-10-25, scripts/live-doc-lint.py (2): the question answered
yes — its `--json` is parsed by the fixture and the text report is read by a CI log and a reviewer —
so stdout is pinned at import, like the others.

2026-10-25, lesson-carriers.py baselined after the review: its two report lines carry an em dash and are
parsed by brain-scan-prep.py and the session-close step; stdout is pinned at the top of the script.
2026-10-25, scripts/shared-reach-check.py (4): the question answered yes — the session-close step reads its
FAIL lines and summary — so stdout is pinned at import, like lesson-carriers.py.
2026-10-31, open-items.py 8 -> 9 after the same question: the new site is the no-owner note
(`note: open PRs not looked for — …`); the bootup and open-items-gate.cjs parse this output, and
the script pins stdout in `main()`, so the em dash leaves as UTF-8 on every platform.

## OS-10 — a shell loop over a path list splits at the space in a Windows profile name

shape: A

invariant: A shell loop over a list of PATHS reads the list line by line
(`while IFS= read -r d; do ...; done <<< "$list"`), never as `for d in $list`. The bare
form splits on every space, and Windows hands out profile paths with spaces as the normal
case (`C:\Users\First Last`), while macOS and Linux home paths almost never carry one. The
loop then walks path FRAGMENTS, and whatever it checks there reports the real directory as
missing — a wrong verdict, not an error. The same holds for ANY unquoted expansion of a
variable that holds paths or path globs (`ls $globs`), not only the `for` form: a glob list
is kept as an array (`a=("$R"/x/*.md)`), never as a space-joined string.
pattern:   for [A-Za-z_]+ in \$[A-Za-z_]+;|disable=SC2086
paths:     --include=*.sh scripts helpers
known:     scripts/brain-update.sh=2
known:     scripts/handover-gate.sh=2
known:     scripts/release-preflight.sh=1
known:     scripts/suite-install.sh=1
instances: 2
repeat:    yes
status:    closed
note:      Measured 2026-09-30 on a Windows instance whose profile name has a space, core
v1.3.41. `onboarding-verify.sh` check 3 reported `suites=MISSING (<First> grandma3 )` for an
installed suite: the `find` result `/c/Users/<First> <Last>/.claude/plugins/cache/...` was
split into `/c/Users/<First>` (no SKILL.md there, so MISSING, and the first fragment's
basename showed up as a suite name) and a relative tail. Checks 6 and 7 walked the same
fragments. Fixed at the three loops over `suite_dirs`; the fixture in
`onboarding-verify-test.sh` builds a config dir with a space and was red against the old
script with the same symptom. The baseline holds the sites that are CORRECT: the two in
`brain-update.sh` and the one in `suite-install.sh` loop over marketplace/plugin/suite
NAMES, which carry no space. `handover-gate.sh` loops over suite PATHS from
`config/ecosystem.json` and is correct only while those paths are written with `~` (the
split happens before the tilde is expanded) — an absolute path with a space there would
reproduce this trap. A new site is read with one question: can an element of this list be a
path?
Second instance 2026-10-12 (PR #309 at 7669f5d, measured on the Windows instance): the
session start's deep-check relay held the artifact globs as one string and expanded it with
`ls $arts` under a `shellcheck disable=SC2086`. Under a brain path with a space the glob
split, nothing matched, and a check already followed was still voiced; the smoke fixture
built its instance under a path without a space and stayed green on all three CI systems.
The pattern widens to the SC2086 disable, because shellcheck flags every other unquoted
expansion and a deliberate split must carry that marker; `handover-gate.sh`'s second count
is the disable in front of `suite-check.py $suites`, the same `~`-written path list as its
loop. The fixture instance now carries a space.

2026-10-25, release-preflight.sh baselined after the review: the one `for n in $PRS` loop iterates
PR NUMBERS read from `git log`, never paths; no element can carry a space.
## OS-11 — a session count by process name counts every CLI call as a session

shape: B

invariant: Whoever counts Claude SESSIONS by process separates a session from a short CLI
call (`claude plugin list`, `claude --version`, `claude mcp …`) by the command line, never
by the image name alone. On macOS/Linux the count is repo-exact (`lsof` cwd), so a CLI call
in another directory never reaches it; Windows has no cwd per process and counts
machine-wide, where every `claude.exe` started by a script is "a second session". The same
process name is a different kind of process — shape B.
pattern:   IMAGENAME eq claude|comm=.*claude
paths:     --include=*.sh --include=*.py --include=*.cjs scripts helpers
known:     scripts/parallel-sessions.sh=2
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-10-09 on the Windows instance, 1.4.1 candidate check. During
`portability-smoke.sh` the collaboration watch reported `!! 2 claude sessions` while one ran
(operator confirmed). A CIM process log (200 ms) showed `onboarding-verify.sh` starting
`claude.exe plugin list` and `plugin list --json` — 36 short processes in four minutes.
Live, with three concurrent `claude plugin list`: the old count said 4 sessions, the new one
1, and the old one right after the new one still saw 4 (the calls were alive throughout).
Fixed in `parallel-sessions.sh`: Windows reads command lines via CIM and drops CLI
subcommands and info flags; `-p` stays counted (a headless run works in the repo); the
lsof path applies the same filter to `ps -o args=`. The two known sites are the tasklist
fallback (labelled "CLI calls counted too", used only without powershell.exe) and the
`ps … comm=` lookup that now filters. Fixture `test-parallel-sessions.sh`.

## OS-12 — a PowerShell pipeline with one result is a scalar, and `[0]` on a string is its first character

shape: A

invariant: A PowerShell expression that takes "the first element" of a pipeline result wraps
it in the array operator — `@(<pipeline>)[0]`, never `(<pipeline>)[0]`. A pipeline that yields
exactly one item hands back that item, not a one-element array; when the item is a string,
`[0]` indexes the string and returns one character. Bash, Python and the multi-line case all
behave as expected, so the defect only shows on the single-line input, which is the common one.
pattern:   = \([^@][^)]*\)\[0\]
paths:     --include=*.ps1 scripts
known:
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-10-10 on the Windows instance (PowerShell 5.1) during the counter-check
of the preflight HTTPS fallback: the FAIL line read `neither SSH (message: g) nor HTTPS` — one
character of a one-line ssh message. The line had stood unchanged on main since the preflight
was written; the new FAIL path only made it visible. Fixed in `preflight.ps1` with `@(...)[0]`,
checked on the same machine. Search over every `.ps1` in the core: that was the only site.

## OS-13 — `python3` is 3.9 on stock macOS, and a 3.10-only call crashes there

shape: B

invariant: Core Python runs on Python 3.9 or newer — the floor is the stock macOS
`/usr/bin/python3` (3.9.6), which `python3` resolves to whenever no newer interpreter is
linked under that name. Elsewhere `python3` is 3.12+, so a 3.10-only call is green on every
machine that writes or tests it and crashes only there. No 3.10+ stdlib call or keyword:
`Path.write_text(newline=)` (pin line endings with `open(path, "w", newline="\n")`),
`zip(strict=)`, `int.bit_count`, `itertools.pairwise`, `aiter`/`anext`, `tomllib`,
`datetime.UTC`. Syntax (`match`, parenthesised context managers, `except*`) and runtime
`X | Y` unions without `from __future__ import annotations` are caught by compiling and
running under 3.9, not by this pattern — CI does both (job `python-floor`).
pattern:   ^(?!.*\b(open|reconfigure|TextIOWrapper)\()[^#]*\bnewline=|zip\(.*\bstrict=|\.bit_count\(|^\s*(import|from) tomllib|datetime\.UTC\b|^\s*from datetime import[^#]*\bUTC\b|\bpairwise\(|\ba(iter|next)\(
paths:     --include=*.py scripts helpers skills
known:
instances: 32
repeat:    no
status:    closed
note:      Measured 2026-10-10 on a macOS brain: a Homebrew upgrade left python@3.14 without
an unversioned `python3` link, so `python3` fell back to `/usr/bin/python3` = 3.9.6, and
`scripts/shared-memory-index.py` died with `TypeError: write_text() got an unexpected
keyword argument 'newline'`. Under that interpreter 10 of 20 `*-test.py` suites failed the
same way. All 32 `write_text(..., newline=)` statements (17 files, scripts and fixtures) now
write through `open()`; afterwards 64 of 64 `.py` files compile and 20 of 20 Python suites
pass under 3.9.6. The other 3.10+ constructs in the invariant: none found. The pattern uses
Python `re` syntax (invariant-check.py's engine) — the negative lookahead is what lets it
see a `newline=` on the CONTINUATION line of a multi-line `write_text(` call while skipping
`open(`/`reconfigure(`; positive control: on the unfixed tree it hits every such
statement. Fixtures are in the search on purpose: they run under the same interpreter.
A new hit is read with one question: does this call exist in Python 3.9?

## OS-14 — a Python program that starts `bash` gets WSL's bash on Windows, not Git Bash

shape: B

invariant: Python code never starts `bash` by bare name. On Windows `C:\Windows\System32\bash.exe`
(the WSL launcher) comes before Git Bash in the PATH a native Python child sees, so
`subprocess.run(["bash", ...])` reaches WSL — on a machine without a distribution it fails
with "Windows Subsystem for Linux has no installed distributions", on one with a distribution
it runs the script in a different system with different paths. A check that needs a shell
script runs in a shell fixture (bash calls bash), or the Python side runs the logic itself.
pattern:   ["']bash["']\s*,|\[\s*["']bash["']
paths:     --include=*.py scripts helpers skills
known:
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-10-11 in CI (windows-latest): `changelog-assemble-test.py` ran
`release-preflight.sh` through `["bash", ...]` and failed on WSL, while a Windows workstation
with a different PATH order was green — the runner, not the machine, showed it. The round trip
moved into `release-preflight-test.sh`; the pattern then has zero hits in scripts, helpers and
skills.

## OS-15 — a hook calls an MSYS tool by bare name, and the hook's PATH has no Git\usr\bin

shape: C

invariant: A helper that runs as a Claude Code hook never starts a Git-Bash tool (`ps`, `kill`,
`sed`, …) by bare name. On Windows the PATH Claude Code hands its children holds `Git\cmd`, not
`Git\usr\bin`, so the tool is ENOENT in the hook while every check run from Git Bash (where
`/usr/bin` is on PATH) finds it. Resolve it from the Git install (`<dir of git.exe>\..\usr\bin`),
or do the work in node; and an unrunnable tool is "unknown", never a silent "no".
pattern:   (execFileSync|execSync|spawnSync|execFile|spawn)\(\s*['"](ps|kill|sed|awk|grep|tail|head|find|xargs|cut|tr|sort|uniq|wc|date|stat|ls|cat)\b
paths:     --include=*.cjs helpers
known:
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-10-11 on the Windows instance: `watch-gate.cjs` ran `execFileSync('ps', …)`
to test a watcher's MSYS pid; inside the hook it threw ENOENT, so every lock read as dead and the
gate blocked a push of a waiting fact file with the shared-memory watcher alive. Its earlier
measurement (exit 0 live, 1 dead, 2026-10-09) had run from Git Bash — the gate was checked where
the defect does not live, the form this register calls C. Reproduced: `node` started directly or
via `Git\usr\bin\bash.exe` gets ENOENT, via `Git\bin\bash.exe` (which adds `usr\bin` to PATH)
finds it. Fixed in the same pass (`psCandidates()`); fixture `test-watch-gate.sh` runs the gate
with exactly the hook's PATH (node's dir + `Git\cmd`). Zero hits after the fix.

## OS-16 — a fixture bounds a command with `timeout`, which stock macOS does not have

shape: B

invariant: A shell script in the core never calls `timeout`. Stock macOS ships none (GNU
coreutils via Homebrew names it `gtimeout`), so the call exits 127 there and every check built
on its output passes or fails for the wrong reason. `perl -e 'alarm …; exec …'` is no substitute
either: under Git Bash the alarm does not survive the exec and the command runs on (rc 0). Bound a
command with a background run and a sleeper that kills it (`deadline()` in the two fixtures below).
pattern:   ^[^#]*(^|[^a-z_`-])timeout [0-9]
paths:     --include=*.sh scripts helpers
known:
instances: 2
repeat:    no
status:    closed
note:      Measured 2026-10-14 on the macOS instance (bash 3.2): `shared-memory-watch-cursor-test.sh`
(PR #342) failed three checks with `timeout: command not found`; its three "untouched" halves passed
trivially because the watcher never ran. The search found a second site, `project-dir-test.sh`,
where the same 127 made "watcher keeps the brain's cursor" pass without a watcher — it now also
fails when the command did not run. Both fixed in #342; zero hits after the fix.

## OS-20 — `os.kill(pid, 0)` asks "is it alive?" on POSIX and kills the process on Windows

shape: B

invariant: A liveness probe in Python never calls `os.kill(pid, 0)` unguarded. On POSIX signal 0
only checks that the pid exists; on Windows `os.kill` with anything but the two console events
calls `TerminateProcess` — the probe ends the very session it asks about. Branch on `os.name`
and ask Windows for a handle (`OpenProcess` with `PROCESS_QUERY_LIMITED_INFORMATION`); each
known site is such a guarded branch.
pattern:   ^[^#]*os\.kill\([^)]*, *0\)
paths:     --include=*.py scripts helpers
known:     scripts/session-audit.py=1
instances: 1
repeat:    no
status:    closed
note:      Registered 2026-10-31 BEFORE a defect, with the first site: `session-audit.py` learned to
read the harness session registry (`~/.claude/sessions/<pid>.json`) and must test the pid. Python
documentation, `os.kill`: "Windows: … any other value for sig will cause the process to be
unconditionally killed by the TerminateProcess API". The Windows branch is unmeasured until the
PR's Windows check.

## OS-17 — `python3` exists on Windows but is the Store stub, and a script that only checks existence runs nothing

shape: B

invariant: A shell file that picks `python3` as its interpreter also probes that it RUNS:
`"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python`. On a Windows machine `python3` can be the
Microsoft Store alias: `command -v python3` succeeds, the call prints "Python was not found" and exits
non-zero. A choice that only checks existence (`command -v "$py" || py=python`,
`$(command -v python3 || command -v python)`) then runs every Python step against the stub - in a
fixture every case fails for the wrong reason, in a git hook the step is skipped without a word.
check:     scripts/test-python-probe.sh — per shell file under scripts/ helpers/ templates/ skills/
(`.sh` or a sh/bash shebang): probe lines >= python3 choices; with a negative control on fixtures.
Discovered by portability-smoke and the CI fixture step like every `scripts/test-*.sh`.
mechanizable: tool — "a probe follows the choice" spans two lines and a count per file; a grep count
over the tree cannot state it.
instances: 4
repeat:    yes
status:    closed
note:      Measured 2026-10-20 on a Windows instance during the full run at the 2.0.2 candidate
(f973145): `test-autonomy-diagnose.sh` (65 FAIL) and `test-decision-review.sh` failed on every tree -
fixed in #57, whose search covered only `PY=` lines in `scripts/*.sh`. The repeat came the same day:
`test-git-hooks.sh` failed in the smoke because `helpers/git-hooks/pre-commit` and
`prepare-commit-msg` (no extension, lower-case `py=`) checked existence only - so on such a machine
the shared-memory commit trailer was silently left out. Both hooks fixed; the tree check now finds no
site, and with the two old hooks put back it names exactly those two.

## OS-18 — a detached Python process starts console children, and Windows gives each one a new console

shape: B

invariant: A Python program that runs DETACHED on Windows (`DETACHED_PROCESS`, no console of its
own) passes `creationflags=CREATE_NO_WINDOW` (0x08000000) to every console child it starts (`bash`,
`git`, `python`). Without it each child gets a NEW console; with Windows Terminal as the default
terminal every console becomes a tab, and the run is slow on top. On macOS and Linux a detached
process has no such step, so the same code is quiet there.
pattern:   DETACHED_PROCESS|0x0+8\b
paths:     --include=*.py scripts helpers skills
known:     scripts/ledger-reconcile.py=1
instances: 1
repeat:    no
status:    closed
note:      Measured 2026-10-19 on the Windows instance: the `--cached` run of `ledger-reconcile.py`
(PR #41, heads before 9831ce0) started one `bash` per check without the flag; 136 tabs opened in one
Windows Terminal window (21:12:58-21:18:36 local time, pairs about every 3 s). 4 checks took 12.3 s
with default flags, 0.11 s with CREATE_NO_WINDOW. Fixed in #41 (`run_check`). The search lists the
detached launch, not the children: a new detached site is read for the children it starts.

## OS-19 — a hook reads a file the command hands over by its Git Bash path, which node on Windows cannot open

shape: A

invariant: A hook that reads a file named in the command text (`--body-file`, `-F`, `--input`)
translates the path as the shell sees it before opening it: `/c/...` to `C:/...`, other `/...` through
`cygpath -m` (`nativePath` in `helpers/public-text-guard.cjs`). Node on Windows reads `/c/...` as a
path on the current drive's root and fails; the hook swallows the read error and judges the command
without the file — on macOS and Linux the same path is the native one, so the defect is invisible there.
pattern:   publishedText\(
paths:     --include=*.cjs helpers
known:     helpers/instance-key-gate.cjs=1
known:     helpers/public-text-guard.cjs=1
known:     helpers/published-text.cjs=3
instances: 2
repeat:    yes
status:    closed
note:      Measured twice on Windows: 2026-10-14 `instance-key-gate.cjs` blocked `gh pr create --body-file
"/c/..."` as "carries no instance key" while the key stood in the file (the same file as `C:/...` passed);
2026-10-25 `public-text-guard.cjs` let a `--body-file /c/...` holding a person's name through (unreadable =
skipped). Both now translate with `nativePath`. The search lists the consumers of the handed-file list: a
new consumer appears as a new site and is read for the translation.
