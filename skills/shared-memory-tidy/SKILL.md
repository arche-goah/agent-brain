---
name: shared-memory-tidy
description: Tidy-up pass over the shared-memory repo — run the deterministic lint, then the judging workflow, then apply only what this side is allowed to decide. Use when the shared memory has grown hard to use (search hits noisy, open points buried, the index over budget), when the lint goes red, or when the operator asks for a tidy-up / "aufraeumen" / "shared memory kompakt halten". NOT for a private brain memory — that is memory-dream.
---

# Shared-Memory Tidy-Up

A shared repo decays differently from a private one. In a private memory the only
question is whether an entry is still true. Here a second author exists, so every
finding carries a second question — *whose call is this?* — and getting that wrong is
worse than leaving the mess: rewriting the other party's entry to tidy the index costs
more trust than a noisy index costs time.

The pass is therefore in two halves with a hard line between them, the same line
`memory-lint` and `memory-dream` already draw:

| Half | Carrier | Decides |
|---|---|---|
| Machine | `scripts/shared-memory-lint.py` | what a machine CAN decide: index drift, schema, names, sizes, archive candidates |
| Judgment | `workflows/shared-memory-dream.js` | what needs reading: duplicates, contradictions, superseded entries, buried open points |

**Neither half writes.** The lint is read-only; the workflow returns a report. Fixes
are a separate, deliberate step — step 3 below.

## Step 1 — the machine half, always first

```
python3 core/scripts/shared-memory-lint.py          # $SHARED_MEMORY_REPO, or --repo DIR
```

Fix everything it finds that is mechanical, in the same pass: add the missing index
lines, add missing frontmatter (author and date from the file's OWN opening lines,
never guessed), correct a `metadata.type` that carries a domain instead of a type,
align a `name` with its filename.

**The ratchet has to click.** When a file listed in `.shared-memory-legacy.txt` gains
its `von`/`audience`/`topic` fields, remove its line. The lint reports that as a
finding of its own; a baseline that never shrinks is decoration.

Run the lint again and get the mechanical classes to zero before starting step 2 —
otherwise the judging pass spends its reads on noise the machine could have removed.

## Step 2 — the judgment half

```
Workflow({ name: "shared-memory-dream",
           args: { date: "<YYYY-MM-DD>", shared: "<abs. path to the repo>" } })
```

Four lenses run in parallel (overlap, collision, currency, findability), every finding
is then handed to a skeptic whose default is "not a finding", and the report groups
what survives **by owner**, not by severity — because owner is what decides who acts.

Before launching, the repeat-run rule in `rules/intelligence.md` applies: if a report
of this type is younger than 14 days and nothing structural changed since, read that
one instead of paying for a new run.

## Step 3 — apply, and only within the mandate

The report sorts findings into four owners. The line between them is not negotiable:

- **`us`** — our own entries, mechanical repairs, pointers we can add without changing
  anyone's meaning. **Do it and report it.**
- **`other-party`** — anything that changes what THEY wrote, or that reads as a
  correction of their measurement. Write it into the shared repo as a note addressed to
  them, or raise it in the PR thread. **Propose, never apply.**
- **`both`** — a convention change, a folder move, an archiving policy. Needs
  agreement; the back-channel is the working surface, not a waiting room.
- **`operator`** — goal, money, hardware, risk, outward effect. Collect it, do not ask
  mid-task.

**Deletion is not in the mandate at any level.** Protocol files are append-only and the
fact files are the record of a collaboration. The strongest move is ARCHIVE — move to
`archive/<year>/`, keep a one-line index entry pointing at the new path — or MERGE, with
the absorbed slug leaving a pointer behind. The lint's archive check enforces the same
restraint: it lists candidates and never proposes removal.

## What the pass will not fix, and why to leave it alone

- **Wikilinks pointing into a private instance memory.** They resolve for nobody but
  their author, and the lint lists them, but only the author knows whether the target
  was a shortcut for something that belongs in the shared repo. Ask; do not rewrite.
- **A long thread on one topic** — question, answer, follow-up, correction, written over
  days by both sides. That is the collaboration working, not duplication. Only a fact
  that a reader must find twice is a duplicate.
- **Two measurements that disagree.** Usually two machines, two versions, two shows. The
  workflow makes every collision finding state the condition under which both are right;
  when such a condition exists, the fix is to say it out loud in both files, not to pick
  a winner.

## Cadence

On the operator's call, when the lint goes red, or when the index passes its size budget
— the last of which the lint reports on its own. Not on a schedule: a tidy-up nobody
asked for is churn in a repo two parties are reading.
