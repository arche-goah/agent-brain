---
name: session-insights
description: Self-analysis of Claude Code sessions. Which skills fire? Which patterns? What could be better? Inspired by /insights from the jens.heitmann reel.
triggers:
  - insights
  - session analyse
  - session analysis
  - claude usage report
  - workflow analyse
  - workflow analysis
  - was hat gefeuert
  - what fired
  - skill usage
  - post session learning
---

# Claude Insights Tracker

Self-analysis for Claude Code sessions. Inspired by the `/insights` command from the **jens.heitmann** reel (DW43RJUkVp2). Own implementation, since the original command is presumably a custom skill.

## When to use
- **Post-session learning** — automatically via `.claude/rules/intelligence.md`
- "What did we do today?" questions
- Skill-optimization sessions
- When a workflow repeats 3x → package it into a skill

## Pipeline

### Step 1: Read session data
- `git log --oneline --since="X hours ago"`
- Current conversation
- Memory-file updates

### Step 2: Pattern detection
- Which skills fired?
- Which tools were used? (Read, Write, Bash, Agent)
- Which files were created/edited?
- Which problems came up? (3-loop errors, corrections)

### Step 3: Insights report
```markdown
# Session Insights — {timestamp}

## What was done
- [Action 1]
- [Action 2]

## Skills that fired
| Skill | Context | Success |

## Skills that SHOULD have fired but did not
- [Skill] — [why it would have fit]

## Recurring patterns
- [Pattern] — already Xx in recent sessions

## Improvement suggestions
1. [Concrete]

## Corrections by the operator
- [What] → add to `.claude/rules/feedback.md`?
```

### Step 4: Persist
- Save: `memory/session_{YYYY-MM-DD}.md`
- Update the `MEMORY.md` index

### Step 5: Auto-trigger
In `.claude/rules/intelligence.md`: on session end → run automatically.

## Related skills
- `memory-dream`
- `verification-before-completion`
