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
- **Taking it:** BEFORE starting the work, and right after a pull, write a short entry with
  `claims: <request-stem or LOG id>` (`scripts/shared-memory-post.py claim --answers <id>`,
  which refuses when someone else already claimed it) — or answer at once with `answers:`.
  A claim written after the work started lets two instances build the same thing. A claim
  closes the request for everyone else and keeps it on the claimer's list ("claimed by you —
  answer or close it") until an `answers:` or `closes:` settles it. Two claims that crossed
  (both pushed before either pulled) show on both claimers' lists ("ALSO claimed by …"): the
  earlier claim keeps the work, the later one withdraws with a `closes:` of its own claim.
- **Default per category:** `parties.json` `"priority": {"os:windows": [...]}` applies to an
  entry addressed to exactly that one category and carrying no `priority:` of its own.

## Settling a request: either side

A request stays open until something settles it, and either side may (operator order
2026-10-13: "if we gave a satisfying answer, he may say 'fine, done' — or we say 'answered,
done' and he adds at most 'received and enough'"):

- **The answerer:** an entry with `answers: <request-stem>` (or any entry of the addressee
  naming it).
- **The asker:** an entry with `closes: <request-stem>` ("answer received, enough").
- **A LOG-only request** has an id the inbox prints with it: `<area>/LOG@<date>#<n>` (n = the
  n-th heading that day in that LOG, whoever wrote it). Either side settles it by naming that id — in
  `answers:` / `closes:` / `claims:` of a file, or in a later LOG entry from an addressee (any
  device of an addressed person or category) — the asker's own entry settles it only when its
  heading says so, `(status: done)` or `ERLEDIGT`; a reminder that repeats the id, and a party
  that was not asked and only mentions the id, settle nothing. A heading marked `(status: info|done|answered|…)` is a
  report, never a request.
- **Entries dated before `STATE_SINCE` (2026-10-20)** are also settled the old way, by words:
  an answer that repeats the title, `re <start of it>`, the request's numbers, or the asker's
  `ERLEDIGT` heading listing the title. From that date on only the id settles — words were
  rebuilt into state five times in nine days and still left answered requests open.

**Write a request as a file**, not as a bare LOG heading: `scripts/shared-memory-post.py
request|reply|note` writes the file with its fields, the LOG line that points at it, and the
index. From `STATE_SINCE` on the lint names a LOG heading to a party that asks something and
points at no file. Only fact files carry a priority — a LOG-only heading has no frontmatter.
Name request files `request-…` or `question-…`: those prefixes are what every reader recognises.

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
  known tokens, the shared LOG-heading parser, the LOG ids and `STATE_SINCE`.
- `scripts/shared-memory-post.py` — the writer: refuses an addressee `parties.json` does not
  know, and resolves `next:` of a request to the devices its addressees reach.
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
