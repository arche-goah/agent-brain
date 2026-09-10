# Memory architecture — how a brain remembers for years, not months

> Mechanism document (Knowledge Carriers ladder, `rules/intelligence.md`): written as an
> explanation of how the pieces interact, not as an incident list. Numbers are from the
> proving instance, 2026-09-09; the harness facts are from code.claude.com/docs/en/memory.md.

## What the harness does, and does not do

- At session start it loads exactly ONE memory file, `MEMORY.md`, and only its first
  200 lines or 25 KB, whichever comes first. Everything past that is silently not loaded.
  A write that crosses the limit succeeds; the harness answers with an error asking for
  a rewrite. No setting raises the cap.
- Every other memory file is read only when the model decides to read it, with ordinary
  file tools. There is no retrieval for memory files at prompt time — description-based
  relevance exists for skills and rules, not for memory.
- `CLAUDE.md` is loaded whole up to 4 MiB and skipped entirely above that.

So the operating truth is: **recall is index-only.** What is not in the loaded index does
not exist for the session unless something makes the model look.

## What that does to a growing memory

Measured on the proving instance after ten weeks (241 transcripts, 135 files):

| Symptom | Number | Mechanism |
|---|---|---|
| Index lines grow | 185 characters per entry (limit 400) | the LINE carries the lesson, because the file is not read — and the file is not read, because the line suffices |
| The byte cap binds first | 18.3 KB at 105 lines, room for ~136 entries | 200 lines is the wrong number to watch |
| Files are never opened | 53 of 135 | nothing points at them at the moment they matter |
| A topic sub-index is not read | 4 sessions, although a rule required it | an unloaded index is invisible; only a gate (`live-read-gate`) made it visible |
| Growth | 31, 61 files in the two full months | ~50 files a month; three years is ~1 800 files, ~10 MB, an index of ~330 KB if flat |

Shrinking the index lines loses recall (the line was the recall). Splitting into topic
sub-indexes hides what was split off. The cap is the symptom; the missing read side is
the defect.

## The tiers

1. **Hot index — `MEMORY.md`.** Loaded every session. Long-term it holds two kinds of
   lines only: the rules that must be present in EVERY session (HARD lessons, identity,
   the operator's standing orders) and one pointer line per topic index. Budget: the
   25 KB, not the 200 lines.
2. **Topic indexes — `index-<topic>.md`.** The specialized memory of one project or
   domain (a rig, a desk, a tool suite, a business thread). Same line format as the hot
   index; `memory-lint` treats a topic index the hot index links as part of the index
   (its entries are indexed, its lines obey the 400-character limit, an unlinked one is
   an orphan). Not loaded at start — injected by the recall hook when the prompt or the
   tool call shows the topic, once per session.
3. **Files — one file, one lesson.** Frontmatter `name`, `description`, `type`, optional
   `keywords`. The description is the hook line's single source; the body carries the
   why, the how-to-apply, and the evidence. Files are named by the recall hook as
   pointers (name, description, path) when their frontmatter matches the prompt.

The hot index stays small because tiers 2 and 3 are reachable without it. That is the
whole point of the hook: it turns "not loaded" from "invisible" into "named when relevant".

## The read side — `helpers/memory-recall.cjs`

Two triggers, one helper, one state file per session:

- **Prompt** (UserPromptSubmit): tokenize the prompt, score every file's frontmatter by
  IDF-weighted overlap (name and keywords weighted double, prefix match from five
  characters as stemming, stopwords from instance data), name the top `k` files with at
  least `minHits` distinct matching tokens, inject the best-matching topic index whole.
- **Tool** (PreToolUse on `Skill|mcp__.*`): a rig skill or a desk MCP tool being called
  IS the context. Instance data maps tool and skill patterns to topic indexes; the
  mapped index is injected as `additionalContext` without touching the permission
  decision.

Guarantees: frontmatter only (no body, so nothing large or secret travels); never
blocks; output capped in bytes (the harness caps hook output at 10 000 characters, the
helper stays far below); a file named in the last `cooldownPrompts` prompts is not named
again; a topic index goes in once per session, whichever trigger fires first.

## The measurement — `scripts/memory-usage.py`

Every hook call appends a record (session, trigger, named files with scores). The
transcripts say what a session actually opened. The join gives precision (named AND
opened) and recall (opened but not named) — the numbers the injection is armed on.
`--record` runs the hook silently until those numbers exist: measure, then arm.

The same script counts opens per file over all transcripts. That is the relevance
SIGNAL memory-dream needs for merge and archive judgments — a signal, not a verdict: a
HARD rule works from its index line without the file ever being opened. Archiving stays
relevance-based, never age-based.

## What stays a judgment

- Which lessons belong in the hot index, and which move to a topic index. The hook
  makes the move safe; deciding it is memory-dream's job, with the usage numbers.
- Whether a topic index should be generated from frontmatter (`topic:` field) instead
  of hand-kept. Generated overviews do not drift (Project Work Ledgers rule); a
  hand-kept hook line can say more than a description. Decide with a year of data.
- Merging files that say the same thing. The hook names them side by side, which is
  how duplicates become visible.

## Windows from the start

The memory directory is minted the way `memory-sync.cjs` mints it: every character
outside `[A-Za-z0-9]` of the ABSOLUTE instance path becomes `-` — on Windows the drive
colon and the backslashes are part of that. `CLAUDE_CONFIG_DIR` and `CLAUDE_MEMORY_DIR`
are honoured. Frontmatter parses with CRLF. Paths in the output are posix text. The
fixtures pass every path that travels inside data through `native()` (Git Bash hands a
native process `/tmp/...` otherwise). Node is the runtime, so no `python3`-in-command-
position trap. The register of known platform traps is `docs/os-traps.md`.
