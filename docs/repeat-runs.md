# Repeat Runs

Mechanism behind `rules/intelligence.md` § Repeat Runs (CANONICAL place — skills point here). The rule file keeps the short rule and its carrier; this page keeps the full wording, moved verbatim on 2026-10-20 (history: `docs/rule-history.md`, same section).

An audit/analysis workflow costs six to seven figures in tokens. Before one runs
again, this sequence applies — **each step costs next to nothing and usually settles
the question already:**

1. **Read the artifacts of the last run, do not regenerate them.** A workflow run
   leaves behind, in the project directory of the launching session:
   - `<project>/<session-id>/workflows/wf_<id>.json` — `result`, `logs`, `agentCount`,
     `totalTokens`, `status`
   - `<project>/<session-id>/subagents/workflows/wf_<id>/journal.jsonl` — the **return
     of every agent**, for verify stages the individual `verdicts`
   What is written there is not computed a second time.
2. **Check freshness.** If a report of the type exists that is younger than 14 days,
   and no major rule/structure rebuild has happened since: do NOT re-run, use the
   existing report and declare that in the result as "reused from <date>".
3. **Only then re-run** — and only if it can be named which question the artifacts
   do not answer.

**Mechanically carried:** `core/helpers/freshness-gate.cjs` (PreToolUse/Workflow) denies a
relaunch whose last completed run is younger than the threshold and cost real tokens,
and demands exactly this sequence — read artifacts, declare reuse, or relaunch with
`// FRESHNESS-OK: <the unanswered question>`. Resume (`resumeFromRunId`) passes freely.
Thresholds are instance data: `.claude/rules/freshness-gate.json` (a scheduled cadence
sets its per-workflow threshold below the cadence instead of carrying a marker).

**A report that recommends its own repeat run is not an assignment.** It is checked
against the run record: if an agent's prose tally deviates from the machine result,
`result`/`logs` count, not the prose.
