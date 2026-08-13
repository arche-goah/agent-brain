---
name: test-survey
description: Survey a repo's test landscape — which test framework, how to run tests, source-to-test ratio, and which modules lack tests. Use for "how is this tested", test coverage assessment, finding untested code, or evaluating test health of an unfamiliar codebase.
---

# Test Survey

## What this skill does

Gives a fast, **structural picture of how a repo is tested** without running
anything. It:

- Finds **test files** by convention: `test_*.py`, `*_test.py`, `*_test.go`,
  `*.test.{js,ts,jsx,tsx}`, `*.spec.{js,ts,...}`, `*Test.java`, `*_spec.rb`,
  and anything under `tests/`, `test/`, `__tests__/`, `spec/`.
- Detects the **framework**: pytest, unittest, jest, vitest, mocha, jasmine,
  go test, junit, rspec — from manifests, config files, and (as a fallback)
  test-file imports.
- Finds the **test command** from `package.json` scripts, Makefile `test`
  targets, and `tox.ini`.
- Computes a **source-to-test file ratio**.
- Lists **source areas with no co-located tests** (heuristic) so you can spot
  likely coverage gaps.

## CRITICAL: structural estimate, not real coverage

The ratio and "untested areas" list are **naming-convention heuristics**, not
line/branch coverage. They can produce false positives (e.g. code exercised by
tests in a central `tests/` directory). For ground-truth coverage, run the
real tool:

| Stack  | Command |
|--------|---------|
| Python | `pytest --cov=. --cov-report=term-missing` |
| JS/TS  | `jest --coverage`  or  `vitest run --coverage` |
| Go     | `go test -cover ./...` |
| Rust   | `cargo tarpaulin`  or  `cargo llvm-cov` |

## How it relates to the built-in review commands

This skill identifies *where tests are thin*; the built-in `/code-review` can
then scrutinize the under-tested code paths it flags. It's comprehension, not
a replacement for running the suite or a coverage tool.

## Usage

```bash
python3 test_survey.py --path /path/to/repo          # Markdown report
python3 test_survey.py --path /path/to/repo --json   # JSON
```

Flags:
- `--path DIR` — target repo (default: current directory).
- `--json` — emit JSON instead of Markdown.

## Guarantees

- **READ-ONLY**, **zero dependencies** (Python 3.8+ stdlib), fully **offline**.
- Skips noise dirs by default.
- Honest when there's little or no formal test setup — it says so rather than
  inventing a framework or command.

## Interpreting the output

- A **ratio near 0** with **no framework/command** usually means the repo has
  little or no automated testing — a real risk for a takeover.
- A healthy ratio varies by stack and style; treat it as a relative signal,
  then confirm with a coverage run.
- Always sanity-check the **untested areas** list against where the repo
  actually keeps its tests before reporting gaps.
