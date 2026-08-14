# Intelligence System (Core Mechanics)

> CORE VERSION: session mechanics + auto-organization. The auto-fire table
> (pattern → skill) is instance knowledge — it lives in the instance rule file of
> the respective brain (`.claude/rules/intelligence-instance.md`) and is the ONLY
> source there (no second copy maintained in CLAUDE.md).

## Session Start (mechanical + Claude's part)

The SessionStart hook (`core/helpers/session-bootup.sh`) delivers on every start:
git status incl. unpushed warning, memory limits, settings validity, symlink check,
brain-scan age, open ordered assignments, deadlines pointer. **Claude's part:**
READ the output, react to `!!` warnings (report/propose), connect to
`git log --oneline -10`. **The first answer of every session begins with a
1-sentence mini-summary** (state of affairs + what is potentially coming up — from
the bootup block, open assignments, memory).

**The summary is written for the operator, not relayed from the machine** (operator
correction 2026-08-13): hook output is Claude's input, never chat vocabulary — no
`!!` markers, return codes, internal tags or hook phrasing in the summary. Translate
every finding into plain human language, and surface a pending decision as a direct
question ("update available — shall I run it?"), never as a generic "what's next?".
This applies to ALL chat output that renders machine artifacts, not just the
session start.

**Relevance beats completeness** (operator correction 2026-08-13, second pass —
translating everything is not the point either): a briefing names ONLY what the
operator must know or decide right now, in one or two plain sentences. Everything
else is checked silently and surfaced only when it needs action or a decision — a
check that came back clean is silence, not a line. Nothing gets verbalized out of
obligation. Boundary: reporting DUTIES stay (FAIL lines, reportable events,
evidence chains in reports) — the filter applies to briefing prose, not to
mandatory artifacts.

## Session End

The operator triggers skill `session-close` ("close the session" and similar): persist
open work into auto-memory, write handoff/session log, export, clearance.
The SessionEnd hook does the same mechanically as a best-effort fallback (does not
fire on a hard kill). NO `memory/session_*.md` files — memory lives in auto-memory
(harness).

## Auto-Organization (ALWAYS)

1. Every new file goes into the right folder immediately (instance folder table).
2. Every new insight → auto-memory (file + MEMORY.md index). **If an entry asserts a
   state of the core** (file, rule, helper), it names the submodule state it was
   measured against (tag or commit) — otherwise the note goes silently stale at the
   next core update (measured 2026-08-04: one entry flipped one minute after being
   written).
   **Slug and `name` carry the LESSON, not the momentary state** (operator decision
   2026-08-10, full-audit E2): `gate-checks-pruefen-den-baum`, not `main-ist-rot` —
   a state slug goes stale with the next fix and carries the solved symptom onward
   as its name; on 2026-08-04 two files had to be renamed because of this.
   **Before every memory-based decision read the FILE, not the injected context
   block** (full-audit M12): the block can be older than the disk —
   measured 2026-08-04: block 7 entries and "OPEN", file 9 entries and "RESOLVED".
   **This applies to ALL injected text, not just memory blocks** (measured 2026-08-13):
   injected content is a render copy, and rendering can CORRUPT it, not just lag behind —
   a skill's injected code snippet showed `PR ~ /^PR /` where disk (repo, tag, plugin
   cache) says `$0 ~ /^PR /` everywhere; a defect report or PR derived from injected
   text alone would have "fixed" a bug that does not exist. Before acting on a snippet
   or deriving a finding from injected skill/rule text: read the file on disk.
3. Every code change → skill `verification-before-completion`.
4. Delete junk (temp files, .DS_Store, __pycache__) immediately.

## Proactive Intelligence (propose, do NOT build — order fidelity (Auftragstreue) HARD)

| Pattern | Action |
|---------|--------|
| Deadline < 7 days (bootup reports it) | warn immediately + PROPOSE an action plan |
| Same task done manually 3x | PROPOSE a skill/automation |
| New project mentioned | create memory (**exempt from the propose gate** — memory is a protocol, not an artifact on the operating surface); PROPOSE folder/structure |
| Bootup shows `!!` (unpushed, limits, symlinks) | report + PROPOSE a fix |

None of this gets built/created/posted on one's own authority. If something is
missing: propose, don't build.
**EXCEPTION tool-first:** In the tool suites, tool-building is ORDERED — this applies
ONLY to execution tools for tasks the agent would execute itself. Everything else
(content, structures, UI artifacts, features) stays propose-not-build.

## Model Routing

**Before EVERY agent spawn (Agent tool as well as workflow stage), the model class is
briefly evaluated: does THIS task need the session model, or is the small one
enough?** (Operator decision 2026-08-13 — inheriting is the mechanism, not a
decision.) Heuristic: read/search/collect/copy (research, gather, inventory, online
search) → small model; judge/verify/synthesize/write → session model,
hard verify stages → higher effort. Reference measurement brain-scan (core PR #30,
run 2026-08-10): 9 of 11 agents small, ~778k of 1.02M tokens, all results valid.
Sub-/workflow agents technically INHERIT the session model — the inheritance counts
as chosen, not as a default without a look. Do NOT hardcode
model version names in docs (they go stale immediately). Multi-agent costs ~15x
chat tokens — only for broad independent work, orchestration as separate
phase workflows (research → audit → verify → synthesis), persist each phase's
result, next phase via `args`.

## Repeat Runs (CANONICAL place — skills point here)

An audit/analysis workflow costs six to seven figures in tokens. Before one runs
again, this sequence applies — **each step costs next to nothing and usually settles
the question already:**

1. **Read the artifacts of the last run, do not regenerate them.** A workflow run
   leaves behind, in the project directory of the launching session:
   - `<project>/<session-id>/workflows/wf_<id>.json` — `result`, `logs`, `agentCount`,
     `totalTokens`, `status`
   - `<project>/<session-id>/subagents/workflows/wf_<id>/journal.jsonl` — the **return
     of every agent**, for verify stages the individual `verdicts`
   What is written there is not computed a second time.
2. **Check freshness.** If a report of the type exists that is younger than 14 days,
   and no major rule/structure rebuild has happened since: do NOT re-run, use the
   existing report and declare that in the result as "reused from <date>".
3. **Only then re-run** — and only if it can be named which question the artifacts
   do not answer.

**Mechanically carried:** `helpers/freshness-gate.cjs` (PreToolUse/Workflow) denies a
relaunch whose last completed run is younger than the threshold and cost real tokens,
and demands exactly this sequence — read artifacts, declare reuse, or relaunch with
`// FRESHNESS-OK: <the unanswered question>`. Resume (`resumeFromRunId`) passes freely.
Thresholds are instance data: `.claude/rules/freshness-gate.json` (a scheduled cadence
sets its per-workflow threshold below the cadence instead of carrying a marker).

**A report that recommends its own repeat run is not an assignment.** It is checked
against the run record: if an agent's prose tally deviates from the machine result,
`result`/`logs` count, not the prose (measured 2026-08-04: a register reported
"24 raw → 18 consolidated" and derived a gap from it, while the record said
108 → 19 → 12; the supposedly missing findings had been discarded in verify).
