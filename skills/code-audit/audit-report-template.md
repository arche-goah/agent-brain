# Code Audit — <REPO NAME>

- **Repo:** `<absolute path or URL>`
- **Audited:** <YYYY-MM-DD>
- **Auditor:** <agent/human>
- **Scope:** <whole repo | subtree | specific dimensions>
- **Recon basis:** <link/note to repo-recon output>

## Executive summary

<3-6 sentences: what the project is, overall health, the single most important
thing to fix, and whether it's safe to take over / ship. State residual risk
and what was NOT covered.>

## Severity counts

| Severity | Count |
|----------|------:|
| Critical | 0 |
| High     | 0 |
| Medium   | 0 |
| Low      | 0 |

## Prioritized findings

> Sorted by severity, then confidence. Each maps to `findings-schema.json`.
> Refuted findings have been removed (kept in an appendix if useful).

### F-001 — <title>
- **Location:** `path/to/file.py:123`
- **Dimension:** correctness
- **Severity:** high  |  **Confidence:** confirmed
- **Evidence:**
  ```
  <offending code / trace / the reasoning the verifier could not refute>
  ```
- **Recommendation:** <specific, actionable fix>

### F-002 — <title>
- **Location:** `path/to/other.ts:45-60`
- **Dimension:** input-validation-security
- **Severity:** critical  |  **Confidence:** high
- **Evidence:** ...
- **Recommendation:** ...

<repeat per finding>

## Dimension coverage

| Dimension | Reviewed? | Notes |
|-----------|:---------:|-------|
| Correctness / logic bugs | ✅ | |
| Error & exception handling | ✅ | |
| Concurrency / race conditions | ✅ | |
| Input validation & security surface | ✅ | deferred deep scan to `/security-review` |
| Resource / memory leaks | ✅ | |
| Dead & duplicated code | ✅ | |
| Dependency risk | ✅ | from `dependency-audit` |
| Test coverage gaps | ✅ | from `test-survey` |
| Docs/comment accuracy vs code | ✅ | |

## Recommended next steps

1. Run `/security-review` against: <files/areas>.
2. Run `/code-review` on the diff once fixes begin.
3. Run the real coverage and vulnerability scanners (see `test-survey` /
   `dependency-audit`).
4. <other follow-ups>

## Appendix — refuted / dropped candidate findings

<Findings raised by reviewers but refuted during verification, with the reason.
Kept for transparency so they aren't re-raised next audit.>
