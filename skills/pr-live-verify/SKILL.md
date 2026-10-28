---
name: pr-live-verify
description: Re-measure a collaborator's PR claims on OUR OWN hardware before merging, then split the result into confirmed / corrected / not-reproduced, write the measurement state into the affected documentation row, and feed corrections back as a follow-up PR. Use whenever an incoming PR asserts live-measured behaviour of a device, desk, rig or tool we also own — "check the open PRs", "a collaborator sent a PR", "verify this PR on our rig". NOT for pure code/refactor PRs with no hardware claim — those go through a code review. Pairs with collab-watch, which arms the watch and owns the merge by the repo's ownership rules.
---

# Live re-verification of an incoming PR

> **Why this exists.** A collaborator's PR that says "live-verified end-to-end" is a
> measurement report from *their* rig. Merging it copies their environment's truth into
> a document every instance then follows (why: Evidence, 2026-08-17 and 2026-10-24).

## When this fires

An incoming PR asserts behaviour of hardware or a live tool we also have.
If we cannot reproduce it (no such device, no license, no source material), say so and
review on the diff alone — an honest "not reproducible here" is a valid outcome and
belongs in the PR thread.

`collab-watch` still owns discovering PRs and the merge; a release stays with the repo's
owner. This skill is the review step in the middle.

## The order that matters

**Read the PR text before touching the rig.** Extract every claim into a list, and mark
each one: *mechanism* (X causes Y), *value* (a number, a count), or *procedure* (do A then
B). Numbers and counts are the ones that travel badly between rigs; mechanisms are the
ones worth a negative control.

**Read the measurement state of every documentation row the PR adds or changes.** A row
that documents live behaviour carries date · machine or tool · method in its evidence
cell (`rules/thinking-protocol.md`, evidence chain: `measured A/B/A` · `measured once` ·
`derived` · `assumed`). A row without it is read as `assumed` — the question for its
state is the FIRST review comment, before any re-measurement, and a suite that opted in
(`live_docs` in its `dependencies.json`) names such rows with
`python3 <core>/scripts/live-doc-lint.py --changed <base-ref>` at the PR head.

**Then check what the repo already says.** A PR usually corrects an older statement. Read
that older statement first — sometimes the PR is right about the fix and wrong about
which line was actually wrong.

## Rebuild, don't spot-check

Build the thing the PR describes, from the state the PR starts from. A spot check on an
existing show measures our leftovers, not their claim.

Save first, versioned, so the rebuild is free: for a desk that means a backup with a
timestamped label before you leave the operator's current state, and again at each
milestone. With that in place, a restart costs nothing and stops being a decision.

**Guard the operator's own work.** Never overwrite what they were doing. Work in a scratch
artifact (save-as, throwaway show, branch), and remove any test object you create in their
space before moving on.

## Measure, don't accept `OK`

A command returning `OK` is not a result. For each claim take the readback that would
distinguish it from its opposite:

- **State claims** — read the property before and after. The strongest evidence is a
  property that does not *exist* in one state and does in the other.
- **Value claims** — read the actual numbers per element, not an aggregate. Two reads
  against a moving source, seconds apart: if the numbers are identical, the thing is
  frozen, not fine.
- **Mechanism claims** — run the negative control. Remove the cause, confirm the effect
  disappears, put it back, confirm it returns. A/B/A or it is a correlation.
- **Reachability claims** — prove the socket, not the property. A status field can be
  anti-correlated with reality; an established connection cannot.

**Absence at the moment of measurement is not absence over the interval.** A screenshot
taken after someone dismissed a dialog does not show that no dialog appeared. If a human
acted in the window, their action is part of the measurement — ask before concluding.

## The dialog gate (operator present vs. fully autonomous)

Any live re-verification can hit a modal confirmation that no tool call reveals. Both
paths are legitimate; pick by the mode you are running in, and say which one you picked:

- **Operator present** — the fast path. Ask them to confirm, name the exact dialog text
  so they know what they are approving, and keep going. No special permissions needed.
- **Fully autonomous** — the agent must hold the input permissions to confirm dialogs
  *itself*, and that must be verified **before the run starts**. Without it the run parks
  silently on a dialog nobody sees, and reports nothing. A missing permission is a
  precondition failure, not a mid-run surprise: check it up front or do not start.

Never conclude "no dialog appeared" from a quiet tool result. The tool call returns `OK`
and the desk waits.

## Sort the result into three buckets

Every claim ends in exactly one:

| Bucket | Meaning | Goes into the PR comment as | Goes into the documentation row as |
|---|---|---|---|
| **Confirmed** | reproduced with a readback | the readback, briefly | `<date> · <this machine, tool version> · measured A/B/A` (or `measured once` when no negative control was possible) |
| **Corrected** | reproduced differently | what we measured, what it contradicts, and why it matters operationally | the row changed to what was measured, with its own state; the old evidence stays appended (claim schema rule 5: a superseded claim is kept, marked, never deleted) |
| **Not reproduced** | did not occur here | plus *why* — usually install-specific (license, platform, version) | the row's state unchanged; a qualifying clause names the install property |

"Not reproduced" is not "wrong". It usually means the PR states an install property as a
general one, and the fix is a qualifying clause, not a deletion.

**A correction must carry its consequence.** "The count is 9, not 15" is half a finding;
"the count is rig-dependent, so count it via <readback> instead of copying the number" is
the whole one.

**The measurement state is written by the one who measured** — in the follow-up PR, into
the evidence cell of the affected row. The reader never rebuilds it from a PR thread
(identity is written, state is read).

## Then: comment, merge, follow-up PR

1. **Comment on the PR** with the three buckets, with numbers. This thread is the shared
   memory between instances — it is where the other side gets to counter-check.
2. **Ask for the counter-check explicitly** on anything measured on a narrower setup than
   theirs (one fixture type, one platform, one license tier). Name the open question.
3. **Merge in the repo's style** if the PR is net-correct. Docs with a few wrong lines
   still beat no docs, as long as the corrections follow immediately.
4. **Push the corrections as a follow-up PR**, never a direct commit to the default
   branch — the measurement state of every touched row included. Run the repo's leak scan
   and language check before committing — measurement notes are full of machine names,
   source names and home paths, and those are instance data that must not reach a shared
   repo. The machine in the evidence cell is named by class and version ("macOS onPC
   2.5", "Windows workstation, onPC 2.5"), never by host name.
5. **Propagate to every variant.** A skill with slim/full variants, a rule quoted in two
   references, a claim repeated in a gotcha table — a correction that lands in one of them
   leaves the others asserting the old thing.

## Feed the environment finding home

Re-verification regularly turns up something about *our* setup rather than the PR:
a discovery path that was switched off, a permission that was never granted, a
configuration that only works because of something already running.

That belongs in our own docs, not in the PR thread — with the measurement, the working
recipe, and a note to restore whatever you changed. If you changed a config to make the
test possible, restore it afterwards and document both states: the one that works on the
network, and the one for a local test.

## Evidence

The measurements behind "Why this exists", by date. They stay with the skill so the rule keeps
its measured reason; the text above carries only a pointer.

- **2026-08-17 and 2026-10-24 — why this exists.** Measured on 2026-08-17 against two such PRs:
  most claims held, but six statements were wrong, incomplete or install-specific —
  including one that would have sent an autonomous run into a silent hang, and one whose
  stated mechanism was the opposite of what the desk actually does. None of that is
  visible from reading the diff. Measured again 2026-10-24 over 188 merged collaborator
  PRs: 39 of 157 reviews took a measurable claim over unread; the damage sat in
  documentation of live device behaviour, where three rows were later refuted by their
  own author — the rows carried no hint of how they had come about.
