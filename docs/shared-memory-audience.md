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

## Who takes it: ranked candidates

A request to a category reaches several parties. Ranking says who is expected first, so the
request can go out to everyone as information without the later ones thinking they must act
now (operator order 2026-10-13). The ranking is per task, never fixed:

```yaml
audience: os:windows
candidates: kim-pc, person:sam, person:lee   # ordered, any tokens
escalate_after: 24                                                 # hours per rank (optional)
```

- **First candidate:** an open request, as before.
- **A later candidate:** listed at session start as *waiting*: "queued: candidate 2, after
  <who is before you>, unclaimed; yours from <time>". It is visible, but not a duty yet.
- **When nobody before them took it within `rank × escalate_after` hours** (counted from
  the request's first commit), it becomes that candidate's open request.
- **Not listed at all:** comes after every listed candidate.
- **Taking it:** write a short entry with `claims: <request-stem>`, or answer with
  `answers: <request-stem>`. Either one closes the request for every other candidate.
- **No `candidates:` in the entry:** the default order from `parties.json` applies
  (`"candidates": {"os:windows": [...]}`, `"escalate_after_h": 24`), but only for an entry
  addressed to exactly that one category.
- Without either, everyone reached is a first candidate (the behaviour before).

Only fact files carry a ranking. A LOG-only heading cannot hold frontmatter.

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
