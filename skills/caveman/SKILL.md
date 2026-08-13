---
name: caveman
description: >
  Level switching for caveman mode (lite | full | ultra | wenyan-*). The mode itself is
  PERMANENTLY active as an output style in every brain with the brain-core plugin enabled —
  not via this skill.
  Use when user says "/caveman <level>", "caveman lite/ultra", "wenyan", or asks what the
  mode is. NOT needed to turn caveman on (runs by itself from session start).
---

# Caveman — Level Switching

**The rules do NOT live here.** Canonical source: `core/output-styles/caveman.md` in the
agent-brain repo, delivered via the **plugin channel**. It takes effect through
`force-for-plugin: true` in that file's frontmatter: the style applies as soon as the plugin
is enabled, and it overrides a deviating `outputStyle` setting of the instance.

**`.claude/settings.json` is NOT the mechanism** and `.claude/output-styles/` is
NOT the source. Both stood here until 2026-08-04 and were wrong: on Windows the style
reached not a single response via the settings route, and a second style file under
`.claude/output-styles/` is explicitly withdrawn — whoever creates one builds exactly the
divergence this paragraph is meant to prevent.

Why an output style at all (2026-08-02, after an incident): the mode previously existed
only as a prose instruction in CLAUDE.md and was overlooked at session start — an
instruction in context is not a mechanism. The output style is the frame itself and cannot
be forgotten.

## What this skill still does

Switch the level. Default is **full**.

| Call | Effect |
|--------|---------|
| `/caveman lite` | No filler/hedging, but whole sentences + articles |
| `/caveman full` | Default: articles dropped, fragments OK, short synonyms |
| `/caveman ultra` | Additionally drops conjunctions where unambiguous; each fact stated once |
| `/caveman wenyan-lite\|-full\|-ultra` | Classical-Chinese register variants |

The level holds until the next change or session end. The complete definition of each
level incl. examples is in `core/output-styles/caveman.md` — when in doubt, read there,
do not add material here (single source).

**Off:** "stop caveman" / "normal mode" — applies only to the running session; the next
one starts with caveman again.
