# Content review — how a change is built and how it fits the whole

A function check (fixtures green) and an OS check (green on macOS and Windows) say that a change WORKS.
They do not say that it is the RIGHT change. That second question used to wait for the coherence scan and
the full audit, which then found the same kinds of defects in bulk: two copies of one rule, a new gate
next to an existing one that already covered half of it, a reader fixed where the writer was wrong.
Operator order 2026-11-10: ask it in small portions, on every PR, on every side.

`helpers/content-review-gate.cjs` holds an approval (`gh pr review --approve`) and a merge (`gh pr merge`)
until a review carries the three lines below, each with a real answer. A merge needs that review from an
instance other than the author's.

```
Fit:    <answer>
Design: <answer>
Cost:   <answer>
```

## Fit — does it belong, and does it already exist?

- What already does this, or part of it — a rule, a gate, a script, a skill, a data file? Search, do not
  recall (`grep` the helper names, the rule text, `helpers/README.md`).
- Is the change a duplicate, an extension or a contradiction of that? A duplicate is a finding.
- Is it in the right place: core (every brain), a suite (one tool domain), or one instance only?
- Which rule text names the behaviour, and does the change keep rule and mechanism in step?

## Design — the right object, at the right level?

- Is it fixed where the defect arises (writer, design) or where it shows (symptom, reader)? The changelog
  fragment's `level:` says it; is that honest?
- Does it copy a rule another file already carries (a second reader, a second regex, the same logic in
  another language)? Two copies drift; name the one source instead.
- Is there a simpler way — data instead of code, an existing seam, fewer lines?
- What does it couple to what? A new read of another tool's file is a contract; is it written down?

## Cost — what does it cost, what does it weaken?

- How often does it run (every tool call, every turn end, session start, on demand)?
- What does it add to always-loaded context, to a run's tokens, to a session's wait?
- A new gate: what is its frequency design, its escape, and which existing check does it weaken or make
  ritual (a gate that fires on every hit with no quiet period trains people to override it)?

An answer may be short; it may not be empty. "Nothing found" is an answer when it names where you looked.

## Risk — and the model that may build and review it

Operator order 2026-11-10: a PR is judged by reach, complexity and risk, and that sets the intelligence
that builds it and the one that reviews it — nothing critical is built or reviewed with a smaller model;
a bigger model on a small change is allowed, only wasteful.

Every PR body carries `Risk: low|medium|high — <why>`:

- **high** — wide reach or a hard failure: a hook or gate every brain runs, a rule, the release or merge
  chain, the contract, security, anything irreversible or live. A wrong change blocks or misleads every brain.
- **medium** — a script's or helper's logic, a workflow, a skill: wrong output in one place, caught by a
  fixture or a later check.
- **low** — docs, changelog, data rows, a fixture case: nothing runs differently.

The changed files set a floor the author cannot declare below (`pr-risk.json`, `floors`); the reviewer may
raise the risk in the review. `pr-risk.json` `minimum` sets per risk the least model for the build and for
the review. The model is MEASURED from the session transcript, never taken from a claim: at the first
`git commit` in the core, at `gh pr create`, and at the approval, whose `Model:` line must name the model
the review ran on. Models are matched by family (`tiers`: haiku < sonnet < opus < fable), never by version,
so a newer version of a family counts at once; a new family is one entry in `tiers` — until it is there, that
model counts as not measured (said on stderr, nothing checked), never as the smallest. Synthetic transcript
entries (`"model":"<synthetic>"`) are skipped; the last model of a known family counts.

**When the session's model is below the minimum,** the session says so and hands the work on — it does not
ask the operator which way, it decides by the work:

- an **agent** on that model (Agent tool, `model: "<family>"`) when the build or review is self-contained:
  one PR, a brief with goal, files and fixture; the agent builds and commits, the session opens the PR;
- a **session** on that model when the work needs the operator (questions, decisions), a live system, or
  many steps over time. A parallel session on that model takes it by SendMessage with the brief; if none
  runs, the closing message asks the operator to start one.
