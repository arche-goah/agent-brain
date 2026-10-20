# Reload watcher — the boot-stamp contract

Rule: `rules/working-rules.md` § A Needed Reload Is Not a Wait State (operator order
2026-08-06, sharpened 2026-08-14). The rule file keeps the three rules in short form; the
full wording, the watcher call and the suite contract stand here (moved verbatim in the
context diet of 2026-10-20). Why: `docs/rule-history.md`, same section.

Three rules, in this order:

1. **Ask for the smallest reload that does the job.** A changed or added MCP tool needs
   the CLIENT to re-read the tool list — an `/mcp` reconnect. A full Claude restart is
   the bigger hammer and is rarely the one required; asking for it by reflex costs the
   operator their session context for nothing. Name which one you need and why.
2. **Arm the watcher in the SAME turn, then keep working.**
   `core/scripts/wait-mcp-reconnect.sh <boot-stamp-file> [timeout_s]`, started in the
   background (Bash `run_in_background`), exits when the server writes a fresh boot
   stamp — the agent is re-invoked and runs the verification by itself. Never end a turn
   on "tell me when you've reconnected".
3. **The same holds for EVERY action expected from someone else** (operator decisions
   2026-09-10 and 2026-10-05): re-plugging a cable, switching a device on, a check
   requested from another machine or another party. Build the measurement, arm the
   watcher on the measurable state, THEN give the instruction — and the instruction
   says what will NOT move (a default state produces no change). A request is an
   opening move, not a hand-off: before every turn end ask "what do I expect from whom,
   and how will I learn that it has arrived?" Where every probe is forbidden, the
   instruction stands without a watcher.

**Proof is the server's own boot stamp, never its reachability** — a stale server answers
too, with the OLD code. The stamp is the suite's half of the contract: an MCP server
writes a small file at startup whose content changes on every boot, and documents its
path in its AGENTS.md (the path is suite knowledge and stands only there, never in a core
rule). A server without
a stamp cannot be PROVEN back — that missing carrier is itself the finding, and the waiter
says so instead of reporting green. Until its suite adds one, the same script's
`--process <pattern>` mode is the stopgap on macOS/Linux (all old pids of this session's
children gone, a new one up); on Windows it refuses, and the finding stays open either way.
