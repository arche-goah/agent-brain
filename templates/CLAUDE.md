# CLAUDE.md - <your-brain-name>

> Heart of the setup, loaded every session. Bootstrapped from agent-brain/templates
> — core rules come from `core/` (submodule), core skills from the
> brain-core plugin. ONLY instance things live HERE: who you are, your projects,
> your rigs, your rule additions.

## Core (comes from agent-brain — changes only as branch + PR, never on the consumed state)

The core rules are loaded here via @-import (Claude Code memory imports —
do NOT delete them, otherwise the rules only sit on disk instead of in context):

@core/rules/thinking-protocol.md
@core/rules/techniques.md
@core/rules/arbeitsregeln.md
@core/rules/intelligence.md
- Hooks/helpers: `core/helpers/` (wired up in `.claude/settings.json`).
- Contract: `core/CONVENTIONS.md` + `core/core-contract.json`. Core changes go
  as a PR against `agent-brain`, NEVER as a local copy (CONVENTIONS §13). The short
  path: feature branch directly in the submodule `core/` — the submodule is a
  full checkout. Only the consumed state (pin/main) is off-limits; `file-guard`
  blocks edits there mechanically.
- Core update: `bash core/scripts/brain-update.sh` — one command, follows the
  marketplace pin on every layer (plugin cache with provenance check, submodule
  remote, `.gitmodules`, tag). Recommended weekly, never on a show day. NOT
  `git submodule update --remote core`: that tracks `main`, not the released pin —
  and after a core repo move it resolves the OLD repo's main.

## Instance rules (yours — additions to the core, not a replacement)

- `.claude/rules/arbeitsregeln-instanz.md` — folder mapping, tool paths, language.
- `.claude/rules/intelligence-instanz.md` — auto-fire table (pattern → skill).
- `.claude/rules/feedback.md` — the operator's preferences/corrections (BINDING).
- `.claude/rules/mechanism-rules.json` — rules for the mechanism-guard.

## Person & Goal

<!-- Who are you, what is the goal of this brain? 3-5 lines. -->

## Project Structure

> ILLUSTRATION, not a norm. Authoritative are: the folder mapping in
> `.claude/rules/arbeitsregeln-instanz.md`, the root whitelist in
> `core/rules/arbeitsregeln.md`. If either of those changes, the new state applies
> THERE — this tree does not become a second source (same rule as for the
> auto-fire table).

```
<your-brain>/
|-- <root files>   # root whitelist: see core/rules/arbeitsregeln.md (no separate list here)
|-- core/          # agent-brain submodule (edits only on a feature branch — file-guard enforces this)
|-- docs/          # your docs (maintenance/ with session-log.md + decision-log.md)
|-- config/        # your configs (ecosystem.json!)
|-- scripts/       # your utility scripts
|-- src/           # your code
`-- .claude/       # rules (instance) / skills (instance skills ONLY) / settings.json
```

## Ecosystem

`config/ecosystem.json` = which state of which suite runs here (repo × commit ×
version × requires_core). Maintenance: `python3 core/scripts/ecosystem-sync.py --write`.
Before every hand-over/take-over: `core/scripts/handover-gate.sh`.

## Memory

Auto-memory (`~/.claude/projects/<munged-project-path>/memory/`) is loaded every
session. Limits: MEMORY.md max 200 lines / 25 KB.
