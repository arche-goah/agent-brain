# Shared memory: what is open, who is on the move, what belongs together

The operator's word (2026-09-22): the shared memory "has to be cleanly linked and indexed
in itself, so that everyone finds their way everywhere automatically and does not have to
search deliberately." Agreed between the two writing parties on 2026-10-14. Five OPTIONAL
frontmatter fields under `metadata:` carry it; an entry without them is as valid as before,
and nothing is copied or moved.

## The fields

```yaml
metadata:
  status: open                  # open | decided | superseded | info (default) | draft
                                # — and answered | done | closed, the inbox's settled values
  next: kim-pc, person:sam      # who is on the move; REQUIRED while status is open
  related: [ops/a.md, b-slug]   # entries this one belongs with (path, or a bare slug)
  topics: [show-setup]          # further areas this entry is filed into — no copy, no move
  supersedes: ops/old-plan.md   # the entry this one replaces
```

Lists are written `[a, b]`, `a, b`, or as `- a` block lines under the key.

## What the tools make of them

- **`scripts/shared-memory-index.py`** (the generator) writes into `<area>/INDEX.md`, per
  entry: the status when it is not plain info, `next` while open, `related` — and the
  REVERSE direction ("linked from") into the other entry's line, so nobody maintains the
  back-reference by hand —, "superseded by" on the entry a successor names, and a section
  "Filed here from other areas" for entries that name the area in `topics`.
  It writes **`<area>/OPEN.md`**: every `status: open` entry of the area (own and filed),
  one line each — who is on the move, the age, the title, the path. The page is written
  where an area has open entries, and rewritten as "nothing open" only where it already
  exists: a stale list never stands, and no area gets an empty page it never asked for.
  The root `INDEX.md` keeps its shape and appends `· N open` to an area's pointer line.
- **`scripts/shared-memory-lint.py`** check 10, only where an entry USES a field: a status
  outside the vocabulary; `open` without `next` (entries dated 2026-10-14 or later — the 41
  entries that already carried `open` before the rule are not re-judged); `next` naming no
  device of `parties.json`; `related` / `supersedes` pointing at no file; `topics` naming a
  folder that is not an area (a folder with a `LOG.md`). The same checks run at commit time
  through `--staged`.
- **`scripts/shared-memory-inbox.py`** already read `status:` before these fields existed
  (a request is open until a settled status or an answer names it); the vocabulary above is
  one set for both tools.

## The relation fields: `answers`, `claims`, `closes`

```yaml
metadata:
  answers: core/request-check-42-2026-10-21, core/LOG@2026-10-21#3
```

They name what an entry settles: a request's file stem, or a LOG request's id
`<area>/LOG@<date>#<n>` exactly as the inbox prints it. The answerer KNOWS what it answers —
writing it down is cheaper than every reader guessing it from words. `scripts/shared-memory-post.py
reply --answers <id>` writes it; lint check 11 names a value that resolves to nothing (entries
dated `STATE_SINCE` = 2026-10-20 or later; before, 9 entries named a LOG request in prose,
which no tool can follow). Because the id is a heading's place that day, a LOG is append-only
for its headings: at commit (`--staged`) the lint names a heading inserted, edited or removed
within a day that stays. `open-items.py` keys a LOG request by the same id, so its class and
repeat counter stay with it when its wording changes.

## Not in this cut (deliberately)

A root line "on the move: <device> N · …" and a bootup line "open, you are on the move: N"
wait for the first weeks of real `next` values — the count in the root pointer line and
the per-area page are the measurement they will be built on.

Related: `shared-memory-audience.md` (who an entry is for, and how a request is settled).
