- **skill-gate: a skill can name the Bash/Monitor commands that need it (`load-before-commands`)** (test: T1) (level: reader;
  higher: design — a registry of which command reaches which system; not needed, the skill that governs the system names
  its commands; debt: a command spelled another way, an alias or a script name not in the pattern, passes). Coherence
  register 2026-11-02 P1-15 (CONFIRMED trigger gap): a multi-system measurement skill held MCP calls only; the Bash probes of
  the same measurement (an OSC router, an Art-Net sender, `nc`) never loaded it. Frontmatter `load-before-commands` and
  `skill-gate.json` `commands` are a regex on `tool_input.command` of Bash and Monitor; a skill may declare tools, commands
  or both. Fixture +5 (two red on the old gate).
