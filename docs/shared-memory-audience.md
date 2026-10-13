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

## Who is asked first: priority (a hint, never a sequence)

Any request that several parties can take — a Windows check, a review, a test run — may say
who is asked first (operator order 2026-10-13). Priority is INFORMATION: no timers, no
escalation. Anyone reached may claim the task at any time and decides themselves whether they
can and want to take one they are not asked first for.

```yaml
audience: alle-collaborator            # or os:windows, person:<p>, devices
priority: kim-pc, person:sam, os:linux # ordered, any tokens (optional)
```

- **Asked first** (the first priority token that reaches you): an open request, as before.
- **Everyone else reached:** the request is listed as a hint, not a duty:
  "optional: priority n, asked first <who>; unclaimed - take it if you can and want".
- **A request to everyone without `priority:`:** a hint for everyone (before 2026-10-13 such a
  broadcast request reached nobody's list).
- **Taking it:** write a short entry with `claims: <request-stem>` (or answer with
  `answers: <request-stem>`). That is the record; it closes the request for everyone else.
- **Default per category:** `parties.json` `"priority": {"os:windows": [...]}` applies to an
  entry addressed to exactly that one category and carrying no `priority:` of its own.

Only fact files carry a priority — a LOG-only heading has no frontmatter. Name request files
`request-…` or `question-…`: those prefixes are what every reader recognises.

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
