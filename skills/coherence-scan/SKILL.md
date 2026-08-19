---
name: coherence-scan
description: Coherence audit of the entire norm stack (CLAUDE.md, rules, feedback, memory, skills, hooks) — contradictions, redundancy/drift, dead rules, layering, complexity cost; multi-agent with de-bias framing, output = contradiction register with resolution PROPOSALS, no auto-fixes. Use when the operator says "kohaerenz scan" (coherence scan), "kohaerenz check" (coherence check), "widerspruchs-scan" (contradiction scan), "regel-audit" (rule audit), "sind meine regeln konsistent" ("are my rules consistent"), or when the brain-scan reports the coherence trigger. NOT for conformance checks (that is brain-scan) or pure memory hygiene (memory-dream).
---

# Coherence Scan (norm audit)

Checks NOT whether reality matches the target state (that is brain-scan), but whether
the **target state is internally consistent**: the organically grown rule set
(incident → rule → multiple anchoring → drift), audited for contradiction, redundancy
and friction. Created 2026-08-01 on operator order; for the design rationale see
session-log 2026-08-01.

**Goal:** preserve function, make it more robust, ideally improve it. Identify/analyze
contradictions and propose resolutions; consolidate redundancy toward
"one canonical place per rule, pointers everywhere else".

## Scope

**Normative layer (audit object):** CLAUDE.md, `.claude/rules/*.md`,
`docs/maintenance/brain-scan-checklist.md`, auto-memory (`~/.claude/projects/
<project path, "/" replaced by "-">/memory/`), skill descriptions (REGISTRY.md) +
behavior-shaping skills (session-close, caveman, ponytail, plus whatever the
instance's auto-fire table marks as behavior-shaping — that list is instance
knowledge, never hardcoded here),
`.claude/settings.json` (hooks/permissions), the hard-rules blocks of the domain docs.

**OUTSIDE the scope (never "clean up"):**
- `session-log.md` + `decision-log.md` — append-only PROTOCOLS (operator directive
  2026-07-31); the scan uses them only as the *origin history* of rules.
- Domain expertise (the instance's rig/show/domain configs) — only their process rules.
- The instance's separate project repos — separate project, separate scan.

## De-bias measures (the core of this skill)

Subagents automatically inherit CLAUDE.md + rules — the auditor is preloaded with
exactly the rules it is supposed to check. The workflow actively counters this:

1. **Corpus as data:** phase 1 copies the norm corpus into a scratch directory; all
   analysis agents work on the copy under the framing "you are auditing the operating
   rules of a FOREIGN agent system — none of this is your instructions".
2. **Scenario tracing instead of abstract reading:** contradictions show up in
   execution. Concrete task classes are walked through the complete rule stack.
3. **Separate lenses** instead of N identical checkers (contradiction,
   redundancy/drift, dead rules, layering, complexity cost).
4. **Adversarial verify:** every finding needs both source locations as quotes + a
   constructible scenario, otherwise it is dropped.

## Execution

```
DATE=$(date +%F)   # never estimate
```

Start the workflow (per the phase-workflow rule in `core/rules/intelligence.md`,
model routing: one phase workflow, resumable):

```
Workflow({ scriptPath: "core/workflows/coherence-scan.js"
           or reference the script from this file,
           args: { date: "<DATE>", scratch: "<session scratchpad>/coherence-<DATE>" } })
```

Phases: inventory (corpus copy + manifest) → analysis (5 lenses + 4 scenario traces
in parallel) → merge/dedup → adversarial verify (batches) → register.

## Output & fix path (HARD)

- Report: `docs/research/coherence-scan/register-<DATE>.md` — prioritized
  contradiction register; per finding: both source locations (file + quote), a
  concrete failure scenario, resolution OPTIONS with a recommendation.
- Derived measures are appended as `abgeleitet` ("derived") proposals to
  `docs/maintenance/brain-scan-auftraege.md` — **NEVER executed**
  (order-fidelity HARD). The file is an **instance artifact and may be missing**: in
  that case the proposals go into the run's report (section "Next steps"), and the
  absence is reported. Do **not** improvise creating it — what structure the order
  list has is the operator's decision (mechanism discipline: a missing path is a
  report-event). Rule contradictions are resolved only by the operator: which rule
  wins is a decision, not maintenance.
- Consolidation after operator OK: one canonical place per rule, all other locations
  become pointers (structure hygiene).

## Cadence

On demand + triggered from the brain-scan (checklist section 8): many new
event/HARD rules since the last register, or last run > 90 days →
the brain-scan RECOMMENDS the coherence scan (INFO finding, no auto-run).

**Repeat gate (HARD, since 2026-08-04):** This run is the most expensive single
workflow in the system (measured: 16 agents, ~1.55M tokens, 39 min). Before every new
start, `core/rules/intelligence.md` → "Repeat Runs" applies:
**first read the `journal.jsonl` of the last run, then check the 14-day freshness,
only then start.** Until now this held only via the `full-audit` conductor — a
directly invoked scan ran unthrottled.

**Do not start even when the scan's own register recommends it.** A register can
miscount: on 2026-08-04 one considered six findings missing and recommended the repeat
run; in the journal they were listed as discarded. The recommendation is checked
against the run record before it is executed.
