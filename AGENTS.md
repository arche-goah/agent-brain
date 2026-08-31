# AGENTS.md — agent-brain

Rules for any agent working in this repository. They exist because this repo is
consumed by more than one person's setup — a sloppy commit here breaks someone else's
session start.

1. **Tool, not instance.** Nothing personal enters this repo: no names, private IPs,
   MACs, home paths, show/venue/rig identifiers. `scripts/leak-scan.py` must print
   `0 findings` before every commit. If a rule needs an example, write it generically
   ("the operator", documentation IPs).
2. **No file travels twice.** A file lives in the plugin channel (`skills/`,
   `output-styles/`) OR the submodule channel (everything else) — never both, never
   additionally copied into a consuming brain.
3. **Paths are derived, never hardcoded.** Helpers use `$CLAUDE_PROJECT_DIR`/cwd;
   scripts resolve CORE (their own checkout) and INSTANCE (cwd or `BRAIN_DIR`)
   separately. A path that only resolves on one machine is a defect.
4. **Renames are breaking.** A helper name, script name, config key or hook wiring is
   interface: renaming needs a major bump of `contract_version` in
   `core-contract.json` (with a WHY in its history) and one version of alias/deprecation.
5. **Versions are explicit — and graded by CONTENT, not by habit** (operator order
   2026-08-13: nine minor bumps in four days drifted toward a 2.0 that would mean
   nothing). Every release: bump `version` in `.claude-plugin/plugin.json`, add a
   CHANGELOG entry, tag `vX.Y.Z`. The marketplace pins tags, never `main` — an
   untagged change reaches nobody. Grading (operator order 2026-08-14, tightening
   the 2026-08-13 wording): **patch (third digit) is the DEFAULT** — fixes, docs,
   rule wording, CI plumbing, AND new capabilities that have not yet PROVEN
   themselves in real runs. Felt size is not a criterion: the stabilization phase
   after a release keeps producing "one more thing that wasn't final", and every
   one of those is a patch. **minor** (second digit) = a deliberate re-release
   with clear notes once a feature set is ROBUSTLY PROVEN (ran in production
   sessions, not merely built and merged); **major** (first digit) = only a big,
   solid, THOROUGHLY TESTED mega step (breaking changes always land here, but
   size and proof are the bar, not breakage alone). A batch takes the highest
   grade inside it — which, under the patch default, is normally still a patch.
   `x.10+` and `x.y.10+` are normal — never round to a milestone number for
   aesthetics; 2.0.0 is earned by the step, not by the counter.
   **Mechanically carried:** run `bash scripts/release-preflight.sh vX.Y.Z` BEFORE
   tagging — it enforces manifest==tag, a CHANGELOG section, no pre-existing tag
   (the race guard: an existing tag or open release PR means the release happened
   elsewhere — comment there, never re-cut), and HEAD==origin/main. CI re-checks
   manifest+CHANGELOG on every pushed `v*` tag, so a broken tag turns red on the
   repo page instead of failing silently on the next consumer update (the v1.2.0
   incident: tagged with the manifest still on 1.1.2).
6. **CI must stay meaningful — and paid for by a shared budget.** `ci.yml` runs
   leak-scan, skill-lint and suite-check against this repo itself. Never replace a
   failing check with an echo. Actions minutes are one account-wide pot: `push`
   triggers are always branch/tag-filtered (an unfiltered `push` plus `pull_request`
   runs every PR branch twice — that exhausted the account quota mid-month on
   2026-08-13 and killed CI everywhere), and macOS/Windows runners (10x/2x billing)
   run only where the check needs that OS. `scripts/suite-check.py` enforces the
   trigger rule for every repo it sweeps. Cut branches from FRESH main: push events
   run the ci.yml of the pushed ref, so a branch forked before a trigger fix keeps
   burning minutes under the old config (measured 2026-08-13 on a pre-#53 branch) —
   no lint on main can catch that.
7. **Language: English only** (operator order 2026-08-13 — supersedes the earlier
   "German content stays German" clause). Everything in this repo and anything else
   that may ever go public — rules, skills, helpers, scripts, templates, workflows,
   docs, commit messages, PR text — is written in English. German is reserved for the
   private brain repos (conversation, session/decision logs with verbatim quotes,
   memory). Existing German content is legacy awaiting dedicated translation sweeps:
   do not add to it, do not mix languages within a change; a CI english-only check
   lands together with the completed sweep (earlier it would be permanently red).
   **Scope: this governs ARTIFACTS** (repo content, file names, logs, docs, commits).
   Conversational chat output is NOT an artifact — it follows the operator's
   language with its native orthography: umlauts/accents are fine in chat
   (operator order 2026-08-13). The ASCII transliteration (ae/oe/ue digraphs) is an
   artifact convention and must not leak into conversation.
8. **Assume a second session.** Working copies on a machine are SHARED between
   parallel Claude sessions. Before push/rebase/branch surgery: run
   `scripts/parallel-sessions.sh` (the bootup hook warns automatically). Rules when
   it flags: commit after every block, NEVER force-push a shared remote, hand work
   over via an explicit note (memory/PR comment) instead of leaving state in the
   tree — and version numbers are assigned by ONE session per release, never two.

9. **An instance's `settings.json` is invisible from here — and every one differs**
   (operator finding 2026-08-20). A capability that must run in EVERY brain is not
   delivered by shipping the file. The measured case: `brain-check.sh` shipped with
   v1.3.15, a second instance updated, started a fresh session, and nothing ran —
   because the hook existed in one brain's settings and nowhere else. The author had
   silently assumed other instances look like his own.
   **Three things are needed, and shipping the file is only the first:**
   - the capability itself in `helpers/` or `scripts/`,
   - the wiring in `templates/settings.json` — that file IS the documented default
     proposal for what a brain should have, the only shared surface that exists,
   - and the DEMAND: `scripts/hook-coverage.py` diffs the template against the brain,
     the bootup voices it every session, and `brain-update.sh` warns after an update.
     Without the third step the second reaches new brains only, because the template
     is copied once at bootstrap and never again.
   Consequence for a reader as much as for a writer: `templates/settings.json` plus the
   `hook-coverage` output is the answer to "what should be wired here" — never another
   instance's file, and never memory of one.

10. **A platform divergence is registered before it is fixed** (operator order
   2026-08-31: "keep all mac/win issues in the register and derive error classes, so we
   do not keep getting stuck in new instances and patching everything by hand").
   CI runs on Linux, most of this repo is written on macOS, and the divergences surface
   on Windows — where they are silent, because the failing path produces nothing to look
   at on the platform that can reproduce it. `docs/os-traps.md` is where they live:
   - **at instance 1**, as an INVARIANT plus the search spanning its space, not as an
     anecdote and not after the third occurrence;
   - stating which of the three shapes it is (A: the platform reshapes a string in
     transit · B: the same command name is a different program · C: the gate does not run
     where the defect lives) — and if it fits none, naming the fourth shape there;
   - with a baseline of the sites that are CORRECT, so a NEW site surfaces and is read.
   The searches run in CI and in `portability-smoke.sh`, which is the point: they execute
   on the platform that cannot reproduce the defect. Six entries came out of a single day
   in which four of them were classes that had already been fixed once and came back
   under a different spelling.
   **Then regenerate the signpost:** `scripts/os-traps-export.py --write` produces a
   pointer entry in the shared-memory repo. A tool repo is read when somebody checks it
   out; the shared memory is read by every instance at session start, so a finding that
   only lands here reaches the other instance days late or never. The entry is generated
   and carries no text of its own — adding a line by hand drifts by the next trap.
