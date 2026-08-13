---
name: parallel-research-agent
description: Spawns 3-5 sub-agents for parallel research tasks. Inspired by /ultraplan from the jens.heitmann reel. Combines the operator's parallel-agents feedback rule.
triggers:
  - parallel research
  - ultraplan
  - sub-agents recherche
  - sub-agents research
  - multi-research
  - parallele sub-agents research
  - parallel sub-agents research
  - parallel agents research
---

# Parallel Research Agent

Spawns 3-5 parallel sub-agents for research tasks. Inspired by the `/ultraplan` command (jens.heitmann DW43RJUkVp2). The implementation uses the operator's "always parallel agents" feedback rule.

## When to use
- Large research topic with several aspects
- Before any plan/phase covering unknown terrain
- Gallery acquisition: deep-dive 5 galleries in parallel
- Grant research: several foundations in parallel

## Architecture

### Master agent (you)
- Decomposes the topic into 3-5 independent research questions
- Spawns sub-agents in parallel (1 message, several Agent calls)
- Synthesizes the results into a final report

### Sub-agents (parallel)
- 1 question, scoped
- Output format: max 200 words
- Source requirements stated clearly

## Model choice (core rule: `rules/intelligence.md`, model routing)

Evaluate before every spawn, never inherit blindly:
- **Sub-agents (pure research: search/read/collect)** → small model
  (`model: "haiku"` in the Agent call)
- **Master synthesis and everything that judges** → session model (no override)
- If a sub-agent needs real judgment (rating sources, resolving
  contradictions), it stays on the session model — justification in the spawn text

## Pipeline

### Step 1: Topic decomposition
Example: "product launch setup"
1. Market 2026 state
2. Platform comparison
3. Pre-launch marketing
4. Pricing strategies
5. Post-launch community

### Step 2: Sub-agent spawning
```
[5 parallel Agent calls in ONE message block]
- Agent 1 (researcher): Market State
- Agent 2 (researcher): Platforms
- Agent 3 (researcher): Marketing
- Agent 4 (researcher): Pricing
- Agent 5 (researcher): Community
```

### Step 3: Aggregation
Collect all 5 outputs in `docs/research/{topic}-{date}.md`:
- Sub-topics as sections
- Synthesis by the master
- Action items

### Step 4: Notion / memory update
New tools/people → Notion DB. Patterns → memory file.

## Limits
- **Max 5 parallel** (token budget!)
- **Min 3 parallel** (otherwise sequential)
- **Output cap per sub-agent: 200 words**

## Related skills
- `dispatching-parallel-agents`
- `research-documentation`

## Reference
- "jens-heitmann-3-new-claude-code-commands" (Instagram, 2026-04-10 — import report not in the repo)
- `memory/feedback_parallel_agents.md`
