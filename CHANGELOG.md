# Changelog — agent-brain

All notable changes to this repo. Versions are graded by content (AGENTS.md #5):
patch is the default (unproven capability included), minor = a proven-feature
re-release with clear notes, major = a big, thoroughly tested step.
The marketplace pins tags, never `main`.

## Unreleased

- **`python -` executed the file passed as its argument, and the one site it hit was the
  hand-tool guard.** Python 3.14's install manager — the `python3` on PATH on a Windows
  workstation — honours a SHEBANG in a file argument even when the program came in on
  stdin: it never ran the stdin program at all, read `#!/usr/bin/env bash` from the
  argument and launched bash on it. So `is_manual()` answered "not a hand tool" **and
  attempted to execute the very script it exists to keep from running**. Isolated: only a
  shebang-carrying file triggers it — a directory, a `.json` and a shebang-less `.sh` pass
  through as argv, which is why the other four stdin-program sites are unaffected and why
  the single affected one is the safety check. Invisible to the interpreter probe
  (`python3 -c 'import sys'` succeeds) and invisible to python.org's `python` 3.11 on the
  same machine. The candidate now travels in the environment. Registered as **OS-6**; the
  fixture from the previous release is what caught it, on the workstation, after CI on
  windows-latest had passed.
- **The trap register now carries derived CLASSES, not only cases** (operator order
  2026-08-31: keep every macOS/Windows issue in the register and derive the classes, so a
  new instance stops rediscovering each one by hand). Six entries in one day are three
  shapes: **A** the platform reshapes a string in transit (separator, line ending,
  encoding) · **B** the same command name is a different program (`grep`'s binary
  heuristic, `python3` as install manager, `stat -c`/`-f`) · **C** the gate does not run
  where the defect lives. Each entry states its shape, each shape says where to look FIRST
  on an unfamiliar platform, and a trap fitting none of the three is the interesting case:
  name the fourth shape rather than filing a one-off. Registering is due at instance 1 —
  that is not the build threshold.
- **`scripts/os-traps-export.py` — the register gets a signpost in shared memory**, because
  a tool repo is read when somebody checks it out while the shared repo is read by every
  instance at session start. Generated, never hand-kept: shapes, entries and status come
  from the register, so the pointer cannot drift the way six entries in one day would drift
  a hand-written list. Fixtures both directions, including the one specific to this tool —
  an entry with no shape must be VISIBLE rather than quietly filed under a shrug — and a
  register it cannot parse fails loudly instead of writing a confident-looking file.
- The routing is in `AGENTS.md` (rule 10) and the pointer for a new brain in
  `templates/invariants.md`: platform classes belong in the core register, never in an
  instance's own — filed per instance, every brain pays for the same trap once.
- **The stop gate moves into the core, and it now catches the HANDOFF, not just the
  question.** It lived in one instance only, so no other brain had it at all. And it
  matched a closing QUESTION — every pattern required a literal `?`. Measured on that
  instance 2026-08-31: four deferrals in one day, not one of them a question, every one
  parking work the three-condition test assigned to the agent — "yours to merge or to
  shred", "tell me which side takes it", "let me know if you want the fixture first",
  "the fix sits with the other instance". A question mark is a FORM; parking work on
  someone else is the FUNCTION, and only the function is the anti-pattern. The new shapes
  are ENGLISH built-ins, per this hook's own contract that a class fix lands in the
  built-ins and a language pack only ever adds a language — putting them in an instance
  file, as they first were, would have fixed one brain and left the class open in the
  others. Wired in `templates/settings.json` so existing brains pick it up through the
  hook-coverage path. Two negative controls in the fixture: a real operator boundary that
  is correctly STATED must pass, and so must a plain measurement report.
- The ported fixture carries the `native()` helper (OS-3) — it hands a transcript path to
  node, and a Git Bash path would have made every must-block case pass for the wrong
  reason. Caught by the trap register in the smoke run, not by review. Its `cwd` is now a
  scratch dir with no instance pattern file, so the new cases are proven to be carried by
  the built-ins alone; it used to be a hard-coded home path, which was both instance data
  in a core fixture and a leak-scan finding.

- **The fixture runner executed what `manual-tools.json` forbade.** That list keeps hand
  tools out of the trigger detector; the runner never read it, so one consumer of the same
  list forbade what the other executed, and the block looked intact from outside. Measured
  on a real instance: a script matching `*-test.sh` was not a test at all — it queries a
  physical network rig device by device. It ran twice, left two partial reports and sat in
  connection timeouts, so the self-test looked HUNG rather than failed; with the hardware
  powered on, a routine self-test would have been talking to production equipment. A
  second declared tool there writes to live devices and was stopped only by an argument
  guard — luck, not a contract. Both loops (shell and python) now skip a declared tool and
  SAY so. The fixture asserts the side effect, not the report: a marker file the hand tool
  writes when it runs. Negative control against the unguarded runner: it runs, 2 FAIL.
- **The arm lock could be deleted by a watcher that did not own it, and the claim was
  check-then-write** (`shared-memory-watch.sh`). The EXIT trap ran an unconditional
  `rm -f`, so a watcher from an earlier session that exits late removed whatever lock was
  there — including one a newer session had legitimately claimed. The next session then
  read "not armed" and started a duplicate on the same cursor, invisible to `status`,
  which can only ever name one pid. Measured: two watchers six minutes apart, both
  polling. Second defect in the same block: `lock_owner_alive` and `echo $$ > "$LOCK"`
  are two steps, so sessions arming close together all passed the check — 8 arming at
  once left 4, 2 and 2 alive across runs. Claim is now one step (`noclobber`, O_EXCL) and
  the trap only removes a lock that still names this process. Fixture
  `shared-memory-watch-lock-test.sh`, three properties; OWNERSHIP is the negative control
  and fails 3/3 on the unpatched script.
- **The watch line named the git ACCOUNT, which cannot identify the party**
  (`shared-memory-watch.sh`). Three parties share the repo and two of them share one
  account, so `%an` is correct exactly when the external collaborator commits and blind
  exactly in the confusable case. Measured incident: a session read `by arche-goah`,
  reported "the colleague sent two decisions", and both entries were `von:` the
  operator's own second machine — the record would have credited him with decisions that
  were never put to him. The line now reports the `von:` field of the changed entries and
  falls back to `unknown party (no von: field)` rather than to a name. Both directions
  are asserted in `shared-memory-watch-test.sh`: an entry from the collaborator is named
  as such, and one from our own workstation must NOT read as the collaborator — both
  pushes come from the same git identity in the sandbox, which is the point.
- Both fixtures take the script path as an optional argument and default to the sibling
  script, because the fixture runners discover suites by name and call them without
  arguments; the argument is what makes the negative controls runnable at all.

- **`shared-memory-index.py`: the factor line names the direction it measured.** "cheaper"
  was a fixed word beside a ratio that falls below 1 as soon as the index is already
  split — so a real run reported `0.1x cheaper per lookup` for a lookup ten times dearer.
  The arithmetic was never wrong; one word quit two opposite cases. Reported by the other
  instance from its own run, which is also the point: the generator had **no fixture at
  all**. It has one now (`shared-memory-index-test.py`, 7 cases): forward slashes in both
  index levels, LF in every written file, managed entries not carried into the root page,
  and both directions of the factor line, so a fix that hard-codes the other word fails.
  Negative control run: defects reintroduced → 5 of 7 red, fix restored → green. The
  discovery from the previous release picked the new suite up on its own.
- **`grep` swallowed report lines by calling the stream binary** — three sites in one
  afternoon, all in the failure path where nobody has a second copy: `session-bootup`
  printed `Binary file (standard input) matches` in place of the AHEAD line it had just
  computed, and `portability-smoke` did the same for a failing suite's FAIL detail AND for
  the os-trap register's drift lines — a gate reporting a failure it then made unreadable.
  14 greps on report paths (`brain-selftest`, `brain-check`, `effect-check`,
  `portability-smoke`) now pass `-a`; the remaining 20 are baselined as **OS-5** so a new
  pipe-grep is read rather than silently added. The review question is one word long: does
  this line end up in front of a human?
- **`brain-check` counted 7 fixtures green where 15 had run.** It matched `^  ok  test-`,
  one of the three naming shapes discovery now finds — a headline number measuring a third
  of what it names, in the one line the operator sees every session start. Counts the
  fixture block instead: 16.
- **The trigger detector reported backslashed paths**, so the other instance's new
  fixture (#100) failed on Windows in both its NEGATIVE cases — it greps the report for
  `scripts/<name>.sh` and got `scripts\<name>.sh`. The fixture was right; the report was
  platform-shaped. Measured here: that branch plus this one line turns all four of its
  cases green. Fifth site of OS-1 — and one its pattern could not see, because this path
  is built with `os.path.join`, not `str(relative_to())`. The class is the invariant, not
  the spelling that produced it: OS-1 now covers both constructors, searches `.sh` too
  (the defect sat in a python block inside a shell script, invisible to a `*.py` search)
  and carries a baseline of the join sites that only ever reach the filesystem — for a new
  hit the review question is one sentence: does this string reach a reader or a
  comparison, or only the filesystem?
- OS-1 gained the lesson that a PROSE mention counts as a hit: a fixture docstring
  describing the very defect tripped its own register the same day. Honest trade for a
  grep — it cannot tell code from a sentence about code, and weakening the pattern to
  spare the sentence would spare a real site in a fixture too.
- **The trigger detector never looked where CI wiring lives** (`brain-selftest.sh`). The
  classifier already had a `ci` branch for `.yml`/`.yaml` references — but `.github` was
  not among the directories it walked, so that branch was unreachable and every script
  invoked only from a workflow read as untriggered. Measured on this repo: 8 reported, 6
  real; the OS gate runner and one more are `run:` steps in `ci.yml`. Second half, found
  while fixing the first: inside a workflow file a `run:` line CALLS a script and a `#`
  line only mentions one, so workflow files are matched WITHOUT their comment lines —
  counting comments cleared a third script on the strength of prose. Third half, found
  while writing the comment explaining the second: naming a script inside this file makes
  this file that script's "reference" and clears it, which is exactly the trap the
  allowlist comment two blocks up already warned about. The explanation now carries no
  script names. No fixture: `brain-selftest.sh` has none, and the proof here is the
  measured before/after (8 → 6) plus the deliberate wrong state in between (5).

- **A core checkout AHEAD of the pin is not an update** (`session-bootup.sh`). The
  comparison was a string inequality, so a brain verifying an unreleased line — the
  brain-core-next channel exists for exactly this — was told `update available: v1.3.30-4
  -> v1.3.25` and pointed at `brain-update.sh`, which would move the submodule BACK and
  silently discard the checkout under test. Mirror of the suite-side guard from 1.3.24
  (a dev checkout legitimately lags); the class was fixed one function over and not swept.
  Reported either way, because an unremarked divergence from the pin is its own trap, but
  as its own state. Two Windows details fixed with it: the pipeline needed `grep -a`
  (Git Bash declared the stream binary and printed "Binary file (standard input) matches"
  in place of the line it was asked to print), and the line is ASCII, because that block's
  stdout is decoded by the console codepage and an em dash arrived as a replacement char.
- **The trigger detector knows the fixture naming shapes** (`brain-selftest.sh`).
  Discovery removed the only thing that NAMED a suite, so "executables nothing calls"
  reported six of them as untriggered the moment they started being discovered — the same
  indirection blind spot hook-coverage had with the dispatcher. A fixture is triggered by
  construction; all three naming shapes are now recognised as the fixture layer.

## 1.3.31 — 2026-08-31

- **Windows verification of 1.3.26–1.3.30, and the reason it was needed at all.** Three
  defects, one root each, all invisible to CI: `shared-memory-lint.py` and
  `shared-memory-index.py` stated repo-relative paths with `str(relative_to(...))`, which
  is backslashed on Windows — the linter reported 143 of 143 real files as missing from
  the index AND every index line as pointing at a missing file, and the generator, matching
  nothing against the old index, carried every existing entry into the root page (83,205
  chars instead of 1,651) with unfollowable links. The generator additionally wrote CRLF
  into a repo whose `.gitattributes` says LF (17 of 17 lines). `test-recall-gate.sh` handed
  node a Git-Bash `/tmp/...` transcript path: 4 of 13 cases failed and the other 9 were
  green for the wrong reason — the gate itself is fine. After the fix the linter returns
  the macOS numbers exactly (index_drift 0, frontmatter 0, limits 0, unresolved_links 8)
  and `--write` produces a byte-identical index: `git status` clean against what macOS
  generated.
- **`docs/os-traps.md` — a register for platform traps, re-run automatically.** CI runs on
  Linux, most of this repo is written on macOS, and Windows is where it breaks; worse, the
  breakage is silent, because a path comparison that always misses, a fixture whose
  transcript cannot be read and a generator writing CRLF all look like clean runs on the
  OS that cannot reproduce them. Three of these classes had already been fixed once
  (2026-08-10, 2026-08-13) and came back. Four entries, each an invariant plus the search
  spanning its space, run by `invariant-check.py` in CI and in `portability-smoke.sh`, so
  the search executes on every OS even where the defect itself is invisible. Extending it
  is one block; a class belongs there at instance 1.
- **The fixture runners discover suites instead of listing them.** The literal list in
  `portability-smoke.sh` named five suites and had not grown — `test-recall-gate.sh` and
  four `*-test.py` suites ran on Linux only, which is exactly how the three defects above
  shipped. CI carried the same list a second time, one step per suite. All three runners
  now glob (three naming shapes: `test-*.sh`, `*-test.sh`, `*-test.py`) and fail loudly if
  discovery yields nothing: the OS gate went from 5 suites to 12, `brain-selftest` from 8
  to 15. Registered as OS-4 — a hand-kept list of what to run is a second copy of the
  directory, and what it drops is the coverage the suites were written for.
- `invariant-check.py` accepts `--exclude=GLOB`, which its own docstring already promised
  by calling `paths` "the grep argument shape". Without it, a class whose space is
  production code only cannot be stated: the fixtures exercising the same pattern drown the
  baseline. Unsupported, the token fell through to the target list and the search died with
  `path not found`.
- `leak-scan.py` and `english-only.py`'s baseline writer swept along with OS-1/OS-2.
- **`invariant-check.py` reports closed classes that nothing could ever re-open.** The
  register's own header defines closed as "the search runs and finds nothing unknown, not
  that it feels settled" — but an entry with neither a `pattern` nor a
  `mechanizable: tool` has no search and no tool behind it. Measured on a real register:
  13 such entries, 6 closed outright. What produced the class: a class was declared closed
  on the strength of its CARRIER having been built, while three prose copies of the value
  that carrier now owned stayed behind and went stale the moment the value changed. A
  carrier does not delete the copies, it only makes them redundant. Report, never a
  failure.
- **A `status` field is prose, not an enum.** It was matched exactly against
  `("offen", "open")`, which hit 9 of 45 entries on a real register; the other 36 silently
  lost their build-threshold verdict — the one line that says whether a mechanism is due.
  Now matched as a word, with open and closed read separately, because a status can say
  both. This uncovered a second defect it had been hiding: `verdict()` called `int()` on
  the whole hand-written `instances` field, which is prose as often as a number, and those
  entries had simply never reached that line.
- **`ci-watch.sh`: "the run does not exist yet" is a wait in `pr` mode too.** Armed in the
  same turn as the push — which the reload rule asks for — a pr-mode watch hit
  `gh pr checks` before GitHub had registered the run; gh answers rc=1 "no checks
  reported", which fell through to a hard UNKNOWN and ended the watch with no verdict
  seconds before the run turned green. `ref` mode had always known this case and said so.
  An empty check list is the same ambiguity one level on ("this repo has no CI" vs. "not
  registered yet") and now waits as well. The deadline still ends the watch honestly, and
  a genuine gh failure still exits immediately — that negative control is a fixture.

## 1.3.30 — 2026-08-30

- **`scripts/shared-memory-index.py` — the shared index is generated, three levels,
  routing-first.** Measured on the real repo: the hand-written index was 91,029 chars
  across 142 entries, of which only 16 % was title and path. The other 84 % was
  descriptive prose that every one of those files already carries in its frontmatter —
  a hand-maintained second copy, exactly what the project-ledger rule forbids, and it
  had drifted: ten substantive files were reachable only by walking the folders. Root
  routes by topic (1,679 chars), the topic index routes by entry, the file holds the
  text. A lookup costs 20,189 chars (~5k tokens) instead of 91,185 (~22.8k). Nothing is
  invented or shortened — the discriminator is the file's own description cut at a
  sentence boundary — and index lines pointing outside the managed shape are carried
  through verbatim, measured before the first write because one such line existed. No
  "still open" section: 71 of 142 files carry a priority marker, so it would flag half
  the corpus, and no field in that repo reliably says "needs someone". Open work stays
  in the ledgers rather than becoming a third drifting list.
- **`shared-memory-lint.py` follows topic sub-indexes**, and an `INDEX.md` at any depth
  is an index rather than an entry. Generating the split broke the linter the same way
  `memory-lint` broke before #79 — third repo, same invariant: every consumer of the
  index STRUCTURE has to know sub-indexes exist, not only the one fixed first.
- **`invariant-check.py` separates "cannot be mechanized" from "not mechanized yet".**
  Measured on a real register: 43 entries, 8 with a pattern, 35 printed identically as
  `-- external`. One symbol for three states — a class that cannot be greppable (the
  search term is in the change, not the register), a class a named TOOL re-checks, and a
  class nobody has mechanized yet. The third is a backlog, and printed like the others
  it was invisible: a register whose purpose is that "a class needs a place where it
  stays open" had stopped holding 81 % of its classes open. Now `mechanizable: no — …`
  or `mechanizable: tool — …` records the decision, and its absence reports as `??` with
  a closing count.
- **The runner got its first fixture**, which had made it an instance of an invariant its
  own register carries — "a mechanism without a fixture is an assertion about itself".
  Seven cases wired into CI, four negative: a stated reason must not count as backlog,
  `mechanizable` must not silence a real pattern, an open entry must still print its
  verdict, and the tool state must not count as backlog either.

## 1.3.29 — 2026-08-30

- **Archiving is relevance-based, never age-based** (`shared-memory-lint.py`, operator
  instruction). The check shipped in 1.3.27 was wrong twice over, and both errors point
  the same way: it keyed on 120 days without a commit AND on a settled marker in the
  file's own body — so an untouched three-year-old decision scored as archivable, and a
  row saying "done" scored highest, when a settled decision is exactly the one somebody
  has to be able to trace later. Age measures attention, not relevance; "done" marks a
  record, not a leftover. The git-age helper is gone; no date enters this check at all.
  What replaces it is a supersession RELATION — a sentence that supersedes AND names a
  resolvable entry — and two things the real data taught while building it: the direction
  is written both ways (a repo's convention may be the superseded file marking itself
  rather than a successor announcing the replacement, so a one-directional check is blind
  to the convention actually in use), and supersession is often PARTIAL, retiring some
  sections of a file whose remainder still holds. The machine therefore reports the pair
  and its evidence line and does not decide which side may move; that needs a reader who
  can judge whether the content survives completely elsewhere. Deletion stays out of the
  mandate at every level. 25 fixtures, four of them negative — settled-but-unsuperseded
  stays put at any age.

## 1.3.28 — 2026-08-30

- **`skills/shared-memory-tidy` + `workflows/shared-memory-dream.js` — the judging half
  of the shared-memory tidy-up.** The machine half shipped in 1.3.27; this is what needs
  reading rather than counting. Four lenses in parallel (overlap, collision, currency,
  findability), then adversarial verification whose default is "not a finding", then a
  report grouped by **owner** — `us` / `other-party` / `both` / `operator` — rather than
  by severity, because with a second author the question "whose call is this?" decides
  more than "how bad is it?". Rewriting the other party's entry to tidy an index costs
  more trust than a noisy index costs time. Deletion is not in the mandate at any level;
  the strongest proposal is ARCHIVE or MERGE, with a pointer left behind. Three
  misjudgments are built out on purpose, all real shapes in that repo: a
  question/answer/follow-up thread across both sides is the collaboration working, not a
  duplicate; two entries that disagree are usually two machines or two versions, so every
  collision finding must name the condition under which BOTH are right and only one that
  cannot scores P1; an entry labelling itself a snapshot is not stale for saying so.
- **Bulk data never accumulates in the orchestrator** — the architectural rule this
  workflow was rebuilt around, after four measured failures of the same family on four
  real runs. A workflow script has no filesystem access, so anything the orchestrator
  holds can reach the next agent only through a prompt, and an agent handed bulk in a
  prompt regenerates it and drops rows silently, with a correct-looking count beside the
  truncated array. Measured: a tool table came back as 1 row of 141; the same table
  relayed "unchanged" came back as 22 of 141 at 115k tokens; a staging agent told to
  write the JSON it had been given wrote 2 verified and ZERO of 51 unverified. The rule
  that holds is narrower than "write a file": only what an agent PRODUCED can it write,
  so the producer writes and only pointers, counts and titles cross. Each lens now writes
  its own findings file and returns a thin, schema-validated index; verify agents are
  told which entry of which file to read and pointedly NOT given the finding.
  Consequence found on the next run and fixed here: moving findings into agent-written
  files bought completeness and cost validation — two of four lenses wrote `owner` as
  free prose and the routing tally counted a person as an owner class — so the index
  carries the enum, and routing stays constrained even when the file's prose drifts.
- Counts a model is asked for are assertions; the same counts computed in the script are
  measurements. `by_owner` is now reduced from the verified array (`coherence-scan.js`
  has carried the same guard for its register numbers all along).

## 1.3.27 — 2026-08-30

- **`scripts/shared-memory-lint.py` — the deterministic half of the shared-memory
  tidy-up.** The operator ordered that tidy-up as a repeatable procedure rather than a
  cleanup (2026-08-21): keep the shared memory compact, archive settled entries and
  logs, make search hits efficient, keep what matters prominent. This is its machine
  half; duplicates and contradictions stay judgment and belong to a read-only LLM pass,
  the same split `memory-lint` and `memory-dream` already use. Not `memory-lint` with a
  flag — a brain's auto-memory is flat, private, one index, one schema, while the shared
  repo is nested by topic, written by several instances plus an external collaborator,
  and carries append-only LOGs next to one-fact files; pointed at it, the flat linter
  reports the folder structure itself as drift. Seven checks: index drift both ways,
  frontmatter schema, name vs. filename, topic vs. folder, unresolved wikilinks, size
  limits (index and LOG), archive candidates. The archive check never proposes a
  deletion — it lists move candidates and keeps the index line.
  **Ratchet, like `english-only.py`:** the audience/topic convention was decided WITH
  the note that older files are legacy, not violations, so a plain check would be
  permanently red and train everyone to ignore it. Enforced in both directions, and the
  baseline lives IN the linted repo — that repo is private and this one is public, so a
  baseline here would publish a hundred file paths of a private collaboration.
  **Calibrated against the real repo, not guessed.** Four fixtures are false positives
  the instrument produced first: a bash `[[ … ]]` snippet parsed as a wikilink; the
  collaborator's verbatim skill copies linted as one-fact files (depth rule now: exactly
  `<topic>/<slug>.md`); `metadata.type: decision` rejected because the schema had been
  copied from the brain instead of read from that repo's own README; and an
  entry-length cap picked by feel that flagged a fifth of all entries — the measured
  distribution puts the runaway line at 1200, which flags five. Language markers are
  data, not code (`.shared-memory-markers.txt`); the first draft carried an umlaut
  variant that appears in zero real files and broke this repo's own English-only ratchet
  on four CI jobs at once. 21 fixtures, both directions, wired into CI.
  First real run: 139 files, 31 findings — 10 files unreachable from the index, 6 schema
  breaks, 1 name mismatch, 8 links no collaborator can follow, 6 size items.

## 1.3.26 — 2026-08-30

The carrier release, held back through the stability window and cut now that it is
over: knowledge that a session establishes has to leave something behind, and the
tools that read the index have to agree on what the index is.

⚠ **Instances upgrading from 1.3.25:** `RECALL-GATE` gained a SECOND trigger
(verification claims, below). If your `stop-checks.json` already registers the check
in `block` mode, it can now fire on turns that never tripped it before — check the
mode and run `record` for a few sessions first. Nothing else in this release changes
when an existing check fires.

- **recall-gate: verification CLAIMS are the second trigger** — the Windows
  instance's verification-doc-gate proposal (T5), built INTO the research gate rather
  than beside it, because it is one class: knowledge established, session over, no
  carrier. Tool counting misses the cheaper half — a single command can establish a
  mechanism, one tool call, far under any research threshold, worth more than fifty
  listings. That is the proposing instance's own incident: two-level nesting syntax
  verified live, called a breakthrough, nothing written down, recovered from a
  transcript two days and one failed live session later. A claim counts only when a
  verification VERB and a discovery OBJECT meet in the same text block ("verified" AND
  "mechanism/syntax/root cause/live") — the conjunction is the precision filter that
  keeps a routine "CI green, verified" from tripping it, and the reason the two lists
  are separate data. Threshold: 2 claims with nothing persisted since the first
  signal. Word lists are English in the core (this repo is English-only, and a word
  list is data, not code); a brain answering in another language ships its own in
  `.claude/rules/recall-tools.json` — config REPLACES rather than extends, so such a
  brain lists both languages there. Measured before arming (measure-then-arm rule,
  2026-08-20): 40 real transcripts in `--record` mode — the claim trigger fires in
  39/40 (2–37 claims per session), the research trigger in 19/40, `would_block` 0/40,
  because persistence is never zero in that brain. Specific, not silent. Six new
  fixtures, four of them negative controls.

- **memory-dream skill and workflow follow topic sub-indexes too.** The linter learned
  this below; the skill and the workflow did not, so on a brain that split a topic out
  they reported the whole topic as orphans — a class of non-findings hitting exactly
  the brains that followed the compaction advice. Same invariant, one statement per
  carrier. Class swept across the repo: the remaining `MEMORY.md` mentions
  (session-close, session-insights, session-bootup, bootstrap-brain, intelligence.md,
  templates/CLAUDE.md) speak of it as a place or a size limit, never as a form.

- **recall-gate + transcript-recall: research must leave a carrier, and the next
  session must look before it reads live again.** Measured on the Windows instance
  2026-08-21: a session spent ~60 % of its limit reading a reference showfile live, left
  one summary line, no memory file; the next session re-read the same structures live
  until the operator stopped it — the findings sat in the transcript all along. Two
  pieces, one class (same as the verification-doc gate proposal): `helpers/recall-gate.cjs`
  is a Stop check that counts live-research tool calls over the session and fires when
  they pass a threshold with nothing persisted since the first read (memory file, ledger,
  suite reference, shared-memory); cooldown 3 turns, re-fires only after NEW research,
  `--record` mode for the dispatcher so precision is measured before it is allowed to
  block. Which tools are research and which writes are persistence is instance data
  (`.claude/rules/recall-tools.json`, template in `templates/rules-instance/`).
  `scripts/transcript-recall.py` is the read side: one command over the project's own
  transcripts (keyword / `--session` from a commit trailer or `originSessionId`,
  `--days`, `--json`), stdlib, OS-agnostic. Fixtures both directions for both, wired
  into CI. Ships with the next collected release; instances register the check in
  `stop-checks.json` (mode `record` first).

- **memory-lint follows topic sub-indexes** (`index-<topic>.md`). A brain whose
  MEMORY.md grows toward the harness limit (200 lines / 25 KB, truncated silently) can
  now move a topic's entries into `index-<topic>.md` and keep ONE pointer line in
  MEMORY.md — the linter counts those entries as indexed, checks their targets and
  line length, and still reports a real orphan. One level deep, no recursion; an
  `index-*.md` that MEMORY.md does not link is an orphan like any other (a forgotten
  pointer line must stay visible, not silently detach a topic). Fixtures in both
  directions: `scripts/memory-lint-test.py`, wired into CI. Motivation measured on
  the macOS brain 2026-08-21: 121 entries, 19.7 KB, 33 memory files touched on one day
  — line-trimming alone bought ~1.7 KB, not a structure.

## 1.3.25 — 2026-08-20

- **brain-check/brain-selftest: ROOT fallback was one level too shallow in a consumed
  brain** (#77, found + fixed + verified by the Windows collaborator, relayed via
  shared memory). Without CLAUDE_PROJECT_DIR the hooks-wired check silently iterated
  over ZERO hooks and reported clean — a false green indistinguishable from fully
  wired — and memory-lint ran against core/ instead of the real memory. Reproduced
  independently on a second brain (0 hooks before, 13 after; bare repo unchanged).
  On the reporter'''s brain the fix unmasked a real pre-existing memory finding
  (52 name mismatches, 14 dead links) that had never been measured.

## 1.3.24 — 2026-08-20

- **The bootup's suite-update check now measures the right entity** (#75). A suite
  delivered as an installed plugin had its dev/PR checkout compared against remote tags
  a second time and reported a false "update available" while the operator-facing
  plugin was current. ecosystem-sync now stamps `consumer_plugin` onto the repo entry
  mechanically (matched by normalized remote slug from the local marketplace cache —
  a first, hand-annotated version keyed on a field nothing generated and never fired);
  the bootup skips stamped suites, keeps checking checkout-consuming ones, and a
  fixture suite proves both halves. Verified against a real consuming brain in both
  shapes: plugin-installed (skip fires) and checkout-consuming with an empty-installs
  registry husk (check stays live, correctly).

## 1.3.23 — 2026-08-20

- **brain-check/brain-selftest: a later PY override clobbered the python3->python probe**
  (#72, found + fixed + verified by the Windows collaborator via shared memory — no
  collaborator rights on this repo, patch relayed with credit). On any system without a
  python3 alias the machinery check always exited 1 regardless of machinery state; since
  v1.3.18 that failure landed in every session bootup. One PY resolution per script now.

- **The bootup's `|| true` is load-bearing for VISIBILITY, and now says so.** A sibling
  instance measured that the harness passes on only `hook_success`: the content of a
  NON-BLOCKING hook error reaches nobody's context. A non-zero exit from the embedded
  machinery check would therefore turn the whole bootup into a silent failure — the check
  would go quiet exactly in the case where it has something to report. Swallowing the exit
  code is what keeps the message; the comment exists so the next cleanup does not remove
  it. Same instance found the timeout half of this (PR #62, merged): ~6 s of embedded work
  under a 10 s hook timeout killed their entire bootup.

## 1.3.22 — 2026-08-20

- **skill-first had a blind spot the exact shape of the failure it exists to prevent**
  (operator finding). A loaded skill answered step 1 with "yes"; step 2 asked only
  whether the skill has the TOOLS; step 3 fires only when there is NO skill. A skill
  that exists and does not describe the PROCEDURE therefore fell through all three, and
  the work was improvised beside it — same job, different result each time, and the
  difference surfaced as troubleshooting at the hardware.
  - Step 2 now asks whether the skill covers the TASK, with a mechanical test: am I
    about to DECIDE something the skill does not dictate? Then the decision belongs in
    the skill first.
  - Step 3 gains the SEAM case: when skill A says "the other side runs through B" and B
    points back, the work between them belongs to nobody and gets reinvented every time.
    It goes to the skill that owns the artefact being built.
  - The header states that a task ARISING mid-session is a task. The check fires at the
    start of the WORK, not of the session — the unexpected sub-job is exactly where
    improvisation happens.

  ⚠ **Version incident, recorded because the rule exists for exactly this:** this change
  was prepared as 1.3.19 while a parallel session released 1.3.19-1.3.21. The merge
  therefore pushed plugin.json BACKWARDS from 1.3.21 to 1.3.19 on main for a few minutes.
  Versions are assigned by ONE session per release (AGENTS.md #8) — and the practical
  half of that rule is: re-read the version at the moment of the version bump, not when
  the work started. A tag that is burned is never re-cut; the next number supersedes it.

## 1.3.21 — 2026-08-20

- **brain-check --brief no longer mirrors the untriggered count into the unproven
  slot** (#67). Both selftest sections share the "  ??" marker; grepping it across
  the whole output double-counted whenever the fixture gap was 0. The brief line now
  reads the selftest's own tally. Reproduced on a second instance before merge
  (brief said 11 unproven, tally said 0); every consuming brain's bootup summary
  carried the wrong number each session start.

## 1.3.20 — 2026-08-20

- **memory-lint no longer misreads in-flight memory-sync writes** (#65). With several
  sessions open in one repo, a SessionStart lint could read the snapshot mid-write and
  report a phantom "content differs" (measured, workstation invariant I-7).
  memory-sync.cjs now holds an age-checked `.sync.lock` during export/import/prune/
  push/pull; memory-lint skips the snapshot comparison (and says so) while the lock is
  fresh (<15 s). Verified live on a second instance: skip with fresh lock, full check
  without, no lock residue. Residual class noted on the PR (reader-starts-first window,
  concurrent-writer unlink during `pull`) — register-notes, not regressions.

## 1.3.19 — 2026-08-20

- **v1.3.18 regression: the bootup hook timeout could kill the entire bootup** (#62).
  Folding brain-check into session-bootup.sh (v1.3.18) pushed the hook past the
  template's 10s ceiling — measured 11.57s real on an idle macOS machine, and
  `hook_cancelled` under load on Windows, losing the whole bootup summary. Template
  timeout raised to 30. Existing brains carry `timeout: 10` in their own
  settings.json and need the same one-line edit locally — the template only reaches
  brains bootstrapped after this.
- **Reporting duties get their own briefing line** (#63). A FAIL/`!!` item folded
  into a prose summary sentence satisfied the 2026-08-13 boundary rule and still got
  missed; the rule now demands a visually separated line plus the concrete next step.

## 1.3.18 — 2026-08-20

- **The session bootup runs the machinery check itself.** Proposed by a third instance
  that measured the same gap independently on its own machine, and it is the better
  mechanism: `templates/settings.json` reaches only brains bootstrapped AFTER an entry
  lands, while `helpers/session-bootup.sh` is shared core code that every consuming
  brain already runs. An instance cannot forget what it does not have to remember —
  which is the whole point, given that two machines were measured without the wiring
  within hours of the capability shipping.
  - The template entry from 1.3.16 is removed in the same move; keeping both would run
    the check twice on a newly bootstrapped brain.
  - The bootup never fails on it (`|| true`): a broken check must not keep a session
    from starting. Cost on a full brain: ~6 s, one line when everything is fine.
  - `hook-coverage`'s awareness of `core/scripts/` hooks (1.3.16) stays — it is the
    right contract regardless of what the template currently carries. Its smoke case
    now builds its own template instead of depending on the real one, which is why
    removing that entry turned a working check red.

## 1.3.17 — 2026-08-20

- **The machinery check works in a consuming brain, not only in this repo.** Wiring it
  (1.3.16) was not enough: run from a brain it reported "needs a look" and found almost
  nothing, for two reasons that are the same mistake twice — a tool assuming it stands
  where it was written.
  - `brain-selftest.sh` looked for fixtures in `scripts/` only. In a brain the suites
    live in `core/scripts/`, so every mechanism the core ships was listed as unproven
    while its fixture sat unused one directory away. Both locations are scanned now,
    each glob on its own (`ls a b` fails as soon as one is empty, which would have made
    the second location narrow the check instead of widening it).
  - `brain-check.sh` called its sibling scripts relative to the BRAIN, where they no
    longer exist once the brain consumes them from the core. Siblings are resolved next
    to the wrapper itself now — the failure it reported was its own path handling.

  Verified the way the gap was found: with `CLAUDE_PROJECT_DIR` pointing at a consuming
  brain, `brain-check --brief` reports `machinery ok — 6 fixture(s) green, 0 without an
  effect proof`.

## 1.3.16 — 2026-08-20

- **Shipping a capability is not delivering it** (operator finding, same day as
  1.3.15). A second instance pulled v1.3.15, started a fresh session, and no
  self-test ran: `brain-check.sh` was wired in ONE brain's `settings.json` and
  nowhere else. The author had reasoned from his own instance to everyone's — and an
  instance's settings are invisible from this repo, which is exactly why that
  reasoning cannot be checked by looking.
  - `templates/settings.json` now carries the SessionStart hook. That file is the
    documented default proposal for what a brain should have; it is the only shared
    surface between instances.
  - `hook-coverage.py` counts a template hook pointing at `core/scripts/` as well,
    not only `core/helpers/`. `brain-check.sh` lives in `scripts/`, so the check that
    exists to catch "shipped but not wired" was blind to precisely that shape. The
    bootup voices the gap every session and `brain-update.sh` warns after an update —
    which is what reaches brains that were bootstrapped long ago, since the template
    is copied once and never again.
  - AGENTS.md rule 9 states the class: a capability that must run in every brain needs
    the file, the template entry AND the demand. Two out of three is silence.
  - The 3-OS smoke asserts the new case: a brain with the template but empty settings
    must be told about the `core/scripts` hook, and a registered one must not.

## 1.3.15 — 2026-08-20

- **Two silent defects in the hook layer, found by writing the first fixtures.**
  Both had been true for as long as the files existed, and neither is visible by
  reading: a hook that does nothing looks exactly like a hook with nothing to do.
  - `class-gate`, `stop-verifier` and `file-guard` read their input inside a
    `setTimeout(..., 400)`. If the timer fires before the first `data` event the
    buffer is empty, `JSON.parse` throws and the hook **silently allows**. Measured
    on a sibling hook at 0 ms: same input, same file, once blocking and once
    completely silent. All three now read to `stdin` `end`, the way
    `reconnect-gate`, `freshness-gate` and `mechanism-guard` already did. 400 ms
    mitigates the race, it never promised it — and a gate that fails open at random
    cannot be told apart from one that agrees.
  - `junk-cleaner` skipped every dotfile and every directory, so `.DS_Store` and
    `__pycache__` were **never** removed although `rules/intelligence.md` #4 names
    exactly those two. The rule and the code had been saying different things.
    Fixed for both classes, and deliberately by two separate mechanisms, because
    they failed for two separate reasons: the dotfile needed an exception from the
    skip, the directory needed its own handling. Debris is matched by EXACT NAME
    (`.DS_Store`, `Thumbs.db`, `desktop.ini`, `__pycache__`, `.pytest_cache`,
    `.ruff_cache`) — everything on that list is regenerated by the tool that made
    it, an exact list cannot grow teeth the way a regex can, and symlinks are never
    followed.

- **`hook-coverage.py` understands indirection.** A dispatcher hook runs several
  checks itself, so `settings.json` names only the dispatcher; matching on helper
  filenames reported those helpers as missing on every session start. A warning
  that is always there stops being a signal. A helper now counts as covered when
  BOTH halves hold: a dispatcher is wired AND the helper is registered in
  `.claude/rules/stop-checks.json`. Either half alone would have turned the check
  into something you can silence by writing a file — the smoke asserts both
  directions.

- **`helpers/stop-dispatcher.cjs`** — one Stop hook that runs the others and reports
  their findings in ONE message instead of a slab each. Which checks run is instance
  DATA (`.claude/rules/stop-checks.json`), including the operator's language, so the
  engine carries no wording beyond an English fallback. A check can be `mode:
  "record"`: it never blocks and appends its findings to `.claude-state/<marker>.jsonl`
  for a report tool — that is how a noisy-but-usually-right check stops costing a
  re-issued answer without going blind. **The template keeps wiring the two Stop
  helpers directly**; the dispatcher is opt-in, because a brain that wires it without
  a config would run no checks at all and look perfectly fine doing it.

- **`helpers/premise-gate.cjs`** — blocks when a rule-shaped sentence carries an
  ACTION in the same turn (files written, a decision put to the operator, an
  instruction handed over) and asks for it to be held against every single
  observation, labelled measured / derived / assumed. Analysis alone stays free.
  Language data is instance-side; the built-ins are English. ⚠ Build note from the
  measurement: match the FORM of a rule (modal or copula plus universal, verb with a
  universally quantified subject, explicit quantification), never the bare word — the
  first version matched `always|never` and blocked **17 % of all turns**, almost all
  of it narration in the perfect tense. The shipped form blocks 3 %.

- **`scripts/brain-selftest.sh`, `scripts/brain-friction.py`, `scripts/brain-check.sh`**
  — the machinery checks. The first executes fixtures and asks "does every mechanism
  still run"; the second compares wiring against wiring and asks "do they contradict
  each other" (double firing, checks blind to indirection, recorders nobody reads,
  blocking checks without a cooldown, allowlist contradictions, dead imports); the
  third runs both, `--brief` for a session-start line. ~6 s, no model. Neither
  replaces `brain-scan` or `coherence-scan`: those READ configuration and rules and
  judge, which is why a helper can ship, update, pass every check and never run.

- **`scripts/gate-precision.py`** — judges a Stop gate by how often its block CHANGED
  the answer, and says out loud where that measure does not apply (a gate whose
  protocol is "answer with one line" is followed by a short new text, so "changed" is
  trivially true).

- **Five fixture suites, wired into the 3-OS portability job** (`test-guards`,
  `test-stop-checks`, `test-session-helpers`, `test-stop-dispatcher`,
  `test-premise-gate`). Every helper they cover is exercised in BOTH directions —
  an input that must trigger it and one that must stay silent; the second half
  carries the weight, because a gate that blocks everything is as broken as one that
  blocks nothing. They declare their subjects in a `# covers:` line so bundling does
  not look like deleting, they run in a brain layout and in this repo, and they bring
  their own instance data instead of borrowing whatever surrounds them.

## 1.3.14 — 2026-08-19

- **class-gate block speaks to the operator — operator-reviewed before release**
  (PR #56). Second finding on the same artifact in one day: the v1.3.13 terse
  block still carried five lines of compressed meta-instruction and produced
  jargon answer lines — word salad for the human whose terminal it lands in.
  Now two plain-language lines ("routine success check, not an error" defuses
  the harness's "Stop hook error:" prefix) and the demanded ⚙ answer line is
  explicitly ordered in plain operator language. The operator sighted a live
  firing and approved this wording. Lesson, same as the output style carries:
  terse is not the goal, readable is — a block text must remember who reads it.

## 1.3.13 — 2026-08-19

- Casing fix for the combination of the two PRs below (PR #55): #53 lower-cased a
  phrase #52's fresh smoke check matched exactly — each PR green against its own
  base, the combination red, caught by the release PR's CI doing its job.
- **class-gate blocks are terse now — the gate shows, the rule explains** (PR #53,
  operator finding, screenshot-verified: a ~20-line pedagogical block plus a long
  reflective answer buried the actual reply in the terminal). The block is 3 lines,
  points at thinking-protocol.md → Class Discipline, and demands ONE compact
  ⚙-prefixed answer line instead of an essay. Same trim applied to the proving
  instance's time-gate.
- **hook-coverage: a template hook that no settings scope wires gets a loud line**
  (PR #52, contributed by emil-workstation from its v1.3.12 catch-up — it measured
  THREE unwired template hooks on itself, including one whose rule text claimed it
  was "mechanically carried"). A hook shipped only as a CHANGELOG sentence leaves
  brains silently half-functional: `scripts/hook-coverage.py` compares the template
  against project/local/user settings by helper filename and reports missing lines
  (never edits — settings are operator territory); `session-bootup` repeats a `!!`
  line until wired; `brain-update` step 4c prints the exact lines to add.
- class-gate cwd strip normalizes separators (Windows transcripts carry backslash
  paths; repo-relative display was broken there — cosmetic, PR #52).
- shared-memory-watch-test pins `core.autocrlf false` in its sandbox (no more CRLF
  warning noise on Windows, PR #52). portability-smoke: 30 checks.

## 1.3.12 — 2026-08-19

- **The class gate moves into the core** (PR #50). The Stop gate that fires on
  SUCCESS (goal & level → invariant → register state) was instance-only, so every
  other brain received the Class Discipline rule as prose — exactly the
  stimulus-response form it is meant to break. Ported unchanged after 14 days of
  live operation (37 firing sessions, no wallpaper effect): transcript turn
  window, 3-operator-turn cooldown read from its own replayed feedback,
  doc/scratch filters, legacy echo marker recognized. `helpers/class-gate.cjs`,
  wired in `templates/settings.json`; existing brains add one Stop-hook line:
  `node "$CLAUDE_PROJECT_DIR/core/helpers/class-gate.cjs"`.
- **Invariant register is a fixed step now** (PR #50, operator order 2026-08-19).
  `templates/invariants.md` seeds the register; `brain-update` creates
  `docs/maintenance/invariants.md` when missing (never overwrites — the register
  is instance history); `bootstrap-brain.sh` creates it on fresh onboarding.
  A class needs a place where it stays open.
- **Foreign instance names removed from shared core artifacts** (PR #49,
  contributed by the Windows instance — measured there against v1.3.10: the
  coherence-scan walked rules that exist in no corpus, pure phantom traces).
  coherence-scan/full-audit/skill-builder/coherence-scan.js now parameterize over
  the instance's auto-fire table and domain ledgers instead of naming one owner's
  skills, domains and repos (CONVENTIONS §1). A walked rule existing nowhere is
  now itself a declared finding.
- portability-smoke +4 checks (gate block/cooldown/doc-turn, register template
  parses in the runner), all three OSes.

## 1.3.11 — 2026-08-19

- **Anti-hallucination #8: mechanism over memory — a recalled rule is a pointer,
  not a license** (PR #43, contributed by the Windows instance from its own
  operator instruction). Before applying a rule recalled from memory, restate its
  mechanism causally in your own words; if you cannot, re-verify at the primary
  source before acting. Incident behind it: two memory entries read as
  contradictory under text-level pattern matching; both were correct once the
  actual mechanism was traced. Complements v1.3.9/v1.3.10: those govern how a
  lesson is STORED (invariant + carrier), this one guards the moment of APPLYING
  it — together they close both ends of the stimulus-response failure.

## 1.3.10 — 2026-08-19

- **Class discipline moved into the core** (PR #46, phase 2 of the 2026-08-06
  rebuild, shipped after the two-week evaluation measured that the register and
  gate carry). Four carriers that proved themselves on one instance now reach
  every brain:
  - `scripts/invariant-check.py` — the invariant-register runner, pure Python
    (a grep subprocess is a Windows mine). The port surfaced a defect in the
    grep era: `--include` filters also swallowed explicitly named file targets,
    so a register could carry a dead target and report ok. Explicit targets are
    now always searched; otherwise hit-for-hit equivalent on both live registers.
  - `helpers/stop-verifier.cjs` v2 — reads the TURN from the transcript (text
    written by the edit tools since the last real operator message) instead of
    the git working tree, which measured history: stale artifacts blocked
    unrelated turns, committed work went unseen. Pre-existing markers in a
    touched file no longer block; only markers this turn added do.
  - `helpers/session-bootup.sh` — deadline headings (`## YYYY-MM-DD`) are now
    computed: nearest date, distance in days, `!!` when under 7 days or overdue.
    "present — check it" was presence, not effect.
  - `rules/thinking-protocol.md` — Class Discipline section as a POINTER to the
    mechanism (Class Gate skill, register + runner) carrying the build threshold.
  - `rules/intelligence.md` — skill-first order of inquiry (operator order
    2026-08-19): skill exists? → use it; tools complete? → missing tool is the
    build order; repeatable class without a skill? → define it first; ad hoc
    intelligence only for genuine one-offs. Procedures live in skills, memory
    holds lesson + pointer.
  portability-smoke grew six checks for all of this, executed on the three CI
  OSes (the Windows leg caught a real one: node cannot open MSYS /tmp paths).

## 1.3.9 — 2026-08-19

- **Knowledge carriers: a lesson is not kept until it has a carrier** (PR #44).
  A sibling instance self-diagnosed the failure mode: domain rules recalled as
  stimulus→response text instead of a causal model, errors repeated despite the
  notes, no skills forming for repeatable tasks. The core's only skill-formation
  trigger was "same task done manually 3x" — a repetition counter nothing counts,
  so it never fired; the working trigger (per-task class question) lived only in
  one instance's operator orders. `rules/intelligence.md` now carries a
  Knowledge-Carriers ladder — name the invariant, pick the strongest carrier
  (check/gate > tool/skill > mechanism doc > memory), mechanism docs written as
  explanation and placed in the suite when reusable — and the proactive table
  asks the class question at execution time instead of counting. Propose gate
  unchanged.

## 1.3.8 — 2026-08-18

- **Shared-memory awareness is a carrier now, not a habit** (PR #41). An instance
  learned about the shared record only when someone remembered to pull it — and a
  stale checkout is indistinguishable from a quiet one. Measured on 2026-08-18: a
  second instance's first pull of the session was stale and only the second brought
  in an entry that had been waiting; on the same day it asked, in the shared repo,
  whether any watchdog existed at all, because it could not see the other machine's
  instance-local scripts. That is the shape of instance-local mechanics: they work
  for exactly one brain and are invisible to the next one.
  Two levels, one cursor, both folded into the core:
  `helpers/shared-memory-check.sh` runs from `session-bootup.sh` and reports what
  arrived since this instance last looked; `scripts/shared-memory-watch.sh` is the
  persistent live watch for a running session, driven by Monitor. Skill
  `shared-memory-watch` documents when to arm it unasked.
  Properties kept from the proving instance: one watcher per machine (lock), own
  pushes are not events (reachability, never author names — one operator's name is
  the same on both their machines), a missing cursor aborts loudly instead of
  watching blind, and the repo path is overridable so the core hardcodes no instance
  path. `scripts/shared-memory-watch-test.sh` is the negative control — a watcher
  nobody has seen fire cannot be told apart from a broken one — and it now runs in
  the portability job on all three operating systems.
- Stale skill counts in `plugin.json` and `README.md` replaced by a pointer to
  `skills/REGISTRY.md`; the number had drifted twice already and is generated anyway.

## 1.3.7 — 2026-08-17

- **The cross-instance record is part of closing a session, not an afterthought**
  (PR #39). `session-close` secured memory, session log, decision log and commits —
  and said nothing about the record OTHER instances read at their session start.
  Measured the day this landed: three merged PRs corrected a claim the shared record
  still stated as open, and the entry only got written after the operator asked; the
  close had already reported success. It slips because a PR thread, a chat answer and
  a merged commit all *feel* like the finding is recorded — those are the volatile
  forms, and a collaborator on another machine reads none of them.
  Step 1 now asks, per finding, whether its REACH goes past this machine, and requires
  the entry to be pushed before the session ends. Step 5 requires the close report to
  name what went there **or** state that nothing had that reach — an unstated step
  reads as done. Where the shared record lives stays instance knowledge
  (CONVENTIONS §1); the skill only demands that the question is asked.

  Released on its own instead of collected: a rule about persistence that exists only
  on `main` is the very failure it describes — present, not effective.

## 1.3.6 — 2026-08-14

- **The Python interpreter is resolved, no longer assumed** (PR #37). A bare
  `python3` in command position is a Windows landmine: the python.org installer ships
  only `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH
  but does not run — so probing has to RUN the interpreter, never `command -v`.
  `onboarding-verify.sh` carried the fix and the explanation since the Windows
  onboarding; the class was never swept into its ten neighbours. Measured 2026-08-14 on
  a colleague brain mid-migration: no working `python3`, so every settings reader in
  `brain-update.sh` returned empty and the script printed `DONE` without having done
  anything — a green check with no effect, on the script that carries a migration. The
  same file documents this exact failure mode for the CR-in-pipes class two dozen lines
  above its first unguarded call. Swept: `session-bootup.sh`, `bootstrap-brain.sh`,
  `brain-update.sh`, `ci-watch.sh`, `effect-check.sh`, `handover-gate.sh`,
  `portability-smoke.sh`, `release-preflight.sh`, `suite-install.sh`,
  `last30days/sync.sh`. Carrier against a relapse: a CI lint step greps `*.sh` for a
  bare `python3` in command position — it found a site the sweep itself had missed
  before the first push. Proof: `portability-smoke.sh` under a stubbed `python3` goes
  from 3 FAIL to all-green, unstubbed stays green.

## 1.3.5 — 2026-08-14

- **`scripts/wait-mcp-reconnect.sh` + the rule that a needed reload is not a wait
  state** (operator order 2026-08-14, sharpening the 2026-08-06 watchdog order). Two
  things were wrong with the previous answer to "this needs a restart": it asked for a
  full Claude restart where an `/mcp` reconnect refreshes the tool list, and its watcher
  lived in one instance, matched `ps` output and compared PID sets. `ps -o comm=` does
  not exist on Windows, and the PID-set comparison is undecidable when a second session
  runs the same server — a foreign session's PID survives every reconnect of this one,
  so "all old PIDs gone" never becomes true and the watcher sleeps through the restart.
  The waiter now reads a boot stamp the SERVER writes (content compare, not mtime — the
  `stat -c/-f` / `date -r` class already broke the bootup in v1.2.0), which is one `cat`
  on every platform and reports the process that actually serves this session.
  Reachability is explicitly not proof: a stale server answers with the old code.
  Exit 0 reconnected · 2 unknown (loud) · 3 usage. Carried by portability-smoke, so all
  three exit paths are EXECUTED on ubuntu, macOS and Windows, not just parsed.
  The suite half of the contract is the stamp itself (grandma3-suite ≥ 1.1.12 writes
  `<GMA3_IPC_DIR>/mcp-boot.json`); a server without one cannot be waited on, and the
  waiter reports that missing carrier instead of reporting green.

## 1.3.4 — 2026-08-14

- **ci-watch.sh — robust CI waiter for PRs and refs, tags included** (PR #34,
  operator order after two ad-hoc watchers broke in one session): `gh run list
  --branch <tag>` never matches a tag run (a loop compared an empty field against
  "completed" forever — silence looked like still-running), and zsh's no-split on
  unquoted variables 404'd every call with the error swallowed. The tool matches
  refs via the headBranch JSON field, enumerates every terminal state, and cannot
  end silently: exit 0 green, 1 red, 2 UNKNOWN (loud, never reads as green).
  9 stubbed fixtures both directions wired into CI; proven live on its own PR.

## 1.3.3 — 2026-08-14

- **preflight.ps1 parses on Windows PowerShell 5.1 and measures the right thing**
  (PR #31, found and fixed by the workstation brain, proven ALL GREEN on real
  Win 11/PS 5.1): the file now carries a UTF-8 BOM (BOM-less .ps1 is read as ANSI
  by PS 5.1 — an em-dash byte became a string terminator and zero checks ran) and
  the SSH check proves GitHub ACCESS via `ssh -T` output like the bash edition,
  demoting the ssh-agent service to a WARN.
- **Node install advice satisfies the script's own gate** (PR #32): the bash
  preflight recommended `OpenJS.NodeJS.LTS` while gating on Node >= 23.6 —
  current LTS is 22, so the printed fix failed the very check that printed it.

## 1.3.2 — 2026-08-14

- **LA1 language audit, names** (PR #23) — every German-named artifact renamed with
  a one-major deprecation path: `rules/arbeitsregeln.md` -> `rules/working-rules.md`
  (stub keeps old imports loading via a relative `@working-rules.md` chain), skills
  `autonomer-lauf` -> `autonomous-run` and `kohaerenz-scan` -> `coherence-scan`
  (pointer stubs remain), workflows `coherence-scan.js` / `full-audit-synthesis.js`,
  templates `rules-instance/` with `working-rules-instance.md` +
  `intelligence-instance.md`, interface key `reports.kohaerenz` -> `reports.coherence`.
  session-bootup warns on legacy imports/skill names until the instance migrates.
- **LA1 language audit, ratchet** (PR #26) — `english-only.py` now token-checks every
  tracked PATH against a German name dictionary (all suffixes; shrink-only baseline
  `english-legacy-names.txt` carries only the deprecation stubs) and the content word
  list grows by 19 unambiguous words. Negative controls in both directions.
- **Spec Gate** (PR #24) — `verification-before-completion` gains the order-fidelity #4
  carrier: every completion claim answers the spec-deviation question explicitly; a
  deviation becomes a debt entry and is reported first.
- **Version grading** (PR #27, operator order 2026-08-14) — patch is the release
  default; minor is a deliberate re-release once features are proven in real runs.
- **Project Lifecycle rule** (PR #28) — `working-rules.md` defines what gets CREATED
  when a new project domain starts: tool/instance cut, ledger birth, domain-keyed
  history, memory placement, aggregator registration, suite wiring.
- **Self-contained onboarding** (PR #29) — `ONBOARDING.md` plus ported English
  scripts (`preflight.sh`/`.ps1`, `setup-shell-start.sh`, `onboarding-verify.sh`)
  and `docs/onboarding-contract.md` (11 checks, suite checks SKIP when absent);
  replaces the separate onboarding kit for the generic path. `preflight.ps1` is
  not yet exercised on a real Windows machine.

## 1.3.1 — 2026-08-13

- **Rules: Project Work Ledgers** (PR #21, operator decision 2026-08-13) — uniform
  project tracking across instances in `rules/arbeitsregeln.md`: one hand-maintained
  detail list per project domain in the PRIVATE instance repo (never the project/tool
  repo), entries carry `id`/`class`/`reach`/`origin` as the English cross-instance
  interface; overviews are generated, never hand-kept; `reach: shared` marks entries
  for the org shared-memory export (one-file-one-fact, deliberate act at close);
  decisions are pointers into the change/decision logs; brain maintenance lists carry
  brain-function work only. Patch: rule addition, no new mechanics.

## 1.3.0 — 2026-08-13

- **Bootup: suite clones are covered by the released-state check.** The existing
  check reads marketplace pins, so it sees plugins and the core submodule — but
  suites are consumed as git clones, and a new suite release tag reaches no pin:
  it slipped past every session start. The bootup now compares, for every
  `kind=suite` entry in the brain's ecosystem record, the newest remote `v*` tag
  against the newest tag reachable from the local checkout (parallel
  `ls-remote`, offline-silent). Only a genuinely newer remote tag is reported —
  a developer checkout sitting ahead stays silent; consumer checkouts get the
  `suite-install.sh` one-liner. Minor: new check.

## 1.2.1 — 2026-08-13

- **New capability: `helpers/freshness-gate.cjs` — the repeat-run rule gets a
  mechanical carrier (PR #15; ships first in 1.2.1 because v1.2.0 was tagged
  without it).** PreToolUse(Workflow) hook: relaunching a workflow whose last
  completed run is younger than the freshness threshold and cost real tokens is
  denied, pointing to the run record + journal instead. Explicit escapes only:
  `resumeFromRunId`, `// FRESHNESS-OK: <the unanswered question>`, failed or
  cheap prior runs. Thresholds are instance data
  (`.claude/rules/freshness-gate.json`) so a scheduled cadence lowers its
  per-workflow threshold instead of carrying a permanent marker. 12 fixtures in
  both directions wired into CI; template settings, helpers README (drift:
  mechanism/secret-guard rows were missing) and the rule pointer in
  `rules/intelligence.md` updated. Minor grade inside a patch-numbered release:
  the 1.2.x line was already assigned when the batch closed — content noted
  here, counter not reshuffled.

- **Fix: the v1.2.0 release shipped with `plugin.json` still saying 1.1.2** —
  the release checklist (AGENTS.md #5) bumps it every time, and the version
  string is exactly what the plugin cache collides on (the measured crossover
  class): same string + different content = a stale cache that looks current.
  No content change beyond the manifest version.

## 1.2.0 — 2026-08-13

- **New capability: `scripts/suite-install.sh` — one command fetches a released
  tool suite.** Colleagues consume the suites (mikrotik, grandma3, chataigne,
  show-tools) as git clones, and until now "get the release" was tribal
  knowledge (clone, fetch, find the right tag). The script resolves path +
  remote from the brain's ecosystem record (defaults for a fresh brain), clones
  or fetches, and checks out the newest `v*` tag — never `main`: an untagged
  state is not released. Local changes and developer checkouts (anything
  sitting on a branch it did not just clone) are a hard stop, so it can never
  eat a working copy. `--all` updates every suite the brain records; the
  ecosystem record is refreshed afterwards. Wiring (.mcp.json entry, skill
  symlinks) stays a documented hand step on purpose — launchers carry
  operator-specific addresses and credential names.

## 1.1.2 — 2026-08-13

- **Rules: the session-start summary is written in human language (PR #12).**
  The rule ordered a mini-summary but said nothing about its language, so raw
  hook vocabulary (`!!` markers, return codes) leaked into chat and pending
  decisions ended as a generic "what's next?" instead of a direct question
  ("update available — shall I run it?"). The Session Start section of
  `rules/intelligence.md` now requires translating machine artifacts into
  operator-facing language — in every chat output, not just the session start.
  Patch: docs only.

## 1.1.1 — 2026-08-13

- **brain-update: cache provenance checks EVERY install scope, not entry zero
  (PR #9).** With a project-scope duplicate next to the user-scope install, the
  records masked each other and a FAIL could hide behind a healthy first entry
  (measured on both brains during the repo-move migration). Each scope is now
  verified on its own; the FAIL text names the scope so the printed
  uninstall/reinstall heals the right record.
- **Docs: the canonical core update path is `brain-update.sh` (PR #10).**
  templates/CLAUDE.md, README and CONVENTIONS still recommended
  `git submodule update --remote core` + `claude plugin update` — `--remote`
  tracks `main`, not the released pin, and after the brain-core → agent-brain
  repo move it resolves the OLD repo's main (now an archive notice). All three
  spots name the one command and say why `--remote` is not the path. Patch:
  fix + docs, no new capability.

## 1.1.0 — 2026-08-13

- **brain-scan: CVE identifiers require an official source (PR #2).** Both SOTA
  scan agents carry a shared CVE rule: an identifier counts as fact only when read
  in the same run from an official source (the repo's GitHub Security Advisories,
  NVD/MITRE by ID, vendor advisory). Web-search-only numbers are titled
  UNCONFIRMED, state `configured`, never `verified`. Incident: a scan reported
  five CVE numbers as P0/verified that exist in no official source.
- **brain-update: plugin cache provenance is verified against the pinned source
  (PR #3, message wording PR #7).** The cache is keyed by name+version, not by
  source — after a repo move, foreign content can survive under the right version
  name. Step 2b compares each installed `gitCommitSha` against the pin's remote
  tag SHA; a mismatch FAILs loudly (foreign content OR stale install record —
  indistinguishable from the SHA; the printed reinstall heals both) and FAIL
  lines now reach the exit code instead of printing DONE over them. Minor: new
  verification capability.
- **brain-scan launcher: headless background-wait ceiling raised to 90 min
  (PR #4).** Headless `claude -p` kills background work after 600 s by default
  (documented: `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`, default 600000, since
  CLI v2.1.182) — the scheduled scan died report-less at rc=0. 90 min instead of
  infinite so a hung run cannot pile up; an outer value wins.
- **thinking-protocol #0: relative time references are measurement claims
  (PR #5).** "Yesterday"/"last week" assert a measured timestamp — read the
  source's timestamp and compute, or omit the time reference entirely.
- **Language scope: native orthography belongs to chat, ASCII transliteration to
  artifacts (PR #6).** AGENTS.md #7 states the artifact scope explicitly;
  the caveman style carries the chat-side rule to every consuming brain.

## 1.0.1 — 2026-08-13

- **brain-update: the core/ submodule follows the MARKETPLACE PIN on every layer
  that names the repo.** Ported from the predecessor's final release and extended:
  step 3 reads the pinned `source.repo`/`source.ref` for the core plugin from the
  refreshed marketplace cache, aligns the submodule origin when the pin names a
  different repo (ssh/https forms compare equal), and now ALSO rewrites the
  `.gitmodules` declaration (+ `git submodule sync`). A fresh clone reads only
  the declaration — the live-only fix left every future clone of a migrated
  brain resolving the old repo, where the pinned commit does not exist (found by
  a second instance right after the cut, 2026-08-13). Step 5 commits
  `.gitmodules` along with the pin. Patch: fix of the cutover mechanism.

## 1.0.0 — 2026-08-13

Initial public cut. This repo is a fresh cut of a privately grown core: the full
released state of its predecessor, with a fresh history, fully translated to
English, and with maintainer-internal tooling removed. The version counter starts
at 1.0.0 — the predecessor's counter does not carry over.

Content at the cut:

- **Plugin channel** (`.claude-plugin/plugin.json`, plugin name `brain-core`):
  22 general-purpose skills under `skills/`, the caveman output style under
  `output-styles/` (active via `force-for-plugin`).
- **Submodule channel**: working rules (`rules/`), session hooks and guards
  (`helpers/`), contract and audit scripts (`scripts/`), audit workflows
  (`workflows/`), instance templates (`templates/`), the ecosystem contract
  (`CONVENTIONS.md` + `core-contract.json`).
- **CI**: leak scan, skill lint, english-only ratchet, helper/workflow parse
  checks, 3-OS portability smoke (scripts are executed, not only linted),
  contract checks.

The plugin keeps the name `brain-core` so existing `brain-core:<skill>` references
in consuming brains stay valid; only the repo is new.
