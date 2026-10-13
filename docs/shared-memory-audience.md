# Shared memory: who an entry is for (`audience`)

Operator order 2026-10-11: address by **OS**, by **person** (every device of theirs), or by a
**specific device**. The writer states the intent; the tools resolve who it reaches.

## Syntax

`audience` in a fact file's frontmatter, and the addressees after `AN` / `TO` in a LOG
heading, take a comma-separated mix of:

| Token | Reaches |
|---|---|
| `<device-id>` | exactly that device (`<person>-<machine>`, as before) |
| `person:<person>` | every device of that person |
| `os:macos` · `os:windows` · `os:linux` | every device with that OS |
| `alle-collaborator` (also `alle`, `all`, `everyone`) | everyone |

Example: a check that any Windows machine can run goes to `audience: os:windows` — not to
the one Windows machine the writer happens to remember (measured 2026-10-11: such a request
went to a machine that was switched off while another party's Windows machines were on).

## Data: `parties.json` at the shared-memory repo's root

The list of people and machines lives in the shared-memory repo, never in this public repo:

```json
{"people": {"<person>": {"github": "<login>",
                         "devices": {"<device-id>": {"os": "macos"}},
                         "legacy_ids": ["<old id>"]}}}
```

`os` is `macos`, `windows`, `linux` or `null` (unknown — such a device is reached by its id
and its person, never by an `os:` token). A new machine is one line in its person's
`devices`; a new person is one entry under `people`.

## Who reads it

- `scripts/shared-memory-parties.py` — the resolver (stdlib): a device's categories, the
  known tokens, the shared LOG-heading parser.
- `scripts/shared-memory-inbox.py` — a device in `SHARED_MEMORY_SELF` also answers to its
  `person:` and `os:` tokens. Without `parties.json`: SELF as given, as before.
- `scripts/shared-memory-lint.py`, check 9, for entries dated 2026-10-11 or later: every
  `audience` token resolves; a Windows check (fact file or LOG heading) goes to `os:windows`
  unless the entry says why one machine is needed (`one-machine: <why>`). Older entries are
  not re-judged.
- `shared-memory-lint.py --staged` — the same checks as a commit gate: only the staged fact
  files and the LOG headings the commit ADDS are judged (entry checks only, no repo-wide
  debts). Wire it into the git pre-commit hook of every machine that writes to the shared
  memory. Without that the rule never fires: measured 2026-10-13, more than a dozen Windows
  checks went to one machine after the rule was written, because the lint ran only in the
  weekly scan.
