# CLAUDE.md — agent-brain

Tool repo (the shared core), NOT an instance — rules/skills/helpers live here,
no show data, no memories. Contract: `CONVENTIONS.md` + `core-contract.json`.
Working instructions for agents: `AGENTS.md`. Before every commit: `python3
scripts/leak-scan.py` (0 hits mandatory — names/IPs/home paths are instance material).
Changes to core rules follow the rule-conflict protocol in
`rules/thinking-protocol.md`. Release = tag + version in `.claude-plugin/plugin.json`.
