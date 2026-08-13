---
name: dependency-audit
description: Inventory a repo's dependencies across ecosystems (npm, pip, go, cargo, bundler, composer) — versions, dev/prod, pinned vs floating — and point to the right vulnerability/outdated scanners. Use for "what does this depend on", dependency review, supply-chain inventory, or auditing third-party packages in an unfamiliar repo.
---

# Dependency Audit

## What this skill does

Builds a **unified, offline inventory** of a repo's third-party dependencies
across ecosystems and surfaces simple supply-chain hygiene signals. It parses:

- **npm** — `package.json` (+ `package-lock.json`)
- **pip** — `requirements.txt`, `pyproject.toml` (PEP 621 + Poetry),
  `poetry.lock`
- **Go** — `go.mod`
- **Rust** — `Cargo.toml` (+ `Cargo.lock`)
- **Ruby** — `Gemfile.lock`
- **PHP** — `composer.json`

For each dependency it records name, version/spec, ecosystem, dev-vs-prod
scope, and pinned-vs-floating. The report aggregates counts per ecosystem,
lists **unpinned production dependencies** (reproducibility / supply-chain
risk), and flags names that appear in **multiple ecosystems**.

## CRITICAL: this is inventory only — it does NOT detect vulnerabilities

The script runs fully offline and reports only what the manifests literally
say plus structural heuristics. **It does NOT invent CVEs, "outdated"
warnings, or vulnerability claims** — doing so would be hallucination. For real
vulnerability and outdated data, run the ecosystem's own scanner online:

| Ecosystem | Vulnerabilities | Outdated |
|-----------|-----------------|----------|
| npm       | `npm audit`     | `npm outdated` |
| pip       | `pip-audit`     | `pip list --outdated` |
| go        | `govulncheck ./...` | `go list -m -u all` |
| cargo     | `cargo audit`   | `cargo outdated` |
| any       | `osv-scanner --recursive .` | — |

## How it relates to the built-in review commands

This complements the built-in `/security-review`: this skill gives the
*inventory and pinning posture*; `/security-review` does the deep dependency
and code security analysis. Run this first to know what's in the tree, then
point the scanners above and `/security-review` at anything concerning.

## Usage

```bash
python3 dep_audit.py --path /path/to/repo          # Markdown report
python3 dep_audit.py --path /path/to/repo --json   # JSON inventory
```

Flags:
- `--path DIR` — target repo (default: current directory).
- `--json` — emit JSON instead of Markdown.

## Guarantees

- **READ-ONLY**, **zero dependencies** (Python 3.8+ stdlib), fully **offline**.
- Skips noise dirs (`node_modules`, `vendor`, `target`, `.venv`, etc.) so it
  inventories *declared* deps, not installed transitive trees (lockfiles
  excepted, which it parses directly).
- Degrades gracefully: missing or malformed manifests are skipped, not fatal.

## Interpreting the output

- **Unpinned prod deps** are the headline hygiene signal — they make builds
  non-reproducible and widen the supply-chain attack surface. A committed
  lockfile mitigates this even when specs float.
- **Cross-ecosystem names** can indicate duplicated functionality or a
  polyglot service worth a closer look.
- High **dev vs prod** ratios are normal; what matters is the prod surface.
