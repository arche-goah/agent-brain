# Changelog — agent-brain

All notable changes to this repo. Versions are graded by content (AGENTS.md #5):
patch is the default (unproven capability included), minor = a proven-feature
re-release with clear notes, major = a big, thoroughly tested step.
The marketplace pins tags, never `main`.

## Unreleased

- **`cached-verdict.sh` no longer files a run that was cut off as its verdict, and `brain-check --brief` names what is red.** Measured 2026-09-24 on a macOS brain: the session start showed `SELF-TEST: FAILURE` with a single green fixture line above it and no failing check anywhere, while a fresh uncached run was 43/43 green. The signal traps (`trap release_lock EXIT INT TERM`, in the parent and in the background child) only cleaned up, and bash continues after a trap handler returns: TERM landed on the fixture run and on the script alike, the handler released the lock, and execution went on into the store — the one line printed so far and rc 143 were written under the CURRENT key and replayed as "unchanged" until the key changed. Reproduced with a two-line payload killed by TERM after the first line: meta `new|…|143`, output one line. Signals now only set a flag; the lock goes on EXIT; an interrupted run stores nothing, keeps the previous verdict and says so. What delivers the TERM (hook timeout, session end) is not measured — the fix does not depend on it. Second, the brief form printed only lines matching `!!` or `FAILURE`, so it could say "red" without saying what: it now also carries each failing check's indented detail lines and the `(reused: …)` line that says the verdict is a stored one, and a red result that names no failing check says so explicitly as a defect of the self-test. Fixture property 9 in `cached-verdict-test.sh`: a run killed mid-way in the foreground and in the background keeps the previous meta and output, announces that nothing was stored and releases the lock; a run that FINISHES with a failure is still stored (negative control). Red against the previous script: 4 of 7 checks fail.

## 1.3.39 — 2026-09-24

- **AGENTS.md rule 11: merging into `main` meets two walls.** Measured 2026-09-24 on #158: a PR opened by the code-owner account cannot be approved (GitHub forbids self-approval, CODEOWNERS names one account), so its path is the admin bypass; and on an instance whose `settings.json` has no `allow` rule for that call, the auto-mode classifier refuses the bypass before it leaves the machine, while another instance with `Bash(gh pr *)` allowed merges the same way. The knowledge lived only in one instance's private memory, so the second instance searched for the cause on GitHub. The rule quotes both refusals verbatim, says which one is an instance permission, and asks for `--match-head-commit` on the reviewed state.

- **`brain-check.sh --brief` no longer raises a permanent false alarm on Windows, and when it does warn it names what to look at.** Measured 2026-09-24 on a Windows brain (Git Bash, Python 3.14) against v1.3.38: the session-start form printed `[: 1<0x97> decide each, ...: integer expression expected` and `!! brain-check: needs a look` at every start, while a hand-run `brain-check.sh` was green. `brain-friction.py` left its stdout to the platform: through a pipe Python on Windows writes the ANSI codepage and CRLF, so the headline em dash left as the single byte 0x97 and the `sed` that lifts the candidate count could consume neither. Fixed at the producer: `brain-friction.py` and `invariant-check.py` (the second parsed site, read by `brain-selftest.sh`) pin `sys.stdout` to UTF-8 and LF. Second, OS-independent: the brief branch's `sed` range had no room for the space before the count (`allowlist-contradiction (1):`), so it said "needs a look" and named nothing. Register entry OS-9 in `docs/os-traps.md` (baseline of 13 non-ASCII print sites, only one parsed). Gates in `portability-smoke.sh`, each red against the unfixed state: the friction stdout carries no CR and decodes as UTF-8 — asserted on the bytes of a PIPE, because a `>` redirect ends LF on the same machine and would be green against this defect — and a fixture brain with a declared-but-called hand tool makes brief mode warn AND name the tool.

- **`brain-friction.py` no longer reports a fixture as a scheduler.** Measured 2026-09-24 on a Windows brain: `onboarding-verify.sh` is allowlisted as hand-run by construction, and the friction scan reported it as an `allowlist-contradiction` against `test-onboarding-leak-check.sh` — its own fixture. The check's own wording already drew the line ("being USED by another tool is fine; being scheduled behind the operator's back is not"), the code did not: ANY caller counted. That put two mechanisms of this repo against each other — `brain-selftest.sh` demands an effect proof for every mechanism, and writing one then produced a permanent friction candidate on every instance that has a hand tool with a fixture, which is the shape the repo asks for. Callers are now filtered with the SAME fixture predicate `brain-selftest.sh` already uses for the identical blind spot (`test-*`, `*-test.sh`, `*-test.py`). Second defect in the same line, surfaced by the fixture: the report named `callers[0]`, so with a fixture sorting ahead of a real scheduler it pointed at the harmless half of the find; it now names a real caller. Fixture `scripts/brain-friction-test.py`, four cases: fixture-only caller stays silent, a real caller is still reported, with both present the REAL one is named (names chosen so the fixture sorts FIRST — the first draft used the obvious names and passed against the broken scanner, proving nothing), and the sibling `stale-allowlist` branch still fires. Red against the previous script: 2 of 4 fail. Measured on the reporting brain: the candidate is gone, the scan reports no candidates, self-test green. Class searched — `brain-selftest.sh` already excludes fixtures at both of its own sites (`is_fixture`, and the glob-discovered runners), so this was the one remaining place where a fixture counted as a wiring.
- **`leak-scan.py --root` scans the tree it is pointed at, with that tree's watch list.** Measured 2026-09-23 by a brain-scan on a macOS brain: the documented way for a brain to re-measure itself, `python3 core/scripts/leak-scan.py --only <paths>`, scanned the `core/` submodule, because `ROOT` is the script's own checkout — every person hit of that run lay in paths that exist only as `core/…`, and every brain re-measurement along that path since the core split was a pseudo-measurement. The watch list was read from the cwd while the files came from the script's checkout, so the two halves of one scan could even refer to different trees. New `--root DIR` sets both: files and `.claude/rules/leak-names.json` come from DIR. The default is unchanged (the scanner's own checkout), so suite CI, the core CI and `handover-gate.sh`, which all run it from the repo it lives in, behave exactly as before. Measured with the fix against the same brain (`--root <brain> --only CLAUDE.md .claude/rules`): 103 findings (101 person, 2 instance), where the old path reported only core files. Fixture in `portability-smoke.sh` (all three CI runners): a tree with its own watch list, a name and a run-time-built home path is scanned from a DIFFERENT cwd with `--root` and both hits are reported; the same call without `--root` from inside that tree does not see them (negative control: the default did not silently become the cwd). Red against the previous script: `--root` does not exist there, argparse exits 2. Class searched: the other callers (`handover-gate.sh`, the CI step, the global pre-commit hook) `cd` into the repo the scanner lives in, so they were right by construction; the hook deliberately skips a brain, which is the instance itself.
- **Session start names a reply on your own PR, names fresh moves, and says when it could not look.** Measured 2026-09-22 on a macOS brain: a collaborator posted "OK for merge" as a comment on two core PRs; the session starting four hours later showed neither, and the operator had to ask. Two independent gaps. First, `pr-ball.py` knew one move on your own PR — a CHANGES_REQUESTED review — and only after 24 h; a comment (the only review the ruleset leaves a collaborator) or an approval was never a move, and a fresh move was silence. New kind `yours - reply since your last commit`: someone else (not a bot) reviewed or commented after your last commit and your last comment. Every open move is now named; `--stall-hours` (default 24) only decides whether the line carries `!!`. Second, the start at 18:09 showed no network line at all — no open PRs, no PR move, no shared-memory commits — and a rerun three minutes later showed them; why the first run failed is not measured, because every network call was `2>/dev/null` and a failed call was indistinguishable from "nothing new". Now a failed `gh search` prints `open PRs: NOT checked - gh search failed (rc=N ...)` and skips the move query, and a failed shared-memory fetch prints `shared-memory: NOT checked - fetch failed` (the cursor still stays, as before). Fixtures: `test-pr-ball.sh` gains the measured comment case, an approval, an own answer and an older comment handing the move back, a bot comment, a fresh move named without `!!` and a stall with it — red against the previous script on the three positive cases; `test-shared-memory-check.sh` gains a fetch against a dead remote (NOT-checked line, no commit line, cursor unchanged) — red against the previous script. Measured on the real brain: with a failing `gh` in PATH the bootup prints the NOT-checked line under bash and zsh; with the real `gh` the new kind fired at once on a live PR whose reply had sat unanswered for nine days.
- **`release-preflight.sh` check 5 asks the repo it is checking.** Measured 2026-09-23 from a brain against a suite (`RELEASE_PREFLIGHT_ROOT=<suite>`): `gh pr list` resolves its repo from the working directory, not from `$ROOT`, so the competing-release-PR check answered for the caller's checkout (agent-brain) and printed a green "no competing open release PR" for the suite. The Release chain for suites that carry no copy of the script relies on exactly this call. `gh` now runs inside `$ROOT`. Fixture case 10 in `release-preflight-test.sh`: started from this checkout against a repo whose origin is a bare local twin, the check must not read green — red on the previous script (it answered for agent-brain), green now. Case 10 alone depends on an authenticated `gh` (without one both versions print `?`, measured on macOS in review), so case 10b puts a stub `gh` first on `PATH` that records its working directory and asserts it is `$ROOT` — network-free, red on the previous script also with `GH_TOKEN=bogus`, green now. Class searched: the script's other repo reads already use `git -C "$ROOT"`; this was the only call that took its repo from the working directory.

- **Session start says when the brain-scan is due, and a newer report clears a failed scheduled scan.** Operator decision 2026-09-23 on a macOS brain: no more unattended scans — the scan is confirmed and started inside an active session, and session start must announce it when it is due or overdue. Trigger was a scheduled run that fired on a lid-closed laptop on battery: only ~45 s dark wakes every 8-17 min (`pmset -g log`), every agent froze with each sleep and was restarted as stalled, and after the 90 min ceiling the run was killed with 2.34M tokens and no report. The bootup printed only the report age (`latest report 8d ago`), a number the reader has to hold against a threshold they may not know. Now it adds its own `!!` line: `brain-scan DUE` from 7 d (the scheduled runner's interval), `brain-scan OVERDUE` from 14 d (the repeat-run freshness window), and `DUE: no report yet` when there is none. Second half: an in-session run writes no run-record line, so once the scan moved into sessions, the last scheduled `fail` would have stood at every start forever — a `brain-scan` fail older than the newest report is now superseded and silent; a fail newer than the report stays voiced. The scheduled runner itself is unchanged and still works for a brain that keeps it. Fixtures in `portability-smoke.sh` (all three CI runners): fresh report is silent on both lines, an old report reads OVERDUE, no report reads DUE, an older brain-scan fail is swallowed and a newer one is not (negative control). Red against the previous bootup: three of the new checks fail, the negative control passes on both.

- **`shared-memory-index.py` no longer re-ingests its own output.** Reported by the collaborator instance 2026-09-21 and reproduced here the same day: every `--write` run appended the five topic pointers of the root page (`- [ops](ops/INDEX.md) — 98 entries`) a second time, under "Not one-fact entries" — three generations were standing in the shared repo, and the run that measured the defect added a fourth. Cause: the carry rule keeps every `- [` line of the OLD root index whose targets are real files outside the managed fact-file set, and the generator's own topic pointers are exactly that — real `<topic>/INDEX.md` files that are not fact files. A generator may not read its own output as foreign input. Topic pointers are now excluded by PATTERN (`^[^/]+/INDEX.md$`), not against the current topic list, so a pointer of a topic that no longer exists is dropped with them; a `seen` guard closes the same class one level up, so a duplicate already standing in the old index is carried once instead of twice. The stale generations heal on the next run, they do not need to be edited out by hand. Three fixtures in `scripts/shared-memory-index-test.py`, red against the previous script: the topic pointer appears once, a genuine unmanaged line (a delivery-copy README) still survives, and a second run reproduces the same page byte for byte. The first two assert on the SECOND page on purpose — on a fresh repo `<topic>/INDEX.md` does not exist yet while the old root is read, so run one carries nothing and a first-page assertion passes with the defect in place; the generation starts at run two, which is why the defect could sit unseen in a repo that is only ever regenerated in place. Class searched across the other core generators that read a file before writing one: `ecosystem-sync.py` re-reads its own manifest but keyed by repo (a dict cannot accumulate duplicates), `regen-skill-registry.py` and `os-traps-export.py` read inputs only — one site, no mechanism.
- **`cached-verdict.sh` reaps a lock whose holder is gone.** Measured 2026-09-18 on a macOS brain: the self-test stayed red at every session start with an 18 h old fixture verdict, marked "another session is measuring now; this is the previous result" — while no measuring process existed (`pgrep` empty). A fresh run without the cache was 42/42 green. The lock directory had outlived its run (a run killed without its EXIT trap firing leaves it behind), and the script honoured every existing lock unconditionally, so the dead run's verdict was replayed forever. The lock now carries the holder's PID and an owner token: a lock whose PID is dead is reaped and announced ("a previous run left its lock behind and is gone — reclaiming it"), a PID-less lock only after a minute (a live holder is between `mkdir` and the PID write), and any lock older than `CACHED_VERDICT_LOCK_MAX_MIN` (default 60) regardless of PID, because after a reboot the dead holder's PID can belong to an unrelated process. On a background miss the lock names the CHILD, not the parent that returns at once. Release only removes a lock that still carries the own token, so a run that outlived the ceiling cannot delete its successor's lock. Same answer the shared-memory watcher already gives (PID + `kill -0`); the third lock in the core (`memory-sync.cjs`) is age-checked on the reader's side — class searched, this was the only site without a staleness rule. Fixture `cached-verdict-test.sh`: the former "known limit" line becomes property 7 (dead holder reaped, live holder honoured and untouched, fresh PID-less lock honoured, old PID-less lock reaped, live PID past the ceiling reaped) and property 8 (a running background child is not reaped, and releases when done); against the previous script all five reaping checks fail, the honouring checks pass on both. Side fix in the fixture's counter: `grep -c` prints `0` AND exits 1 on no match, so `|| echo 0` produced `0\n0` — an assertion of zero runs could never pass.

- **Removed the empty junk file `skills/playwright-skill/0)`.** Found by a brain-scan on a collaborator instance: a zero-byte file with a code fragment as its name, present since b2faf33. The same scan's claim that `skills/REGISTRY.md` was stale was re-measured there and refuted (only the date changes), so it is not part of this change.

## 1.3.38 — 2026-09-15

- **`onboarding-verify` check 8 stops reporting the brain's own home paths as a leak.** Measured 2026-09-13 on the second machine of one brain (Windows, user profile with a space): the check was red with two hits, both of them the brain's own paths, and one of them came out of the report the check itself had written one line earlier. Two independent causes in one line. First, the extraction pattern `[A-Za-z0-9._-]+` stops at a space, so the hit was the first name only while the self-filter compared it against the full name from `id -un` — it could never match, and the own home path read as foreign on every run. The own paths are now REMOVED FROM THE TEXT before anything is extracted, which is what makes a username with a space work at all; both spellings are stripped (`id -un` and the basename of `$HOME` can differ on domain logins). Second, a brain that runs on more than one machine carries the other machine's username in its docs, device profiles and archived reports — twelve occurrences there, none of them a leak. Those usernames are instance knowledge and are declared in `.claude/rules/leak-names.json` under the new key `own_home_names` (template updated; missing file or missing key = empty list, i.e. the single-machine case), and the check's own output class (`onboarding-report*`) is excluded from the scan. A structurally red gate teaches people to walk past a red gate, which is the opposite of what it is for — and the old behaviour was worse than noisy: with three own paths filling the `head -3`, a REAL foreign path could not even be seen. Fixture `scripts/test-onboarding-leak-check.sh` drives the real script against a throwaway brain and proves both directions: own path (with the running user's actual name), declared other machine and an archived report stay silent; a foreign home path is reported and named; a name that merely resembles a declared one is still a leak. Red against the previous script: all three checks fail, with the own paths crowding out the foreign one exactly as described. The strip matches WHOLE names (maintainer review): a plain prefix strip hid a foreign user whose name merely starts with an own one, turning a correct FAIL into a silent OK. It is one awk pass now — literal match, so a dot in a name is a dot; one name per line, so a space does not split it; case-insensitive, so a declared lowercase name also covers a capitalised Windows profile; and only when the next character cannot continue a username. Three more fixture cases (prefix of an own name, declared name with space and case, dot), red on the prefix strip, green now. **Windows counter-measurement 2026-09-15 on the other Windows machine, two corrections.** The prefix case was built from the RUNNING user's name and asserted that `${me}ia` appears in the output — on a profile with a space that assertion is unreachable, because the extraction charset has no space and can only ever return the first word. The `FAIL` fired correctly there, so nothing was blind; the case was red anyway, on both Windows brains and only on those, because the fixture suites run on `ubuntu-latest` while the `windows-latest` leg runs only `portability-smoke.sh` — a structurally red gate on exactly the machine class this fix is for. It is built from the declared space-free own name now and tests the same property everywhere. Second, one own-path hit survived the strip on that machine, and no strip could have caught it: a local state log held the harness's own scratchpad path, which spells the running profile in the Windows **8.3 short form** — a spelling `id -un` never returns, and whose tilde falls outside the extraction charset, so the token was cut there before any comparison. The scan now reads only what git **tracks** when the brain is a repo: untracked and ignored files cannot reach a remote, so they cannot leak, and the submodule and ignored trees drop out by themselves instead of being named one by one; a brain that is not a repo yet keeps the directory scan with the local state directory excluded. New fixture case in both directions (untracked silent, the same file tracked loud and named), red against the previous script. Registered as `OS-8` in `docs/os-traps.md`, with the search over every site that derives "who am I" from `id -un`. Measured on that machine after the change: the own-path hit is gone, both genuine foreign hits remain. Maintainer counter-measurement on macOS, same day: the tracked-only scan excluded the own reports with a pathspec (`:!:onboarding-report*`), which git anchors at the repo root — a tracked report at the script's own default location `docs/maintenance/` read as a foreign leak again. The list is now filtered by basename in any directory; fixture case for a tracked report below the root, red on the pathspec version, green now.
- **Session start names the PR moves that are yours, not only the PRs that exist.** Measured 2026-09-15 on two core PRs: a maintainer review requested changes on a collaborator's PR, and two days later nothing had moved. Both sides' session starts carried a line about it — `open PRs` named the titles, the shared-memory check named the new commits and files — so each side knew something was new and neither was told the next move was theirs; the review round-trip stalled with both believing they were waiting on the other. New `scripts/pr-ball.py`, fed by one GraphQL call in `session-bootup.sh` (same owner, same offline silence as the PR search): **yours** = your PR whose newest review by someone else requested changes after your last commit; **review** = someone else's PR you are involved in (reviewed before, review requested, or @-mentioned in the body — the only ask available before a collaborator has write access) with a commit newer than your last review or comment. Only moves open 24 h or longer, never drafts, one `!!` line or silence. Fixture `scripts/test-pr-ball.sh`: both sides of the measured case fire, a commit or a comment hands the move back, a bystander, a fresh move and a draft stay silent, no input is silence with exit 0, the line is pure ASCII (the first CI run on Windows printed the em dash as a replacement character — Python writes through the console code page there), and the bootup actually calls the script.
- **`brain-scan`, `memory-dream` and `full-audit-synthesis` move their bulk data between agents as files, same as `coherence-scan`.** The fix for the coherence workflow closed one site of a class that had three more: `memory-dream` relayed both analysis summaries and every finding behind one 50,000-char limit, `full-audit-synthesis` relayed the complete catalog (up to 40 measures with sources and proposals) behind another, and `brain-scan` interpolated every finding line of eight scan sections plus `JSON.stringify(fixResults)` — the fix protocols — into its report prompt with no limit at all. Measured on the coherence run of the same shape (2026-09-13, 16 agents, 2.47M tokens): 241,137 chars went into a relay, 60,000 arrived, 6 of 9 producers never reached the consumer — with the counts green, because they matched while the content did not. Now the producing agent writes its findings to a file under a `scratch` folder (new required arg, as in `coherence-scan`), the consumer reads the files itself, and across the boundary travel only a path, a measured count and a narrow schema-validated index; every consumer stage is gated by `assertFiles()`, which aborts when a file the script started is missing rather than reporting on a partial set. Three fixtures prove it without running a workflow (`test-brain-scan-files.sh`, `test-memory-dream-files.sh`, `test-full-audit-synthesis-files.sh`): each is red against the previous state and green now. And because three sites of one root is the mechanism threshold, `test-workflow-relays.sh` now fails on ANY `relay()` in `workflows/` with a five-digit limit — its old check knew only the bare `JSON.stringify(...).slice(...)` pattern, which is exactly why three workflows could read green while relaying bulk. The second half of that gap is closed too: `brain-scan`'s real site was `${JSON.stringify(fixResults)}` — no `.slice(`, so the old check never saw it, and no limit, so the new one had nothing to measure; the fixture now also fails on any data variable stringified straight into a prompt (an UPPERCASE constant — a schema, a prepared index — stays allowed). Red-green measured on Windows against the previous `brain-scan.js`. Callers updated: the `full-audit` and `memory-dream` skills pass a `scratch` folder per stage. The headless runner `scripts/brain-scan.sh` is a caller too: it passed only the date, so the scheduled scan would have thrown at its first line while `claude -p` exited 0 (maintainer review). It now creates a temp scratch folder, names it in the Workflow args and grants it via `--add-dir` — not under `.claude-state/`, which the template deny list blocks for Read/Edit — and `test-brain-scan-files.sh` fails when the runner's call lacks either (red on the previous runner).
- **After the close commit, no hook touches a tracked file.** Measured 2026-09-13 on two machines (macOS and Windows): every session started with a dirty tree, and `git pull --ff-only` on the second machine failed on the same files. Two post-commit writers: `session-closing.sh` (SessionEnd) appended a session-log line carrying `last: <close-commit>` and `uncommitted=N`, which is different BY CONSTRUCTION from the line the skill had written before the commit, so its dedupe never matched; and `memory-sync.cjs export` (Stop and SessionEnd) rewrote `lastSync` in `docs/memory-snapshot/.sync-manifest.json` even when no memory file had changed (diff of exactly one line, 75 s after the close commit). Now the `session-close` skill calls `session-closing.sh --pre-commit` before its commit: the line carries no post-commit state (the commit that contains it IS the close commit), and an untracked stamp under `.claude-state/` tells the later hook run that this session's line exists; the hook consumes the stamp and leaves the log alone. Two limits kept on purpose: no hook commits (the commit policy is instance knowledge), and a session that dies without the skill still gets its line from the hook, now marked `hook-end` — a dirty tree is then the honest state. The stamp carries the session id when the harness substitutes `${CLAUDE_SESSION_ID}` into the skill text and works without one otherwise; the hook reads its id from stdin. `memory-sync.cjs` writes the manifest only when the tracked hash set changed — `lastSync` now means "the set last changed", the 3-way base itself stays tracked. Side finding, same PR: the bootstrap `.gitignore` never excluded `.claude/HANDOFF.md`, which the hook rewrites after every commit. Fixtures, both directions and without a Claude run: `test-session-closing.sh` — a throwaway brain whose last commit is a close commit with the pre-commit line leaves `git status --porcelain` EMPTY after the hook, a brain without that line gets the `hook-end` line and is dirty, a stamp from another session id does not silence the hook, a stamp without an id does, and the template ignores `HANDOFF.md`; `test-session-helpers.sh` — two exports without a memory change leave the manifest byte-identical, a changed memory file changes it. Red-green measured against the previous scripts.
- **`autonomous-run` names its carrier by its core path, drops two instance-only pointers, and says in one voice when a run ends.** Collaborator finding 2026-09-13 (second brain, no carrier for the skill): the skill wrote `scripts/loop-watchdog.sh` five times without the `core/` prefix — from a brain that is a dead path, and on the proving brain even an ambiguous one (a byte-identical leftover copy under the instance's `scripts/` from the 2026-08-03 split); it pointed at a memory (`auftragstreue-vor-aktivitaet`) and a plan document (`testbench-v4-plan.md §4b`) that exist in one instance only; and hard gate 5 said "only `remaining` = 0 ends the run" while step 4 says a run whose reserve pool runs dry reports "pool empty, time was still left" and stops — the same operator decision (2026-08-02/08-08) read as a contradiction. Now: `core/scripts/loop-watchdog.sh` everywhere, with the note that `arm`/`beat`/`core-done`/`disarm` are plain file writes and only the periodic `check` needs an OS scheduler the instance sets up (launchd, Task Scheduler, cron), and that the alert is a macOS notification plus a log line — elsewhere only the log line lands; the memory pointer becomes the core rule it stands for (order fidelity #3, `core/rules/working-rules.md`), the plan pointer becomes "the run's plan document, the four admission criteria are the contract"; gate 5, the mode table and the description all say the same thing: the run ends at `remaining` = 0, or earlier only through the explicit pool-empty report of step 4 — nothing else. Wording, no behaviour change; the watchdog script itself is untouched.
- **The self-test's hook mode no longer leaks into the fixtures it runs.** Measured 2026-09-13 on a macOS brain: `brain-selftest-test` failed at every session start ("the hand tool was skipped without saying so") and passed by hand. The session-start hook exports `BRAIN_SELFTEST_BG=1` for its own call; every fixture inherited it, the fixture's nested self-test on a throwaway brain deferred its cold-cache miss to the background, and the skip line it asserts never printed. The content-keyed verdict cache then replayed the red result to hand runs too, so the failure looked like a real defect. `brain-selftest.sh` now reads the variable into its flag and unsets it before any fixture runs, and `brain-selftest-test.sh` pins its own nested run to the foreground, so it is deterministic when started by hand from a shell that carries the variable. Red-green: the fixture passes by hand and fails with `BRAIN_SELFTEST_BG=1` on the previous scripts; a new probe fixture runs the runner in hook mode and fails if a fixture sees the variable (measured red with the `unset` removed, green with it). Class searched: the only other reader is `test-order-list-reader.sh`, which sets the variable itself for the bootup it drives — intended, not inherited.
- **Core paths in the rules carry the `core/` prefix, all six of them, and CI keeps it that way.** Measured by the collaborator on v1.3.37 (2026-09-13): six mentions of a core script or helper in `rules/*.md`, three written as `core/scripts/…`, three as bare `scripts/…`/`helpers/…`. The rules are read only from inside a brain, where the core is the `core/` submodule — a bare path resolves against the brain root, where nothing lives. The three lines now carry the prefix (`intelligence.md`: `core/scripts/test-workflow-relays.sh`, `core/helpers/freshness-gate.cjs`; `working-rules.md`: `core/scripts/wait-mcp-reconnect.sh`), and a lint step in CI fails on the next `scripts/` or `helpers/` in `rules/*.md` without it; a path that legitimately points elsewhere (`.claude/skills/<x>/scripts/`) has its own prefix and stays silent. Tested both directions locally: clean tree silent, one prefix removed and the step names the line.
- **`verification-before-completion` no longer points at one instance's memory.** The live-systems section required reading the memory `verify-and-never-stop` IN FULL — a memory that exists in one brain and in none of the others consuming this core (collaborator finding, same day). The part of that memory that holds on every rig now lives in `references/live-system-pass-bar.md`: passed means end to end in the CURRENT state, through EVERY operation, on SEVERAL objects, with TWO independent read paths, the whole after the parts — plus what does not count (syntax green, one object, one read path, a state before the last edit). Device details stay in the device suites; the skill reads the reference and says "if the instance carries its own bar on top, read that in addition". No other instance pointer of this kind found in the skill (the `codex-review` mention was already conditioned on the instance carrying it).
- **Ponytail's scope names build tasks with an artefact, not only code.** The skill said "NOT for non-coding requests" while one instance fired it as the only engineering-discipline carrier on TouchDesigner networks, shaders, MCP setups and configs — and had deleted its second carrier for exactly that reason (collaborator finding from a full audit, 2026-09-13). Operator decision the same day: scope A, the ladder applies word for word wherever something with a construction gets built; prose, research and decisions stay out. Explicitly under A/B test — the operator ordered a comparison to verify it, tracked in the proving brain's order list; if the wider scope produces worse work on non-code artefacts, this line moves back.
- **Checklist template §5 carries the 400-character index-entry limit.** `memory-dream` cites it as "checklist limit", `memory-lint.py` enforces it (measured to fire on a real brain the day the template shipped), and the template stripped it by mistake. Same collaborator audit.
- **`coherence-scan` moves its findings between agents as files, not as prompt text.** Measured 2026-09-13 on a real run (16 agents, 2.47M tokens): the 9 lens agents produced 241,137 chars of raw findings, the merge prompt relayed 60,000 of them (25 %), and 6 of 9 lenses never reached the consolidation at all; the register stage lost the same way (75,345 chars verified, 60,000 arrived, findings 16-20 missing from the prose). `assertCount()` stayed green throughout, because the numbers matched while the content did not — `relay()` marks a cut, it cannot make one harmless. Now every producer writes its bulk to `<scratch>/findings/` (`lens-<slug>.json`, `merged.json`, `verify-batch<n>.json`) and the next stage reads it there; across an agent boundary travel only a path, a measured count and a title/severity index (`relay()` limits are all below 10,000 chars). Every consumer reports what it actually read from disk, and `assertFiles()` compares that against what the script started: a missing lens file — an agent that died, was skipped, or wrote elsewhere — aborts the run LOUDLY before any merge tokens are spent, instead of consolidating a partial corpus that reads like a complete one; a verify batch without a verdict for an indexed title, or a title the merged file does not contain, aborts the same way (the old code defaulted such findings to PLAUSIBLE). The corpus builder now also copies `.claude/rules/mechanism-rules.json`, `config/machines/*.md` and EVERY `.claude/skills/*/SKILL.md` — three sources the verify agents of that run had to measure by hand because the corpus never carried them. Fixture `scripts/test-coherence-scan-files.sh` proves the change without running the workflow (seven figures in tokens, freshness gate): statically, no bulk `relay()` and an `assertFiles()` gate on each of the three consumer stages; behaviourally, the helper block extracted VERBATIM from the workflow against a directory of synthetic lens files — all present is silent, one missing is loud and names it, a dead agent (null) is loud, a differently spelled directory is not a gap. Red-green: against the previous script the fixture fails on all five static checks. Prompts of the lenses and scenarios, the verify criteria and the register structure are unchanged; the helpers `relay()`/`assertCount()` stay, now carrying only indexes.
- **`onboarding-verify.sh` no longer writes its report into the brain root.** Line 15 put `onboarding-report.txt` at `$BRAIN/`, and with no brain resolved at `$PWD` — which, from inside a brain that does not live under `~/Projects/*-brain`, IS the brain root. Every such run violated the root whitelist of `rules/working-rules.md`; measured three times on one instance (two mv/rm traces, one brain-scan finding), never on the instance that only ran the script from the core checkout. The report is an artifact and gets an artifact's place: `docs/maintenance/onboarding-report-<host>-<date>.txt` inside the verified brain (directory created; host and date in the name so two machines never overwrite each other), `--out <file>` overrides. The working directory now counts as the brain when it is one (`core/` plus `.claude/settings.json`), ahead of the `~/Projects` glob — that is the incident's path, where check 5 had also reported "no brain found" for the brain it stood in. With no brain anywhere the report still lands in the working directory, under the new name. No whitelist exception. Fixture `onboarding-verify-test.sh` runs the real script against throwaway brains, both directions: no `onboarding-report.txt` in the root, the file under `docs/maintenance/`, `--out` wins and suppresses the default, the working-directory-is-a-brain path, and the no-brain fallback. `docs/onboarding-contract.md` and `ONBOARDING.md` name the new path.

## 1.3.37 — 2026-09-13

> **BETA-PHASE TAG on `brain-core-next`.** Four strands from one day, all reviewed by the
> collaborator with a Windows counter-measurement (#130) and a reader check (#133): the
> session-start hook survives its own timeout, the shared-memory register carries a date
> per entry and can be asked what is new, bootup and close carry the read and write side
> of shared memory as one class, and the brain-scan templates ship with every new brain.
> `brain-core` stays on v1.3.32 until the operator releases.

- **Shared memory is read at bootup by topic and freshness, and its delivery is checked at close.** The operator's order of 2026-09-13 names read AND write, bootup to closing, as one class. Measured before: the bootup reported a commit count (level 1), the close skill asked in prose whether a finding reaches past this machine, and nothing mechanical sat between "written" and "delivered". Now `shared-memory-check.sh` follows its commit line with a freshness line from the register — `N entries dated since <last check> — ops 13, core 7, …` plus the `--since` query for the list — and stays silent when nothing is dated after the last check, so the line cannot become noise. `session-closing.sh` measures the shared repo at close: uncommitted files or unpushed commits produce a `FAIL shared-memory:` line the close skill reads, a "NOT delivered" section in HANDOFF.md, and a `shared=dirty:N,unpushed:M` field in the session-log line; a clean repo is silence. Neither helper had a fixture before — a mechanism without one is a claim about itself — so both got one, every property in both directions: `test-shared-memory-check.sh` (line with the right tally on fresh entries; silence on a current cursor; silence when the repo moved but nothing is dated after the check; silent seeding) and `test-session-closing.sh` (clean is silent; edited-not-committed fails; committed-not-pushed fails; pushed is silent again; no shared repo invents nothing). Measured on the real brain with a backdated cursor: `21 entries dated since 2026-09-12 — ops 13, core 7, show-tools 1`.

- **Brain-scan checklist and order list are bootstrapped into every new brain.** Collaborator request 2026-09-13: his first brain-scan ran without either file — the workflow reads `docs/maintenance/brain-scan-checklist.md` and `brain-scan-auftraege.md` by fixed path, the bootup counts the open orders from the second, and the core created neither. Two brains that scan against different structures produce reports nobody can line up. `templates/` now carries both as the SHAPE, in English, with instance items stripped: the configured/verified state model, six sections with one declared behaviour check each, and the order list's `id`/`class`/`reach`/`origin` convention with the operator/derived rule spelled out. `bootstrap-brain.sh` copies them from day one. New checklist item, found on two brains the same day: no `npx` MCP server on `@latest` in `.mcp.json`. **Review finding by the collaborator, fixed in the same PR:** the English template's section headings and the two readers (`session-bootup.sh`'s `task OPEN:` line, `brain-scan.js`'s order prompt) named different strings, so a bootstrapped brain got an order list nobody read — measured, 0 lines with one order present. Both readers now accept the German and the English headings, the template mirrors the German sections one to one (`Open (ordered)` / `Proposed (derived)` / `Done`), and `test-order-list-reader.sh` runs the real bootup against both languages plus a negative. That fixture caught a second defect on the way: the first fix used `sed`'s `\|` alternation, a GNU extension that matches nothing on BSD sed — 0 lines for both languages on macOS, green on GNU CI. Registered as OS-7 in `docs/os-traps.md`, fixed with `-E`, no other site in core or the proving instance.
- **The shared-memory register carries a date per entry, and can be asked what is new.** Operator order 2026-09-13: a session must be able to ask "what changed in the shared record since I last looked, in the topic I am working on" — at bootup and mid-session. Measured that day: 0 of 240 entries carried a `date` field; every date lived in a filename or in prose, which a filter cannot read. So `date: YYYY-MM-DD` joins `von`/`audience`/`topic` as a required frontmatter field (README of the shared repo, same ratchet in `shared-memory-lint.py`, baseline re-snapshotted there so legacy files are exempt exactly once). `shared-memory-index.py` reads the field and, for a file without it, falls back to the last git commit touching the file — one `git log --name-only` pass, no back-fill — and marks that case `~` in the index line so "the author dated this" and "only git could say" stay distinguishable. Every topic line ends with its date, every root topic line names the newest, and `--since YYYY-MM-DD [--topic]` prints matching entries newest first with a count line that always states how many are undated. Also fixed: the generator listed its own per-topic `INDEX.md` as an entry, invisible until a date made the line stand out. Fixtures +6 (index, git date pinned via `GIT_COMMITTER_DATE`) and +3 (lint), all green.
- **The session-start hook stopped being killed.** Measured 2026-09-13 on a full brain: `session-bootup.sh` took 102.5 s against its 30 s hook timeout, 93.6 s of it the fixture half of `brain-selftest.sh` — so the bootup had been cancelled at every start since 2026-08-21 (41 `hook_cancelled` records in 33 transcripts on one macOS brain; a Windows brain reported the same the same day). The first summary lines arrive, the brain-check line never did, and a carrier that never delivers looks like one with nothing to say. The "~6 s" in the bootup's comment was that stale. New `scripts/cached-verdict.sh` runs an expensive check at most once per machine per key, with a `mkdir` lock so parallel sessions do the work once, and ALWAYS announces a reuse with age and key — silence reading as green is the defect this fixes, not a feature. The fixture half of the self-test now goes through it keyed on CONTENT (core commit + fixture-file hashes + bash/git versions), not on a clock: a 24 h stamp would skip right after a core update, the one moment the answer can change, and re-run all week when nothing did. The hook alone sets `BRAIN_SELFTEST_BG=1`, so a miss re-measures in the background and reports the previous verdict; a hand-run `brain-check` keeps measuring in the foreground, because a person running it wants an answer. Measured after: bootup 8.4 s; self-test 1.7 s on a hit, 1.7 s on a miss in hook mode, full measurement by hand. Fixture `cached-verdict-test.sh` proves both directions of every property (reuse announced, changed key re-runs inside a fresh window, expired window re-runs, a cached FAILURE stays a failure, two simultaneous sessions run once, background miss lands next call); the existing `brain-selftest-test.sh` caught two regressions on the way (a fresh run printing nothing, and a cold cache hiding the hand-tool skip line) and passes. Known limit, stated in the fixture: a lock left by a crashed run is reported, not reaped. The foreign-state checks (pins, tags, PRs) are under 9 s together and untouched — the helper's `--max-age` is there for them when a measurement says it is worth it.

## 1.3.36 — 2026-09-12

> **BETA-PHASE TAG on `brain-core-next`.** Second beta of the day: v1.3.35 shipped the
> promise gate and the content guard, this one carries the onboarding contract's plugin
> scope (and its same-day correction), two collaborator-reported guard/skill fixes, and
> the supply-chain bumps. `brain-core` stays on v1.3.32 until the operator releases.

- **The mechanism guard judges what a command EXECUTES, not what it merely writes.** Patterns were matched against the raw command including heredoc bodies, so a commit message that only DESCRIBES a banned mechanism as prose tripped the guard (found live while committing a register that discussed exactly such a finding). Reported by BlurredVision. Stripping every heredoc, however, would have turned the guard off through one syntax: measured against the fixture rule, 7 of 8 shapes whose body is executed went from seen to blind (`bash <<EOF`, `sh -s`, `ssh`, `python3 -`, `node`, `eval "$(cat …)"`, `source /dev/stdin`). So the CONSUMER decides and the default is fail-closed — cat/tee bodies are stripped, eval/source never, an unknown consumer keeps its body in the scanned text. Fixtures in `scripts/test-guards.sh` cover both directions; with the blanket strip restored, exactly the three executed fixtures go red.
- **`session-close` no longer states a commit/push policy of its own.** Step 4 had cached one instance's dated policy as if it were the core's, and a cached policy goes stale silently — the drift the Rule-Conflict Protocol's back-propagation step exists to catch. Reported by BlurredVision, whose first fix replaced it with their own instance's (stricter) rule; three brains consume this core and their rules genuinely differ, so the skill now names none: it reads the instance's rule and applies it, and asks when there is none. The stricter default for an unwritten rule, the "close the session is not by itself a go-ahead" clarification and uncommitted-with-a-reason are kept.
- **Supply chain:** `actions/checkout` and `actions/setup-python` bumped to the current majors, SHA-pinned as the ruleset now requires.

- **Which plugin scope is the instance's decision, not the core's.** The scope paragraph written the same morning said "install the core once, in scope `user`" and justified it with "the core must reach every session on the machine" — a statement about OUR machines, not about the core. The first collaborator it applied to starts Claude only inside their brain and asked what technically requires `user`. Measured, nothing does: `brain-update.sh` reads the enabled plugins from the project `settings.json` AND the user config, and `plugin-scope-check.py` is green on a single install in either scope, red only on the duplicate — the check never had an opinion, only the prose did. Binding is "exactly once"; `ONBOARDING.md` now names the two cases (`user` when sessions start in more than one directory on the machine, `project` when every session starts in the brain) and keeps the `enabledPlugins`-does-not-install measurement with its version and its age attached.

- **Plugin scope is part of the onboarding contract.** Measured on the third collaborator's first day (2026-09-12): `brain-core` 1.3.32 enabled in scope `user` AND `project` at once — every skill and hook loaded twice, "which version wins" left to the harness, and `onboarding-verify.sh` reported it as one green line because the text listing does not show scopes. The contract says: the core is installed exactly ONCE — and the binding part is the once, not which scope (corrected the same day, see the entry below). `--scope project` also stays the documented, temporary exception for a trial beside an existing setup. Check 2 of `onboarding-verify.sh` reads `claude plugin list --json`, prints the scope per core entry and goes RED on a duplicate, with the uninstall command in the line; CLIs without `--json` keep the old presence check. The check is its own file (`scripts/plugin-scope-check.py`, fixture `plugin-scope-check-test.py`): the first, inline version never parsed because of shell quoting and reported that as green — the positive control caught it before the PR, which is what the negative-control clause of the contract is for. Input the checker does not understand reports as UNCHECKED, never as green.
## 1.3.35 — 2026-09-12

> **BETA-PHASE TAG, replaces v1.3.34 on `brain-core-next`.** Two strands land together
> because they were built the same day and both touch what a PR is allowed to do:
> the promise carrier (a conduct gate) and the content guard plus supply-chain
> hardening (a repository gate). `brain-core` stays on v1.3.32 until the operator
> releases after the beta.
>
> **Repository settings that are NOT in this diff** and were set on 2026-09-12 by the
> operator's decision: ruleset `main-protection` (1 approval incl. code owner, stale
> dismiss, required checks `leaks` / `lint` / `contract` / `portability` on three OS /
> `shellcheck`, deletion and non-fast-forward blocked, bypass for repository admins
> only), secret scanning with push protection, Dependabot security updates and the
> dependency graph, CodeQL default setup, an Actions policy of GitHub-owned plus
> verified actions, and `sha_pinning_required` — that last one only after this tag's
> content made every workflow reference a SHA, verified by counting the unpinned
> `uses:` lines on main rather than trusting the claim.

- **Content guard — the malicious-content classes a text repo can carry, as a CI gate.** With a third collaborator on the public core (2026-09-12), a PR is now the normal way content arrives, and this repo ships hooks that run silently in every consuming brain plus text that becomes model instruction. `scripts/content-guard.py` (stdlib, no network) refuses nine classes, each a search: binary files, invisible/bidi characters and mid-file BOMs, mixed-script words (homoglyphs), prompt-injection markers, `curl | sh`, decode-and-exec, `eval`/`new Function`/`vm.runIn*`/`exec(`, network calls inside `helpers/`, and opaque base64-ish blobs. Baseline on this repo: 0 findings after two deliberate exclusions the fixture pins (a regex LITERAL naming curl inside secret-guard is a description, not a call; Playwright's `$$eval` is a selector). Suppression is visible only — an inline `content-guard-ok: <reason>` or the `scripts/content-guard-allow.txt` ratchet — never by editing a pattern. Fixture `scripts/content-guard-test.py`: one negative control, one positive control per class, both suppression paths, and the proof that the allow list is class-specific.
- **CI hardening around it:** the workflow token is read-only by declaration (`permissions: contents: read`), every action is pinned by commit SHA with the version as a comment (a tag can be moved), `.github/dependabot.yml` proposes the bumps, `.github/CODEOWNERS` names what a review must not wave through, a `shellcheck --severity=error` job covers the update path's shell, and `dependency-review-action` gates a PR's manifest changes against the advisory database (no manifest exists today — the seat is there for the first one). Repo-side, set by the operator the same day: a ruleset on `main` (1 approving review incl. code owner, required checks `leaks`/`lint`/`contract`/`portability (3 OS)`, admin bypass only), secret scanning + push protection, CodeQL default setup (JavaScript, Python, Actions), Dependabot security updates, Actions policy "GitHub-owned and verified only". Still open on the repo side: `sha_pinning_required` flips on only after this PR is on `main`, otherwise it would turn `main` red first.
- **A promise bound to a condition kept being obeyed after the condition was gone — new `helpers/promise-gate.cjs`.** Measured on a collaborating instance 2026-09-11: the operator granted permission for ONE unattended task while he slept ("no commit, no push, no bash"). The task finished, the operator was back in the chat and awake, and the promise was still in force — so the mandatory commit step of `session-close` was silently skipped to avoid breaking it, and the close was reported as complete. This is not rule density: a promise is one more text in context, replayed as stimulus-response instead of checked causally. The condition IS the why, which is exactly what `rules/thinking-protocol.md` already demands under "Mechanism over memory". The gate fires when a first-person commitment and the condition that bounds it appear in the SAME sentence, and asks for the promise to be stated with its expiry. Pairing is per sentence on purpose — turn-level pairing reproduces the false-positive class the premise gate measured its way out of.
- Every hit is appended to `.claude-state/promises.jsonl`, and `skills/session-close` now walks that file: per promise, does its condition still hold. That is the half a hook cannot do — in the incident the agent never cited the promise, it just omitted a step, and an omission has no text to match. The gate bounds the promise where the text IS explicit (when it is made); the close re-checks it where it matters (before the session ends).
- Frequency measured before choosing the mode, not after: 323 real operator turns across six transcripts, with the instance pattern data installed, **0 hits (0.0 %)**; a positive control injected into the same pipeline fires, so the zero is a measurement and not a blind instrument. Rare enough to block rather than only record. Stated plainly: that also means the gate has not yet fired in real work on the measuring instance — the incident it was built from happened elsewhere.
- `scripts/test-promise-gate.sh`: 13 fixtures, both directions. Each half alone stays silent, a quoted promise stays silent, a commitment and an unrelated horizon in two different sentences stay silent, `--record` never blocks and the record is actually written. The discriminator runs the German incident sentence against a cwd WITHOUT the instance pattern file and requires silence — if it fired there, the German hit would not be coming from the data and every green line above it would be suspect.
- Language stays DATA: built-in patterns are English, everything else goes in `.claude/rules/promise-patterns.json` (`commitment_patterns`, `condition_patterns`). Registration is instance data as well — a line in `.claude/rules/stop-checks.json`, never a second Stop hook in `settings.json` (it would fire twice).

- **The mechanism-guard could not see the tool class it exists for.** `templates/settings.json` wired it to matcher `Bash`; a hand-built watcher is a `Monitor` command, so the one mechanical carrier against improvising past a documented path was blind to improvised watchers, in every bootstrapped brain. The guard itself needed no change - it reads `tool_input.command` and never looks at `tool_name`, and Monitor carries the same field. Matcher widened to `Bash|Monitor`. The template rule file said "matched against the bash command", which is the assumption that produced the gap; it now says otherwise. Found by walking into it: a session polled CI in a hand-built Monitor loop instead of using `ci-watch.sh`, and the guard never saw the command. Counter-measured on the other instance: 60 unique ad-hoc poll commands across 37 sessions, so the class is real and not local.
- **`hook-coverage.py` compares the MATCHER, not only the command.** It reported full coverage for exactly the state above: the hook was wired, so it counted as covered, while its matcher named fewer tools than the template. A wired hook with a narrower matcher is now its own reported gap - which is what reaches brains bootstrapped before this change, since the template alone only ever reaches new ones.
- `test-guards.sh`: the mechanism-guard probes take a tool name, and a Monitor payload must block. That proves the guard is tool-agnostic; the wiring half belongs to hook-coverage. Neither check alone separates "guard runs here" from "guard would run here if it were wired".
- New example rule in the template: a hand-built CI poll loop points at `ci-watch.sh`. Measured against 12 commands including real ones from both instances, no false positive - the prescribed org-watch loop (`gh pr list`) passes, and a negative lookahead lets a compound command through that calls `ci-watch.sh` itself.
- **`brain-update.sh` printed DONE and exited 0 after failing its submodule step.** Started from the plugin cache without `BRAIN_UPDATE_ROOT`, the brain root resolves two levels above the script — beside the cache, not into a brain. `cd` succeeded (the directory exists), every later step silently found nothing, and the only visible trace was one bare `fatal:` from `git commit`, the single call in the file without a stderr redirect. Three ways a path is not a brain now name themselves and exit non-zero: not a git repository, no `core/`, `core/` present but not initialised.
- **`git diff --quiet` was tested with `if !`, which merges "there are differences" (1) with "could not tell" (128).** That is how the non-repo case reached the commit path in the first place. The exit code is now read explicitly and anything above 1 is a FAIL.
- **`git -C core rev-parse --git-dir` is not a test for an initialised submodule.** git walks upwards, so inside a brain an EMPTY `core/` answers with the superproject and the probe reports a healthy submodule. Both the new precondition and the existing alignment guard now test `core/.git`, which is the thing being asked about. Found by the fixture: the third case passed while the state it describes was present.
- **The verify-then-checkout guard on the core tag could never hold.** `ls-remote` returns the TAG OBJECT sha for an annotated tag while the local side resolved a COMMIT sha, so the comparison always failed, every run took the repair path, and a brain already sitting on the tag was told `core v1.3.34 -> v1.3.34`. The remote ref is dereferenced now (with a fallback for lightweight tags), and the same brain reports `already on`.
- `brain-update-test.sh`: three probes for the states above, asserting non-zero exit AND the absence of DONE. Run against the real script — the checks sit directly after the cd, so nothing else executes.

## 1.3.34 — 2026-09-02

> **BETA-PHASE TAG, replaces v1.3.33 on `brain-core-next`.** First beta finding, on
> the very first beta step: a test-channel machine could not cleanly GET onto the
> beta. `brain-core` stays on v1.3.32 until the operator releases after the beta.

- **brain-update follows the ENABLED core channel** (#111): the submodule alignment
  was bound to the literal plugin name `brain-core` — with `brain-core-next` enabled
  and `brain-core` disabled it skipped SILENTLY and still printed DONE (measured:
  plugin on 1.3.33, submodule left on v1.3.32). Now: either channel matches, both
  enabled at once FAILs with instructions, neither enabled WARNs instead of silence.
- **Class closed, not the instance** (#111): `onboarding-verify.sh` accepts either
  channel for plugin presence and cache dir (a beta machine read as "brain-core
  MISSING" before); `session-bootup.sh` compares the submodule against the ENABLED
  channel's pin (a correct beta state read as stale against the held brain-core pin).
  `file-guard.cjs` checked and not affected (matches the repo manifest name).
- The new updater block is grep-free (OS-5 register ratchets DOWN:
  brain-update.sh 2 → 1 pipe-grep sites).

## 1.3.33 — 2026-09-02

> **BETA-PHASE TAG.** Pinned on `brain-core-next` ONLY (the operator's four-step of
> 2026-09-02: develop → verify on mac AND win → beta phase → release/pin). The
> `brain-core` pin stays on v1.3.32 until the beta ends and the operator releases.
> Full-audit strand: PRs #107 + #108 + #109, every change counter-checked by the
> second instance (byte-level where it mattered).

- **Two multi-agent/verification invariants lifted from instance memory into core
  carriers** (#107): `rules/intelligence.md` gains "only the producer writes"
  (workflow scripts have no filesystem; relayed content truncates silently — measured
  1/141 and 22/141 rows surviving a prompt relay); `verification-before-completion`
  gains the "One Symbol, Two States" gate (check output is evidence only if it
  differs between world states; every "nothing found" must say whether it found
  nothing or SAW nothing).
- **codex-review triggers genericized** (#107): another owner's Vercel-portfolio/PM2
  context replaced by generic deployment/production wording.
- **Origin-marker alias** (#107, tightened in #108 after the Windows counter-check):
  `origin: operator` is canonical; the literal `von: Operator` and the documented
  operator-name form stay matchable — brain-scan's context phase now names all three
  forms explicitly (the placeholder wording silently unmatched the literal core form).
- **`## Common Failures` heading restored** in verification-before-completion (#108;
  eaten by the #107 section insert) and the full-audit write-side promotion wording
  names the list's own marker (#108).

- **The multi-agent invariant "only the producer writes" had no carrier, and the
  workflows themselves were the pattern it forbids.** Five sites relayed bulk data across
  an agent boundary inside a prompt with a bare `JSON.stringify(x).slice(0, N)` — a cut
  that leaves no trace in the log, in the payload, or in the report built from it, so half
  the data reads exactly like all of it. Replaced by `relay(obj, limit, what)`: it logs the
  cut and writes a `[TRUNCATED: n of m chars]` marker INTO the payload the agent reads, so
  the loss survives into the report instead of vanishing at the boundary. The invariant's
  second half was missing too: `coherence-scan.js` computed the authoritative P0/P1 counts
  and then asked the agent to footnote any deviation — a warning where the rule says abort —
  while `memory-dream.js` returned the agent's REPORTED counts as the workflow's result and
  never compared them against the array it was holding. Both now go through `assertCount()`,
  which throws; memory-dream returns the script-side numbers.
- `test-workflow-relays.sh`: fixture for the above, and the guard against the next bare site.
  Its first version passed while the defect was reintroduced — the grep stopped at the first
  `)` and could not see a relay whose payload contains parentheses, which is every real one.
  "Found nothing" and "cannot see it" printed the same OK; caught by the red-green cycle,
  not by reading the pattern. Discovered by the same rule the fixture guards.
  It creates no temp directory on purpose (OS-3).
- **The cache provenance check could not name which of two states it had found**
  (`brain-update.sh`). It compares the recorded install commit against the pinned tag,
  and those disagree in two different situations: the record is stale (the content IS the
  pinned release — `claude plugin update` never rewrites `gitCommitSha`), or the content
  is foreign (the plugin loading right now is not what the pin names). Both printed FAIL,
  and the comment above the check said so and accepted it because the remedy is the same.
  The remedy is, the URGENCY is not. Measured on two consecutive releases: content 1.3.31
  then 1.3.32, both correct, record still holding the sha of the 1.3.25 install — so the
  check failed on every UPDATED plugin and only ever passed on a freshly installed one,
  which is the opposite of useful. Discriminator: the version inside the cached
  `plugin.json` against the version the tag encodes, which this ecosystem guarantees
  because `release-preflight` refuses to cut a tag where they differ. Stale record is now
  a NOTE that names itself; foreign content stays a FAIL and says which version it found.
- `brain-update-test.sh`: first fixture for that script. Three cases, and the negative one
  carries it — foreign content must report its OWN version, never the pin's, or the fix
  would have softened a real defect into a reassuring note. Its stdin program takes both
  paths from the environment (OS-6): a `.json` argument is safe today only because it
  carries no shebang, and that is an assumption about the input, not a property of the
  call.

## 1.3.32 — 2026-08-31

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
