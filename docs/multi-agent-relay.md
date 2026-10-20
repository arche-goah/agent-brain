# Multi-Agent Relay and Model Routing

Mechanism behind `rules/intelligence.md` § Model Routing. The rule file keeps the short rule and its carrier; this page keeps the full wording, moved verbatim on 2026-10-20 (history: `docs/rule-history.md`, same section).

**Before EVERY agent spawn (Agent tool as well as workflow stage), the model class is
briefly evaluated: does THIS task need the session model, or is the small one
enough?** (Operator decision 2026-08-13 — inheriting is the mechanism, not a
decision.) Heuristic: read/search/collect/copy (research, gather, inventory, online
search) → small model; judge/verify/synthesize/write → session model,
hard verify stages → higher effort.
Sub-/workflow agents technically INHERIT the session model — the inheritance counts
as chosen, not as a default without a look. The audit workflows (`memory-dream`,
`coherence-scan`, `full-audit-synthesis`) take that choice per stage at launch through
`args.models = {<stage>: '<tier>'}` (stage names in each script's routing block), so
a session on the top tier can keep the verify stage there and run the collecting and
judging stages one or two tiers below without editing the script. Do NOT hardcode
model version names in docs (they go stale immediately). Multi-agent costs ~15x
chat tokens — only for broad independent work, orchestration as separate
phase workflows (research → audit → verify → synthesis), persist each phase's
result, next phase via `args`. Resume matches cached agents by call ORDER: a script meant
to be resumable runs no two unawaited `pipeline()` strands side by side, and after a run
killed by a limit nobody resumes blind — count `started` against `result` in its
`journal.jsonl` and salvage finished results from there first.

**Multi-agent invariant — only the producer writes (measured 2026-08-30):** a workflow script has NO filesystem access; whatever
the orchestrator holds reaches the next agent only through a prompt, and an agent
does not pass content through — it regenerates it and truncates SILENTLY. Therefore: bulk data is written to a file by the agent
that PRODUCED it; across the agent boundary travel only path, count, and verdict,
plus a narrow schema-validated index. Routing-critical fields belong in that
validated index, not in the agent-written file (agent-written files lose schema
validation). And a number the model is asked to REPORT is a claim; the same number
computed in the script is a measurement — the script-side count wins, with an
abort (not a warning) on mismatch. **Carried, not only stated:** the workflows use
`relay()` (a cut is logged AND marked inside the payload, so truncated data cannot
read as complete) and `assertCount()` (a mismatch throws); `core/scripts/test-workflow-relays.sh`
fails on a new bare `JSON.stringify(...).slice(...)` relay site.
