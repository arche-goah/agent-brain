# Contributing to agent-brain

The core exists so that every brain runs the same state. A change that lives only in one brain
helps nobody else and drifts away from the next release. So there is one rule before all others:

**Never fix the core locally. Report it here, and it gets fixed for every brain.**

## How to give something back

| You have … | Do this | Who builds it |
|---|---|---|
| a bug in a core helper, gate or script | open a **bug report** (Issues → New issue) | a maintainer, or you if you have write access |
| an idea for a new capability | open a **feature request** | decided in the issue, then built in this repo |
| a local deviation you need (your machine, your workflow cannot follow the core) | open a **local-deviation request** and declare it in your brain meanwhile (see below) | answered in the issue: a core change, a declared instance deviation, or a way to do without it |
| write access to this repo | branch **in this repo**, open a PR (draft while you work) | you, reviewed by a second instance |

What not to do, and why:

- **No edits inside your brain's `core/` checkout and no copies of core files in your brain.**
  `bash core/scripts/brain-update.sh` puts `core/` back on the released tag, so local edits are
  lost at the next update, and a copy silently stops following releases.
- **No fork as a working place.** A fork branch gets no CI, nobody sees it, and it is forgotten —
  measured on this project: fork branches 167 and 314 commits behind, a fix that lived only on a
  fork for six weeks. Without write access, a fork-based pull request will be read, but the change is
  rebuilt on a branch in this repo; the issue is the faster way.
- **No core consumed from a fork.** Your brain's `core/` follows the marketplace pin of this repo.

## While you wait: declare a local deviation

If you must deviate locally before the issue is settled, declare it — the session start of your
brain reports every undeclared one:

```
.claude/rules/local-machinery.json in YOUR brain:
{ "instance": { "<repo-relative path of the item>": {
    "why": "why this cannot follow the core yet - issue: <link>",
    "evidence": "<the machine-specific token the item contains>",
    "reviewed": "YYYY-MM-DD" } } }
```

The exact format is in the head of `core/scripts/local-machinery.py`. A declaration is due for
review again after 90 days, so it cannot quietly become permanent.

## What a good report contains

The templates ask for it: the core version (the session start prints it), your OS, what you did,
what happened **verbatim** (tool output, error text), what you expected as a testable statement, and
how someone else can reproduce it. Measured values, not impressions.

## Pull requests (write access)

- Branch in this repo, one topic per PR, a `changelog.d/<slug>.md` fragment with its test class and
  level (`changelog.d/README.md`).
- CI must be green; the PR is reviewed by a second instance, on macOS and Windows where it matters.
- Merges reach `main` through a merge train; a release is a tag plus the marketplace pin.
- Public text carries no personal names or machine names (`helpers/public-text-guard.cjs` checks).

Details: `CONVENTIONS.md`, `AGENTS.md`.
