---
name: memory-dream
description: Memory hygiene and maintenance - merge duplicates, resolve contradictions, update stale info, compress index, optimize CLAUDE.md
triggers:
  - memory dream
  - memory aufraeumen
  - memory cleanup
  - dream
  - aufraeumen
  - cleanup
  - deduplizieren
  - deduplicate
---

# Memory Dream - Memory Hygiene & Maintenance

Inspired by Claude Code's /dream command. Automatically cleans, optimizes, and maintains the memory system and CLAUDE.md.

**Workflow variant (since 2026-08-01, building block for full-audit):** The analysis
part (steps 1-2 + findings collection) is formalized as `core/workflows/memory-dream.js` —
STRICTLY read-only, writes `docs/research/memory-dream/report-<date>.md` with proposals.
Fixes (steps 3-7 below) run ONLY after operator OK, or when the operator explicitly
triggers "aufraeumen" (clean up) / "dream" — and even then: never edit the snapshot
directly, changes go via auto-memory + memory-sync export.

## When to use
- Memory index (MEMORY.md) approaching 200 lines
- Suspected duplicate or contradictory memories
- After intensive sessions with many new memories
- Regular maintenance (recommended: weekly)
- User says "aufraeumen" (clean up), "dream", "memory cleanup"

## Pipeline

### Step 1: Audit Memory Index
Read the MEMORY.md index file. Check:
- Total line count (warn if >150, critical if >200)
- Broken links (files referenced but don't exist)
- Orphan files (exist in memory/ but not in MEMORY.md)

### Step 2: Read All Memory Files
Read every .md file in the memory directory. For each check:
- **Duplicates**: Two files covering the same topic
- **Contradictions**: Conflicting information between files
- **Stale info**: Relative dates ("next week", "soon"), outdated facts
- **Too vague**: Memories that don't provide actionable context

### Step 3: Merge Duplicates
If two files cover the same topic:
1. Merge content into the more comprehensive file
2. Delete the redundant file
3. Update MEMORY.md index

### Step 4: Resolve Contradictions
If files contradict each other:
1. Check which is more recent
2. Verify against current codebase state
3. Keep accurate version, update or remove the other
⚠ **Limit (kohaerenz-scan principle, 2026-08-01):** Applies only to FACT
contradictions (IPs, paths, statuses). If RULES contradict each other (type:feedback,
HARD rules): ONLY report — which rule wins is decided by the operator, never by
maintenance.

### Step 5: Update Stale Info
- Convert relative dates to absolute dates
- Check if referenced files/features still exist
- Update project status if changed
- Remove completed/irrelevant project memories

### Step 6: Compress Index
Ensure MEMORY.md stays concise (norms = brain-scan checklist, canonical):
- Each entry max 400 characters (checklist limit; previously "150" here — superseded)
- Remove entries for deleted memory files (then run `memory-sync.cjs prune` for the snapshot)
- KEEP the curated order (⭐ priorities, thematic grouping) — do NOT alphabetize,
  do not re-sort by type

### Step 7: Audit CLAUDE.md
Check CLAUDE.md:
- Project structure matches actual filesystem
- Skill count is accurate
- Links and references still valid
- No outdated information

### Step 8: Report
```
## Memory Dream Report
- Files audited: X
- Duplicates merged: X
- Contradictions resolved: X
- Stale entries updated: X
- Orphan files cleaned: X
- MEMORY.md lines: X/200
- CLAUDE.md issues found: X
```

## Trigger (clarified 2026-08-01)
- User says "aufraeumen" (clean up) or "dream" · after sessions with 3+ new memories · MEMORY.md > 150 lines
- **Before a repeat run:** `core/rules/intelligence.md` → "Repeat Runs"
  (repeat runs: read the artifacts of the last run → 14-day freshness → only then start).
- Only the ANALYSIS may run automatically (read-only workflow → report).
  **Fixes NEVER run automatically** — even on a casual "aufraeumen", first show the
  report, then wait for operator OK (order fidelity; rule contradictions are in any
  case operator-only, see step 4).
