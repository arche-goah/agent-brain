---
name: audit-audit
description: Audit of the audits — the level ABOVE the deep checks. Checks every check a brain has (scans, reviews, analysis scripts, self-tests, recorders) for function, cost, effect and findability, and ends with an action plan by priority in which every finding is handled. Mainly for heavy core contributors. Use when the operator says "audit-audit", "master audit", "audit the audit", "audit of the audits", "the level above the full audit", "what do our checks bring", "which analyses are there" (an instance adds its language in its auto-fire table); propose it (never start it) when three or more new analyses or check levels appeared since the last run, or when a question "what exists / what makes sense" about the checks stays unanswered. NOT for auditing the brain itself (brain-scan, coherence-scan, memory-dream, full-audit).
---

# Audit-Audit (audit of the audits)

The other levels ask whether the brain is in order. This one asks whether the instruments that say
so are: do they run, what do they cost, does anything they find get done, and can anyone find them.
Born from the operator's order "time to audit our audit process — function, efficiency,
effectiveness" (first run 2026-10-09, second 2026-11-02 on the macOS instance). The second run found
the class this skill closes: an analysis without a name, a trigger and a carrier is invisible to
every check and does not even show up as missing (the operator asked twice for "the level above the
full audit"; a coherence register answered "the corpus names none").

**Only on the operator's OK; the AI proposes it with the reason and the measured price**, like the
deep checks (`rules/intelligence.md`, "levels of self-check"). Price measured on the macOS instance:
0.87 M tokens (three parts, 2026-10-09), ~1.4 M tokens (five parts, 2026-11-02) — about one brain-scan.

## Step 0 — read the last run, reflect the method

Read the previous run's synthesis and its action plan. Before running again, write `pre-run.md` in the
new run folder: what the last method missed, what is new since (analyses, levels, releases), what each
part adds this time. A run that repeats its method unexamined repeats its blind spots. The repeat-run
rule (`rules/intelligence.md`) applies: younger than 14 days and nothing structural since — reuse.

## Step 1 — five parts in parallel, each writes its own file

Run folder `docs/research/audit-audit-<date>/` (file names may be in the instance's language). One agent
per part, session model (every part judges); **only the producer writes** (`rules/intelligence.md`,
multi-agent invariant) — across the boundary only path, counts, verdict. A part's measurement scripts
live in a subfolder of the run folder.

| Part | File | Question |
|---|---|---|
| Inventory | `inventory.md` | every check there is (skills, workflows, report scripts, self-tests, recorders, bootup sections), counted by SEARCH: what it checks, its trigger and where that is written, who really fires it, last run with evidence, where its result lands; lists "no trigger", "never ran", and how many the rules name |
| Function + return channel | `function.md` | the last run's proposals: built / partial / not, with evidence; does each check do what its header claims, has its instrument a positive case; overlaps, dead parts, logs without a reader |
| Efficiency | `efficiency.md` | cost per run type from the workflow records (`totalTokens`, plus transcripts where a resume overwrote the record), start ballast per agent, cadence against the freshness rule, bootup time and output size, findings per 100k tokens, the price of this run |
| Effectiveness | `effectiveness.md` | exit of every finding since the last run in the ledgers, `check:`/`exit:` coverage, recurrence, hit rate (which operator corrections and register mishaps did a check find, which none), fix-to-tick latency |
| Findability probe | `findability-probe.md` | a fresh agent answers ONLY from its loaded context, with no tool: "which checks exist, by level, with trigger? what is above the full audit?" — compared with the inventory; red until the rules carry every level |

## Step 2 — synthesis with an action plan that handles every finding

`synthesis.md`: the picture in a few sentences, then the **action plan** as ONE table with seven columns
in this order — id · stage · finding · source · exit · owner · check (the header words may be in the
instance's language; the gate reads positions): id like `AA-1`; stage P0 (measures wrong, hides a
fault, blocks findability), P1 (effective gap or large cost driver), P2 (tidy-up); source =
`<part file>.md§<heading words>`, several separated by `;`; exit from the `backlog-catch-up` vocabulary
(ai-does-it, done-already, drop, in-pr, later-at-system, operator-decision, other-side, parked). Rows are
bundled into work packages; every package is ONE ledger entry with a `check:` that is red while the work
is missing. Sections without a finding are listed under a heading that starts with `## No finding` (or the
instance's words, passed as `--none-heading`) with the reason. The operator's decisions go through the
question tool: at most three, plus the plan's release.

**Gate:** `python3 scripts/audit-audit-plan-check.py <run folder>` — red while a heading of a part report
is covered by no plan row and not listed as without finding, or a row lacks a valid stage, exit, a
resolving source or (for ai-does-it / operator-decision) its check. The synthesis is not done before it is
green; its negative control (one row removed) is red.

## Step 3 — evaluate with the operator, then build

Present the plan; on the release, work the packages in the agreed order. Core findings become core PRs;
a review by a second heavy contributor's AI is requested on every core PR that changes a check level or a
check's contract. Tell the other contributors what the tool can do once it stands (shared memory, topic
`core`).

## What this skill does not do

- It fixes nothing inside the run — fixing is step 3, after the release.
- It does not replace the deep checks; it asks whether they earn their cost.
- A review of a foreign repo or a live-system check that never ran is no defect — it is bound to an
  occasion; "never ran" is a finding only for a check that promises a cadence.
