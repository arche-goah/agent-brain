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

**What counts as the last run** (audit-audit 2026-11-10, AA-9): a completed record; a
record that ended `failed` but wrote its report (a dated report of the workflow for the
run's date — two of seven deep runs on one brain failed at the script's final check after
the report stood on disk); and a dated report in the repo without a record on this
machine (a run on another machine, a pulled brain). The report places the gate reads:
`docs/research/<workflow>/<anything>-YYYY-MM-DD.md`, `docs/research/<workflow>-YYYY-MM-DD/`
and `docs/maintenance/<workflow>-YYYY-MM-DD.md` — a workflow that writes elsewhere is
seen only by its records. A **resumed** run is one run with its earlier attempt: the
resume rewrites the record with the resumed part's tokens only (measured -58 %), so the
token floor does not apply to it, and `scripts/run-price.py` adds the earlier attempt's
agent transcripts to its price.

**Price of a run:** `python3 core/scripts/run-price.py` prints the median tokens per run of
each deep check from this machine's own records (count and date range with it); a workflow
without a record is quoted with the old fixed number, marked "fallback". The brain-scan
head quotes the same.

**A report that recommends its own repeat run is not an assignment.** It is checked
against the run record: if an agent's prose tally deviates from the machine result,
`result`/`logs` count, not the prose.
