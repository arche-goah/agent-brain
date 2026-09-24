# Brain-Scan Checklist (target state)

> The brain-scan workflow (`core/workflows/brain-scan.js`) audits this brain AGAINST this
> file. It is instance knowledge: the structure below is the shared shape every brain of the
> ecosystem scans against, so that two brains' scan reports are comparable; the items under
> each section are yours — add, remove and sharpen them as your setup grows. Sections and
> the state model stay; the rest is yours.
>
> Lives at `docs/maintenance/brain-scan-checklist.md`. Fixes found by a scan are NOT applied
> from here — they go to `brain-scan-auftraege.md` and run only with the operator's marker.

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
- [ ] Deny list covers at least: `.env*`, `.claude-state/**`, and every secret-carrying file of this instance.
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

## 6. Shared memory (if this brain takes part)

**Behaviour check:** `python3 core/scripts/shared-memory-lint.py --repo <shared repo>` exits 0.

- [ ] The shared-memory clone exists, is on `main`, and has no uncommitted or unpushed changes at session close (the close hook reports it).
- [ ] Every entry this brain wrote carries `von` / `audience` / `topic` / `date` (README convention of the shared repo).
- [ ] The session-start check reads what is new by topic since the last look (`shared-memory-check.sh` line present at bootup).
