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

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
1. **Act proactively** - don't ask, do. Work through to the end. **Within the granted
   assignment and the defined paths** — the assignment space itself is never expanded
   on one's own authority (boundary: order fidelity (Auftragstreue) #5, mechanism
   discipline).
2. **Pragmatism > perfection** - no half measures.
3. YOU MUST **NEVER endanger social accounts** - only official APIs, never
   post/delete/change on your own authority. AI-generated content that goes online is
   labelled as such (operator base rule).
4. **Skills ALWAYS fire automatically** - never wait for slash commands. Scan all
   skills semantically.
5. **Parallel agents** for 2+ independent tasks that are each substantial in their
   own right (observe the cost/model-routing rule in `rules/intelligence.md`
   — multi-agent costs ~15x chat tokens); small stuff sequentially in the session.
6. **Existing files:** ALWAYS read first, then edit.
7. **Commit-ready means committed** (operator decision 2026-08-01): commit continuously and
   on your own; whatever is not committed is named WITH its reason. Where and when it is
   pushed stays instance policy (skill `session-close`); whether finished work is committed
   does not.
8. **Shell commands are atomic and must match a permission pattern** (operator decisions
   2026-08-01 / 2026-10-07): Claude Code approves a Bash call by matching its text against
   allow patterns, so a compound chain (`cd <dir> && git push`, `a; b`) matches none of them
   and turns into a prompt or a denial. Issue commands one by one; work in another directory
   through the tool's own flag (`git -C <abs-path> push`), never through `cd … &&`. Multi-line
   content goes into a file that is then run or applied — no shell heredocs, which also
   trip the harness's obfuscation heuristics.
9. **A PR is opened together with its CI watch** (operator decision 2026-10-09): whoever
   opens a pull request arms `core/scripts/ci-watch.sh pr <repo> <n>` in the same turn
   (background) and reads the result before calling the PR ready. **Never in the foreground** (operator 2026-10-13): a core run takes
   about 15 minutes, so every CI wait runs detached, one watch per PR in parallel, and the
   session keeps working until the verdict arrives as a notification. Carried
   by the core's own `mechanism-rules.json` (`foreground_only`). **And the same holds for
   every push that starts a run** (operator correction 2026-10-13, "fatal"): a push onto a
   PR branch, a merge (a push to the base branch), a tag — each gets its `ci-watch.sh
   pr|ref` in the same turn. Carried twice: `core/helpers/watch-gate.cjs` blocks a turn end after a push
   into a checkout with workflows without a ci-watch on that repo, and the standing watch
   (`repo-activity-watch.sh` inside collab-watch) reports every red run on a watched repo
   as `CI-RED`, so a red check is seen even when no one armed a watch.
   **One exception, the closing turn** (coherence scan 2026-10-15): a session being closed
   arms no watch it will not live to read — skill `session-close` lists each such push, PR or
   open question as an `open end:` line in its session-log entry, and the close stamp of that
   turn lets `watch-gate`/`question-gate` pass exactly the listed items, nothing else.
10. **A commitment about future behaviour becomes rule text in the same turn** (operator
    decision 2026-10-09): "from now on I will…" said only in chat binds nothing and is
    invisible to every check. Write it where rules live — the instance's rules if it is
    about this brain only, a core PR if it holds for every brain — so the local-machinery
    inventory sees it and its reach can be checked like any other carrier.
11. **Core PRs: new functionality is discussed first, follow-ups may be pushed** (operator
    decision 2026-10-09).
    A core PR that brings NEW functionality (a new gate, hook, script, skill or rule) is
    agreed with the operator before it is built; usually the order itself is that
    agreement. A FOLLOW-UP — a fix, a correction, a catch-up inside an agreed strand, the
    clear findings of an ordered audit, the port of instance machinery that already runs,
    the rule text for a correction the operator gave — may be pushed and opened without a new word. That
    is the agreed channel ASK OR ACT step 1 names. Making a repo public, a first
    publication, a push outside the organisation's repos and a deployment stay gated.
    Carriers on every push: leak-scan, the English-only ratchet, the instance's name guard.
12. **Two sessions, one working copy: commit by path, never rewrite, never touch the other's
    operation** (operator direction 2026-10-13). A checkout
    has one index and one HEAD; git cannot tell sessions apart. While a second session runs on
    the machine, a session that is not working in its own scratchpad worktree commits only its
    own paths (`git commit <paths> -m …`), stages only its own paths, never amends, stashes,
    hard-resets, switches branch or force-pushes there, pulls `--ff-only`, and leaves a rebase
    or merge it did not start untouched — it messages the session that owns it instead. Branch
    work goes into `git worktree add` under the scratchpad, which is private by its path. The
    carrier is `core/helpers/shared-working-copy-guard.cjs`; a deviation needs the marker and is
    finished in the same turn, so the other session never meets a half-done state.
```

### File Rules

`bootstrap-brain.sh` writes `.gitattributes`
into every new brain (line-ending class), and it MUST live in root so the rule
applies repo-wide; `.gitmodules` is created by git as soon as the same script mounts
`core/` as a submodule (`bootstrap-brain.sh`, `git submodule add`) — the location is
dictated by git and cannot be moved. Both stood in opposition to the rule that
produces them.

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
**Naming:** kebab-case, lowercase, English, no umlauts/spaces.
**Root files:** Only README.md, CLAUDE.md, LICENSE, .gitignore, .gitattributes,
.gitmodules, .mcp.json, .env, .env.example (the instance may extend the whitelist,
never silently).

**Invariant behind the two dot files:** *What git itself necessarily creates in the
repo root, a whitelist cannot forbid.*

YOU MUST comply with these rules:
- NEVER place files in root (except the whitelist above)
- NEVER create duplicate docs (first check whether one exists)
- NEVER use code fragments as file names (flex, mb-6, BigInt(0), void)
- Delete junk files immediately when discovered

**A baseline stays generic** (operator decision 2026-09-06): how one concrete setup uses
a general baseline goes into its own file that REFERENCES the baseline instead of
copying it.

**Identity is written, state is read** (operator decision 2026-08-05): what a tool can
read live (link, lease, address in use, version, counters) is never frozen into labels,
configs or docs. A snapshot that must be written carries its date and source. The other
half (operator decision 2026-10-19): what only its producer knows, the producer writes as a
field; a reader never rebuilds it from prose. **Every change declares its level**, fix or
feature — symptom · reader · writer · design, why not the next higher one, the debt left —
in its changelog fragment (`core/helpers/change-level.cjs`; open debts return at session start).

**Files the operator opens are versioned, never overwritten under the same name**
(operator decision 2026-10-04): every output the operator opens, loads or prints carries
a version and a timestamp in its name; a new iteration is a new file. **An operated
artifact is saved as a dated copy before AND after every rebuild** (operator decision
2026-08-03, sharpened 2026-09-18) — that needs no approval, and the missing save is the
defect; a bare overwrite stays the operator's call.

The folder mapping (what goes where) is instance knowledge — table in the instance
rule file.
```

### Session Traceability (3 layers)

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
1. **Verbatim:** Claude Code transcripts, long retention (`cleanupPeriodDays`).
2. **Chronology:** `docs/maintenance/session-log.md` — per session close 2-4
   semantic index lines (topic, decisions with pointer, loose ends).
3. **Distillate:** document decisions domain-keyed (why + what was discarded, in the
   domain's change log); pillar decisions ADDITIONALLY in
   `docs/maintenance/decision-log.md`.

**Audit rule:** session-log + decision-log are PROTOCOLS, not a fact-knowledge base —
append-only history, never "clean up"/consolidate, never treat facts from them as
current state. A FOLD is not a clean-up: it moves old entries byte-identically into an
immutable fold file and leaves a marker line — nothing is edited or dropped. The
session log is folded at session close above the instance's threshold
(`SESSION_LOG_FOLD_MAX_BYTES`, skill `session-close` step 2).

**Archive and compact by relevance, never by age** (operator decision 2026-08-30): only
what lives on completely ELSEWHERE (successor plus pointers in both directions) is moved
out; deleting is outside the agent's mandate. Exception for logs (operator decision
2026-09-25): a log may rotate by period, with clean pointers and nothing lost — sorting
log lines by relevance would mean judging the record. Keep log entries short (heading
plus one line, the content in a fact file) so one period fits the limit.
```

### Project Work Ledgers (operator decision 2026-08-13)

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
How project work (todos, intermediate states, decisions) is tracked, so that every
instance and every colleague files it the same way and lists stay compatible:

1. **One hand-maintained detail list per project domain**, in the PRIVATE instance
   repo (`docs/<domain>/offene-punkte.md` or the instance's equivalent) — NEVER in
   the project/tool repo itself. Operator orders, hardware context and intermediate
   states are instance knowledge; project repos may become public (tool/instance
   split). Every entry carries four fields (English keys and values — they are the
   cross-instance interface; the prose around them may be the instance's language):
   - `id:` stable slug — referencable, survives rephrasing
   - `class:` todo | decision | lesson
   - `reach:` project | brain | shared (see 3.)
   - `origin:` operator | derived (derived = proposal, needs an OK). Legacy lists
     may still carry the instance's documented operator name as the value
     (e.g. `origin: Alex`) or the older `von: <name>` marker — aggregators and
     scan prompts MUST match both forms; new entries write `operator`.
2. **Every overview above the detail lists is GENERATED, never hand-maintained.**
   A second hand-kept list drifts — measured repeatedly. Aggregation is a script's
   view over the registered detail lists, not a document anyone edits.
3. **`reach: shared`** marks an entry for the org's shared-memory repo as soon
   as more than one brain works the project: exported as one-file-one-fact WITH a
   back-reference to the source `id`. The export is a deliberate act at session
   close (leak discipline) — nothing propagates itself. Exception: a DECISION whose
   reach goes beyond this brain is pushed in the same pass it is made (operator
   decision 2026-09-06) — documented internally is not arrived.
4. **Decisions are pointers, not copies.** The full why lives in the domain change
   log / decision log (Session Traceability above); a `class: decision` entry
   only references it. No second maintenance.
5. **The brain's own maintenance/scan order list carries ONLY brain-function work**
   (consistency, carriers, audits). Domain work in the brain list — or brain work in
   a domain list — is misfiled and gets moved, not tolerated.

Which domains exist and where their lists live is instance knowledge (folder table
in the instance rule file).
```

### Project Lifecycle (operator order 2026-08-14)

Measured: a catch-all held 150 entries, whole projects among them, because
   nothing said when an area is due.

Moved 2026-10-20: the six steps stand verbatim in `docs/project-lifecycle.md`; the rule file keeps a two-line pointer.

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

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
**The trigger is the UNEXPECTED subtask.** The planned main task gets researched; the
subtask that pops up in the middle ("I quickly need a fixed IP / a value source / a
measuring point") gets improvised — because it looks small and the local lever is
within reach. That is exactly where the silent deviation arises.

**MANDATORY — three questions BEFORE an unexpected subtask is touched:**
1. **Tool or throwaway?** Does the result stay in the system, or is it a one-off grab?
2. **Where does it belong?** Which mechanism already exists for it (device config/
   role, app-native structure, repo script, MCP tool)? When unclear: READ, don't guess.
   **Cross-reference tool-first (harmonization 2026-08-10):** If the instance has
   ORDERED tool-building as the path for a tool environment (the suites' tool-first
   rule), then independently building the tool IS the defined path — no contradiction
   with the discuss-first requirement: that targets paths WITHOUT any definition, not
   the ordered tool path.
3. **Does it survive reset/restart/an unfamiliar operator?** If not, it is not a
   result but a debt (cf. order fidelity #4).
An answer of "I don't know" means: read up or ask first — do not act.

**THIRD CASE — the interrupted path:** If a defined path EXISTS but is currently not
working, that is a **REPORTING EVENT, not an occasion to improvise**. Two branches
(split 2026-08-10, harmonization with the instances' stop discipline):
- **RESTORING the defined path** is reversible work within the assignment space —
  do it and report afterwards, don't wait for approval (kick off a restart, arm a
  watcher, repair the broken link).
- **Everything OTHER than the defined path** (alternative access, substitute path,
  rebuild) stays gated: report → propose → only on explicit instruction.
**Building an alternative access path is always a DECISION, never a repair** — even
if the result would be clean.

**A refusal is a decision, not an obstacle** (operator decision 2026-10-12). An action the
permission layer refused — a permission rule, the auto-mode classifier, a hook — is NOT
re-issued in another form: not as another command for the same effect (`gh api -X PUT
…/pulls/<n>/merge` after a refused `gh pr merge`), not through another tool (PowerShell
after a refused Bash call, a file edit after a refused command), and not through another
session or party asked to do it instead (that launders the refusal). The refusal is a
REPORTING EVENT: say what was refused and what it was for, and name who can take the step
(the operator, or a party that holds the right on its own). Retrying the same call after
the operator granted the permission is not a re-issue. **Carried by** the core's own
`mechanism-rules.json` (read by `mechanism-guard` from the enabled core plugin): the raw
API merge is blocked unless the marker quotes the operator.

**THE REQUIRED OUTCOME is binary:** either **"I find the prescribed defined path and
take it"** — or **"there is no defined path" → it gets DISCUSSED.** A third case does
not exist. No "I'll quickly do it differently and mention it": the questioning must
come FROM THE AGENT, BEFORE acting.
**"DISCUSSED" does not mean "end the turn on a question".** It means the question is
raised through the channel that fits it (step 3 below) while the ordered work goes on.

**ASK OR ACT — the one ordered procedure** (coherence finding 2026-09-18). Every other rule about asking or stopping points
here. Take the FIRST step that applies:
1. **Irreversible or externally effective** (deploy, publish, making a repo public, a push
   to a public repo outside an agreed channel — see Working Rule #11 —, send, delete, a
   write to a live system outside its agreed frame, money, hardware):
   its gate applies — the operator's word first, regardless of confidence. These are
   examples; the one authoritative set, and what "agreed frame" means for each live
   system, is the instance's operator-only list (one place — see the end of this section).
2. **Needed to fulfil the order as specified** and a defined path exists: take it, in the
   order's space. An interrupted defined path: restore it (THIRD CASE above).
3. **Needed to fulfil the order, but NO defined path exists** — the "there is no defined
   path → it gets DISCUSSED" case above. Raise it through the channel that fits it (the
   instance's ledger plus the next report; the other party's shared-memory channel when
   the path is theirs to define) AND, if the order can proceed meanwhile, name the
   assumption you continue under — in that entry and in the report, so the choice is
   visible and reversible, never silent. If the order cannot proceed without the answer
   and the answer belongs to the operator, the question ends the turn (last paragraph
   below). (Operator decision 2026-10-12.)
4. **Adjacent** — useful, but not needed for the order: write it where it is decided
   without blocking (the instance's ledger as `origin: derived`, or the shared-memory
   channel for another party), and CONTINUE the ordered work. The operator hears it in
   the next report, as a proposal with a recommendation.
5. **Otherwise** (reversible, own terrain, inside the order): do it and report.
A question ENDS the turn only when the next step of the order cannot proceed without the
answer AND the answer belongs to the operator — the instance names its list of
operator-only matters (goal, money, hardware, risk, external effect, release) in ONE place:
`.claude/rules/operator-only.json` (template in `core/templates/rules-instance/`). Operator decision
2026-10-16: only what really needs the operator goes to the operator; what can be settled cleanly
alone or between the AIs, is reversible and documented, the AI decides — in every brain. Not by
topic: a technical question can be a real choice. Per question, the comparative test: a
measurement or a reversible A/B test can decide it → run it and report; it rests on the
operator's experience, goal or taste → ask, with options and a recommendation. `core/scripts/decision-readiness.py` names at every session
start a brain where this cannot hold (rule not loaded, list missing, everyday commits and pushes
behind a permission dialog, or every check switched off).
Such a question is asked through the question tool, not as closing prose (`intelligence.md`,
"Presenting to the Operator").
**An order that names a condition is read with its condition** (operator decision
2026-10-16): "then", "after the answer", "once it is merged", "clear it with X" bind the
order to an event, and the event comes first — the sequencing word is the operator's
"not yet", not filler. Before the first expensive or externally effective step of such a
turn (a workflow, a fan-out of agents, a model run, a push, a PR write) the agent names the
condition and shows that it is met, or says why the word is no condition here. Carried by `core/helpers/conditional-order-gate.cjs` (PreToolUse); the
operator's own words for a condition are instance data (`.claude/rules/condition-patterns.json`).
Named cases (every other turn-end rule points here):
- **A hand step for the operator** (a command only they may run, a cable, a device): first
  finish the independent reversible work of the turn, arm the watcher on the step's effect,
  then end the turn with the command block as the closing message — only the closing
  message reaches the operator.
- **A remark the operator repeats** about an artifact (thinking-protocol #5): stop, mirror,
  get the yes through the question tool (sentence above) — that ends the turn.
- **A status message inside a long run** is a turn end like any other: allowed, but with
  the continuation armed first (`ScheduleWakeup` in a timed run, a watcher otherwise).

**Mechanically secured:** `core/helpers/mechanism-guard.cjs` (PreToolUse on
Bash/Monitor and Write/Edit) blocks shortcuts for which a documented path exists, and
demands either the process or an explicit `# MECHANISM-OK: <reason>` marker. Two sources
of rules: the instance's own (`.claude/rules/mechanism-rules.json` — rig, doc paths) and
the TOOL's own: a tool that is meant to be driven through its MCP server ships
`mechanism-rules.json` at its root naming its internals (IPC files, running its server by
hand, GUI drivers), and the guard finds it whether the tool arrives as a clone in
`.mcp.json` or as an enabled plugin. Every newly discovered shortcut gets added where it
belongs — the system learns, not just the agent. Not available = report, THIRD CASE above.
**A rule whose documented path is "agree it with the operator first" may demand the
operator's word behind the marker** (`needs_operator_word: true`, operator decision
2026-10-12): the justification must then quote the operator — the words in `"…"` or `„…"`
plus the date they were said — or point at a record file that exists (`path[:line]`);
otherwise the guard denies and names what is missing. A paraphrase is not a quotation. Rules without the field behave as before.
**A request to another machine names the defined path AS IT EXISTS THERE** — read how that
machine runs the tool (clone or plugin, version) before writing the steps; a step that only
works on the sender's setup turns the receiver's next move into improvisation.
```

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

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
Every brain runs the same released core. A mechanism that would help every brain — a
gate, a check, a hook, a script — is built IN the core (or in the owning suite) as a
PR, never as a local copy that works here and nowhere else. "Essential", in the
operator's word: a local fix is a fix nobody else gets, and a brain that runs its own
machinery measures a different system than its collaborators do.

Allowed deviations are DECLARED, with the reason, in `.claude/rules/local-machinery.json`:
- **instance** — machinery that can only live in this brain (it acts on this operator's
  hardware, services or projects). The entry says why AND names as `evidence` the
  instance-specific token the item relies on (a host, device, person or project name); the
  checker verifies the token is really in the item. "Not yet ported" is not a reason, and a
  reason without evidence is a self-declaration nobody checked. An item that relies on no token — a section of
  the instance's own rule files, a one-off measurement script — may name as `reach` the
  written reach analysis that judged it instead; the checker verifies the file names the item.
- **external** — a third-party skill or plugin used as it is (a vendored skill pack, an
  official marketplace plugin). Not ours to port to the core; the entry names its `source`.
- **alpha** — a development checkout under test, with an expiry date and what is being
  measured. Past the date: merge, extend with a reason, or unwire.

**A suite that ships as a plugin is consumed as the plugin** (operator order 2026-10-11). Its MCP server and
skills come from the marketplace on every machine; a clone of the suite feeds a brain only to
check a PR head, as a declared alpha with a date, and goes back afterwards. A suite's name is
not an instance identity token: it names shared tooling and cannot prove an item instance-only.
Carried by `core/scripts/local-machinery.py`, class `clone` (a suite clone wired as MCP server
or skill source while an added marketplace publishes that repo).

**A fork is not a place for work** (operator direction 2026-10-11: the core exists to give
everyone the same state; a time-boxed local alpha is how a new feature reaches it, but an
unnoticed drift away from it must not happen — the default is not to turn off, but to find
the common way and build on it). Core work happens on a branch IN the core repo — every
collaborator has write access there, so a branch is seen, gets CI and reaches the others;
a fork branch gets none of that and is forgotten. A brain consumes the core only from the
org repo at the released pin, never from a fork. Finished work is a PR in the repo;
everything else is a declared alpha with an expiry. Carried by `core/scripts/fork-drift.py` in the brain-scan's machine
checks: it names fork work that never reached the core and a core consumed from a fork.

**The finding addresses the AI, not the operator** (operator decision 2026-10-11). On every reported deviation the agent: (1) reads what the machinery
does and why it is local, (2) judges whether that makes sense, (3) decides — core-worthy =
open the core PR (or name the open one) and declare it as alpha until merged; instance-only =
declare it with the reason; obsolete = unwire. The declaration IS the written analysis. The
operator hears only what needs his decision under the instance's own rules.

**Mechanically carried:** `core/scripts/local-machinery.py` runs at every session start. A new carrier
type gets a planted case and a negative control in its fixture.
```

### A Needed Reload Is Not a Wait State (operator order 2026-08-06, sharpened 2026-08-14)

A change to a tool that only takes effect after the server reloads ends many turns with
"this needs a restart" — and then the agent waits for a human reply. That is a wait
state the agent can dissolve itself.

Moved 2026-10-20: the full wording, the watcher script and the boot-stamp contract stand verbatim in `docs/reload-watcher.md`; the rule file keeps the three rules in short form.

### Order Fidelity (Auftragstreue) (HARD)

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
1. **The assignment is the measure, not the activity.** Autonomy without a principal
   becomes self-occupation.
2. **No self-invented goals while an operator assignment is open.**
   Autonomous loops work through an **assignment list**; every item carries an origin
   marker (`von: Operator` | `abgeleitet`, i.e. derived — same semantics as the
   ledger fields `origin: operator | derived` above; both marker forms are valid,
   consumers match both). Derived items are **proposals** and need an OK.
3. **An empty list is a SUCCESS, not an emergency.** List empty → **report and
   stop**, don't refill. NORMAL CASE: assignment fulfilled → check-in with the
   operator. NARROW EXCEPTION only for the explicitly scheduled time-boxed run
   ("push through 2 h autonomously"): there, follow-up tasks may be derived — but
   only from a **reserve pool agreed beforehand** (criteria: documented as open ·
   doable without operator/hardware · no pending operator decision · same assignment
   space), which is not extended during the run.
4. **A workaround is a DEBT, not a checkmark.** Compromise → immediate entry "spec
   not fulfilled" with priority. Done is only what works **as specified**.
   **4a. GOAL SUBSTITUTION:** Rule 4 only fires when something is perceived AS a
   compromise. The more expensive case is the unnoticed rewriting of the GOAL
   ("build his rig" → "demonstrate his structure"). Mechanical trigger instead of
   good intentions: If a requirement names **concrete nouns with a number or proper
   name**, those are deliverables, not examples. Before ANY substitution: (a) state
   that a substitution is happening, (b) say why the original is not obtainable
   (attempted + attempt showable — not "wasn't lying around"), (c) **only then**
   keep building.
   **TOOL REACH ≠ SPACE OF POSSIBILITIES:** If a tool reads from a fixed location
   (library folder, preset directory, registry), that location is a **storage
   place**, not a catalog. If what is required is missing there, the question is
   "where do I get it", not "what do I take instead".
5. **"Additive" is NOT "harmless".** Do not build anything onto a user's operating
   surface that they did not order — not even "helpful" things. If something is
   missing: **propose, don't build.**
6. **Overall state beats single test.** A gate that only checks one's own change
   cannot see that the whole is broken. For artifacts with an operating surface:
   **target state as a file + check against it.**
7. **A question is not an approval; own notes are not orders; the machine is part of
   the order** (operator decision 2026-08-18). When the operator asks what a plan
   MEANS, it is not ordered yet: answer, then wait. A ledger or memory entry proves
   that the TOPIC came from the operator — never its scope, time or machine; those are
   asked, not filled in. For hardware-bound tools, settle WHICH machine first.
8. **Test material comes from the order, never from the disk** (operator decision
   2026-09-25): the operator's own files are used only when named or already part of
   the running order. A test that needs more material asks which — it does not search
   the disk and pick.
9. **An ordered audit orders its clear fixes** (operator decision 2026-09-02): clear
   (one correct version) plus safe (reversible, no live system, no shared carrier) =
   do it, do not present it. Structural changes against a documented operator decision
   stay proposals.
10. **What the operator just criticised is not re-released unseen** (operator decision
    2026-08-19): the corrected iteration waits for the operator's review.
```

### Working Across Parties

(operator order 2026-10-11, after a hand-over
   between the operator's own machines lay unseen until the operator asked on every side)

(operator correction 2026-10-11: "you crossed each other
   there for nothing — that costs time")

Measured the day the rule was written: one finding,
   two fixes from two machines three minutes apart (one closed), and a merge over the finding
   because a reader showed 200 characters of the comment.

Wording before the context diet of 2026-10-20, verbatim. The rule file now carries the condensed rule; this is the past state it was condensed from.

```text
For brains that share carriers (core, suites, shared memory) with other operators and
their AIs:

1. **Name the party, never a role word** (operator decision 2026-09-12): with more than
   one collaborator, "the colleague", "the other side" or "the other session" identifies
   nobody — use the proper name. The person and their AI are named apart ("<name>" vs.
   "<name>'s AI"): a proposal of an AI is not a decision of its person. Machine ids stay
   in data fields; a git author is no proof of the party (accounts can look alike).
   **One login can carry several instances** (operator order 2026-10-11):
   every PR, comment and review an AI posts carries its instance key
   (`<!-- instance-key: … -->`, a hash, names nobody — `core/helpers/instance-key-gate.cjs`
   refuses the post without it), and every check that decides "is this mine?" decides by
   login AND key (`core/scripts/instance_key.py`). A PR from a sibling instance under the same
   login is a hand-over to us, not our own.
2. **Responsibility is assigned only by the operator** (operator decision 2026-08-19). An
   assignment is STATE with a date — measure it (`core/scripts/parallel-sessions.sh`, the
   shared-memory record) before leaving work out, never recall it (2026-08-21). A new
   domain inherits no owner.
3. **The owner of a domain decides its domain questions** (operator decision
   2026-09-06): a technical question in another party's domain is neither pre-decided
   here nor put to this operator — it goes to that party, or is decided together later.
4. **Judge the sum, not the single change** (operator decision 2026-08-31): what counts
   is what all of this side's changes together mean for the other party — four small
   interventions are one big one.
5. **One finding, one builder** (operator correction 2026-10-11). Whoever reports a finding on a PR says in the same
   comment whether they build the fix ("PR follows" / "the author's" / "open for anyone").
   Whoever wants to build a fix for SOMEONE ELSE's finding first reads the repo's open PRs
   (`gh pr list --state open`) and the thread: an existing PR or a claim means counter-check,
   not build; nothing there means one line in the thread ("building it"), then build. And
   nothing is merged over an open finding in its thread — read the comments in full, never
   through a tool that cuts them short.
6. **An operator may hand the AI side of their brain to another party's AIs** (operator
   decisions 2026-10-16/18). Recorded in the shared memory (who hands over, to whom, what stays
   with the operator). In this order: first the brain's AI decides whatever it can and may
   itself (ASK OR ACT, as always); only what it cannot goes on, by one test — does it need a
   human at that machine, or judgement about the core and AI mechanics? (a) **Own terrain,
   reversible** (tidy-ups, memory, local branches, commits and pushes to that brain): the
   brain's AI decides and reports. (b)
   **A human at that machine** (a permission dialog, a push or merge only their hand can trigger,
   writes at their devices, their domain, money, hardware, anything time-critical while the
   receiving side is not active): their operator, directly — never parked on the receiving side.
   (c) **Core and AI mechanics** (rule interpretation, gates, skills, hooks, deep checks, what
   touches several brains, reviews): the receiving AIs decide, through the shared memory; no
   answer the same day = the safe default or leave it, never the human instead. Sending a (c)
   question to the human who handed it over is the defect this item closes; the handover is
   data in the shared memory's `parties.json` (`ai_handover`), and its lint names such a
   referral when it is written.
```

## rules/intelligence.md

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

### Repeat Runs (CANONICAL place — skills point here)

(measured 2026-08-04: a register reported
"24 raw → 18 consolidated" and derived a gap from it, while the record said
108 → 19 → 12; the supposedly missing findings had been discarded in verify)

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
