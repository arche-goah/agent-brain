---
name: repo-recon
description: Rapidly orient in a large, unfamiliar codebase — map structure, languages, entry points, build/test/run commands, dependencies, and hotspots into a written report. Use when starting on a new/unknown repo, onboarding to a codebase, "understand this repo", "what is this project", auditing or reviewing an unfamiliar repository before making changes.
---

# Repo Recon

## What this skill does

Produces a fast, written **orientation report** for a repository you did not
write. Run it the moment you walk into an unfamiliar codebase, before reading
files one by one. It answers: *what is this, what is it built with, how do I
run it, and where is the action?*

The report covers:

- **Summary** — total files, total lines of code, on-disk size; and if it's a
  git repo: remote, current branch, total commit count, last 5 commits.
- **Languages** — breakdown by file count and by LOC.
- **Directory map** — top 2-3 levels with per-dir file counts and sizes.
- **Detected stack & tooling** — package.json, pyproject.toml, go.mod,
  Cargo.toml, pom.xml, build.gradle, Gemfile, composer.json, Dockerfile,
  docker-compose, Makefile, and CI configs (GitHub Actions, GitLab, etc.).
- **Build/test/run commands** — extracted from package.json `scripts`,
  Makefile targets, and pyproject `[project.scripts]`.
- **Entry points** — main.py, index.js, manage.py, cmd/*, bin/*, etc.
- **Dependency manifests** — found, with cheap dependency counts.
- **Hotspots** — largest source files by LOC, and most-churned files via git
  history (last 500 commits).
- **Config & docs** — README/CONTRIBUTING/etc., docs/, env templates.

## How it relates to the built-in review commands

This skill is **comprehension**, not deep review. It feeds the built-in
`/code-review` (line-by-line diff review) and `/security-review` (deep
security scan) by telling you *where to point them*. Use repo-recon first to
get the lay of the land, then dispatch those commands at the hotspots and
high-risk surfaces it reveals. See the `code-audit` skill for the full
whole-repo audit methodology that orchestrates all of these.

## Usage

```bash
# Markdown report for the current directory
python3 recon.py

# A specific repo, top-20 lists
python3 recon.py --path /path/to/repo --top 20

# Machine-readable JSON (for piping into an audit pipeline)
python3 recon.py --path /path/to/repo --json
```

Flags:
- `--path DIR` — target repo (default: current directory).
- `--top N` — how many items in each top-N list (default: 15).
- `--json` — emit JSON instead of Markdown.

## Guarantees

- **READ-ONLY.** The script only reads the target and prints to stdout. It
  never writes to or modifies the target repo.
- **Zero dependencies.** Python 3.8+ stdlib only; runs fully offline.
- **Graceful when not git.** Git facts (remote, commits, churn) are skipped
  with a clear note if the target isn't a git repo or git is unavailable.
- **Noise excluded.** Skips `.git, node_modules, venv, .venv, dist, build,
  __pycache__, target, .next, vendor, .idea, .gradle` by default.

## Typical workflow

1. Run `recon.py` against the unknown repo and read the report.
2. Note the entry points, the build/test commands, and the hotspots.
3. Hand off to `code-audit` for a structured, dimension-by-dimension audit,
   or run the project's own test command (see `test-survey`) and inventory
   its dependencies (see `dependency-audit`).
