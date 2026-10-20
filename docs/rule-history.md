# Rule History

The incidents, measurements and past states behind the always-loaded rule files in
`rules/`. The rule files carry only the rule, its date and its carrier; what moved
out of them stands here verbatim, under the section it came from. Protocol, not
rule: nothing here changes what an agent must do.

## rules/working-rules.md

### Working Rules

A red check found days
   later is a check nobody watched (measured: a PR sat red while the session reported
   the others green).

(operator 2026-10-13: "that blocks every
   other activity — with several core PRs waiting on CI, hours go by")

Measured the day the
   rule was written: 65 of 263 ci-watch calls in three days ran in the foreground.

Measured that day: five pushes to PR branches, four watched;
   the fifth went red (runner never acquired) and the operator found it; six merges, none
   watched.

The core repo is public, so "push to a public repo" alone
    gated every core branch — and collided with merging core PRs without a word per PR.

, after three incidents in three days

### File Rules

`bootstrap-brain.sh` writes `.gitattributes`
into every new brain (line-ending class), and it MUST live in root so the rule
applies repo-wide; `.gitmodules` is created by git as soon as the same script mounts
`core/` as a submodule (`bootstrap-brain.sh`, `git submodule add`) — the location is
dictated by git and cannot be moved. Both stood in opposition to the rule that
produces them.

### Project Lifecycle (operator order 2026-08-14)

Measured: a catch-all held 150 entries, whole projects among them, because
   nothing said when an area is due.

### Mechanism Discipline (HARD)



The three questions above do NOT catch this: a cleanly
built second path passes all three — and is still wrong, because the question
"should a second path exist here at all?" is never asked.

(Coherence scan of a Windows
instance, 2026-10-12: a loaded skill still called the raw API merge a "second legitimate
form" while `collab-watch` forbade exactly that.)

(coherence finding 2026-09-18: the decision
was spread over a dozen rules on three ranks, and the stop gate and this section gave
opposite answers for the same case)

Split out of the adjacent step on 2026-10-12 (operator decision): the two
   cases shared one step and one outcome — note it and continue — which fits an adjacent
   idea, but turns a NEEDED subtask without a path into exactly the improvisation this
   section names.

Measured on
a collaborating brain the day the rule was written: "dann coherence scan" — then, after the
two instances asked had answered — was read as "now", and nine analysis agents ran before
the answer came.

(Incident 2026-10-11: a defined path was
not available on a second machine; the session built its own client and wrote straight
into the tool's IPC file instead of reporting. Not available = report, THIRD CASE above.)

(incident 2026-09-12: two merges in a shared repo carried the marker with a verbatim quote
that stands in no transcript of that day — the gap it should have shown was papered over by
the invented evidence)

### One System, Not Local Workarounds (HARD, operator order 2026-10-08)

(measured 2026-10-09: three
  items declared instance-only were general)

(operator order 2026-10-11: no
special-purpose tinkering — here, at collaborators, in other instances)

Measured the day the rule was written:
two collaborator forks, their main far behind, about twenty leftover branches of merged
PRs, one fix that had lived only on a fork branch for six weeks, and one open PR still
served from a fork.

(operator, same day: "the human does not
have to be bothered every time something deviates, but there should be a classification and
analysis of what deviates, why, whether that makes sense, and whether something should move
into the core as a PR")

It
inventories EVERY carrier of behaviour — the search space is the invariant, not the last
incident: hooks, stop checks, MCP servers, git hooks, scheduled jobs, extra plugins, skills,
workflows, output styles, agents, commands, rule sections, scripts — and names every item
that is neither core nor declared with evidence, every undeclared item that contains none of
the instance's `identity_tokens` (presumably general), every near-duplicate of a core tool
under another name, every expired alpha, and every file edited inside `core/` (the pin check
sees moved commits, not edits in place); one summary line counts each class.

Measured on
the proving brain the day the rule was written: 12 of 31 hook entries ran from unmerged
checkouts, 8 from instance scripts — at least four of those general mechanisms — and
nothing had reported it, because every one of them worked.

### A Needed Reload Is Not a Wait State (operator order 2026-08-06, sharpened 2026-08-14)

A change to a tool that only takes effect after the server reloads ends many turns with
"this needs a restart" — and then the agent waits for a human reply. That is a wait
state the agent can dissolve itself.

### Working Across Parties

(operator order 2026-10-11, after a hand-over
   between the operator's own machines lay unseen until the operator asked on every side)

(operator correction 2026-10-11: "you crossed each other
   there for nothing — that costs time")

Measured the day the rule was written: one finding,
   two fixes from two machines three minutes apart (one closed), and a merge over the finding
   because a reader showed 200 characters of the comment.

## rules/intelligence.md

File header before the 2026-10-20 diet, verbatim:

> CORE VERSION: session mechanics + auto-organization. The auto-fire table
> (pattern → skill) is instance knowledge — it lives in the instance rule file of
> the respective brain (`.claude/rules/intelligence-instance.md`) and is the ONLY
> source there (no second copy maintained in CLAUDE.md).

### Session Start (mechanical + Claude's part)

(operator order 2026-10-12, after a coherence scan counted more than ten
first-reply requirements spread over this section, each with its own date, and a blocking gate
behind them)

, after an audit of the audit process

(operator, 2026-10-09: "technical terms that mainly serve internal and AI logic —
always weigh whether the human really needs the code, or whether it hinders more than
it helps")

, second pass —
translating everything is not the point either

folding a FAIL/`!!` line into the middle of a
prose summary satisfies the letter of the boundary above but not its point — the
finding reads as one more status clause among several and gets lost exactly the
way the terseness rule was designed to prevent for everything else.

(Incident: a mini-summary listed "brain-check: needs
a look" as one clause among five in a single sentence; the operator had to call it
out explicitly before it got the visibility the boundary rule already entitled it
to.)

(a standing approval, full-audit 2026-10-15 on a Windows instance: its rules said
requests addressed to that machine are handled without asking, and the first reply asked
anyway)

(operator correction
2026-10-10: "I want to hear that question mainly at the session start, not again
and again")

(Incident: the bootup listed nine open requests and six PRs; the first reply said
"nine older requests, nothing new" and named none — two days after the data side had
been fixed, because the relay side had no carrier.)

#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Session Start (mechanical + Claude's part). The full wording it was condensed from, verbatim:

The SessionStart hook (`core/helpers/session-bootup.sh`) delivers on every start:
git status incl. unpushed warning, memory limits, settings validity, symlink check,
brain-scan age, open ordered assignments, deadlines pointer. **Claude's part:**
READ the output, react to `!!` warnings (report/propose), connect to
`git log --oneline -10`. **The first answer of every session begins with a
1-sentence mini-summary** (state of affairs + what is potentially coming up — from
the bootup block, open assignments, memory).

**The first reply has ONE target form — fill the slots, in this order, and nothing else is
required of it** (operator order 2026-10-12). Each slot names the paragraph that defines it; the paragraphs below stay the
definition, this list is the order and the checklist:

1. **Mini-summary** — one sentence, state + what is coming up (above). Plain words
   ("The summary is written for the operator", "Kind and matter in plain words").
2. **The operator's own request** — if the first message carries an order or a question,
   it is answered or started here, before any housekeeping. A session usually starts for
   that reason, not for the open points.
3. **Reporting duties, one line each** — FAIL / self-test failure / an acute warning, each
   on its own line with the next concrete step ("A reporting duty needs its own line").
4. **Open points for this instance** — split by who acts: "n I can handle — shall I?" (ONE
   question, only here — and the one closing question the stop gate lets stand, as
   `stoppen-gate.cjs` already codes it) and "m need you" (up to three named, more offered); items reported
   before said louder; "nothing open" or "could not read" when that is the state ("Open
   points that concern this instance"). Items of a class the operator approved once for good
   are handled and reported, not asked — the class and the operator's quoted words live in
   the instance file `.claude/rules/open-items-standing.json`. Carried by `open-items-gate.cjs`.
5. **Due decisions** — a brain-scan or deep check that is due, a deferred point said once,
   a pending update: each as a direct question with the price where there is one, asked
   through the question tool ("Three levels of self-check", "Presenting to the Operator").

Everything else that the bootup showed and that came back clean stays silent ("Relevance
beats completeness"). Slots that are empty are left out, not announced. A later reply in the
same session repeats none of slots 3-5 unless the state changed or an unanswered question
becomes the next step's blocker (then asked again, verbatim — "Presenting to the Operator").

**The brain-scan runs only in an active session, on the operator's OK** (operator
decision 2026-09-23): the bootup reports it due after 14 days and overdue after 28; the
first answer asks, and the scan starts in this session once the operator says yes. A new
scan needs at least 7 days since the last completed one — `freshness-gate.cjs` carries that
floor as the core default for `brain-scan`; earlier only on the operator's clear word, given
as the `FRESHNESS-OK` marker (operator decision 2026-10-18: every two weeks is the report
cadence, one week the floor). No
scheduler starts it unattended — an unattended run has no one to read its findings,
stalls when the machine sleeps, and costs tokens nobody ordered. `core/scripts/brain-scan.sh`
stays only for an instance that explicitly opts into a scheduler and says so in its own
rules.

**Three levels of self-check — every brain knows all three, and their price** (operator
decisions 2026-10-09):
1. **Session start** — every session, mechanical, near-free: open items, deviations from
   the core, register drift, growth of the always-loaded context. Reports only what is off.
2. **Brain-scan** — every two weeks, on the operator's OK (above). It first checks what became of
   the last run's findings, then the boundary between instance and core, then the
   checklist; every finding leaves with an exit (skill `backlog-catch-up`). It does not
   fix inside the run — fixing happens in the session with the operator.
3. **Deep check** — only on a reason: `coherence-scan` (contradictions between rules),
   `memory-dream` (memory hygiene), `full-audit` (all of them plus synthesis, before a big
   restructuring). The AI RECOGNISES the reason and TELLS the operator — what, why now, and
   the measured price — and never starts it on its own (an operator who handed the AI side to
   another party's AIs: those AIs decide, `working-rules.md` Working Across Parties #6). Reasons: five or more new dated
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
**Commands and exact text for the operator take the instance's form** (operator decision
2026-10-19, "each brain its own form"): how a reply hands a command or exact text to a person
(block, inline, file) is set in ONE place of the instance's operator rules. Code that IS the
artefact (a file, a PR body) is untouched.

**Kind and matter in plain words, never a priority or ledger code** (operator
correction 2026-10-08): every note from an AI to a human — session-start report,
chat, a proposal, shared-memory prose to a collaborator — says WHAT it is (task,
proposal, serious problem, acute need for action, note) and what it is about, in
words. Priority grades (P0/P1/P2) and ledger ids (an audit's finding numbers,
order-list ids) are lookup handles: at most a trailing reference in parentheses,
never the word that carries the meaning. Same class as the `!!` markers above: a
handle the machine needs is not vocabulary the reader has.
The same holds for EVERY internal classification scheme, not only priorities and ids (operator, 2026-10-09): decision-circle letters, test classes, gate names, finding classes. Say
what the code MEANS for the reader — "the AIs settle this among themselves", "this
decision needs you", "needs a run on both machines before release" — and keep the
code in the data field where a machine reads it. The test before using one: would
the reader understand the sentence with the code deleted? If not, the code was
carrying the meaning and has to be translated.

**Relevance beats completeness** (operator correction 2026-08-13): a briefing names ONLY what the
operator must know or decide right now, in one or two plain sentences. Everything
else is checked silently and surfaced only when it needs action or a decision — a
check that came back clean is silence, not a line. Nothing gets verbalized out of
obligation. Boundary: reporting DUTIES stay (FAIL lines, reportable events,
evidence chains in reports, every open point that concerns this instance — next
paragraph but one) — the filter applies to briefing prose, not to mandatory artifacts.

**A reporting duty needs its own line, not a clause inside the summary sentence**
(operator correction 2026-08-20): A FAIL/`!!`/
SELF-TEST-FAILURE item gets (a) its own visually separated line, not blended with
push status or PR counts, and (b) the next concrete step (verify/report/propose),
not just the bare state word.

**Open points that concern this instance are a reporting duty, never briefing prose**
(operator correction 2026-10-07): every item under "open for us" in the bootup — an
open request addressed to this instance, an open PR — reaches the first reply, split by
WHO has to act. Items the agent can answer or handle itself (its own circle): the count
and ONE question whether to go ahead — a session usually starts for another reason, so
the agent starts none of them without that OK — unless the operator approved the item's CLASS
once for good (a standing approval, full-audit 2026-10-15). Such a class is declared with the operator's quoted words and date
in `.claude/rules/open-items-standing.json`; its items are handled and the reply reports what
was done. That question is asked ONCE, at the session
start (startup or resume) — never again later in the same session (operator correction 2026-10-10). After a compaction, after the operator's go, and for every own item that
turns up mid-session: handle it and report what was done; a report never ends on "n I can
handle — shall I?". Items that need the operator: the count;
up to three, one short bullet each (what it is about, who needs what); more than three,
the offer to list them — a wall of items at session start intimidates. Nothing open: say
"nothing open". A source that could not be read: say so — never "nothing". An item that
an earlier session already reported and nobody has acted on is said LOUDER ("reported in
N sessions since <date>, nothing done yet"), never quieter: attention rises with every
repeat. "Nothing new" describes commits, never open points. The relevance filter above
does not apply to these items. Carried by
`core/scripts/open-items.py` (the list, the class per item — automatic from `circle:`
and the addressee, otherwise the agent's `--classify` — and the repeat counter) and
`core/helpers/open-items-gate.cjs` (Stop: blocks a first reply without that form, with an
unclassified item, or in a session whose bootup never arrived).

### Session End


#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Session End. The full wording it was condensed from, verbatim:

The operator triggers skill `session-close` ("close the session" and similar): persist
open work (states into their ledger, lessons to their strongest carrier with pointers into
auto-memory — Knowledge Carriers below), write
handoff/session log, export, check every repo the session wrote to, clearance.
The SessionEnd hook does the same mechanically as a best-effort fallback (does not
fire on a hard kill). NO `memory/session_*.md` files — memory lives in auto-memory
(harness).

### Auto-Organization (ALWAYS)

(measured 2026-08-04: one entry flipped one minute after being
   written)

, full-audit E2

; on 2026-08-04 two files had to be renamed because of this

(full-audit M12)

—
   measured 2026-08-04: block 7 entries and "OPEN", file 9 entries and "RESOLVED"

—
   a skill's injected code snippet showed `PR ~ /^PR /` where disk (repo, tag, plugin
   cache) says `$0 ~ /^PR /` everywhere; a defect report or PR derived from injected
   text alone would have "fixed" a bug that does not exist

#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Auto-Organization (ALWAYS). The full wording it was condensed from, verbatim:

1. Every new file goes into the right folder immediately (instance folder table).
2. Every new FACT → auto-memory (file + MEMORY.md index); a new LESSON goes to its
   strongest carrier (Knowledge Carriers below) and memory keeps at most the pointer —
   a lesson filed only as memory is recalled as text, not as a mechanism. **If an entry asserts a
   state of the core** (file, rule, helper), it names the submodule state it was
   measured against (tag or commit) — otherwise the note goes silently stale at the
   next core update.
   **Slug and `name` carry the LESSON, not the momentary state** (operator decision
   2026-08-10): `gate-checks-pruefen-den-baum`, not `main-ist-rot` —
   a state slug goes stale with the next fix and carries the solved symptom onward
   as its name.
   **Before every memory-based decision read the FILE, not the injected context
   block**: the block can be older than the disk.
   **This applies to ALL injected text, not just memory blocks** (measured 2026-08-13):
   injected content is a render copy, and rendering can CORRUPT it, not just lag behind. Before acting on a snippet
   or deriving a finding from injected skill/rule text: read the file on disk.
3. Every code change → skill `verification-before-completion`.
4. Delete junk (temp files, .DS_Store, __pycache__) immediately.

### Knowledge Carriers (lesson → invariant → carrier)

(self-diagnosed on a
live instance 2026-08-19: domain rules remembered per incident, not derivable
from how the system works — errors repeated despite the notes)

("stays where I let
go", "even when no finger holds it")

(Incident 2026-08-20: the front question
slid from "which procedure do I use" to "what is this case in general" before a
single observation was in; a summary built on that guess was refuted by the
operator's second observation in the same message, and a decision draft had
already been stacked on it.)

(incident 2026-08-19, `macro5001`: written from session memory a day AFTER
   the decision it silently omits, then followed instead of that decision)

Measured gap (operator finding 2026-08-20): a loaded skill answered step 1
   with "yes", step 2 asked only about TOOLS, and step 3 fires only when there
   is NO skill — so a skill that exists and does not describe the procedure
   fell through all three, and the work got improvised next to it for half a
   day.

Measured on a proving brain: a whole suite sat parked
for weeks over one tool boundary, and nothing named which work the boundary actually blocked.

#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Knowledge Carriers (lesson → invariant → carrier). The full wording it was condensed from, verbatim:

A lesson that lives only as prose (a feedback entry, a memory note) gets recalled
as a stimulus→response pattern, not as a causal model: the agent re-applies the
remembered TEXT while the mechanism underneath has moved on. Prose entries
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
what condensing drops first, and they carry the causality.

**Skill-first order of inquiry (operator order 2026-08-19), on EVERY task,
before the first move — and a task that ARISES mid-session is a task (the
check fires at the start of the WORK, not at the start of the session; the
unexpected sub-job is exactly where improvisation happens) — intelligent analysis yes, but in this sequence:**

1. **Is there a skill that covers this?** Use it. Never improvise alongside an
   existing skill, not even "just this once". That rank belongs to VERIFIED
   skills only: a skill that contradicts the ledger, a primary source or a
   live measurement LOSES — re-read the source before following the skill.
   A DRAFT (`_draft-<name>`, `status: draft`, `provenance:` per step —
   CONVENTIONS §11) may be used, but it outranks nothing either: a prototype,
   not an authority.
2. **Does the skill COVER this task — the procedure, not just the topic?** (Operator finding 2026-08-20.) The test is mechanical: **am I about to DECIDE something the skill does
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

**A tool's limit does not stop a suite; it becomes a ticket** (operator decision
2026-10-11). When a real technical limit of one tool is met, the limit is filed in the SAME
turn as a ticket in the tool's repo — the problem, what was measured, where the boundary
runs, what follows from it, and how to replicate it — and the suite keeps running for
everything the boundary does not touch.
Parking a domain stays the operator's word; a limit the AI met is a ticket, never a park.

### Proactive Intelligence (propose, do NOT build — order fidelity (Auftragstreue) HARD)


#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Proactive Intelligence (propose, do NOT build — order fidelity (Auftragstreue) HARD). The full wording it was condensed from, verbatim:

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

### Presenting to the Operator

 — reading every one costs hours to days

(order of the Windows instance's operator, 2026-10-15, after a report ended on a prose
  list he could not answer — "ask me a clean question" — and three decisions then reached
  him through the tool: "the way you just asked me, cleanly and interactively, I want it
  always for operator decisions"; both translated)

(measured 2026-10-15 on
  a Windows instance: four records for one question, three of them rewordings)

(operator decision
  2026-10-11: "yes, the AI may close its own settled questions — but set it up cleanly,
  document and justify it")

Justification: the gate exists so
  that a question does not scroll away unanswered — a question the work has answered is not
  that case, and a human made to close it by hand is pure friction (measured 2026-10-11 on a
  Windows brain: the agent's `resolve` call was refused by the harness classifier because
  that brain lacked the template's `Bash(node core/helpers/*)` permission, and the operator
  had to run it; the macOS brain, which carries the permission, closed three such questions
  the same day).

#### Wording before the 2026-10-20 diet

Rule now: `rules/intelligence.md` § Presenting to the Operator. The full wording it was condensed from, verbatim:

What reaches the operator is sorted first; the count of open proposals is not a
presentation (operator decision 2026-09-18).

- **Only real operator decisions** (the instance's operator-only list is the one authoritative
  set — `working-rules.md` ASK OR ACT; examples: goal, money, hardware, risk, external effect,
  release, ownership) are presented — each with a recommendation, answerable by
  number. The rest is done, closed, handed to the party that decides it, or left.
  This includes yes/no questions at the end of a report (operator decision
  2026-09-24): reversible, own brain or a PR, no operator knowledge needed = do it
  and report.
  **Such a decision is asked through the interactive question tool (`AskUserQuestion`)** (operator order 2026-10-15): one question per
  decision, the recommended option first and marked "(Recommended)", options in plain words
  without codes, several decisions in one call (up to four). A prose question at the end of a
  reply is for a clarification that is no decision. Where the tool is missing (headless, a
  scheduled run, a harness without it), prose stays the fallback and the reply says so in one
  line starting `⚙ no question tool:`. Carried by `stoppen-gate.cjs`: a closing decision
  question without the tool call or that line is not let through by re-issuing it.
- **The comparative test** (operator decision 2026-10-09): an item goes to the operator
  only if the operator can decide it BETTER or more cleanly than the AI — because it
  rests on their goal, taste, money, body, devices or relationships. If measurement,
  rules and context let the AI decide it as well, the AI decides and reports. Every
  report that carries open items splits them in one line each: "n I handle myself" ·
  "m really need you" — and the second number is usually small.
- **A sub-agent's framing is not a decision** (operator decision 2026-08-22): "waits
  for OK" from a workflow is its filing category under its own implements-nothing
  boundary. The item passes ASK OR ACT (`working-rules.md`) and the comparative test above before it reaches the operator;
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
- **A point the operator deferred is said once per session — and only the operator defers**
  (operator decisions 2026-08-03 and 2026-10-10). Deferred means the operator postponed THIS
  point in their own words ("later", "not now", "next week", a date). Then it is not raised
  again in the same session — neither as a question nor as a trailing "still open" line; it
  comes back when the operator returns to it, when a new measurement changes the situation
  (data loss turning acute), or once in the next session's start report. A question the
  operator replied past without addressing it is NOT deferred: it is unanswered, stays open,
  and is asked again where it matters, louder each time (the repeat rule for open points
  above). Louder means an own prefix line ("open since N sessions:") BEFORE the
  byte-identical question sentence — never a rephrasing: the question gate keys a question
  by its normalised sentence, so a rephrased repeat is a new record.
  The agent never files its own silence or the operator's silence as a deferral.
  Carried by `core/helpers/question-gate.cjs`: `deferred` is accepted only with the
  operator's words as the note; `unanswered` keeps the question listed and askable.
  **The agent closes its own question once its work has answered it** (operator decision 2026-10-11): a question the agent asked, then settled by measuring, building
  or reading instead of waiting, is resolved `answered` by the agent with the resolution in
  the note; only `deferred` needs the operator's words. The permission is part of the template; `hook-coverage.py` now reports a
  brain that does not grant it, like an unwired hook.
- **Name the server, never "the MCP"** (operator decision 2026-08-20) — also in a
  reconnect request. Generally: before a proposal, check that its load-bearing word is
  unambiguous for the reader; an internal short word can mean something else to them
  (operator decision 2026-09-18).

### Model Routing

Reference measurement brain-scan (core PR #30,
run 2026-08-10): 9 of 11 agents small, ~778k of 1.02M tokens, all results valid.

(measured 2026-07-10: a
resume of a two-strand run missed the cache for all but six agents, ~8M tokens twice)

, four
failures in one workflow

(measured:
1 of 141 rows survived a "create a table" relay; 22 of 141 survived "return the
JSON UNCHANGED, you are a pipe"; a count field next to the array stayed correct
while the array was cut)

#### Wording before the 2026-10-20 diet

Moved verbatim to `docs/multi-agent-relay.md` (rule now: `rules/intelligence.md` § Model Routing).

### Repeat Runs (CANONICAL place — skills point here)

(measured 2026-08-04: a register reported
"24 raw → 18 consolidated" and derived a gap from it, while the record said
108 → 19 → 12; the supposedly missing findings had been discarded in verify)

#### Wording before the 2026-10-20 diet

Moved verbatim to `docs/repeat-runs.md` (rule now: `rules/intelligence.md` § Repeat Runs (CANONICAL place — skills point here)).

## rules/thinking-protocol.md

### Anti-Hallucination Rules

— two incidents in one day

(Incident: a fact from the visuals box transferred to the MacBook —
     the fact was right, the machine was not.)

(Incident: TD DAT survives inside the .toe → the "measurement" was 1.6 h old
     history.)

(Incident: "completed yesterday" claimed for an event
     whose install record said SAME day — "yesterday" was derived from the phrase
     "next session" in a note, never from a timestamp.)

(Incident 2026-08-04: a
     register counted "24 raw → 18 consolidated" and derived a gap of six findings
     from it; the record said 108 → 19 → 12, the "missing" ones had been discarded in
     verify. The recommendation derived from it would have cost 1.5 million tokens.)

— treating a
   remembered rule as a fixed text to replay is stimulus-response, not
   understanding, and it fails silently in exactly the case where a new
   situation looks similar but differs in the load-bearing detail.

(Incident: an instance held two memory entries from different sessions
   that read as contradictory; both were correct once the actual mechanism
   was traced out — the text-level pattern match had missed the
   distinguishing condition entirely, and no contradiction existed once
   restated causally.)

### Class Discipline (pointer — the mechanism lives elsewhere)

(measured on a proving instance: five classes, up to 15 single fixes of the same
root in 12 days)

### Confidence Assessment

(coherence-scan
K-13, 2026-08-01)

### Priority Hierarchy on Contradictions

Rank 2 added on 2026-08-04 (operator decision, coherence-scan P1-2): the HARD blocks
were not located anywhere in this list at all — neither above nor below feedback.
They asserted their precedence only themselves. The fourth HARD block, "One System, Not
Local Workarounds" (operator order 2026-10-08), joined rank 2 on 2026-10-15 — the same
defect, found by the coherence scan of a Windows instance: a HARD block without a rank.

### Rule-Conflict Protocol (operator instruction 2026-08-01, from coherence-scan K-19 — CANONICAL place)

Measured on a proving brain the same day:
   18 of 24 general-looking operator rules existed only in the instance — written
   down twice (protocol + compact rule), never asked where they belong.

Measured: a rig rule allowed port-dropping writes only during
   load-in, another allowed only port-neutral writes during load-in — read together,
   never; both stood unflagged for weeks.
