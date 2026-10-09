# Brain-Scan Checklist (target state)

> The brain-scan workflow (`core/workflows/brain-scan.js`) audits this brain AGAINST this
> file. It is instance knowledge: the structure below is the shared shape every brain of the
> ecosystem scans against, so that two brains' scan reports are comparable; the items under
> each section are yours — add, remove and sharpen them as your setup grows. Sections and
> the state model stay; the rest is yours.
>
> Lives at `docs/maintenance/brain-scan-checklist.md`.
>
> **What a scan does with this file** (operator decisions 2026-10-09, after an audit of the
> audit process): it first states what became of the LAST run's findings (done / decided /
> dropped / still open / vanished — `core/scripts/brain-scan-prep.py`, deterministic), then
> runs the machine checks (sections 0, 9, 10 and the boundary between instance and core),
> then the agents check sections 1-8. It reports and sorts, it never fixes: every finding
> leaves with exactly one exit (done already · the AI does it · the other side · parked ·
> later at the system · drop · operator decision — skill `backlog-catch-up`), at most three
> operator decisions are presented, and a finding seen a third time without a fix is a
> decision, not another line. Fixing happens in the session with the operator.
>
> **Every section has an executor** — a section nobody runs is a wish, measured twice. If you
> add a section, give it one in `core/workflows/brain-scan.js` (`SECTION_EXECUTORS`); the
> core fixture fails on a template section without one.

## 0. State model: `configured` vs. `verified`

Every item below reaches one of two states, and the report names which:

| state | meaning | reached by |
|---|---|---|
| `configured` | the prerequisites exist (file, entry, syntax, schema) | reading / parsing |
| `verified` | a DECLARED behaviour check RAN and returned the expected result | executing / measuring |

A section states which behaviour check it declares. A section that declares none can never
exceed `configured`, and the report says so — presence is not effect.

## 1. Permissions & security

**Behaviour check:** none declared (a real one would provoke a forbidden call and observe
the deny — not from the scan, the scan is read-only). → maximum `configured`.

- [ ] No wildcard grants (`Edit(**)`, `Read(**)`) in `.claude/settings.json` / `.claude/settings.local.json`.
- [ ] Deny list covers at least: `.env*` (read + edit), `.claude-state/**` (EDIT only — the mechanisms write their measurement logs there and session-close must read `promises.jsonl`; a read deny blocks that while an edit deny is what protects the logs), and every secret-carrying file of this instance.
- [ ] No script that is both Bash-allowlisted AND editable without a prompt (write-then-execute). Name deliberate exceptions here, with the reason.
- [ ] No secrets in plain text in `.mcp.json`, tracked configs, or new commits (`python3 core/scripts/leak-scan.py --root .` — without `--root` it scans the core checkout, not this brain).
- [ ] No `npx` MCP server on `@latest` in `.mcp.json` — every one carries a fixed version (`npm view <pkg> version` on the day it was set; bump deliberately). *(mechanical: `grep -n '@latest' .mcp.json` must be empty)*

## 2. Skills

**Behaviour check:** `python3 core/scripts/skill-lint.py` exits 0.

- [ ] `skill-lint.py` runs with exit 0 (covers frontmatter, registry count, listing budget mechanically).
- [ ] Every skill has YAML frontmatter with `name` (kebab-case, == folder name) and `description`.
- [ ] `REGISTRY.md` count == real skill count (directories + symlinks with `SKILL.md`).
- [ ] Every symlink into a tool suite resolves.
- [ ] The auto-fire table lives ONLY in `.claude/rules/intelligence-instance.md` — no second copy anywhere.

## 3. Hooks & settings

**Behaviour check:** `bash core/scripts/brain-selftest.sh` ends with "everything that has a proof passed it"; `python3 core/scripts/brain-friction.py` reports no contradiction between mechanisms.

- [ ] `.claude/settings.json` is valid JSON and every registered hook event is a valid Claude Code event.
- [ ] Every hook script exists; its stdin/output schema matches the current hook API (spot check: echo test).
- [ ] Stop checks are registered in `.claude/rules/stop-checks.json` only — `settings.json` carries the dispatcher, never a second check.
- [ ] `timeout` values are plausible (seconds, not milliseconds) and the session-start hook finishes inside its timeout (measure it; a killed bootup reports nothing).
- [ ] Every mechanism that shapes behaviour hangs on a MECHANISM (hook, gate, lint), not on prose — a rule that exists only as text is a finding.
- [ ] Hooks that inject FOREIGN text into the context (file contents, git lines, task lines) frame it as data and sanitise it.

## 4. Docs vs. reality

**Behaviour check:** none declared. → maximum `configured`.

- [ ] `CLAUDE.md`: every tool/version claim spot-checked (`which` / `--version`).
- [ ] Model names in `CLAUDE.md` / rules == the family actually available.
- [ ] `CLAUDE.md` under 200 lines (guideline; exceeding it is a finding, not an auto-fix).
- [ ] Every referenced file exists (structure diagram, mandatory references, session-start checks).
- [ ] The MCP table in `.claude/rules/intelligence-instance.md` == `.mcp.json`, both directions.

## 5. Memory

**Behaviour check:** `python3 core/scripts/memory-lint.py` exits 0.

- [ ] `memory-lint.py` runs with exit 0 (index, frontmatter, links, limits, snapshot).
- [ ] `MEMORY.md` under 200 lines / 25 KB — the harness reads nothing past that.
- [ ] No index entry line over 400 characters (`memory-lint.py` limits — measured to fire on a real brain; an index line that carries the lesson instead of pointing at the file is what pushes MEMORY.md to its cap).
- [ ] Every memory file is linked from `MEMORY.md` or from a topic sub-index `index-<topic>.md` that `MEMORY.md` links.
- [ ] The repo snapshot (`docs/memory-snapshot/`) matches the live memory (`core/helpers/memory-sync.cjs export`).

## 6. Git & repo hygiene

**Behaviour check:** the `git` / `du` queries are measurements of the real state → `verified`.

- [ ] `main` is pushed; no branch carries work that exists nowhere else.
- [ ] The repo root holds only the whitelist (`core/rules/working-rules.md` plus the instance extension) — anything else is a finding.
- [ ] No junk tracked or lying around: `.DS_Store`, `__pycache__`, large log folders, built artefacts.
- [ ] No new binaries over 5 MB in git.

## 7. SOTA delta (web, lightweight)

**Behaviour check:** none possible (claims by others about other systems) → at most `configured`, every claim with a source. A delta becomes `verified` only when it is re-measured in this setup — and then in the affected section, not here.

- [ ] Claude Code changelog since the last scan: breaking changes or features that break setup assumptions (hooks API, skills budget, permissions, memory limits).
- [ ] MCP spec / security: new CVE patterns or deprecations that touch the servers this brain runs.

## 8. Shared memory (if this brain takes part)

**Behaviour check:** `python3 core/scripts/shared-memory-lint.py --repo <shared repo>` exits 0.

- [ ] The shared-memory clone exists, is on `main`, and has no uncommitted or unpushed changes at session close (the close hook reports it).
- [ ] Every entry this brain wrote carries `von` / `audience` / `topic` / `date` (README convention of the shared repo).
- [ ] The session-start check reads what is new by topic since the last look (`shared-memory-check.sh` line present at bootup).
- [ ] No request addressed to this brain stays unanswered: `shared-memory-inbox.py --open` lists 0, or every listed request has a dated note why it waits.

## 9. Invariant register (if this brain keeps one)

**Behaviour check:** `python3 core/scripts/invariant-check.py docs/maintenance/invariants.md`
— run by the scan's machine step, never by an agent. → `verified`.

- [ ] No drift: no new, changed or vanished site in any registered search.
- [ ] Every class whose verdict is "MECHANISM due" is a finding with an exit — the register's
  own report is read by nobody else.

## 10. Self-check

**Behaviour check:** `bash core/scripts/brain-selftest.sh` (every mechanism with a proof
passes it), `core/scripts/local-machinery.py` (behaviour carried outside the core is
declared, with reason and evidence) and `core/scripts/commitments.py` (no promise about
future behaviour lives only in chat since the last scan) — all run by the machine step. A
script missing from an older core is reported once as "not available". → `verified`.

- [ ] The self-test passes; a crash of a check reads as a crash, never as a clean run.
- [ ] Every hook, script or rule that runs outside the core is declared as instance machinery
  or as an alpha with an expiry.
- [ ] No loose commitment since the last scan.

## Deep check (recommendation, never started by the scan)

The machine step writes one line per triggered deep check into the report, with the reason
and the price measured on the proving brain: `coherence-scan` (five or more new dated rule
lines since the last coherence register, or a finding back a third time), `memory-dream`
(memory index at 90 % of its limit), `full-audit` (an open order-list entry carrying the
token `rebuild-ahead`). The AI tells the operator — what, why now, the price — and starts
nothing on its own.
