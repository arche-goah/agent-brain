# Changelog — agent-brain

All notable changes to this repo. Versions are graded by content (AGENTS.md #5):
patch is the default (unproven capability included), minor = a proven-feature
re-release with clear notes, major = a big, thoroughly tested step.
The marketplace pins tags, never `main`.

## Unreleased

- **`ci-watch.sh ref` accepts a bare commit sha.** (test: T1) Measured 2026-10-09: `ci-watch.sh ref <repo> 8c4e344` waited out its whole timeout and reported UNKNOWN on a commit whose CI was green — runs carry a branch name, never the sha, and ref mode matched `headBranch == ref`. A ref of at least 7 hex digits that is a prefix of the resolved commit now matches by sha alone; branch and tag refs are unchanged. Fixture: two new cases (bare sha green / red); live: the old version timed out, the new one reported green on the same sha, `ref main` unchanged.
- **The self-test sees MCP server launchers.** (test: T1) Measured 2026-10-09: a brain's TouchDesigner launcher, started by the client from `.mcp.json`, was reported as "mentioned in documentation only, never invoked" — the detector walks `.claude`, `.github`, `core`, `scripts`, `docs`, `config` and never read the root `.mcp.json`. It now reads `command` and `args` of every server there as wiring (prose elsewhere in the file does not count). Fixture `brain-selftest-test.sh`: new case "a launcher in .mcp.json counts as wiring"; against the old script it fails, against the new one all 8 checks pass.

- **A question to the operator stays open until it is settled — it no longer scrolls away.** (test: T2) Operator, 2026-10-09: "das geht oft unter bei multiplen tasks, wenn du einen vorschlag machst". Measured in that session on the Windows instance: seven proposals ended as questions to the operator; background events and other work followed, the operator's next prompts were about something else, and two of them (run the overdue brain-scan; build a clock check) were gone until the operator asked "is anything still open?". The core carried the agent's promises (`commitments.py`) and requests from other instances (`open-items.py`), not the agent's own open questions. New `helpers/question-gate.cjs`, Stop hook in the settings template plus a CLI: every reply the operator saw is split into sentences; one that ends in "?" (outside code and quotes, emphasis markers stripped) and matches a proposal pattern (English built in; other languages as instance data `.claude/rules/open-questions.json`, template shipped) is recorded in `.claude-state/open-questions.json`. When the operator has written after it and it is still `open`, the turn is blocked once with the ids; it is settled by one call, `question-gate.cjs resolve <id>=answered|dropped|deferred[:note]` — an act, not prose. `deferred` keeps it out of the session (a postponed point is said once) and the bootup lists open and deferred questions at every start. Questions of the reply being ended are recorded, never blocked. Fixture `test-question-gate.sh`, 17 cases both ways (incl. a question behind notification replies, one in bold markers, code/quotes, a plain why-question, German only with instance data); an always-allow stub fails the must-block cases. Replayed on the real session with two German patterns: 7 questions found, all 7 real proposals to the operator, none false.
- **The session start says when the system clock is wrong.** (test: T1) Measured 2026-10-09 on the Windows instance: the clock ran two hours behind real UTC (three outside sources agreed: api.github.com, cloudflare, ptb.de), `w32tm` said `Source: Local CMOS Clock`, last sync `unspecified` — a time-service fix from 2026-09-24 had fallen back after a reboot without a sign. Internally the machine was consistent, so nothing local noticed. It broke silently: every commit timestamp of that machine (an answer appeared two hours BEFORE the request it answered in a cross-instance timeline under one GitHub account) and every time-based cursor (a PR watcher built `since=` from `date -u` and replayed one old comment on every poll — the only reason it surfaced). New `scripts/clock-skew.py`, run by the bootup: one HEAD to `api.github.com`, its `Date` against the system clock; one `!! clock:` line beyond 120 s, silent within it and silent when the reference is unreachable (3 s cap — offline is no finding). Stdout pinned to UTF-8/LF (os-traps OS-9 — the first run printed the dash as cp1252). Measured: 362 ms live; fixture `test-clock-skew.sh` (no network via `CLOCK_SKEW_REFERENCE`: two hours behind and ten minutes ahead reported, 30 s and unreachable silent, a no-op stub misses the incident).
- **The watch skills no longer promise a watch that outlives the Monitor.** (test: T0) `shared-memory-watch` said the watcher "keeps running; it ends with `TaskStop` or with the session". Measured 2026-10-09 on the Windows instance (Claude Code 2.1.295): the Monitor announced "expires in 30m" despite `persistent: true`, sent the expiry notice after 30 minutes, and the watcher process was gone at the next `status` ("not armed"). Both watch skills now say to re-arm on the expiry notice and point at `watch-gate.cjs`, which catches a missed re-arm. Text only.

## 1.4.0 — 2026-10-09

Minor release, named by the operator: not one big step, but the sum — every brain now sees where it deviates from the shared core, every open point and every loose commitment reaches the operator sorted (at most three real decisions), the brain-scan checks what became of its own findings, and collaboration watching, the live-read gate and the first maintenance tools moved from one instance into the core. Verified on macOS and on a Windows brain (candidate #211, plus re-checks); first real run of the rebuilt brain-scan on the proving brain.

- **ollama-fallback carries no machine state.** (test: T0) Brain-scan 2026-10-09: the public skill held one instance's install state (version, path, pulled models, dated). Replaced by how to read the state live.
- **The brain-scan report agent writes the report itself, not an intermediate file.** (test: T1) First real run of the rebuilt scan (2026-10-09): the harness refused the report agent's Write of `findings/report-body.md` ("Subagents should return findings as text, not write report files"); the run then correctly aborted on the count gate (deep-check lines 0 vs 1) instead of returning a report it never wrote. The old scan wrote `scan-<date>.md` directly and passed. Now the body goes straight into the deliverable and the script-written head is prepended by one shell command.

- **The brain-scan can run with the scripts of a core under test.** (test: T1) `args.core` (default `<brain>/core`) points the machine step, the shared-memory lint and the inbox at a dev checkout; without it a brain testing an unreleased core measured with its old installed tools while claiming to test the new ones (found when the first run of the rebuilt scan was prepared, 2026-10-09).

- **An own act that expects a reaction no longer ends the turn without a live watcher.** (test: T2) Incident on the Windows instance 2026-10-09: the Windows check of the 1.4.0 candidate was pushed to shared memory, the turn ended, no watcher ran; the Mac side's re-check request surfaced only when the operator asked "are your watches running?" — "I had to point it out manually again". Transcript scan over every retained session of that instance: 63 pushes into shared memory, 30 covered by a live watcher, 33 not, at least 7 of those answers that drew a follow-up (classified from commit texts); 7 `gh pr create`, none with a watch armed before. The PR side of the class was filed as a prose rule on 2026-08-20; the shared-memory side surfaced only as watcher-CORRECTNESS bugs (cursor, lock, reachability), never as "nobody started it". The only carrier was prose ("arm in the SAME turn") — an omission leaves no artifact and no failure signal, and no scan checked use instead of presence. New Stop hook `helpers/watch-gate.cjs`, in the settings template (not behind the dispatcher, so a brain without `stop-checks.json` gets it too; hook-coverage reports it in existing brains): reads the turn's tool calls; a `git push` touching the shared-memory repo with a fact file from SELF to another party committed since the turn began and not closed (`status:` answered/done/decided/info/closed — the inbox reader's set, so `status: info` is the declared "nothing awaited"), or a `gh pr create`, with no live watcher (pid in the lock of `shared-memory-watch.sh`, plain or inside collab-watch, answers `kill -0` — the scripts' own `status` definition, so an expired or killed Monitor counts as not armed; for PRs a live collab-watch repo lock or a watch-pr/ci-watch/collab-watch Monitor in the turn) blocks once per turn with the arm command. Fixture `test-watch-gate.sh`, 16 cases both ways incl. a dead-pid lock and a notification inside the turn; an always-allow stub fails the must-block cases. Replayed on the real transcript: blocks without a watcher, passes with the live one.

- **Three findings of the Windows check of the 1.4.0 candidate, fixed.** (test: T1) Measured on the workstation 2026-10-09 (all green, three observations): many waiting items collapse into one start line (above 5, `OPEN_ITEMS_WAIT_COLLAPSE`); `always-loaded.py --memory <directory>` is refused instead of measuring the directory entry; `commitments.py` says when it checked English phrasing only (a brain in another language without instance data reported found=0 as if clean). Fixture cases for each.

- **Every open point reaches the first reply — split by who has to act, louder on every repeat — and a session whose bootup never arrived is caught.** (test: T2) Incident on the proving brain 2026-10-07: the bootup listed nine open shared-memory requests to the instance and six open PRs; the first reply said "nine older requests, nothing new since the last start" and named none. The data side had been fixed two days earlier (open requests ignore the cursor, 1.3.43); the relay side had no carrier, and the rule "relevance beats completeness" even covered the omission. Measured on the way: the open-request list used the inbox's 30-day default, so a 32-day-old request fell out silently; the PR line capped at six; the bootup itself had been cancelled by its hook timeout 38 times on one macOS brain, the last on 2026-09-23 (none since). The operator's form for the first reply: "n items I can answer/handle myself — shall I?" (one OK — a session usually starts for another reason, and the agent starts none of them without it) plus "n need you directly" (up to three: one short bullet each, what and who needs what; more: the offer to list them — a wall of items intimidates). New `scripts/open-items.py` is the ONE open list at session start: every open request to this instance (no age window — age is shown, not used to drop) and every open PR under the ecosystem owner. Per item a class: automatic where the data says it (`circle:` A/C = `ai`, B/D/E/F = `human`; a request addressed to a person by name — instance data `humans`, a machine id built from the name does not count — = `human`; a PR = `ai`), otherwise printed `?` until the agent classifies it once (`--classify '<id>=ai|human:<why>'`, per machine in `.claude-state/open-items-class.json`). Per item a repeat counter keyed by session id (`.claude-state/open-items-seen.json`; resume and compaction never count twice): "first report", then "!! reported in N sessions since <date>, nothing done yet". A source that could not be read says NOT checked (the inbox count is checked against the parsed lines, so a capped list, an unset `SHARED_MEMORY_SELF` or an unparsed line can never read as "nothing open"); a clean start says "nothing open"; parked domains (instance data `parked`) stay on one line. It replaces the bootup's capped "open PRs" line and, inside the bootup, the shared-memory check's own open-request list (run by hand, the check still lists them). New Stop check `helpers/open-items-gate.cjs`, in the settings template: reads the TRANSCRIPT, not a state file, and blocks the first reply after a startup/resume bootup that lacks the form (both counts as digits, the opening question when the agent has items, every operator item named when there are at most three, the offer when there are more, the repeat wording, "nothing open", a NOT-checked source, the parked line), that leaves an item unclassified — and blocks when the bootup was cancelled, missing or from an older core. Compaction and every later turn pass. `stoppen-gate.cjs` leaves the closing question alone on exactly that turn, and only when the opening question is due (a wider version silenced every stoppen-gate fixture). Phrasing beyond English is instance data (`nothing_patterns`, `failed_patterns`, `parked_patterns`, `offer_patterns`, `repeat_patterns`). `rules/intelligence.md`: open points are a reporting duty, not briefing prose. Fixtures: `test-open-items-gate.sh` (26 cases; an always-allow stub turns all 14 must-block cases red, the stoppen-gate of `main` turns the opening-question case red) and `test-open-items.sh` (24 cases, no network; dropping the count check, the lost-counter line or the machine-id guard turns their cases red). Existing brains: hook-coverage reports the new Stop hook until it is registered (`stop-checks.json` with the dispatcher, or the template line).

- **Open items after the alpha: named in plain words, counted only when read, quiet while the move is someone else's.** (test: T2) Alpha on the proving brain 2026-10-07..09, three evaluable sessions: one correct pass, one correct block, one false block, no missed omission; bootup 14.0-15.4 s, never cancelled. Fixed from the measurement: (1) a request now counts as named by its date, its topic words (file slug; kind words like "request" do not count, an instance adds its language as `generic_words`) or its age in days (`age_unit_patterns`) — the false block came from a reply that named all eleven items with their age; the date-only check pushed replies toward file names against the plain-words rule. (2) A session counts as a report only once its transcript shows the list reached a human (the bootup block, then a real prompt); a hand run never counts — a session without any transcript and two hand runs inside a development session had inflated every counter. (3) A PR whose move is not ours prints as `[PR|wait]` and does not count up: we reviewed or commented after its last commit, or the repo belongs to someone else (instance data `owners`) and no review was asked of us — two approved PRs had been printed "nothing done yet" in every session after. The PR list comes from one GraphQL search (reviews, review requests, comments, last commit); the shown date is when the PR was opened, not its last activity. (4) A dated wait (`waiting` in instance data, or `waiting-until: YYYY-MM-DD: <why>` in a PR body) is quiet until the date and louder after it. (5) The `why` says what a decision circle means instead of its letter; the bootup instruction asks for plain words and says wait items need no relay. (6) A request from another side in a parked domain leaves the parked line and is listed as answerable (receipt, state, when it resumes) — one such question lay 30 days on the parked line. (7) The operator's prompt can already be the go-ahead (`goahead_patterns`, built-in "go ahead", "handle everything"): then the count and repeats are still required, the shall-I question is not. (8) `stoppen-gate` leaves a closing question alone when a bootup line orders it ("... — ask the operator", e.g. the brain-scan question it blocked on 2026-10-09), on any turn; other questions are judged as before. Follow-ups, not in this change: derived ledger items with do/ask/drop exits, and a stop check against priority/ledger codes in replies to humans. (9) A run without an owner reports "PRs (no owner given) NOT checked" instead of "nothing open" — measured: a hand run without `--owner` said "nothing open (requests and PRs both read)" while twelve PRs were open. (10) Only the bootup (a real session id) writes the counter file; a hand run reads and prints but never writes — measured: that same hand run rewrote the file and every item lost its history. Fixtures: `test-open-items.sh` 41 cases (PR cases from a saved GraphQL answer via `OPEN_ITEMS_PR_FIXTURE`; reverting either fix turns its cases red), `test-open-items-gate.sh` 38 cases.
- **The stop dispatcher tells every check whether the operator or a notification opened the turn — and a check can sit notification turns out.** (test: T2) Measured on the proving brain over 2026-09-07..10-06: 39 of 164 real Stop-check firings (24 %, up from 16 % in the month before) landed on a turn that no operator text opened — a finished background task, a watcher event, a CI verdict — spread across five checks (class 11, stoppen 12, diagnose 11, premise 4, verifier 1). Spread over five checks means the cut belongs in the dispatcher, not in one gate. The dispatcher now reads which user record opened the running turn: a record that is nothing but harness frames (`<system-reminder>` / `<task-notification>`, stripped, no text left) is a `notification` turn; anything with the operator's own words is `operator`; hook feedback does not open a turn. Every check gets `turn_kind` in its stdin payload, and a check entry may set `"onNotification": "skip"`. Without it every check runs as before — the default changes nothing; which check sits those turns out is a per-check, measured decision in the instance config. Fixture `test-stop-dispatcher.sh`: seven new cases (skip honoured, default still runs, kind handed over for both kinds, frame plus operator words = operator, hook feedback keeps the kind); against the previous dispatcher five of them are red. Checked on a real transcript: a watcher-expiry turn reads `notification`, the operator's next message `operator`. **The same definition fixes the gates' cooldowns** — the root of the 2026-09-02 finding: every gate that counts turns (absence, class, premise, promise, recall, stoppen, stop-verifier in the core; four more on the proving brain) took a notification record as an operator turn boundary, so a cooldown ran out on turns nobody had written. One helper, `helpers/turn-kind.cjs` (`isNotification`), now serves the dispatcher and all seven core gates; a record that is nothing but frames no longer counts down a cooldown. Fixture `test-turn-kind.sh`: the definition (frames only / frames plus operator words / plain text / a bare reminder) and the effect — after stoppen-gate fired, three notification turns keep it quiet, three operator turns end the cooldown; against the previous stoppen-gate the notification case is red.

- **coherence-scan audits every gate data file and reports dead carriers.** (test: T1) Coherence-scan 2026-09-18 on the proving brain (§P1-19, option B): the corpus took exactly one `.claude/rules/*.json` (the mechanism rules), so the live-read gate's data file, a skill's `references/` schema that a core rule delegates to, and the forced output style were outside the audit — and the MANIFEST still said "Anomalies: None". The same scan found a pointer to a deleted hook script by chance, not by construction. The inventory now copies EVERY `.claude/rules/*.json`, every instance skill's `references/*.md` and `core/output-styles/*.md`, and runs a carrier check: every carrier path named in CLAUDE.md, `.claude/rules/*.md` and `core/rules/*.md` is tested with `ls` (a `references/` path also resolves against the root of a suite a skill is symlinked from), and every dead one is listed with file and line under the MANIFEST's Anomalies and in the returned `missing` (cap 20 -> 40). Prompt change; measured with a standalone port of the check: proving brain 29 named carriers, 0 missing (one false positive found and fixed on the way: a suite's root-level `references/`); planted negative control with the historic dead pointer flagged 2 of 2. `test-coherence-scan-files.sh` and `test-workflow-relays.sh` green.
- **Notes to a human name the kind and the matter in plain words; the CLAUDE.md size check becomes a diet review.** (test: T0) Operator correction 2026-10-08 on the proving brain: session reports spoke of "P1" and audit finding ids instead of saying what was going on. `rules/intelligence.md` gets the rule next to the existing "written for the operator" paragraph: task, proposal, serious problem, acute need for action or note, plus what it is about; a priority grade or ledger id at most as a trailing reference in parentheses. The template checklist replaces the bare "CLAUDE.md under 200 lines" with a per-section diet review (still needed, in this form, in the right place; state/todos/history out, rules stay always-loaded) and a trend on the always-loaded total; it states that 200 lines is a self-set target, the documented harness cut being for MEMORY.md. `rules/thinking-protocol.md`, rule-conflict step 2: a new instruction decides its reach in the same pass (core PR / suite PR / instance only) — measured on the proving brain the same day, 18 of 24 general-looking operator rules existed only in the instance. Rule and template text only.
- **Every brain's session start names where and why its core behaviour differs from the shared core.** (test: T2) Operator order 2026-10-08: "we must make sure the core is set up for everyone so that no local workarounds arise, but work happens on one robust shared system — essential"; and "exactly this realisation should happen in every brain: where and why core functionality deviates from the shared core." Measured on the proving brain the same day: of 31 hook and stop-check entries, 11 ran from the released core, 12 from three unmerged development checkouts (the whole session start and the whole stop dispatcher among them) and 8 from instance scripts, at least four of them general mechanisms no other brain had — and nothing reported it, because everything worked. New `scripts/local-machinery.py`, run by `session-bootup.sh`: reads the hooks in `.claude/settings.json` and the checks in `.claude/rules/stop-checks.json`, classifies each as core / instance / outside, and prints one line per finding — hooks from outside the brain and the core without a dated alpha declaration (loud), expired alphas (loud), instance hooks without a reason to live only there, and files edited inside `core/` (the existing pin check sees moved commits, not edits in place). Declarations as instance data `.claude/rules/local-machinery.json` (`instance`: path -> reason; `alpha`: path/prefix -> until + why), template shipped empty. New HARD section "One System, Not Local Workarounds" in `rules/working-rules.md`. Fixture `test-local-machinery.sh` (11 cases both ways; against a no-op script 6 fail), picked up by the portability smoke's glob. Silent and exit 0 when everything is core or declared; a broken settings file never blocks a start. Hooks are not the only entry: MCP server paths from `.mcp.json` and skill symlink targets are traced to their git checkout, and a checkout outside the brain that is not on main is named (`<checkout>@<branch>`) unless declared as alpha. Stdout pinned to UTF-8/LF because the session start parses it (os-traps OS-9). Scripts outside hooks are scanned too (measured 2026-10-09: one diverged copy of a core script was what a brain-scan checklist actually ran, and a same-named thin wrapper on another core script looked identical to a copy from outside, and dozens of general tools lived only in one instance): an instance script with the same name as a core script is loud; an instance script with no declared reason is listed for the AI to classify (fixtures skipped).
  - *Addendum, carrier inventory* (test: T2). Operator order 2026-10-09: "we need robust analysis and checks that then run on all instances" — on the proving brain the detector kept missing deviations that surfaced only when the operator asked. Four root causes, each designed against: (1) the search space followed the incidents (hooks, then scripts), not the invariant — now one INVENTORY over every carrier type (`CARRIERS`: hooks and stop checks from project, local and user settings; MCP servers run from the brain; effective git hooks, local or global `core.hooksPath`; scheduled jobs that reference the brain — per-user LaunchAgents, `schtasks` on Windows, said once as `unchecked=scheduled` elsewhere; enabled plugins that are neither the core plugin nor a suite from `config/ecosystem.json`; real-directory skills; non-symlink workflows; output styles, agents, commands; rule text per `##`/`###` section; every script in the brain outside `core/` and nested checkouts), with a carrier-coverage self-test in the fixture: one planted item per carrier, every one must be reported, and removing that carrier's line from the scanner must turn its case red (13 negative controls; a carrier without a planted case fails the fixture). (2) "Instance-only" was a self-declaration nobody checked — a declaration now names `evidence`, the instance token the item relies on, and the checker verifies it occurs in the item (string form still accepted, reported as "reason without evidence"; evidence not found = loud); with `identity_tokens` (hosts, IPs, persons, devices, domain words) an undeclared item containing none of them is reported as presumably general. (3) Near-duplicates under another name were invisible — an item whose name shares a run of two name tokens with a core script, helper, workflow or skill is named as "possible duplicate of core <name>" (`distinct_from` silences it); same-named skills and workflows join scripts as loud shadows, and a same-named THIN WRAPPER that only calls the core item (it names `core/<path of the same name>`) is reported as a wrapper to remove, not as a diverged copy — from outside the two looked identical (measured 2026-10-09). Two more blind spots from a function analysis the same day: a hook or stop-check target that does not exist is loud (8 of 11 stop checks on the proving brain pointed into dev checkouts by absolute path; a removed checkout would have silently ended them, declared or not), and a carrier declared in two contradicting places is loud (listed in the core's `manual-tools.json` as run-by-hand yet wired as a hook, stop check, git hook, scheduled job or MCP server; or matched by both an instance and an alpha declaration). (4) Findings had no consequence — a last line `local machinery summary: items=N shadow=N ... undeclared=N` carries the counts per class for the session start and a status note; still no blocking gate. New `--home`, `--decl` (try declarations without editing the brain) and `--carriers`. Fixture 69 checks (against a no-op script 41 fail; the 16 that stay green are the silent halves), Windows: every temp path that travels as data goes through `nat()`, and the real home and global git config are kept out via `--home` and `GIT_CONFIG_GLOBAL` (os-traps OS-1/OS-3/OS-9 notes updated).
- **The caveman alarm at session start no longer counts the bare setting as armed.** (test: T2) Measured 2026-08-04 on macOS and Windows: the `outputStyle` setting arms nothing on its own — only an enabled plugin with a forced style, or a style file in a local output-styles dir. The bootup counted the setting anyway, so its alarm stayed silent exactly when the plugin lost the style (instance ledger, 2026-09-18). The check moved into `scripts/caveman-armed.py` (fixture `test-caveman-armed.sh`, 6 cases both ways; the bare-setting case fails against the old logic). effect-check E1 required only that a plugin key APPEAR in the settings, so a channel set to `false` still counted as enabled; it now requires the value `true`.
- **Ask or act: one ordered procedure, and a BLOCKED end for autonomous runs.** (test: T0) Coherence finding on the proving brain 2026-09-18: the ask-or-act decision was spread over a dozen rules on three ranks; Mechanism Discipline said "DISCUSS" while the instance's stop gate blocked any turn that ended on a question, so for a cheap, reversible subtask without a defined path every choice broke a HARD rule. `rules/working-rules.md` now carries ONE four-step procedure (gate for irreversible/external · defined path inside the order · adjacent = write it down without blocking and continue · otherwise do and report) and says "DISCUSSED" never means ending the turn on a question. `skills/autonomous-run` gains a third end: every remaining item depends on an interrupted path the operator must restore — report BLOCKED, arm a waiter on the path, disarm, stop (before: wakeups kept the watchdog green with nothing doable, or the 3-loop limit pointed at a substitute path). `rules/techniques.md` #5: a different approach is a different fix, never a different access path.
- **The session start names growth of the always-loaded context.** (test: T2) On the proving brain CLAUDE.md had crept to 258 lines with state, todos and history that belong in ledgers; a diet review cut it back (2026-10-08), but nothing showed the creep between reviews — growth costs every session and never fails. New `scripts/always-loaded.py`, run by the bootup: totals CLAUDE.md + `.claude/rules/*.md` + `core/rules/*.md` + the MEMORY.md index and compares against an ACCEPTED baseline (`--accept`, set at the diet review; state in `.claude-state/always-loaded.json`), so small daily steps add up instead of hiding. Silent within 2 KB; first run creates the baseline silently. Checklist template gains the review line. Fixture `test-always-loaded.sh`, 6 cases.
- **An invariant register gets a generated routing index.** (test: T1) The shared memory and the private memory route through indexes; the invariant register had none — 222 KB in one file on the proving brain, read whole or grepped to answer "which classes exist, which are open". Operator order 2026-08-30: one index principle everywhere (generated, routing length, detail stays in the file). New `scripts/invariant-index.py <register> [--write]`: one line per class — title, status (cut, never rephrased), and what holds it (pattern / tool / no = judgement / prose = nothing re-checks); writes `<register>-index.md` beside it. On the proving brain 14,867 instead of 235,403 characters per lookup. Fixture `invariant-index-test.py` (9 checks, incl. LF bytes).
- **New skill `backlog-catch-up`: a flood of old open points becomes at most three operator decisions.** (test: T1) The louder session start (#197, #201) makes old open points visible — on its first run in a brain with a backlog, all at once. Measured on the proving brain 2026-10-08: 68 derived proposals; sorted by hand into seven exits (done already 13, the AI does it 28, the other side 5, parked 5, later at the system 10, drop 3, operator decision 4). The skill makes that sorting the same in every brain: one plain sentence instead of a list, every item read in its source and measured, exactly one exit each, at most three decisions with a recommendation, the sorting written to a file, the AI's own items done in the same run. Ships in the same release as the louder checks — never the checks alone.

- **General operator rules that lived only in one instance move into the core.** (test: T0) Measured on the proving brain 2026-10-08: most general-acting rules in its `feedback.md` had no core counterpart, so every other brain worked without them. Ported in generic form, harmonized with the existing text (no second copy): `rules/working-rules.md` — AI content online is labelled (#3); a folder is no proof of a project; baseline generic, setup in its own file; identity written, state read; files the operator opens are versioned, dated save before and after a rebuild; archive by relevance, logs may rotate; a decision with reach is pushed in the same pass; "needed reload" extended to every action expected from someone else; Order Fidelity #7-#10 (a question is not an approval, test material from the order, an ordered audit orders its clear fixes, no unseen re-release of what was just criticised); Working Rules #7 commit-ready means committed, #8 shell commands atomic and matching a permission pattern (no `cd … &&`, no heredocs); new section "Working Across Parties" (proper name not role word, ownership is assigned and measured, the domain owner decides domain questions, judge the sum). `rules/thinking-protocol.md` — a repeated remark is a misunderstanding; "only derived" is no answer; absence is measured on every level; goal before class; a conflict in one's own rules with a clear recommendation is applied, not presented. `rules/techniques.md` #12 — never suggest a break. `rules/intelligence.md` — the brain-scan runs only in an active session on the operator's OK (no scheduler by default; `scripts/brain-scan.sh` is opt-in); a public tool is a comparison order; technical limit vs. build-up work; new section "Presenting to the Operator" (only real decisions, sub-agent framing, measurable is not an open point, hands-on items, parked domains still answer requests, name the server). `skills/verification-before-completion` — look before presenting an artifact with an appearance; the pass bar reference gains self-contained, stranger-readable, operator surface = standalone run, hands off during the operator's run. `AGENTS.md` #12 — who merges and who releases, beta before stable, the T0/T1/T2 test classes defined. `CONVENTIONS.md` — suite ownership (lead maintainer merges, tags and pins alone; branch in the repo; outside the core the author merges) and marketplace-ready from the first file. Rule text only.
- **New PreToolUse gate `live-read-gate`: a live system is not touched before its mandatory reading was read completely.** (test: T2) Ported from the proving instance, where it has run since 2026-09-02. Incident there: the agent probed a live network with ad-hoc pings and MCP calls, diagnosed "device down" and asked the operator to restart it, without having read the domain ledger that exists to prevent exactly that diagnosis — the prose rule "read it first" had stood in the instance's CLAUDE.md for weeks. New `helpers/live-read-gate.cjs`: when a tool name or a Bash command matches a domain in the instance's `.claude/rules/live-read.json`, the call is denied until every required file of that domain was read in THIS session. What counts is what the Read tool DELIVERED (`toolUseResult.file` startLine/numLines over the whole transcript), unioned and held against the file's current line count — a capped single Read, a window that skips the start, a hole in the middle, or lines appended after the read all stay blocked, and the deny names the offset to continue at. A Bash `cat` counts only for a file small enough for untruncated Bash output; grep/head/sed never count. Two gaps closed on the instance before this port and kept closed here: the gate first trusted the Read CALL (a 1468-line ledger opened the gate at 29 %, measured 2026-09-18), and first scanned only a 16 MB transcript tail (image-heavy sessions lost their own reads). Generic engine, all domain data in the instance file; template `templates/rules-instance/live-read.json` ships with no domains. No instance file = silent no-op; a broken file = no-op plus a `BAD-CONFIG` line in `.claude-state/live-read-gate.log`. No bypass marker. Wired in `templates/settings.json` as PreToolUse `Bash|mcp__.*` (an instance gating other tools widens the matcher). Fixture `test-live-read-gate.sh`, 26 checks both directions (blocked before read, allowed after a full read via Read or small cat, partial/capped/holed/grown reads stay blocked, prose mentions and unrelated tools pass, a read 18 MB back still counts, broken and missing instance file), plus a negative control: every must-block case is also run against an always-allow stub and must flip — 12 of 12 do. OS-3 and OS-5 baselines extended after the native-path and predicate review. Existing brains that run their own copy of this gate keep it until they switch the wiring to `core/helpers/live-read-gate.cjs`.
- **Maintenance tools that lived only in one instance move into the core (first package).** (test: T1) A class sweep on the proving instance found general machinery that every brain could use living only there, unreviewed and untested on Windows. Each now reads its configuration from args, env or instance data, carries its WHY, and has a fixture in both directions:
  - `scripts/mcp-call.py` — call one MCP tool over stdio like the client does, so a tool change is testable without a reconnect. Takes a server NAME from the instance's `.mcp.json` (command/args/env, `${VAR:-default}` expanded) or a bare launcher; a tool error (`isError`) is exit 1, no answer is exit 2 with a deadline (a silent server no longer blocks forever). Fixture `mcp-call-test.py` against a fake server: 8 cases.
  - `scripts/mcp-toolcount.py` — a server that starts is not a server that works: counts each server's tools (paged `tools/list` followed) against `.claude/rules/mcp-expected.json` (template `templates/rules-instance/mcp-expected.json`); a deviation in either direction fails. Shares the stdio client with `mcp-call.py`. Same fixture: 6 cases, a count off by one as negative control.
  - `scripts/transcript-archive.sh` — dated archive of all session transcripts (`${CLAUDE_CONFIG_DIR:-~/.claude}/projects`), read back and counted; an incomplete archive is now exit 1 (was a warning with exit 0), and a destination inside a git work tree is refused. Fixture `test-transcript-archive.sh`: 9 checks.
  - `scripts/transcript-latency.py` — turn duration split into tool and model time, calls per turn, per-family call latency, output volume, per local day; transcript dir derived like `transcript-recall.py`, default families = the most-called, `--json`. Fixture `transcript-latency-test.py`: 11 checks on a synthetic transcript with known numbers.
  - `scripts/skill-first-measure.py` — Skill calls per session and Stop-gate firings per turn kind. Uses the core's turn-kind definition (a notification is a `<task-notification>` record with nothing but harness frames) and counts every gate tag in a dispatcher block. Fixture `skill-first-measure-test.py`: 15 checks, including parity with `helpers/turn-kind.cjs` when present (SKIP, said so, until #198 lands).
  - `scripts/session-log-fold.py --log decision` — the decision log folds with the SAME engine and guarantees as the session log (byte-identical move, sha-derived id, proof before and after writing); `## ` headings that are not entries and code fences are guard blocks, never folded. No second fold script. Fixture `session-log-fold-test.py`: 4 new cases (13 total), the session cases unchanged.
  - `scripts/staged-names.py` — blocks a commit whose staged ADDED lines name someone from a brain's `leak-names.json` (`names` and `instances`), for the core and suite repos where `leak-scan.py` runs without names on purpose; an instance wires it into its own pre-commit. A missing list passes and says so. Fixture `staged-names-test.py`: 6 cases, three negative controls (removed line, unstaged change, longer word).
  - `scripts/wait-mcp-reconnect.sh` absorbs the instance's process watcher instead of shipping a second one: a boot stamp ABSENT at arm time is refused at once (exit 3; `--allow-absent` for a server's first stamp) — a watcher without a starting state cannot prove a change; `--process <pattern>` is the POSIX stopgap for a server without a stamp (only children of this session's claude process, all old pids gone, a shrinking set is no restart, nothing matched at arm time is refused) and refuses on Windows. Fixture `test-wait-mcp-reconnect.sh`: 11 checks. `rules/working-rules.md` names the stopgap.
  OS-3 baseline +2 (`test-transcript-archive.sh`, `test-wait-mcp-reconnect.sh`) after the review in `docs/os-traps.md`.
- **Collaboration watch moves into the core: one arm call, every channel, autonomous handling.** (test: T2) Until now the watch that tells a session about collaborators' work — new PRs, merges, comments (also on merged PRs), inline review comments, shared-memory pushes, sessions joining the repo — lived only in one private instance and a private maintainer plugin, under one fixed term the operator had to say. New: `scripts/collab-watch.sh` arms all channels in one `Monitor` call, each under `scripts/watch-supervisor.sh` (a dying watcher prints `WATCHER-DIED`; the supervisor now kills its own child on TERM, because Git Bash on Windows has no `pkill`). Repos, intervals and parties are instance data (`.claude/rules/collab-watch.json`, template `templates/rules-instance/collab-watch.json`), checked by `scripts/collab-watch-plan.py`: unique tags (one cursor per cadence), one watch per repo, no unfilled placeholder, scopes by party (`all` default, `peers`, a party; a scope selecting an own machine is refused — one account, not separable by login). `scripts/repo-activity-watch.sh` (bash, ported from zsh) filters raw `gh` JSON through `scripts/repo-activity-filter.py` instead of `gh --jq`, so the filter has a fixture on every OS; no author filter by default, strict `>` against GitHub's inclusive `since`, merges judged by `mergedBy`, local-branch mark for PRs made on this machine, `WATCH-ERROR` when `gh` cannot reach GitHub. `scripts/parallel-sessions-watch.sh` diffs `scripts/parallel-sessions.sh` between polls. `scripts/watch-pr.sh` follows one PR (review verdicts included). New skill `collab-watch` with English and German trigger words (watchdog, monitor, watch, keep an eye on, beobachten, ueberwachen, autonom abhandeln, ...), the handling flow (review with evidence chain, comments, merge by ownership, follow-up PRs, park boundary, hard limits), a local cross-session hand-off section, and `references/watch-lessons.md` with twenty measured lessons. Fixtures: `test-repo-activity-watch.sh` (26 checks; an author filter on the own login and a shared cursor each turn a must-report case red; TERM on the arm script tears down the whole tree and frees the locks), `test-collab-watch-plan.sh` (36), `test-watch-supervisor.sh` (6, incl. child dies with its supervisor), `test-watch-pr.sh`. Mutation check: the inclusive-`since` fix, the supervisor child kill and the exiting TERM trap each turn their fixture red when reverted. Found by the live smoke and fixed on the way: a TERM trap that only cleans up swallows the signal — the arm process kept running with every supervisor gone (the instance script it is ported from has the same shape). Not measured: whether the harness's agent messaging reaches another local session.
- **Loose commitments are found: a promise about future behaviour made only in chat.** (test: T2) Measured on the proving brain 2026-10-09: the AI said "from now on I start the CI watch with every PR" in chat; nothing carried it, so no later session, no other brain and no check could see it. The operator: no stop gate, but regular, mechanical checks for every brain. New `scripts/commitments.py` reads the session transcripts, finds first-person commitments (English built in, other languages as instance data `.claude/rules/commitments.json`, quoted mentions ignored) and counts one as carried when a rule write in the same session shares its words, or today's rule text/docs hold it in one paragraph (60 %, at least three words). Run at two places, never mid-conversation: `session-close` (this session; the close is complete at loose=0 or with each dropped one named) and `effect-check` E6 (14 days, WARN), which the brain-scan already runs. First run on the proving brain found two real loose commitments of the last two weeks; both now carried. Fixture `commitments-test.py` (10 checks, negative control on the first-person filter). Template `templates/rules-instance/commitments.json`.
- **Brain-scan v2: return channel first, every finding leaves with one exit, no fix stage.** (test: T2) An audit of the audit process on the proving brain (2026-10-09) measured a one-way funnel: proposals piled up unread (68, three to five weeks old, 13 already done unnoticed), a quarter of report-only measures vanished, the same finding came back up to ten times without becoming a decision, 19 of 32 fix agents ended without doing anything (~2M tokens), two checklist sections (invariant register, self-check) had no executor, and the context agent cost ~121k tokens per run for reading three files. Now: a new deterministic `scripts/brain-scan-prep.py`, run by ONE small runner agent in place of the context and effect agents, states per earlier finding done / decided / dropped / still open / vanished (from the previous report's new `## Finding index` and the order list's `id:` entries), marks findings seen twice as decision-due, runs effect-check, invariant-check, brain-selftest, local-machinery and commitments (missing on an older core: one "not available" line), and writes a deterministic "deep check suggested: …" line with reason and measured price (≥5 new dated rule lines since the last coherence register, a finding back a third time, memory index at 90 %, an open `rebuild-ahead` entry). The report stage sorts every non-OK finding into one of seven exits (skill backlog-catch-up), presents at most three operator decisions with a recommendation, and is gated by `assertExits` (every raw finding accounted for, a third recurrence must be an operator decision). The session start relays the deep-check line. The checklist template gains sections 9 (invariant register) and 10 (self-check); every template section must have an executor (fixture). `shared-memory-dream.js` no longer ships a hard-coded `FRESHNESS-OK` marker, which had disabled the freshness gate for that workflow permanently. Fixtures: `brain-scan-prep-test.py` (36 cases), `test-brain-scan-files.sh` (each shape rule against the real file and a planted mutant, `assertExits` behaviour), portability-smoke (deep-check line relayed / silent).

- **`ci-watch.sh ref` judges the ref's CURRENT commit across every workflow.** (test: T1) Measured 2026-10-05: right after a merge burst, `ci-watch.sh ref <repo> main` said GREEN while main was red — it took `runs[0]`, the newest run of ANY workflow on the branch, and a one-minute side workflow had finished green while the five-minute CI run of the same push failed; a green run of an older commit could count for a newer tip the same way. Ref mode now resolves the ref to its commit (`gh api repos/<r>/commits/<ref>`, branches and peeled tags alike), takes every run on exactly that commit, waits while any is still running, and is green only if all are. Fixture: three new cases (side-workflow green + CI red, older commit green, one workflow still running); the old code answered green to all three.
- **The assertReport fixture can no longer pass on a crash.** (test: T0) Windows check of #194: 4 of the 6 new cases were green against a workflow WITHOUT the helper, because the ReferenceError counted as "loud". Only the helper's own refusal counts now, plus an explicit "helper defined" check; against a workflow without the helper all 7 fail.

## 1.3.43 — 2026-10-05

- **The audit workflows abort when their report was not written; brain-scan scans shared memory.** (test: T1) Measured 2026-10-02 on a Windows brain: the harness denied memory-dream's report agent its Write, the agent returned `report_path: ""`, and the workflow finished as a normal success. The script has no file access, so `assertReport()` (in the verbatim-extracted helper block of all four workflows) requires the returned path to be exactly the one the script named and a byte count the writer MEASURED with `wc -c`; empty path, other path or 0 bytes abort. brain-scan also fell through `if (summary)` when its report agent died — now a hard error. Section numbers: the template checklist had 6 = Shared memory and no git/SOTA sections while the workflow scanned "6 = git, 7 = SOTA", so no agent ever scanned shared memory; the template now has 6 Git & repo hygiene, 7 SOTA delta, 8 Shared memory, and a new `shared-memory` scan agent (lint, clean clone, `shared-memory-inbox.py --open` — unanswered requests are P1). Fixture `test-memory-dream-files.sh` +6 cases both ways. Reported by a collaborator's full audit.

- **Session start lists open requests, not only new ones — and says so when nothing is new.** (test: T2) Measured 2026-10-05 on a macOS brain: three requests addressed to it by name were shown once at a session start, never relayed, and the cursor moved on; every later start was silent, because a clean check printed nothing. `shared-memory-inbox.py --open` lists entries whose `audience` names this instance, that are requests (file name starts with `request`/`question`, or `status: open`; instances add their own words via `SHARED_MEMORY_REQUEST_PREFIXES`), and that none of our own fact files or LOG sections names yet — independent of the cursor, last 30 days. `shared-memory-check.sh` runs it on every start and prints `shared-memory: nothing new since last start` instead of silence. Fixture both ways (`scripts/shared-memory-open-requests-test.sh`, 13 checks; 7 fail against the old code), wired into the portability smoke.
- **New Stop check `absence-gate`: an absence claim needs a search over every registered source.** (test: T2) Incident on the proving brain: "the desk's send rate is documented nowhere" was stated after searching only the shared-memory repo, while a manual excerpt sat in a tool suite and a wire measurement in a testbench runlog. New `helpers/absence-gate.cjs`: when the turn's own prose makes an absence claim ("documented nowhere", "has never been measured", "there is no record of", English built-ins), the search calls of the same turn (Grep/Glob `path`, Read `file_path`, Bash grep/rg/find/ag/ack/fd/git grep path arguments, with a leading `cd`) are held against the instance's source roots in `.claude/rules/absence-sources.json`; a root counts as searched when a search ran on it, inside it, or on a parent of it. Unsearched roots are named; a visible `⚙ scope: <what, and why only that>` line lets a deliberately narrower search pass. `claim_patterns` and `scope_markers` in the same file EXTEND the built-ins (languages are instance data). No roots file = inert. `--record` never blocks and hands `{record:[...]}` to the stop-dispatcher (`.claude-state/absence-gate.jsonl`), including `delegated` (searches handed to a subagent are invisible to the gate — the known blind spot, measured rather than guessed). Template `templates/rules-instance/absence-sources.json` ships empty; register in `stop-checks.json` with `mode: record` first. Fixture `test-absence-gate.sh`, both directions, 11 cases: incident shape blocks and names the unsearched roots; full search, parent search, Read inside each root, no claim, quoted claim, scope marker, no roots file and cooldown stay silent; record mode records and never blocks; an instance claim pattern extends the built-ins. OS-3 baseline extended after the native-path review.
- **No personal names in the public core.** (test: T0) Fixtures, comments, examples and changelog credits named the operator and two collaborators by first name or by a machine id derived from it. Replaced with neutral placeholders (`alex-macos`, `alex-workstation`, `sam-*`, `kim-win`, "a collaborator"); behaviour unchanged, every touched fixture re-run green. Private instances keep their own names.
- **Settings template: `.claude-state/**` is edit-denied only, no longer read-denied.** (test: T0) The session-close skill requires reading `.claude-state/promises.jsonl`, and the measurement mechanisms (recall-gate, memory-recall) write their logs there for later evaluation; the template's `Read` deny blocked all of that. Measured 2026-09-30 on the proving brain: the close step could not read the promises file. The protection that matters — nobody edits a gate's log — stays as the `Edit` deny. The checklist template says so. Existing brains: remove `Read(.claude-state/**)` from your own `.claude/settings.json` `permissions.deny`.
- **The session close checks every neighbour repo the brain records, not only its own tree.** (test: T2) The rules send every tool change to a suite repo next to the brain ("commits go THERE"), and the close gate verified one working tree. Coherence-scan 2026-09-18 §P1-12: a suite patched on a work branch stays uncommitted on the machine, the close says "persisted — you can shut down", and the other machine never sees it. `helpers/session-closing.sh` (skill step and SessionEnd hook) now reads the repos from the brain's ecosystem lockfile `config/ecosystem.json` (written by `ecosystem-sync.py`, so no second list) and prints `FAIL neighbour repo <name>: N uncommitted file(s), M unpushed commit(s) in <path>` plus a HANDOFF section for each one that is dirty or has commits on its checked-out branch that are on no remote. The brain root (step 4 covers it), the shared-memory repo (own line) and paths that do not exist are skipped; `~` resolves against `HOME`; no lockfile = no check. Unpushed is measured on `HEAD`, not `--branches`: on the proving brain three suites carry stale local branches (squash-merged PRs, a history branch) that are on no remote, and `--branches` gave each a permanent count no session could clear; with `HEAD` the real run is silent for all suites. The `session-close` skill: step 1 sends unfinished orders and intermediate states to their ledger and gives memory the lesson plus a pointer (a state in both places became two hand-kept copies); step 2 says `prune` before `export` after a memory was deleted, merged or renamed (export never removes, and the next import revived it), and names `session-closing.sh` as the HANDOFF producer; step 4 makes the gate cover every repo the session wrote to and re-runs the export expecting no diff; the Scope note no longer claims that no hook can touch a tracked file after the close commit without that check. `rules/intelligence.md` Session End says the same in one line. Fixture: seven properties in `test-session-closing.sh` (clean suite silent, dirty suite named with HANDOFF section, brain itself and a missing path skipped, unpushed work branch named, silent after push, stale branch not checked out silent, `~` path followed, no lockfile silent). Red against the previous close (4 checks fail), green after.
- **The session log is folded at session close, above a threshold the instance sets.** (test: T1) On the proving brain the log grew 26 KB -> 81 KB -> 153 KB between weekly scans (2026-08-10 .. 2026-09-30): the fold tool existed, but only in that one instance, and it only ran when a person started it after a scan had flagged the threshold. The fold decision for that brain (2026-08-22) was "fold at session close, where the log is written anyway"; the wiring was missing. New core `scripts/session-log-fold.py`, ported from the instance tool with the same output (it reproduces an existing instance fold byte-for-byte, id `6aa5d19d34e3`): purely extractive, id = sha256 of the moved bytes, no fold-of-folds, reassembly proven before and after writing, line endings kept as they are. New mode `--max-bytes N`: nothing while the log is <= N; above it the oldest whole days are folded until the log is <= N/2, so the next fold is half a threshold away rather than one session; today's entries never move. `helpers/session-closing.sh --pre-commit` (the skill step before the close commit) runs it with `--apply` when `SESSION_LOG_FOLD_MAX_BYTES` is set; unset = no fold, as before; the SessionEnd hook path never folds (it must not touch a tracked file after the close commit). A refusal (out-of-order entries) is a `WARN session-log fold:` line, never a failed close. The `session-close` skill (step 2) and the Audit rule in `rules/working-rules.md` now say that a fold is not a clean-up of an append-only protocol. Fixtures: `session-log-fold-test.py` (9 cases: no-op under the threshold, lossless fold, hysteresis keeps the newest days, idempotent, today never folded, CRLF stays CRLF, out-of-order refused, preview writes nothing, second fold keeps the first marker) and four properties in `test-session-closing.sh` (fold with threshold, none without, none under it, none from the hook). Red against the previous close (5 checks fail, the script does not exist), green after.
- **`memory-lint` checks the manifest -> file direction; `memory-sync prune` heals what it finds.** (test: T1) The snapshot check compared live memory -> snapshot only, and intersected the snapshot with the manifest, so a `.sync-manifest.json` entry whose file exists on neither side vanished from the comparison: "manifest lies" and "all in sync" both printed `all clean`. Measured on a proving brain (brain-scan 2026-09-07): a deleted memory stayed in the manifest for weeks unreported. New finding `manifest entry without a file` (a live file missing from the snapshot stays the existing `missing from the repo snapshot` finding, not a second one). Its fix had to exist too: `prune` only walked snapshot files and never touched such an entry; it now also drops manifest entries with no file on either side (lossless — the entry is a hash of content that no longer exists). Fixtures: three cases in `memory-lint-test.py` (ghost reported, in-sync stays clean, live-only reported once) and two in `test-session-helpers.sh` (prune drops the ghost, keeps the live entry). Red against the previous code on the two ghost cases, green after. Real run on the proving brain's memory (155 files): no ghost, the pre-existing drift lines unchanged.
- **The two class questions get two names: procedure class and finding class.** (test: T0) The core asked "class" in two places — up front (Knowledge Carriers #3: is this task repeatable, is there a skill?) and at "done" (Class Discipline: is this defect a one-off or a class?) — with the same word. Incident 2026-08-20 on a proving instance: the front question slid from "which procedure do I use" to "what is this case in general" before a single observation was in; the resulting summary was refuted by the operator's second observation in the same message, with a decision draft already stacked on it. `rules/intelligence.md` names both, with a table (question, object, place, why there) and the boundary: the procedure class never pre-shapes how data is read — single case with all its subordinate clauses first, mechanism next, class last. `rules/thinking-protocol.md` Class Discipline says "finding class" and points to the split. Rule text only; the matching mechanical carrier (`premise-gate`) is already in the core.
- **`stoppen-gate` carries English only; German is instance data like every other language.** (test: T2) The hook shipped a German pattern pack inline next to its English built-ins, so the core's contract "engine English, languages are data" (operator order 2026-08-19) held for the premise and promise gates and not here — and `english-only.py` exempted the file, so nothing would have noticed a second pack. The inline pack is removed; the thirteen patterns live verbatim in the fixture as the instance file an instance writes to `.claude/rules/stop-patterns.json`. `stoppen-gate.cjs` leaves the english-only skip set, which makes the layering a CI check: the previous engine, unexempted, fails with `NEW GERMAN: helpers/stoppen-gate.cjs`. `english-only.py` states its detection boundary in the header (German drift only, deliberately; how a second language would be added). CONVENTIONS §3 gets the layering contract, naming `recall-gate`'s replace-semantics as the one documented exception. **Migration:** an instance that relies on German stop questions copies the JSON from `scripts/test-stoppen-gate.sh` into its `.claude/rules/stop-patterns.json` before or with this update — without it German handbacks pass silently. Fixture: new case `de-no-pack` (German without the instance file must pass) is red against the previous engine, and the German cases now run through the instance file; 19/19 green after. Measured on the proving brain with its new instance file: German handback blocks, the same transcript from a cwd without the file passes.
- **`skill-lint.py` checks where a skill lives and where its steps come from.** (test: T1) Incident 2026-08-19: an instance wrote four skills out of a running live session straight into its private brain; one was written a day AFTER the decision it silently omits, and the instance then followed its own skill instead of the primary source. CONVENTIONS §11 already forbade that placement and nothing checked it — the linter looked at structure only. Two new categories: `placement` (a real directory, not a suite symlink, whose name/description hits a tool domain of the instance = born in the wrong place) and `provenance` (a new local skill without a `provenance:` field). Both are a ratchet over instance data `.claude/rules/skill-placement.json` (`tool_domains`, `legacy` baseline that may only shrink; a dead or no-longer-needed baseline line is itself a finding). Without that file the ratchet is off and only drafts are checked, so a brain that has not opted in stays byte-identical in every existing category. Draft convention `_draft-<name>` + `status: draft` + `provenance:`: no name-vs-directory finding, kept out of `REGISTRY.md` — by the linter and by `regen-skill-registry.py`, which used to write drafts in. Prose halves: `rules/intelligence.md` skill-first #1 gives the rank to VERIFIED skills only (a skill against the ledger/primary source/measurement loses, a draft outranks nothing); CONVENTIONS §11 documents the PR path (branch `skills/<name>`, CI, counter-read, merge, release) and that the local draft expires on adoption. Fixture `scripts/skill-lint-placement-test.py` (optional second argument = old linter for the negative control + regression guard): red against the previous linter (7 of 7 properties fail, the regen property fails against the previous generator), green after, 16 of 16 with the old linter as control. Child processes are pinned to UTF-8 (OS-9): under a Windows codepage the regen summary line arrived as byte 0x97 and the fixture crashed before its first check; reproduced on macOS with PYTHONIOENCODING=cp1252, green after the pin. Real proving brain (40 skills, ratchet on): every existing category identical old vs. new, 0 placement/provenance findings.
- **Time-word rule: true relative time words are welcome, session history is a source.** (test: T0) `rules/thinking-protocol.md` said "not measured → OMIT"; the operator refinement of 2026-08-19 (time words wanted when true, the running session counts as a source, no forced clock precision) lived only in one instance. Harmonized text, same invariant: an unmeasured time word stays forbidden.
- **Producer agents in the audit workflows write exactly one file and report exactly that path.** (test: T0) Measured 2026-09-30 on a brain-scan run: the effect scan agent wrote its `scan-effect.json` correctly, then wrote a second, out-of-scope `brain-scan-<date>.json` across all sections and returned THAT path. `assertFiles()` aborted the run as designed (no partial report), but a resume was needed. The six "you are the producer, you write" prompts in `brain-scan`, `coherence-scan`, `memory-dream` and `full-audit-synthesis` now say: one file, the named path, no other; the path reported back is exactly that one. Prompt text only — the abort gate stays the carrier.

- **Brain-scan agents read the surroundings before reporting.** (test: T0) Three scans in a row (2026-08-22, 09-23, 09-30) reported a BSD-only `stat -f`/`date -r` whose portable fallback sat in the neighbouring line, and a "missing" file that lives in another repo the referring line names. `SCAN_COMMON` now requires +/-5 lines of context and a ruled-out fallback before an OS finding, and a search over every candidate location (including a named other repo) before a missing-file finding.

- **`scripts/brain-selftest.sh` is executable.** (test: T0) It was mode 644 and only ran via `bash …`.

## 1.3.42 — 2026-09-30

- **Session start names open code-scanning alerts.** (test: T2) Measured 2026-09-30: eight CodeQL alerts in a vendored skill of this core had stood open since the first public cut (2026-08-13), because nothing ever showed them. Behind them sat worse than the alerts said — browser session cookies read silently on every run, a full `gh` token posted to a third party. New `scripts/code-scanning-alerts.sh <owner>`: per non-archived repo of the ecosystem owner (derived from the marketplace, as for the PR line), the open alerts and the folders they sit in, one `!!` line only when something is open. A repo without a scanner (404) or access (403) is skipped; a failed repo listing says `NOT checked` instead of going silent. One call per repo — 7.7 s for 15 repos — so the bootup runs it through `cached-verdict.sh` with a 6 h window and a background refresh, and prints only when there is a line to act on; a reused result carries its age. Fixture `test-code-scanning-alerts.sh` with a fake `gh`: named with folder, clean repo silent, no-scanner repo skipped, failed listing says so. Real bootup on the proving brain: `!! code scanning: 8 open alert(s) — agent-brain 8 (skills/last30days)` plus `(reused: …, measured 31s ago)`.

- **The live shared-memory watcher no longer swallows foreign entries that arrive with an own pull.** (test: T1) A new head reachable from the local checkout counted as "ours" and moved the cursor silently — but the pull before every own push brings along whatever others pushed in between. Measured 2026-09-30 on Windows: a request addressed to this instance (a Windows check) was skipped exactly that way and only found when the operator asked. The watcher now runs the inbox reader over such a range; it drops the own entries by `SHARED_MEMORY_SELF` and anything left is reported. New fixture property (foreign entry pulled in before an own push is reported, the own push alone stays silent); red against the previous watcher on exactly that property. The skill's guarantee text is corrected.

- **The live shared-memory watcher names the sender of a LOG entry.** (test: T1) Its FOUND line read the party only from `von:` fields, which LOG entries do not have — their heading names the sender. The inbox lines printed below it used to cover that, but once `SHARED_MEMORY_SELF` is set they only show entries for this instance, so a LOG entry addressed to someone else left nothing but `unknown party (no von: field)` (measured 2026-09-30, three times in one evening). `shared-memory-inbox.py --senders` now prints every sender in a range, unfiltered, through the same heading parser as the inbox (four live heading shapes); the watcher adds those to its party list. Fixture asserts the sender in the FOUND line; red against the previous watcher.

- **An orphaned shared-memory watcher exits and frees the lock.** (test: T1) Measured 2026-09-30 on macOS: a `shared-memory-watch.sh` whose parent process was gone kept polling and kept the per-machine lock. `kill -0` on its pid stayed true, so the next session was refused with "already armed by another session" and skipped, while the orphan's output reached nobody. The watcher now records the parent it was started by and exits when that parent is gone: checked before every poll (an orphan never advances the cursor for a reader that no longer exists) and every `SHARED_MEMORY_WATCH_TICK` seconds (default 5) while sleeping. The EXIT trap frees the lock; the next arm claims it. Property 4 ORPHAN in `shared-memory-watch-lock-test.sh`: a parent shell starts the watcher and dies; the watcher must have held the lock (setup proof, read while the parent lived), must exit, and the next session must claim the lock. Red against the v1.3.41 watcher (`orphaned watcher still running`), green after. Searched: the only other endless loop in `scripts/` and `helpers/` is `ci-watch.sh`, which ends at its deadline and holds no lock. Real arming path measured on both systems: armed by the Monitor tool the watcher runs (its parent is the Monitor wrapper, not a native process, so `$PPID` is never 1 at start); stopping the Monitor removes watcher and lock within one tick. On Windows the v1.3.41 watcher, stopped the same way, stayed alive holding the lock.

- **`onboarding-verify` checks 3, 6, 7 no longer split a path at a space.** (test: T1) The loops over the cached suite directories were `for d in $suite_dirs`, which walks the fragments of a Windows profile path with a space in the user name: check 3 reported an installed suite MISSING and named the first fragment as a suite. The three loops now read the list line by line. New fixture with a config dir containing a space (red against the old script with the same symptom); registered as `docs/os-traps.md` OS-10 with a search over every `for x in $list;` loop.

- **`onboarding-verify` check 12: shared-memory self.** (test: T1) The session-start inbox and the LOG rotation tell own entries from others' only through `SHARED_MEMORY_SELF`, and nothing set it — not bootstrap, not the template; an instance ran unfiltered until someone read the bootup hint. With a shared-memory checkout present the verifier now demands the name in the brain's `env` block (or the environment) and says where to put it; without a checkout it SKIPs. Fixture covers SKIP / FAIL / OK. Measured on Windows: live verify reads the instance name from the brain settings.

## 1.3.41 — 2026-09-30

- **`last30days` is removed from the core.** (test: T0) Reading the code behind eight open CodeQL alerts (2026-09-30) found that it read the X and Truth Social session cookies from Firefox and Safari on every run unless `FROM_BROWSER=off`, and that `setup --github` posted the full `gh` CLI token to a third party (details: #172, which this supersedes). It is vendored third-party code, measured unused on the operator's machines (no invocations in the Windows brain's transcripts), and its setup installs `yt-dlp` via Homebrew unasked. Proposed by the operator's Windows brain and the operator; the collaborators were asked in the shared memory before merge. Whoever needs it installs it from its upstream repo. Removed: `skills/last30days/`, its line in `NOTICE`, its row in `skills/REGISTRY.md` (regenerated, 25 skills). Instances that still have `FROM_BROWSER=off` set can drop it after updating.

- **Session start reads what the shared memory addressed to this instance.** (test: T2) Measured on a macOS brain on 2026-09-25: the start said `17 new commits` plus a tally per topic, and stopped there. Four entries from a collaborator's instance were addressed to this side, one of them a verbatim message to its operator. None reached the operator until the operator said "yes, read it". The operator's order: the main information belongs in the startup message itself, or it sinks. New `scripts/shared-memory-inbox.py`, called by `helpers/shared-memory-check.sh` over the same commit range as the count. It has two sources. The first is the `<topic>/LOG.md` headings added in that range (`## <date> · <von> — AN <addressees>: <title>`); some messages exist only there. The second is added or changed fact files with their frontmatter `von`/`audience`/`description`. A file whose path the new LOG text already names is not printed twice. Each line carries date, topic, sender and the author's own heading or description, cut at a sentence boundary. Nothing is summarised. The filter is instance data: `SHARED_MEMORY_SELF` (e.g. `alex-macos,alex` in the instance's `settings.json` `env`). Own entries are dropped. Entries addressed to someone else are dropped. Entries for everyone (`alle`, `all`, ...) or with no addressee are kept. Unset, nothing is filtered and the header says so. stdout is pinned to UTF-8 (OS-9). Fixture in `test-shared-memory-check.sh`: a heading and a file addressed to the instance and a heading to everyone are printed. A heading and a file for a third party and the instance's own heading are not. Unset, the third-party heading appears (the filter, not the parser, dropped it). A current cursor keeps the inbox silent. The live watch (`scripts/shared-memory-watch.sh`) prints the same lines under each `FOUND:`: a LOG-only commit has no `von:` field and was reported as "unknown party" while its heading named sender and title (measured 2026-09-25; fixture in `shared-memory-watch-test.sh`, red against the previous watcher). Against yesterday's real range it prints 11 lines, and each one is addressed to this instance or to everyone. The heading pattern covers the four heading shapes that are live in the repo, including `## <date> <von> - <title>` (ASCII hyphen, half of the September headings) and headings with a time note but no title: 226 of 227 dated headings match. A pattern for the `·`/`—` shape alone missed 100 of them. The Windows counter-check (workstation, 2026-09-30) found that the check only FETCHES, so the inbox read fact files from a working tree that did not have them yet: a new file dropped out silently, a changed one was read in its old form (9 lines instead of 10 on the reference range). The inbox now reads the blob at the fetched head. The freshness line had the same defect — `shared-memory-index.py --since` read the working tree — and gets `--ref <commit>`, which reads every entry in one `git cat-file --batch` (0.22 s on the real repo; output identical to the disk read on a pulled checkout). Fixture: a second clone pushes a new and a changed file, the checked clone stays unpulled; new file printed, changed file read in its new form, freshness counts it (4 instead of 5 before the fix).

- **`setup-shell-start.sh` no longer ends silently when a PowerShell query fails.** (test: T1) Measured 2026-09-30 on a third Windows machine: started from a PowerShell 7 parent, `powershell.exe` inherits pwsh's `PSModulePath`, cannot load `Microsoft.PowerShell.Security`, and `Get-ExecutionPolicy` fails. Under `set -euo pipefail` that one query ended the script: the Windows PowerShell profile was written, the pwsh profile was not, the measurement line was missing, and nothing said so. Every PowerShell call now runs with `env -u PSModulePath` (each shell rebuilds its own default), every query is `|| true`, and a policy that cannot be read is a `WARN` line. New `test-setup-shell-start.sh` (fake `uname`/`powershell.exe`/`pwsh`, runs on every OS): red against the previous script with exactly the measured pattern (Windows PowerShell profile written, pwsh not, no measurement line). Real run on the reporting machine with the inherited `PSModulePath`: exit 0, all three profiles found, `lands in` the brain.

- **The shared memory's LOGs rotate by month, and new LOG entries stay short.** (test: T2) Measured 2026-09-25: `ops/LOG.md` held 146,019 bytes thirteen days after it was started. That is 98 entries of ~1.5 KB each, and only 34 of them point to a fact file. `grandma3/LOG.md` is at 54,760 bytes. The lint had flagged "LOG over rotation size" with a fix text, but nothing ran the lint and nothing did the fix. A file that size no longer fits one read, so a reader sees part of the protocol without noticing. Operator decision the same day: a LOG may rotate, with clean pointers both ways and nothing lost, and entries are kept as short as possible so that a month fits the limit. New `scripts/shared-memory-log-rotate.py`. `--write` moves every entry of a closed month verbatim, in order, to `<topic>/archive/LOG-<YYYY-MM>.md`, which points back. The LOG keeps its preamble plus one `Earlier months:` line that links every archive. `archive/` was already outside the fact-file set of the lint and the index generator. The move is computed in memory and written only if every original entry appears exactly once afterwards. Entries are cut only at dated headings, so an undated sub-heading travels with its entry. `--check` runs from `helpers/session-bootup.sh`, is read-only and stays silent unless something is due. It names a due rotation, and it names own entries (`SHARED_MEMORY_SELF`) dated 2026-09-26 or later that exceed 300 bytes. The budget is measured: at the September rate `ops` gets ~225 entries a month, and 60,000 / 225 ≈ 265 bytes each. So an entry is a heading plus one line, and the substance goes into a fact file. The lint's fix text now names the script. OS-2 baseline gains the new pinned write site. Fixture `scripts/shared-memory-log-rotate-test.py` covers:
  - due and not due;
  - every block exactly once, byte for byte;
  - the sub-heading travels with its entry;
  - preamble and both pointers are kept;
  - LF only;
  - a rerun moves nothing;
  - the next month appends and still has one pointer line;
  - an own long entry is named, while a foreign one and one before the cap date are not.

  Dry run against a copy of the real repo with `--today 2026-10-02`: 227 entries before, 227 after; `ops/LOG.md` goes from 146 KB to 275 bytes.

- **`onboarding-verify.sh` no longer moves the shared-memory cursor.** (test: T1) Reported by a collaborator's third machine on 2026-09-30: check 5 runs the brain's bootup, and the bootup advances `config/shared-memory-state.json` — so entries no session had ever shown were marked as seen, the same class as a shared cursor swallowing events between parallel sessions. The script's own header promised "read-only apart from the report file". Check 5 now gives the bootup a throwaway copy of the cursor (`SHARED_MEMORY_STATE`), so its output is unchanged and the real cursor stays put. Searched: the bootup writes no other seen-cursor. Fixture +2 in `onboarding-verify-test.sh` (cursor untouched — red against the previous script; the bootup still ran).

- **A `claude` CLI subcommand no longer logs a session.** (test: T2) Reported by a collaborator's third machine (Windows) and re-measured on macOS on 2026-09-30: `claude mcp list` in a brain directory fires `SessionEnd` with `reason: "other"` and a `transcript_path` whose file was never written; `claude plugin list --json` fires nothing. `session-closing.sh` then wrote a `hook-end` line and a fresh `HANDOFF.md`, so the session log counted a session that never existed and the tree was dirty. The hook now exits silently when the input names a transcript that does not exist; an input without `transcript_path` behaves as before. An escaped JSON backslash is read as `/`, which Git Bash resolves too. Fixture +5 in `test-session-closing.sh`: subcommand writes nothing and leaves the tree clean (red against the previous hook), an existing transcript is still logged, a backslash-escaped path still resolves. The second `SessionEnd` hook, `memory-sync.cjs export`, exports real memory changes on the same trigger — that content exists, so it is not the same defect.

- **onboarding-verify check 8 no longer scans binary files.** (test: T1) Measured 2026-09-30 on a third Windows machine of one brain: a tracked vendor manual (PDF) carries its authors' home paths in its metadata, so check 8 was red on every machine of that brain, and no `own_home_names` entry could fix it. The scan now runs `git grep -I` over the tracked files: git's binary test (a NUL byte) is the same on every OS, so the PDF is skipped and a text file with a stray non-UTF-8 byte is still scanned. Plain `grep -I` was not portable: BSD grep on macOS also skipped the Latin-1 text file (CI caught it). The pattern is written `[/](Users|home)/`, because Git Bash rewrites an argument that starts with `/` into a Windows path before the native `git.exe` sees it. The non-git fallback (a brain that is not a repo yet) keeps plain `grep -r`. Measured on the reporting brain: the only file that drops out of the hit list is the PDF. New fixture 7 in `test-onboarding-leak-check.sh`: a tracked binary with a foreign path stays silent (red against the previous script), a Latin-1 text file with a foreign path stays loud and named.

## 1.3.40 — 2026-09-24

- **brain-scan: a CVE counts as P0/P1 only if the advisory is found and the installed version is affected.** The CVE rule has existed since 2026-08-13. The brain-scan of 2026-09-24 on a Windows brain broke the same class anyway. Two numbers that had been refuted on 2026-08-13 came back as P1. A third came back as P0 with "CVSS 9.0" and the label "unconfirmed". Its advisory was in GitHub's global database all along (`gh api "/advisories?cve_id=..."`): rated MEDIUM, affecting "Context7 through 2.1.2", while 4.1.1 was pinned. The rule named only the affected repo's own advisories, so the agent never looked where the record was. It also compared no version, and it let an unconfirmed number keep P0. The rule now looks in the global advisory database first. A confirmed CVE takes its severity from the advisory and is P0/P1 only if the installed version is inside the affected range; otherwise it is INFO with both versions named. An unconfirmed number is capped at P2. This is still prompt text: a workflow script cannot read the finding files to enforce it. `test-brain-scan-files.sh` is green.

- **`ecosystem-sync.py --write` drops a plugin that is no longer installed.** Measured on 2026-09-24 on a Windows brain in the beta: `brain-core@arche-goah` is deliberately uninstalled, and `brain-core-next` replaces it. The lockfile kept the old entry, and every run reported `plugin brain-core@arche-goah: pinned but not installed`. The script says to "record it with --write once the state is intended", but `--write` updated only the installed plugins and never removed one. So the drift could not be cleared, and `handover-gate.sh` failed on every run. A gate that is always red stops meaning anything. A plain run still reports the missing plugin, and `--write` now removes it. Keys that start with `_` are instance annotations and are kept. New fixture in `portability-smoke.sh`: the missing plugin is reported; after `--write` the plugin is gone, the lockfile reads in sync and the annotation is still there. Against the previous script the second check fails.

- **`cached-verdict.sh` no longer files a run that was cut off as its verdict, and `brain-check --brief` names what is red.** Measured 2026-09-24 on a macOS brain: the session start showed `SELF-TEST: FAILURE` with a single green fixture line above it and no failing check anywhere, while a fresh uncached run was 43/43 green. The signal traps (`trap release_lock EXIT INT TERM`, in the parent and in the background child) only cleaned up, and bash continues after a trap handler returns: TERM landed on the fixture run and on the script alike, the handler released the lock, and execution went on into the store — the one line printed so far and rc 143 were written under the CURRENT key and replayed as "unchanged" until the key changed. Reproduced with a two-line payload killed by TERM after the first line: meta `new|…|143`, output one line. Signals now only set a flag; the lock goes on EXIT; an interrupted run stores nothing, keeps the previous verdict and says so. What delivers the TERM (hook timeout, session end) is not measured — the fix does not depend on it. Second, the brief form printed only lines matching `!!` or `FAILURE`, so it could say "red" without saying what: it now also carries each failing check's indented detail lines and the `(reused: …)` line that says the verdict is a stored one, and a red result that names no failing check says so explicitly as a defect of the self-test. Fixture property 9 in `cached-verdict-test.sh`: a run killed mid-way in the foreground and in the background keeps the previous meta and output, announces that nothing was stored and releases the lock; a run that FINISHES with a failure is still stored (negative control). Red against the previous script: 4 of 7 checks fail.

- **Session start names plugin skills the auto-fire table omits.** Measured on the Windows instance: the brain-scans of 2026-08-04, 2026-08-13 and 2026-09-24 each found the hand-kept pattern -> skill table (`.claude/rules/intelligence-instance.md`) short after plugin updates — the last one missed `shared-memory-tidy`, `shared-memory-watch` and `pr-live-verify`. Three recurrences after a fix is the build threshold, and a scan every few weeks is too slow a carrier. New `scripts/auto-fire-coverage.py` lists every skill of an installed AND enabled plugin (same enabledPlugins rule as the bootup's output-style check) whose `<plugin>:<skill>` id does not occur in the table; DEPRECATED rename pointers are skipped, and a brain can opt a skill (or a whole plugin) out with `<!-- auto-fire-ignore: id ... -->` in the table file. It never edits — which pattern fires a skill is the author's judgement. `helpers/session-bootup.sh` voices the gaps as one `!!` line per session, next to the hook-coverage line. Fixture 13a in `portability-smoke.sh` (all three CI runners): an uncovered enabled skill is named and exits 1, a DEPRECATED pointer, an ignored id and a skill of a disabled plugin are not, the bootup voices it, and a covered table is silent. Measured on the reporting brain: against the pre-fix table the script names exactly the three skills the scan found; against the fixed table it is silent. Windows run of the full smoke: all checks passed.

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

- **The mechanism guard judges what a command EXECUTES, not what it merely writes.** Patterns were matched against the raw command including heredoc bodies, so a commit message that only DESCRIBES a banned mechanism as prose tripped the guard (found live while committing a register that discussed exactly such a finding). Reported by a collaborator. Stripping every heredoc, however, would have turned the guard off through one syntax: measured against the fixture rule, 7 of 8 shapes whose body is executed went from seen to blind (`bash <<EOF`, `sh -s`, `ssh`, `python3 -`, `node`, `eval "$(cat …)"`, `source /dev/stdin`). So the CONSUMER decides and the default is fail-closed — cat/tee bodies are stripped, eval/source never, an unknown consumer keeps its body in the scanned text. Fixtures in `scripts/test-guards.sh` cover both directions; with the blanket strip restored, exactly the three executed fixtures go red.
- **`session-close` no longer states a commit/push policy of its own.** Step 4 had cached one instance's dated policy as if it were the core's, and a cached policy goes stale silently — the drift the Rule-Conflict Protocol's back-propagation step exists to catch. Reported by a collaborator, whose first fix replaced it with their own instance's (stricter) rule; three brains consume this core and their rules genuinely differ, so the skill now names none: it reads the instance's rule and applies it, and asks when there is none. The stricter default for an unwritten rule, the "close the session is not by itself a go-ahead" clarification and uncommitted-with-a-reason are kept.
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
  (PR #52, contributed by alex-workstation from its v1.3.12 catch-up — it measured
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
