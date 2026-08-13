# Working Rules & File Conventions (Core)

> CORE VERSION: only the mechanics that apply to EVERY brain. Instance parts
> (folder mapping, tool paths, rig tables) live in the instance rule file of the
> respective brain (`.claude/rules/arbeitsregeln-instanz.md`, from `templates/`).

## Working Rules

1. **Act proactively** - don't ask, do. Work through to the end. **Within the granted
   assignment and the defined paths** — the assignment space itself is never expanded
   on one's own authority (boundary: order fidelity (Auftragstreue) #5, mechanism
   discipline).
2. **Pragmatism > perfection** - no half measures.
3. YOU MUST **NEVER endanger social accounts** - only official APIs, never
   post/delete/change on your own authority.
4. **Skills ALWAYS fire automatically** - never wait for slash commands. Scan all
   skills semantically.
5. **Parallel agents** for 2+ independent tasks that are each substantial in their
   own right (observe the cost/model-routing rule in `rules/intelligence.md`
   — multi-agent costs ~15x chat tokens); small stuff sequentially in the session.
6. **Existing files:** ALWAYS read first, then edit.

## File Rules

**Naming:** kebab-case, lowercase, English, no umlauts/spaces.
**Root files:** Only README.md, CLAUDE.md, LICENSE, .gitignore, .gitattributes,
.gitmodules, .mcp.json, .env, .env.example (the instance may extend the whitelist,
never silently).

**Invariant behind the two dot files:** *What git itself necessarily creates in the
repo root, a whitelist cannot forbid.* `bootstrap-brain.sh` writes `.gitattributes`
into every new brain (line-ending class), and it MUST live in root so the rule
applies repo-wide; `.gitmodules` is created by git as soon as the same script mounts
`core/` as a submodule (`bootstrap-brain.sh`, `git submodule add`) — the location is
dictated by git and cannot be moved. Both stood in opposition to the rule that
produces them.

YOU MUST comply with these rules:
- NEVER place files in root (except the whitelist above)
- NEVER create duplicate docs (first check whether one exists)
- NEVER use code fragments as file names (flex, mb-6, BigInt(0), void)
- Delete junk files immediately when discovered

The folder mapping (what goes where) is instance knowledge — table in the instance
rule file.

## Session Traceability (3 layers)

1. **Verbatim:** Claude Code transcripts, long retention (`cleanupPeriodDays`).
2. **Chronology:** `docs/maintenance/session-log.md` — per session close 2-4
   semantic index lines (topic, decisions with pointer, loose ends).
3. **Distillate:** document decisions domain-keyed (why + what was discarded, in the
   domain's change log); pillar decisions ADDITIONALLY in
   `docs/maintenance/decision-log.md`.

**Audit rule:** session-log + decision-log are PROTOCOLS, not a fact-knowledge base —
append-only history, never "clean up"/consolidate, never treat facts from them as
current state.

## Project Work Ledgers (operator decision 2026-08-13)

How project work (todos, intermediate states, decisions) is tracked, so that every
instance and every colleague files it the same way and lists stay compatible:

1. **One hand-maintained detail list per project domain**, in the PRIVATE instance
   repo (`docs/<domain>/offene-punkte.md` or the instance's equivalent) — NEVER in
   the project/tool repo itself. Operator orders, hardware context and intermediate
   states are instance knowledge; project repos may become public (tool/instance
   split). Every entry carries four fields:
   - `id:` stable slug — referencable, survives rephrasing
   - `klasse:` todo | entscheidung | lektion (decision | lesson)
   - `reichweite:` projekt | brain | shared (reach — see 3.)
   - `von:` operator | derived (derived = proposal, needs an OK)
2. **Every overview above the detail lists is GENERATED, never hand-maintained.**
   A second hand-kept list drifts — measured repeatedly. Aggregation is a script's
   view over the registered detail lists, not a document anyone edits.
3. **`reichweite: shared`** marks an entry for the org's shared-memory repo as soon
   as more than one brain works the project: exported as one-file-one-fact WITH a
   back-reference to the source `id`. The export is a deliberate act at session
   close (leak discipline) — nothing propagates itself.
4. **Decisions are pointers, not copies.** The full why lives in the domain change
   log / decision log (Session Traceability above); a `klasse: entscheidung` entry
   only references it. No second maintenance.
5. **The brain's own maintenance/scan order list carries ONLY brain-function work**
   (consistency, carriers, audits). Domain work in the brain list — or brain work in
   a domain list — is misfiled and gets moved, not tolerated.

Which domains exist and where their lists live is instance knowledge (folder table
in the instance rule file).

## Mechanism Discipline (HARD)

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
if the result would be clean. The three questions above do NOT catch this: a cleanly
built second path passes all three — and is still wrong, because the question
"should a second path exist here at all?" is never asked.

**THE REQUIRED OUTCOME is binary:** either **"I find the prescribed defined path and
take it"** — or **"there is no defined path" → it gets DISCUSSED.** A third case does
not exist. No "I'll quickly do it differently and mention it": the questioning must
come FROM THE AGENT, BEFORE acting.

**Mechanically secured:** `core/helpers/mechanism-guard.cjs` (PreToolUse/Bash) blocks
shortcuts for which a documented path exists, and demands either the process or an
explicit `# MECHANISM-OK: <reason>` marker. The rules for it are instance knowledge:
`.claude/rules/mechanism-rules.json` (every newly discovered shortcut gets added
there — the system learns, not just the agent).

## Order Fidelity (Auftragstreue) (HARD)

1. **The assignment is the measure, not the activity.** Autonomy without a principal
   becomes self-occupation.
2. **No self-invented goals while an operator assignment is open.**
   Autonomous loops work through an **assignment list**; every item carries an origin
   marker (`von: Operator` | `abgeleitet`, i.e. derived). Derived items are
   **proposals** and need an OK.
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
