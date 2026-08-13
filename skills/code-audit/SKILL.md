---
name: code-audit
description: Systematically audit a large unfamiliar codebase across correctness, error-handling, security surface, dead code, dependencies, and tests — fanning out parallel reviewers and adversarially verifying findings into a prioritized report. Use for "audit this repo", "review the whole codebase", code quality assessment, or a structured pre-takeover review of code you didn't write.
---

# Code Audit

A repeatable methodology for auditing a **large codebase you did not write**.
It turns "review this whole repo" into orientation → parallel dimension
reviews → adversarial verification → a single prioritized report.

This skill is mostly process and templates — the heavy script work lives in
its sibling skills (`repo-recon`, `dependency-audit`, `test-survey`).

## How this relates to the built-in review commands

- **`/security-review`** — deep, dedicated security scanning. **Defer to it**
  for exploit-level security analysis. This skill only maps the *security
  surface* and routes the right files to it.
- **`/code-review`** — line-by-line review of a **diff**. **Defer to it** once
  you start changing code. This skill is **whole-repo comprehension** and
  structured findings for code you haven't touched yet.

Use `code-audit` to decide *where* those commands should be pointed.

## The methodology

### Step 0 — Orient (always first)

Run `repo-recon` on the target. Read the report. You now know the languages,
entry points, build/test commands, dependencies, and hotspots. Do not start
reviewing files blindly before this — the recon tells you where to spend
attention (largest + most-churned files are prime candidates).

Also run `dependency-audit` and `test-survey` up front; their outputs directly
populate two audit dimensions.

### Step 1 — Review dimension by dimension

Audit along these nine dimensions. For each, the question to keep asking is
"where could this go wrong, and can I point to the line?"

1. **Correctness / logic bugs** — off-by-one, wrong operators, inverted
   conditions, mishandled edge cases, incorrect API usage.
2. **Error & exception handling** — swallowed exceptions, bare `except`,
   errors logged but not handled, missing cleanup on failure paths.
3. **Concurrency / race conditions** — shared mutable state, missing locks,
   non-atomic check-then-act, unsafe goroutines/threads/async.
4. **Input validation & security surface** — untrusted input reaching SQL,
   shell, filesystem, deserialization, templating; auth/authz gaps. (Map it;
   hand depth to `/security-review`.)
5. **Resource / memory leaks** — unclosed files/sockets/connections, unbounded
   caches/queues, listeners never removed.
6. **Dead & duplicated code** — unreachable branches, unused exports,
   copy-paste blocks that should be one function.
7. **Dependency risk** — unpinned/floating deps, abandoned packages, oversized
   trees (from `dependency-audit`; confirm vulns online with the listed tools).
8. **Test coverage gaps** — critical paths with no tests (from `test-survey`;
   confirm with a real coverage run).
9. **Docs/comment accuracy vs code** — comments and READMEs that contradict
   what the code actually does.

Record every finding against `findings-schema.json` (id, title, file:line,
dimension, severity, confidence, evidence, recommendation).

### Step 2 — Fan out (parallel reviewers)

For a large repo, dispatch **one sub-agent per dimension** so they run
concurrently and stay focused. Each agent is read-only and returns findings in
the schema — it does NOT write to the repo.

Concrete recipe using the Agent tool (send all in ONE message so they run in
parallel):

```
Agent(subagent_type="reviewer", description="Audit: correctness",
  prompt="""READ-ONLY audit of <repo path>. Dimension: correctness/logic bugs.
  Start from repo-recon hotspots: <list largest + most-churned files>.
  For each issue return a JSON object matching findings-schema.json
  (id, title, location 'file:line', dimension='correctness', severity,
  confidence, evidence, recommendation). Only report issues you can tie to a
  specific line. Return a JSON array, nothing else.""")

Agent(subagent_type="reviewer", description="Audit: error-handling", prompt="... dimension=error-handling ...")
Agent(subagent_type="reviewer", description="Audit: concurrency",     prompt="... dimension=concurrency ...")
Agent(subagent_type="reviewer", description="Audit: security-surface",prompt="... dimension=input-validation-security ...")
Agent(subagent_type="reviewer", description="Audit: resource-leaks",  prompt="... dimension=resource-leak ...")
Agent(subagent_type="reviewer", description="Audit: dead/dup code",   prompt="... dimension=dead-or-duplicated-code ...")
```

(Dependency-risk and test-coverage-gap dimensions come from the
`dependency-audit` and `test-survey` scripts rather than a sub-agent.)

Collect all returned arrays into one candidate findings list.

### Step 3 — Adversarial verification (refute, don't confirm)

Hallucinated findings are the main failure mode of automated audits. Run a
**skeptic pass**: a separate agent whose job is to *refute* each candidate.

```
Agent(subagent_type="reviewer", description="Refute audit findings",
  prompt="""You are a SKEPTIC. Here are candidate findings: <JSON>.
  For EACH, open the cited file:line and try to prove it WRONG — consider
  callers, guards elsewhere, framework behavior, and whether the 'bug' is
  actually reachable. Set refuted=true with a refutation_note for any you
  cannot substantiate, or downgrade confidence. Return the same JSON with
  refuted/refutation_note/confidence updated.""")
```

Rules:
- Drop every `refuted: true` finding from the final report (keep them in the
  template's appendix for transparency).
- Downgrade confidence on anything the skeptic dented but couldn't kill.
- A finding survives only if it has concrete, line-level evidence.

### Step 4 — Synthesize

Merge duplicates, assign final severity/confidence, sort, and write the report
using `audit-report-template.md`. Validate the findings JSON against
`findings-schema.json`. End with explicit next steps (which files to send to
`/security-review` and `/code-review`, which coverage/vuln scanners to run).

## Severity rubric

| Severity | Meaning |
|----------|---------|
| **critical** | Exploitable security hole, data loss/corruption, or guaranteed crash on a normal path. Fix before any takeover/ship. |
| **high** | Real bug hit under realistic conditions, or a serious security weakness needing input. Fix soon. |
| **medium** | Bug in an edge case, meaningful tech-debt/risk, or a notable gap. Plan to fix. |
| **low** | Minor correctness/style/docs issue, low blast radius. Fix opportunistically. |

## Prioritization

1. Sort by **severity** (critical → low).
2. Within a severity, sort by **confidence** (confirmed → low).
3. Break ties by **blast radius** (how much code/users it touches) and by
   whether the file is a recon **hotspot** (large or high-churn = higher
   priority — bugs there are more likely to bite and to be touched again).

## Files in this skill

- `findings-schema.json` — the JSON Schema (draft-07) every finding must match.
- `audit-report-template.md` — fill-in structure for the final report.
