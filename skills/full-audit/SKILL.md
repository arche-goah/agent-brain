---
name: full-audit
description: Overall audit conductor — orchestrates brain-scan (conformance), memory-dream (memory hygiene) and coherence-scan (norm contradictions) as SEPARATE phase workflows and synthesizes them into ONE deduplicated measure catalog (mechanical fixes vs. decision agenda for the operator). Expensive (largest run in the system) — ONLY on explicit call. Use when the operator says "full audit", "gesamt audit" (overall audit), "audit alles" (audit everything), "kompletter selbst-audit" (complete self-audit), or before major restructurings (e.g. repo split R1). Do NOT start automatically.
---

# Full Audit (conductor)

Meta-skill over the three audit building blocks. **No mega-workflow** — the Ultracode
HARD lesson (incident 2026-07-10, ~8M tokens): every phase is its own workflow,
persists its report as a file, the synthesis reads ONLY the reports. An abort never
costs more than one phase; between phases I stay in the loop and check the result.

## Building blocks

| Stage | Workflow | Report | Checks |
|-------|----------|--------|--------|
| 1 | `core/workflows/brain-scan.js` | `docs/research/brain-scan/scan-<date>.md` | conformance: reality == target (checklist) |
| 2 | `core/workflows/memory-dream.js` | `docs/research/memory-dream/report-<date>.md` | memory hygiene (read-only) |
| 3 | `core/workflows/coherence-scan.js` | `docs/research/coherence-scan/register-<date>.md` | whether the target state is internally consistent (de-bias multi-agent) |
| 4 | `core/workflows/full-audit-synthesis.js` | `docs/research/full-audit/gesamt-<date>.md` | dedup + measure catalog over 1-3 |

## Freshness rule (token protection, operator directive 2026-08-01)

> The canonical order lives in `core/rules/intelligence.md` → "Repeat Runs"
> (repeat runs: read artifacts → check freshness → only then run). Here are only the
> stage details of this conductor.

Before every stage, check whether a report of that type already exists that is
**younger than 14 days** AND that no major rule/structure overhaul has happened since:
if so, SKIP the stage and feed the existing report into the synthesis (marked in the
overall report as "reused from <date>"). Stage 3 in particular is expensive (~2M
tokens) — never rerun it reflexively. The operator can explicitly order "fresh" per
stage.

## Procedure

1. `DATE=$(date +%F)` (never estimate). Briefly announce which stages run fresh and
   which reports are reused.
2. **Stage 1** `Workflow({scriptPath: brain-scan.js, args:{date}})` — runs as always,
   including its fix phase (ONLY operator-ordered items — `origin: operator` /
   `von: Operator` / documented-name form; order fidelity). Read the result.
3. **Stage 2** `Workflow({scriptPath: memory-dream.js, args:{date}})` — read-only.
   Read the result.
4. **Stage 3** `Workflow({scriptPath: coherence-scan.js, args:{date, scratch:
   "<session scratchpad>/coherence-<date>"}})` — read-only, register with proposals.
   Read the result. Stages 1-3 may run in parallel (all read-only towards each other);
   on a tight budget, run them sequentially cheap → expensive.
5. **Stage 4 synthesis** `Workflow({scriptPath: full-audit-synthesis.js, args:{date,
   reports:{brain:"<path>", memory:"<path>", coherence:"<path>"}}})` — dedups
   across scans, splits the catalog into (a) **mechanically uncontroversial fixes**
   (doc==reality drift, dead paths) and (b) a **decision agenda** (everything where a
   rule has to win — rule-conflict protocol step 3: explain, discuss, decide per
   case). Appends both as `abgeleitet (full-audit <date>)` ("derived") proposals to
   `docs/maintenance/brain-scan-auftraege.md` — **implements NOTHING**. If the file is
   missing (instance artifact, optional), the proposals go into the overall report and
   the absence is reported — do not improvise creating it.
6. **Closing report to the operator:** overall report path, findings balance, the
   decision agenda as a list. Implementation only after operator OK (promote items to
   the list's own operator marker — `origin: operator` in field-convention ledgers,
   `von: Operator` / the documented operator name in legacy lists; "obvious fixes done
   myself" only if the operator explicitly grants that as a blanket approval, as on
   2026-08-01).

## Trigger & cadence

- ONLY manual ("full audit" and the like) or after structural upheavals (repo split,
  major rule rewrite). NO launchd auto-run: this run is the most expensive in the
  system, and without the operator at the end of the synthesis it fizzles out (the
  decision agenda needs them).
- Mechanical reminder: brain-scan checklist section 8 reports when the last overall
  report is > 90 days old (INFO recommendation, no auto-run).

## Scope boundaries

- Single questions ("are my rules consistent?") → only `coherence-scan`.
  Memory cleanup → `memory-dream`. Weekly routine → `brain-scan` (runs anyway).
- The full audit does NOT check live systems (rig, desk, show machines). WHICH verify
  path covers them is instance knowledge and lives in the instance rule file
  (same move as the session-close live gate — CONVENTIONS §1: "No behaviour that
  only makes sense for one owner's rig"); separate processes, separate sessions.
  ⚠ **STATE THIS ACTIVELY, do not just omit it (operator directive 2026-08-02, after an
  incident):** If the closing report says "full audit ran", it reads like "everything
  checked". On 2026-08-01 the full audit ran on the same day that `router ether6` was
  repurposed live — the resulting naming/logic collision was found only a day later, by
  the operator. Therefore: if the session touched live systems, note EXPLICITLY in the
  report: "live systems NOT part of this audit → run the instance's live verify
  path separately".
  The measurement gate for this lives in the `session-close` skill (step 1).
