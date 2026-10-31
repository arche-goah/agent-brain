# Intelligence System (Core Mechanics)

> CORE VERSION: session mechanics + auto-organization. The auto-fire table (pattern → skill) is
> instance knowledge — `.claude/rules/intelligence-instance.md`, the ONLY source (no copy in CLAUDE.md).

## Session Start (mechanical + Claude's part)

The SessionStart hook (`core/helpers/session-bootup.sh`) delivers git status, memory limits, settings
validity, symlinks, brain-scan age, open assignments, deadlines. **Claude's part:** READ it, react to
`!!` warnings (report/propose), connect to `git log --oneline -10`.

**The first reply has ONE target form — fill the slots, in this order, and nothing else is required
of it** (operator order 2026-10-12); the paragraphs below define each slot:

1. **Mini-summary** — one sentence, state + what is coming up, in plain words.
2. **The operator's own request** — an order or question in the first message is answered or
   started here, before any housekeeping.
3. **Reporting duties, one line each** — FAIL / self-test failure / acute warning, each on its own
   line with the next concrete step.
4. **Open points for this instance** — "n I can handle — shall I?" (ONE question, only here — the one
   closing question `stoppen-gate.cjs` lets stand) and "m need you"; details below.
5. **Due decisions** — a due brain-scan or deep check, a deferred point said once, a pending update:
   each a direct question with its price, through the question tool ("Presenting to the Operator").

Whatever came back clean stays silent; empty slots are left out. A later reply repeats none of slots
3-5 unless the state changed or an unanswered question blocks the next step (then asked again,
verbatim).

**The brain-scan runs only in an active session, on the operator's OK** (operator decision
2026-09-23): due after 14 days, overdue after 28; the first answer asks. Floor 7 days, carried by
`freshness-gate.cjs`; earlier only on the operator's word as `FRESHNESS-OK` (operator decision
2026-10-18). No scheduler starts it unless the instance opts in (`core/scripts/brain-scan.sh`).

**Three levels of self-check — every brain knows all three, and their price** (operator decisions
2026-10-09): (1) **session start** — near-free, reports only what is off; (2) **brain-scan** — every
two weeks on the operator's OK, every finding leaves with an exit (`backlog-catch-up`), no fixing
inside the run; (3) **deep check** — only on a reason: `coherence-scan`, `memory-dream`,
`full-audit`. The AI RECOGNISES the reason and TELLS the operator what, why now and the measured price,
and never starts it on its own (AI side handed over: those AIs decide, `working-rules.md` Working
Across Parties #6). Reasons: five or more new dated rules since the last coherence register; memory
index near its limit or contradictions found; a restructuring ahead; a brain-scan finding back for
the third time. Price per run on one brain (2026-08/10): brain-scan ~1.5M tokens, memory-dream ~0.6M,
coherence-scan ~2.6M, full audit ~6M — said in plain words ("about four times a brain-scan").

**The summary is written for the operator, not relayed from the machine** (operator correction
2026-08-13): hook output is input, never chat vocabulary — no `!!` markers, return codes, tags or hook
phrasing in ANY chat output that renders machine artifacts; a pending decision is a direct question
("update available — shall I run it?"), never "what's next?". **Commands and exact text for the
operator take the instance's form** (operator decision 2026-10-19), set in ONE place of the instance's
operator rules; code that IS the artefact is untouched.

**Kind and matter in plain words, never a priority or ledger code** (operator corrections 2026-10-08,
2026-10-09): every note from an AI to a human says WHAT it is (task, proposal, serious problem, acute
need for action, note) and what it is about. Priority grades, ledger ids and every other internal
scheme (circle letters, test classes, gate names, finding classes) are lookup handles — at most a
trailing reference in parentheses. Test: would the reader understand the sentence with the code deleted?

**Relevance beats completeness** (operator correction 2026-08-13): a briefing names ONLY what the
operator must know or decide now; a clean check is silence. Reporting DUTIES stay — and **a reporting
duty needs its own line, not a clause inside the summary sentence** (operator correction 2026-08-20),
with the next concrete step.

**Open points that concern this instance are a reporting duty, never briefing prose** (operator
correction 2026-10-07): every "open for us" item reaches the first reply, split by WHO acts. Own items:
the count and ONE question whether to go ahead, asked ONCE per session at start or resume (operator
correction 2026-10-10) — a class with a standing approval (`.claude/rules/open-items-standing.json`,
the operator's quoted words) is handled and reported instead; after a compaction, after the go, and
mid-session: handle and report. Items for the operator: the count, up to three one-line bullets, more
offered. "nothing open" / "could not read" when that is the state, never "nothing" for an unreadable
source; a repeat is said LOUDER ("reported in N sessions since <date>, nothing done yet"). Carried by
`core/scripts/open-items.py` and `core/helpers/open-items-gate.cjs`.

History: core/docs/rule-history.md, "Session Start (mechanical + Claude's part)".

## Session End

The operator triggers skill `session-close` ("close the session" and similar); the SessionEnd hook is
a best-effort fallback. NO `memory/session_*.md` files — memory lives in auto-memory (harness).

## Auto-Organization (ALWAYS)

1. Every new file goes into the right folder immediately (instance folder table).
2. Every new FACT → auto-memory (file + MEMORY.md index); a new LESSON goes to its strongest carrier
   (Knowledge Carriers below), memory keeps at most the pointer. An entry asserting a state of the
   core names the submodule state (tag or commit) it was measured against. **Slug and `name` carry
   the LESSON, not the momentary state** (operator decision 2026-08-10). **Before every memory-based
   decision read the FILE, not the injected block** — this holds for ALL injected text (skill/rule
   snippets too): it is a render copy that can lag or be corrupted.
3. Every code change → skill `verification-before-completion`.
4. Delete junk (temp files, .DS_Store, __pycache__) immediately.

History: core/docs/rule-history.md, "Auto-Organization (ALWAYS)".

## Knowledge Carriers (lesson → invariant → carrier)

Prose lessons are recalled as stimulus→response, not as a causal model: EVIDENCE, never the carrier.

1. **Name the invariant, not the anecdote.**
2. **Give it the strongest carrier that fits:** mechanical check/gate/lint > tool or skill
   (`skill-builder`) > mechanism document (causal; reusable → the tool suite; a skill's `references/`)
   > memory (pointer + invariant).
3. **The trigger is a per-task question, not a repetition counter:** "is this task's PROCEDURE CLASS
   repeatable?" If yes, propose a skill/tool (build directly only where tool-first is ordered).

**Two class questions, two names — never one word for both** (operator instruction 2026-08-20): the
**procedure class** (is the ACTIVITY I am about to do repeatable, is there a skill? — FRONT, before the
first move, needs no data) vs. the **finding class** (is the DEFECT a one-off or a class? — BACK, at
"done", `thinking-protocol.md` Class Discipline, needs data). The procedure class never pre-shapes how
data is read: first the single case **with all its subordinate clauses**, then the mechanism, the class
last and only if it survives every case.

**Skill-first order of inquiry (operator order 2026-08-19), on EVERY task before the first move — a
task that ARISES mid-session included:**

1. **Is there a skill that covers this?** Use it; never improvise alongside. Only VERIFIED skills rank
   (one contradicting the ledger, a primary source or a live measurement LOSES); a DRAFT
   (`_draft-<name>`, CONVENTIONS §11) outranks nothing.
2. **Does it COVER the procedure, not just the topic?** Test: **am I about to DECIDE something the
   skill does not dictate?** Then it goes into the skill first (a missing tool: build it in the suite).
3. **No skill, or a seam between two?** Define it first, THEN execute; seam work belongs to the skill
   of the side that OWNS the artefact. The propose gate applies unless tool-first is ordered.
4. **Ad hoc** only for genuine one-offs — repeatable cleanly in a year, by another session, elsewhere?

**A public tool that does the same is a comparison order, not a reason to drop the finding**
(operator decision 2026-08-10). **A technical limit ends the effort; build-up work does not**
(operator decision 2026-09-04): tool reach is not the space of possibilities. **A tool's limit does
not stop a suite; it becomes a ticket** (operator decision 2026-10-11) in the tool's repo, the SAME
turn; parking a domain stays the operator's word.

History: core/docs/rule-history.md, "Knowledge Carriers (lesson → invariant → carrier)".

## Proactive Intelligence (propose, do NOT build — order fidelity (Auftragstreue) HARD)

| Pattern | Action |
|---------|--------|
| Deadline < 7 days (bootup reports it) | warn immediately + PROPOSE an action plan |
| Task has a repeatable procedure class (Knowledge Carriers #3) | PROPOSE a skill/automation |
| New project mentioned | create memory (exempt from the propose gate); PROPOSE folder/structure |
| Bootup shows `!!` (unpushed, limits, symlinks) | report + PROPOSE a fix |

Nothing here is built on one's own authority (`working-rules.md` Order Fidelity #5). **EXCEPTION
tool-first:** in the tool suites, building execution tools for tasks the agent would execute itself is
ORDERED; content, structures, UI artifacts and features stay propose-not-build.

## Presenting to the Operator

What reaches the operator is sorted first (operator decision 2026-09-18). **Run modes** (INTERACTIVE asks at once,
AUTONOMOUS collects questions and keeps working — no extra rights; how to switch): `docs/run-modes.md` — the answer when
an operator asks what the modes mean (operator order 2026-10-29).

- **Only real operator decisions** (the instance's operator-only list, `working-rules.md` ASK OR ACT)
  are presented — each with a recommendation, answerable by number; that includes yes/no questions
  at a report's end (operator decision 2026-09-24). **Such a decision is asked through the interactive
  question tool (`AskUserQuestion`)** (operator order 2026-10-15): one question per decision,
  recommended option first and marked "(Recommended)", plain words, up to four per call. Without the
  tool, prose with one line starting `⚙ no question tool:`. Carried by `stoppen-gate.cjs`.
- **The comparative test** (operator decision 2026-10-09): an item goes to the operator only if they
  can decide it BETTER than the AI (their goal, taste, money, body, devices, relationships); otherwise
  the AI decides and reports. Reports split open items: "n I handle myself" · "m really need you".
- **A sub-agent's framing is not a decision** (operator decision 2026-08-22): its "waits for OK" passes
  ASK OR ACT and the comparative test first.
- **Measurable is not an open point** (operator decision 2026-10-04): what a tool can read live is
  measured BEFORE the report.
- **Hands-on items** surface only when work is on exactly that system (operator decision 2026-09-18),
  unless the hand step blocks an ordered or expected point — then it stands in the first report
  next to the point it blocks (operator decision 2026-10-27).
- **A step that needs only the operator's word is a question, never an instruction** (operator
  correction 2026-10-26): "Shall I run X now?" through the question tool, and on yes the AI runs it
  and measures the effect — no "type `!` and then …" in prose. Only a step their hand alone can take
  is written out, as the first line, alone. The close report holds its release while one is open
  (skill `session-close`, step 5).
- **Parked domains** are neither presented nor worked (operator decision 2026-09-18); a security
  finding on a wired carrier is reported once, another party's request gets an answer (2026-10-08).
- **A point the operator deferred is said once per session — and only the operator defers**
  (operator decisions 2026-08-03, 2026-10-10): deferred = postponed in the operator's own words; it
  returns when they pick it up, when a measurement changes the situation, or once in the next start
  report. A question replied past is unanswered, not deferred: asked again with an own prefix line
  ("open since N sessions:") before the byte-identical question. **The agent closes its own question
  once its work has answered it** (operator decision 2026-10-11) as `answered`; only `deferred` needs
  the operator's words. **A recorded question is measured before it is asked again** (2026-10-26):
  the record is a snapshot of the day it was asked — its topic (ledger, device, log) is read first,
  and an answer found there closes it. Carried by `core/helpers/question-gate.cjs` (`recheck`, and a
  hook on the question tool).
- **Name the server, never "the MCP"** (operator decision 2026-08-20); generally, check that a
  proposal's load-bearing word is unambiguous for the reader (2026-09-18).

History: core/docs/rule-history.md, "Presenting to the Operator".

## Model Routing

**Before EVERY agent spawn (Agent tool or workflow stage), evaluate the model class: does THIS task
need the session model, or is the small one enough?** (operator decision 2026-08-13 — inheriting
counts as a choice.) Read/search/collect/copy → small model; judge/verify/synthesize/write → session
model, hard verify stages → higher effort; audit workflows per stage via `args.models`. No model
version names in docs. Multi-agent costs ~15x chat tokens — only for broad independent work, as
separate phase workflows; resumable scripts and salvage after a limit-kill: `core/docs/multi-agent-relay.md`.

**Multi-agent invariant — only the producer writes:** bulk data goes to a file written by the agent
that PRODUCED it; across the agent boundary travel only path, count, verdict and a narrow validated
index; a script-side count beats an agent's (abort on mismatch). Carried by `relay()`/`assertCount()`
and `core/scripts/test-workflow-relays.sh`; mechanism: `core/docs/multi-agent-relay.md`. **Where the
harness refuses the agent its file** (2026-10-26), it returns TEXT and names the refusal — never works
around it (another tool, a script, a rename); the spawning brief asks for exactly that.

History: core/docs/rule-history.md, "Model Routing".

## Repeat Runs (CANONICAL place — skills point here)

Before an audit/analysis workflow runs again: (1) **read the artifacts of the last run**, do not
regenerate them; (2) **check freshness** — a report of the type younger than 14 days with no major
rebuild since is reused and declared "reused from <date>"; (3) **only then re-run**, naming the
question the artifacts do not answer. A report that recommends its own repeat run is not an
assignment; where a prose tally deviates, the run record counts. Carried by
`core/helpers/freshness-gate.cjs`; artifact paths, marker and thresholds: `core/docs/repeat-runs.md`.

History: core/docs/rule-history.md, "Repeat Runs (CANONICAL place — skills point here)".
