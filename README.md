# agent-brain

The shared core of a multi-instance Claude-Code "brain" setup: everything independent,
private brains need in common — and nothing instance-specific. This repo is a fresh cut
of a privately grown core (2026-08-13); history starts here on purpose. The plugin it
ships keeps its original name `brain-core`, so skill references in consuming brains
(`brain-core:<skill>`) stay valid.

## One repo, two channels — no file travels twice

| Channel | Delivers | Why this channel |
|---|---|---|
| **Plugin** `brain-core` (via a marketplace repo that pins a tag of this repo) | `skills/` (22 general-purpose skills), `output-styles/caveman.md` | one-command install, auto-update, namespaced, no symlinks |
| **git submodule `core/`** | `CONVENTIONS.md`, `core-contract.json`, `rules/`, `helpers/`, `scripts/`, `templates/`, `workflows/` | exactly what a plugin cannot deliver: CLAUDE.md content, settings/hook wiring, contract scripts that must run from a checkout |

Both consumers look the same: a private brain repo as working directory, `core/` as
submodule, core skills from the plugin. Comparability comes from identical structure,
not discipline.

## Consuming it

New brain: `scripts/bootstrap-brain.sh <target>` (creates a private brain from
`templates/`, wires the submodule and the marketplace).

Existing brain: add the submodule, wire `.claude/settings.json` from
`templates/settings.json` (replace the example marketplace with your own), enable the
plugin, delete your local copies of what the core now delivers.

Weekly sync (never on a show day):

```
bash core/scripts/brain-update.sh
```

One command: refreshes the marketplaces, updates every enabled plugin (verifying
cache provenance against the pin), puts the `core/` submodule on the pinned tag —
healing the submodule remote and `.gitmodules` after a repo move — and refreshes
`ecosystem.json`. Not `git submodule update --remote core`: that tracks `main`,
not the released pin.

## Rules of the ecosystem

`CONVENTIONS.md` is the contract prose, `core-contract.json` the machine-readable half,
`scripts/suite-check.py` the enforcement. Before anything is handed over:
`scripts/handover-gate.sh` from the instance root. Core changes are PRs against this
repo — never local edits in a submodule checkout (§13).

## Deliberately NOT in here

- Instance data: memories, feedback rules, rig/show/venue configs, ecosystem.json.
- The Anthropic document skills (docx/pdf/pptx/xlsx — proprietary license) and the
  superpowers pack (third-party): both come with your own Claude Code installation.
- Tool domains (lighting desks, network rigs, show tools): each lives in its own
  suite repo. A new capability never starts here (§11).
- Maintainer-internal tooling (PR watchdog, org release plumbing): lives in a
  private maintainer plugin, not in the shared core.
