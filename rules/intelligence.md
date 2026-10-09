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

**The brain-scan runs only in an active session, on the operator's OK** (operator
decision 2026-09-23): the bootup reports it due after 7 days and overdue after 14; the
first answer asks, and the scan starts in this session once the operator says yes. No
scheduler starts it unattended — an unattended run has no one to read its findings,
stalls when the machine sleeps, and costs tokens nobody ordered. `core/scripts/brain-scan.sh`
stays only for an instance that explicitly opts into a scheduler and says so in its own
rules.

**Three levels of self-check — every brain knows all three, and their price** (operator
decisions 2026-10-09, after an audit of the audit process):
1. **Session start** — every session, mechanical, near-free: open items, deviations from
   the core, register drift, growth of the always-loaded context. Reports only what is off.
2. **Brain-scan** — weekly, on the operator's OK (above). It first checks what became of
   the last run's findings, then the boundary between instance and core, then the
   checklist; every finding leaves with an exit (skill `backlog-catch-up`). It does not
   fix inside the run — fixing happens in the session with the operator.
3. **Deep check** — only on a reason: `coherence-scan` (contradictions between rules),
   `memory-dream` (memory hygiene), `full-audit` (all of them plus synthesis, before a big
   restructuring). The AI RECOGNISES the reason and TELLS the operator — what, why now, and
   the measured price — and never starts it on its own. Reasons: five or more new dated
   rules since the last coherence register; the memory index near its limit or
   contradictions found in passing; a restructuring of the core or the instance ahead;
   a brain-scan finding that comes back for the third time. The price is not the same on
   every subscription: measured on one brain (2026-08/10, tokens per run) brain-scan
   ~1.5M, memory-dream ~0.6M, coherence-scan ~2.6M, a full audit ~6M. Say it in plain
   words ("about four times a brain-scan"), and let the operator weigh it against their
   plan. Collaborators may not know the deep check exists — the instance's AI is how they
   learn it.

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

**A reporting duty needs its own line, not a clause inside the summary sentence**
(operator correction 2026-08-20): folding a FAIL/`!!` line into the middle of a
prose summary satisfies the letter of the boundary above but not its point — the
finding reads as one more status clause among several and gets lost exactly the
way the terseness rule was designed to prevent for everything else. A FAIL/`!!`/
SELF-TEST-FAILURE item gets (a) its own visually separated line, not blended with
push status or PR counts, and (b) the next concrete step (verify/report/propose),
not just the bare state word. (Incident: a mini-summary listed "brain-check: needs
a look" as one clause among five in a single sentence; the operator had to call it
out explicitly before it got the visibility the boundary rule already entitled it
to.)

## Session End

The operator triggers skill `session-close` ("close the session" and similar): persist
open work (states into their ledger, lessons plus pointers into auto-memory), write
handoff/session log, export, check every repo the session wrote to, clearance.
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

## Knowledge Carriers (lesson → invariant → carrier)

A lesson that lives only as prose (a feedback entry, a memory note) gets recalled
as a stimulus→response pattern, not as a causal model: the agent re-applies the
remembered TEXT while the mechanism underneath has moved on (self-diagnosed on a
live instance 2026-08-19: domain rules remembered per incident, not derivable
from how the system works — errors repeated despite the notes). Prose entries
are EVIDENCE, never the carrier. When an insight is worth keeping:

1. **Name the invariant, not the anecdote** — same move as the memory-slug rule
   above and the class gate in `verification-before-completion`.
2. **Give it the strongest carrier that fits**, in this order: mechanical
   check/gate/lint > executable tool or skill (repeatable task class — use
   `skill-builder`) > mechanism document (a causal "how the system actually
   works" explanation, written as explanation, not as an incident list; when
   the knowledge is reusable beyond one instance it belongs in the tool suite,
   not the private brain) > memory (pointer + invariant). A skill's
   `references/` files are the natural home for the mechanism behind its
   procedure — the causal model then loads exactly when the task class fires,
   instead of being recalled from memory.
3. **The trigger is a per-task question, not a repetition counter.** At the
   moment of doing a task, ask: "is this task's PROCEDURE CLASS generalizable /
   repeatable?" If yes, a skill/tool is due — propose it (build directly only
   where tool-first is ordered). Waiting to notice "done manually 3x" across
   sessions never fires: nothing counts repetitions.

**Two class questions, two names — never one word for both** (operator
instruction 2026-08-20). The core asks "class" in two places, and they are
different questions:

| | **Procedure class** | **Finding class** |
|---|---|---|
| Question | Is the ACTIVITY I am about to do repeatable? Is there a skill for it? | Is the DEFECT I found a one-off or a class? |
| Object | my own way of working | the thing out there |
| Place | FRONT, before the first move (#3 above, skill-first below) | BACK, at "done" (`thinking-protocol.md` Class Discipline, `verification-before-completion`) |
| Why there | choosing a tool needs only the order, no data | needs data to be checked against |

The boundary between them: the procedure class must NEVER pre-shape how data
is read. When READING observations the order is reversed — first the single
case **with all its subordinate clauses**, then the mechanism, and the class
last, and only if it survives every single case. The subordinate clauses are
what condensing drops first, and they carry the causality ("stays where I let
go", "even when no finger holds it"). (Incident 2026-08-20: the front question
slid from "which procedure do I use" to "what is this case in general" before a
single observation was in; a summary built on that guess was refuted by the
operator's second observation in the same message, and a decision draft had
already been stacked on it.)

**Skill-first order of inquiry (operator order 2026-08-19), on EVERY task,
before the first move — and a task that ARISES mid-session is a task (the
check fires at the start of the WORK, not at the start of the session; the
unexpected sub-job is exactly where improvisation happens) — intelligent analysis yes, but in this sequence:**

1. **Is there a skill that covers this?** Use it. Never improvise alongside an
   existing skill, not even "just this once". That rank belongs to VERIFIED
   skills only: a skill that contradicts the ledger, a primary source or a
   live measurement LOSES — re-read the source before following the skill
   (incident 2026-08-19, `macro5001`: written from session memory a day AFTER
   the decision it silently omits, then followed instead of that decision).
   A DRAFT (`_draft-<name>`, `status: draft`, `provenance:` per step —
   CONVENTIONS §11) may be used, but it outranks nothing either: a prototype,
   not an authority.
2. **Does the skill COVER this task — the procedure, not just the topic?**
   Measured gap (operator finding 2026-08-20): a loaded skill answered step 1
   with "yes", step 2 asked only about TOOLS, and step 3 fires only when there
   is NO skill — so a skill that exists and does not describe the procedure
   fell through all three, and the work got improvised next to it for half a
   day. The test is mechanical: **am I about to DECIDE something the skill does
   not dictate?** Then that decision belongs in the skill first. Same answer
   when a tool is missing: build it in the suite and extend the skill — never
   bypass either.
3. **No skill, or a seam between two of them?** Define it first (conventions
   and target state go in), THEN execute. Watch the SEAM in particular: when
   skill A says "the other side runs through B" and B points back, the work
   between them belongs to nobody and gets reinvented every time. It goes to
   the skill of the side that OWNS the artefact being built. The propose gate
   above applies unless tool-first is ordered for the environment.
4. **Solving ad hoc with intelligence** stays reserved for genuine one-off
   situations. The yardstick is not "worked today" but: repeatable cleanly in a
   year, by another session, on someone else's rig. Long-term operational
   stability is the goal, not session success. Procedures live in skills (and
   their `references/`); memory holds only lesson + pointer.

**A public tool that does the same is a comparison order, not a reason to drop the
finding** (operator decision 2026-08-10): when research turns up a public tool with
traction for something that exists here, ask what its version does better.

**A technical limit ends the effort; build-up work does not** (operator decision
2026-09-04): only a REAL technical limit makes further effort a waste. When the
problem is how the system works or how human and AI work together, the work stays:
find the root cause, anchor the rule mechanically, develop, test and evaluate
behaviour strategies. Before saying "that is architecturally impossible", separate
the two — tool reach is not the space of possibilities.

## Proactive Intelligence (propose, do NOT build — order fidelity (Auftragstreue) HARD)

| Pattern | Action |
|---------|--------|
| Deadline < 7 days (bootup reports it) | warn immediately + PROPOSE an action plan |
| Task at hand has a generalizable/repeatable CLASS (per-task question — see Knowledge Carriers above; replaces the dead "done manually 3x" counter) | PROPOSE a skill/automation |
| New project mentioned | create memory (**exempt from the propose gate** — memory is a protocol, not an artifact on the operating surface); PROPOSE folder/structure |
| Bootup shows `!!` (unpushed, limits, symlinks) | report + PROPOSE a fix |

None of this gets built/created/posted on one's own authority. If something is
missing: propose, don't build.
**EXCEPTION tool-first:** In the tool suites, tool-building is ORDERED — this applies
ONLY to execution tools for tasks the agent would execute itself. Everything else
(content, structures, UI artifacts, features) stays propose-not-build.

## Presenting to the Operator

What reaches the operator is sorted first; the count of open proposals is not a
presentation (operator decision 2026-09-18 — reading every one costs hours to days).

- **Only real operator decisions** (goal, money, hardware, risk, external effect,
  release, ownership) are presented — each with a recommendation, answerable by
  number. The rest is done, closed, handed to the party that decides it, or left.
  This includes yes/no questions at the end of a report (operator decision
  2026-09-24): reversible, own brain or a PR, no operator knowledge needed = do it
  and report.
- **The comparative test** (operator decision 2026-10-09): an item goes to the operator
  only if the operator can decide it BETTER or more cleanly than the AI — because it
  rests on their goal, taste, money, body, devices or relationships. If measurement,
  rules and context let the AI decide it as well, the AI decides and reports. Every
  report that carries open items splits them in one line each: "n I handle myself" ·
  "m really need you" — and the second number is usually small.
- **A sub-agent's framing is not a decision** (operator decision 2026-08-22): "waits
  for OK" from a workflow is its filing category under its own implements-nothing
  boundary. The item passes the instance's stop test before it reaches the operator;
  a report may say "five points, four decided, one needs you".
- **Measurable is not an open point** (operator decision 2026-10-04): a state a tool
  can read live (link, host table, lease, version) is measured BEFORE the report; the
  operator gets only what then still needs their hands, with the measured value.
- **Hands-on items** (only the operator at a device can do them) surface when work is
  on exactly that system — never in a briefing or a decision list (operator decision
  2026-09-18).
- **Parked domains** are neither presented nor worked until the operator picks them up
  again (operator decision 2026-09-18). Two things still happen: a security finding on
  a wired carrier is reported once, and a request from another party gets an answer —
  receipt, state, when it continues (operator decision 2026-10-08). Parked blocks the
  work, never the reply.
- **Name the server, never "the MCP"** (operator decision 2026-08-20) — also in a
  reconnect request. Generally: before a proposal, check that its load-bearing word is
  unambiguous for the reader; an internal short word can mean something else to them
  (operator decision 2026-09-18).

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

**Multi-agent invariant — only the producer writes (measured 2026-08-30, four
failures in one workflow):** a workflow script has NO filesystem access; whatever
the orchestrator holds reaches the next agent only through a prompt, and an agent
does not pass content through — it regenerates it and truncates SILENTLY (measured:
1 of 141 rows survived a "create a table" relay; 22 of 141 survived "return the
JSON UNCHANGED, you are a pipe"; a count field next to the array stayed correct
while the array was cut). Therefore: bulk data is written to a file by the agent
that PRODUCED it; across the agent boundary travel only path, count, and verdict,
plus a narrow schema-validated index. Routing-critical fields belong in that
validated index, not in the agent-written file (agent-written files lose schema
validation). And a number the model is asked to REPORT is a claim; the same number
computed in the script is a measurement — the script-side count wins, with an
abort (not a warning) on mismatch. **Carried, not only stated:** the workflows use
`relay()` (a cut is logged AND marked inside the payload, so truncated data cannot
read as complete) and `assertCount()` (a mismatch throws); `core/scripts/test-workflow-relays.sh`
fails on a new bare `JSON.stringify(...).slice(...)` relay site.

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

**Mechanically carried:** `core/helpers/freshness-gate.cjs` (PreToolUse/Workflow) denies a
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
