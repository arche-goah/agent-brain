---
name: root-cause-review
description: Review of the brain's root-cause discipline over its own history — every operator correction or mishap in the transcripts, whether the reply named a measured cause, whether a mechanism followed, grouped into classes with a carrier proposal each; report only, no fixes. The heavy tier next to the Stop check root-cause-gate. Use every two weeks with the brain-scan, when the operator says a defect "keeps coming back" / German "das zieht sich durch", "schon wieder", "Fehlerklasse", or when the same correction appears twice in the session start's reports. NOT for a single fresh correction (the Stop check handles it in the turn) and NOT for norm contradictions (coherence-scan).
---

# Root-cause review (the heavy tier)

Operator order 2026-10-26 (translated): "find the cause and fix it generically at the root …
I want you to do root-cause research on your own, always, up to a core PR when needed";
"I want measurable results for root-cause work based on historical data — fixing problems on
the spot without going deep is a failure class"; "once a root-cause fix is built, it can be
tested on the history, and only then the class may show". Two tiers came out of it: the Stop
check `core/helpers/root-cause-gate.cjs` runs along (a correction in the turn needs a cause
line before the turn ends), and this review runs regularly and targeted, like the coherence
scan — it reads what the Stop check could not see: the corrections of the past, whether a
cause was named, whether anything was built, and which of them are the same class.

## When

- With the brain-scan (every two weeks, on the operator's OK); the scan names it as due.
- On a reason: the operator says a defect keeps coming back; the same correction stands in
  two session-start reports; a root-cause fix was just built (the root test: replay it).
- Never on its own authority inside another order — the finding is reported, the run proposed.

Price (measured 2026-10-26, macOS instance): the count itself is a node run over the
transcripts, seconds for 400 of them; the judgment below is one model pass over its list,
about a tenth of a brain-scan.

## Steps

1. **Count** — `node core/helpers/root-cause-gate.cjs --review 60 > docs/maintenance/root-cause-review-<date>.md`
   (`--since YYYY-MM-DD` for the period since the last review; `--dir` only for a test
   directory). The report carries: corrections found, how many replies named a cause, how
   many were followed by a mechanism file within five turns, per month; then every
   correction whose reply named no cause, with date and session.
2. **Read the last review first** (`core/rules/intelligence.md`, Repeat Runs): a correction it
   already judged keeps its exit; only new ones are judged now.
3. **Judge each correction without a cause** — read the turn in its transcript
   (`core/scripts/transcript-recall.py` or the file by its session id):
   - was a cause measured later in the session, only not in the gate's wording → exit
     `wording` (no finding; a pattern for `.claude/rules/root-cause-patterns.json` if the
     wording recurs);
   - fixed on the spot, cause never named → exit `open-cause`: name the cause now from the
     transcript if it can be read there, else `cause unknown — <what is missing>`;
   - the same correction as another one in the list → exit `class`: group them, name the
     invariant (thinking-protocol, Class Discipline) and the carrier that would hold it
     (gate · script · rule with check · ledger `check:` line);
   - a carrier already exists for it (grep the helpers, rules, ledgers) → exit `carried`,
     with the file.
4. **Write the report**: the counts, the exits per correction, the classes with one proposed
   carrier each, and the three biggest classes as the proposal to the operator — plain words,
   recommendation first, through the question tool if a decision is theirs. No fix is
   applied from inside this review (Order Fidelity #5); a clear, reversible, own-terrain fix
   goes into the next order or the ledger as `origin: derived`.
5. **Append the review's date** to the instance's maintenance ledger so the next run can
   `--since` it.

## What the counts mean

- "reply named a cause" is a wording match (`cause_patterns`); a low rate can be a wording
  gap — step 3 separates the two before anything is concluded.
- "a mechanism file written within 5 turns" is a proxy for "a carrier followed"; a rule
  line or a ledger `check:` written later than five turns is not counted — the judgment
  in step 3 can overrule the count, never the other way round.
- A root-cause fix built this week is replayed here on purpose: the further instances it
  would have caught ARE its class (operator 2026-10-26); none found = one instance, said so.
