---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always
---

# Verification Before Completion

## Overview

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## Codex Adversarial Review Integration (Update 2026-04-11, genericized 2026-09-02)

For critical code changes, additionally trigger the Codex adversarial review via the
`codex-review` skill (where the instance carries it).

**Triggers:**
- Before deployments and anything outward-facing
- Before restarting a production process on changed code
- Before `git push` of code that runs unattended
- Before submitting critical code

(Earlier wording named one owner's Vercel portfolio site and PM2 bots — instance
context of another brain; removed, coherence-scan 2026-09-02 §P2-9.)

**Codex checks 7 areas:**
Authentication, Data Loss, Rollbacks, Race Conditions, Degraded Dependencies, Version Skew, Observability Gap

**Advantage:** Codex is much cheaper than Opus → can run often.
**Source:** "chase-h-ai-codex-adversarial-review" (Instagram, 2026-04-11 — import report not in the repo)

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command in this message, you cannot claim it passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the FULL command (fresh, complete)
3. READ: Full output, check exit code, count failures
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## One Symbol, Two States (since 2026-09-02 — a check must separate the worlds)

Verification output is evidence only if it DIFFERS between the world where the
claim holds and the world where it doesn't. Five independent finds in one day
(2026-08-30, operator instance): "checked and clean" and "could not see anything"
both printed `clean`; "forgot to pin" and "deliberately held back" both printed
`STALE`; "cannot be mechanized" and "not yet mechanized" shared one marker. The
error direction is NOT predictable — some hid necessary work, some invented it.

Before trusting (or emitting) any check output, answer two questions:

1. **Which OTHER world state produces exactly this same output?** If one exists,
   it needs its own symbol AND a reason field — not just a flag.
2. **What did I NOT look at?** Anything unexamined is its own state and must never
   read as "checked". Every "nothing found" must be able to say whether it found
   nothing or SAW nothing (an untracked file is invisible to `git ls-files`; an
   empty grep over the wrong directory is not a pass).

The second state usually does not exist yet when the check is written — the world
delivers it later. That is why this is a question asked at every emit, not a
pattern to grep for.

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Relying on partial verification
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "Partial check is enough" | Partial proves nothing |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests (TDD Red-Green):**
```
✅ Write → Run (pass) → Revert fix → Run (MUST FAIL) → Restore → Run (pass)
❌ "I've written a regression test" (without red-green verification)
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## The Class Gate (since 2026-08-10 — a verified FIX is not a verified CLASS)

A defect names exactly ONE instance; verifying the fix proves nothing about its
siblings. Before a defect counts as done (measured 2026-08-06: three instances of one
class in a single day, each "fixed" individually):

1. **Name the invariant** — the general sentence, not the anecdote ("whatever survives
   a reset must never be created unguarded", not "X was unguarded").
2. **Enumerate by SEARCH** — grep/enumeration over the space the invariant spans. Derive
   the search from the INVARIANT, not from the vocabulary of the first find. The result
   is a list, not a feeling.
3. **Close or list** — every found instance gets fixed OR recorded as a finding. A
   silently skipped instance is a debt.
4. At >=3 instances or recurrence after a fix: build a MECHANISM (a check that trips on
   the class), don't stack single fixes. Where an invariants register exists in the
   instance, add the class line there.

The gate function above verifies the fix; this gate verifies the class. Both run before
any completion claim.

## The Spec Gate (since 2026-08-14 — a workaround is a DEBT, not a checkmark)

Order fidelity #4 (`rules/working-rules.md`): done is only what works AS SPECIFIED.
The gate function proves "it works"; this gate asks "is IT the thing that was
ordered?" — a verified workaround still fails the order. Before any completion
claim, answer explicitly:

1. **Does the delivered result deviate from the ordered spec in ANY way?**
   Workaround taken, scope trimmed, requirement substituted, a named deliverable
   replaced by "something equivalent", a number missed? Concrete nouns with a
   number or proper name in the order are deliverables, not examples (#4a).
2. **If yes: record a DEBT entry instead of a checkmark** — "spec not fulfilled"
   with priority, in the order list / ledger the assignment came from, plus the
   reason and what the original would take. Then report the deviation FIRST, not
   the success.
3. **A silent substitution is the expensive case** (#4a goal substitution): if you
   notice the goal itself drifted while working, say (a) that a substitution
   happened, (b) why the original was not obtainable — attempted and showable,
   not "wasn't lying around" — and (c) only then continue.

Answering "no deviation" is a claim like any other: it needs the line-by-line
requirements check from the table above, not a feeling.

From 24 failure memories:
- your human partner said "I don't believe you" - trust broken
- Undefined functions shipped - would crash
- Missing requirements shipped - incomplete features
- Time wasted on false completion → redirect → rework
- Violates: "Honesty is a core value. If you lie, you'll be replaced."

## Live systems / operator surfaces (HARD, operator order 2026-07-12 — pointer since 2026-08-01, coherence-scan K-08)

Before any done/passed claim about a live-operable artifact (MA3 show, rig,
show setup, operator surface): read the memory `verify-and-never-stop` IN FULL and
apply the PASS bar — the WHOLE function in its CURRENT state, EVERY control element
individually, after diagnostic interventions first RESTORE + re-verify of the whole,
proof on multiple fixtures/channels. A green partial test on a broken whole is a
false pass.

## When To Apply

**ALWAYS before:**
- ANY variation of success/completion claims
- ANY expression of satisfaction
- ANY positive statement about work state
- Committing, PR creation, task completion
- Moving to next task
- Delegating to agents

**Rule applies to:**
- Exact phrases
- Paraphrases and synonyms
- Implications of success
- ANY communication suggesting completion/correctness

## The Bottom Line

**No shortcuts for verification.**

Run the command. Read the output. THEN claim the result.

This is non-negotiable.
