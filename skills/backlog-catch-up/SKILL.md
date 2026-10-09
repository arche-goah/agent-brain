---
name: backlog-catch-up
description: Sort a large backlog of old open points (derived proposals, open requests, local deviations from the core) into seven exits so the operator gets at most three real decisions instead of a wall of items. Use when the session start shows many old open items at once — typically the first start after a core update made them visible —, when a ledger has grown stale ("68 Vorschläge liegen"), or when the operator says "räum die liegengebliebenen Punkte auf" / "catch up on the backlog". NOT for a single new item (answer it) and NOT for the shared-memory repo's own hygiene (shared-memory-tidy).
---

# Backlog Catch-Up

A check that makes old open points visible is right — and on its first run it is a flood.
On the proving brain (2026-10-08) the session start suddenly showed 68 derived proposals,
most of them three to five weeks old. Listed one by one they would have cost the operator
hours; sorted, they came down to **4 questions**. The other 64 were the AI's own work.

**The invariant:** old open points are AI work until proven otherwise. The operator hears
the RESULT of the sorting — never the raw list.

## When it starts

- The session start reports more open items than the instance's threshold
  (`backlog_threshold` in the instance's open-items data; without one: 10), or
- a ledger's derived items are older than the instance's age limit, or
- the operator asks for it.

Say ONE sentence before starting, in plain words — no codes: *"With the update, 40 old points
became visible. I am sorting them; afterwards you get at most three decisions."* Then work.
The sentence is not a question: sorting reads and measures, it changes nothing outside
the brain.

## Procedure

1. **Collect** from the generated overviews, never from memory: the instance's ledger
   aggregator (derived items), the open-items list (requests to us, PRs), the
   local-machinery report (hooks outside the core). One row per item with its source path.
2. **Read each item in its source file, whole**, and MEASURE its state today where a tool
   can read it (`gh pr view`, grep for the file it names, the live config it describes).
   Measured on the proving brain: 13 of 68 were already done by later sessions and the
   ledger did not know. A row without a measurement says "not measured".
3. **Give every item exactly one exit:**

   | Exit | Meaning | What happens |
   |---|---|---|
   | done already | a later session built it | tick it off with the evidence |
   | the AI does it | clear, reversible, own brain / own suite / a core PR | do it (ordered audits order their clear fixes), report in the summary |
   | the other side | a collaborator is on the move | one shared-memory note to that side's AI; it is decided there |
   | parked or postponed | the operator parked the domain or named a later date | leave it; a REQUEST from another side still gets a receipt |
   | later, at the system | a hand-step at a device or work on one specific system | mark it, raise it when work on that system starts |
   | drop | superseded or without subject | drop it with the reason |
   | **operator decision** | goal, money, hardware, risk, external effect, release — and not answerable by measurement | at most THREE, each with a recommendation, answerable by number |

   More than three operator decisions means the cut is wrong. Re-check each one: is it a
   decision, does it block anything now, can only the operator make it? What fails goes to
   another exit. If more than three still remain, the rest is offered as a list ("there are
   two more; shall I list them?").
4. **Write the sorting to a file** in the instance's maintenance folder, with counts per exit
   and one table per exit. Sorting a list in the session context is lost at the next
   compaction.
5. **Do the AI's own items in the same run**, mark the rest in their ledgers, push the notes
   to the other sides.
6. **Report in four lines:** how many points, how many done, how many handed on, the (at most)
   three decisions. Wording: what a thing IS and what it is about, never a priority or
   ledger code as the carrying word.

## Between brains

When several brains update in sequence, every brain runs this pass for ITSELF. Points
between the sides are settled by the AIs over the shared memory. A human hears only what a
human must decide, by name ("this needs you and <collaborator>" — not a code for the circle of people
involved). A side that is still on an older core release is not chased: it gets the louder
checks and this skill in the same release, never the checks alone.

## Not this skill

- One new request → answer it, no sorting.
- The shared-memory repo's duplicates and stale entries → `shared-memory-tidy`.
- Contradictions between rules → `coherence-scan`.
