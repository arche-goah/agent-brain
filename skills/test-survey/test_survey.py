#!/usr/bin/env python3
"""
test-survey — structural survey of a repo's test landscape.

READ-ONLY: scans the target repo and prints a report to stdout. Never modifies
the target; never reaches the network. Zero third-party dependencies
(Python 3.8+ stdlib only).

It detects test files by convention, infers the framework and test command,
computes a source-to-test file ratio, and lists source dirs/modules that
appear to have NO corresponding tests. These are STRUCTURAL ESTIMATES, not
real coverage — run the actual coverage tools (see SKILL.md) for true numbers.

Usage:
    python3 test_survey.py [--path DIR] [--json]
"""

import argparse
import json
import os
import re
import sys
from collections import Counter

NOISE_DIRS = {
    ".git", "node_modules", "venv", ".venv", "dist", "build", "__pycache__",
    "target", ".next", "vendor", ".idea", ".gradle",
}

# Source-code extensions we care about for the source/test ratio.
SOURCE_EXTS = {
    ".py", ".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".go", ".rs",
    ".java", ".kt", ".rb", ".php", ".c", ".cpp", ".cc", ".cs", ".swift",
    ".scala",
}

# Directory names that, by convention, hold tests.
TEST_DIRS = {"tests", "test", "__tests__", "spec", "specs"}


def is_test_file(rel):
    """True if a path looks like a test file by common naming conventions."""
    base = os.path.basename(rel)
    parts = rel.replace("\\", "/").split("/")
    # Anything living inside a conventional test directory.
    if any(p in TEST_DIRS for p in parts[:-1]):
        return True
    patterns = [
        r"^test_.*\.py$", r".*_test\.py$",          # Python (pytest/unittest)
        r".*_test\.go$",                              # Go
        r".*\.test\.(js|jsx|ts|tsx|mjs|cjs)$",        # Jest/Vitest
        r".*\.spec\.(js|jsx|ts|tsx|mjs|cjs)$",        # Jasmine/Mocha/Vitest
        r".*Test\.java$", r".*Tests\.java$",          # JUnit
        r".*_spec\.rb$", r".*_test\.rb$",             # RSpec / minitest
    ]
    return any(re.match(p, base) for p in patterns)


def detect_framework(path, test_files):
    """Infer test framework(s) from manifests, config, and imports."""
    fw = set()

    # --- Manifest / config signals -----------------------------------------
    pkg_path = os.path.join(path, "package.json")
    try:
        with open(pkg_path, encoding="utf-8") as fh:
            pkg = json.load(fh)
    except (OSError, ValueError):
        pkg = None
    if isinstance(pkg, dict):
        blob = json.dumps({
            k: pkg.get(k) for k in
            ("dependencies", "devDependencies", "scripts")
            if k in pkg
        }).lower()
        for name in ("jest", "vitest", "mocha", "jasmine", "ava", "cypress",
                     "playwright"):
            if name in blob:
                fw.add(name)

    def exists(*rel):
        return any(os.path.exists(os.path.join(path, r)) for r in rel)

    if exists("pytest.ini", "conftest.py", "tox.ini"):
        fw.add("pytest")
    if exists("jest.config.js", "jest.config.ts", "jest.config.cjs",
              "jest.config.mjs"):
        fw.add("jest")
    if exists("vitest.config.js", "vitest.config.ts", "vite.config.ts"):
        fw.add("vitest")
    if exists("go.mod"):
        # go test is built in; only claim it if there are *_test.go files.
        if any(f.endswith("_test.go") for f in test_files):
            fw.add("go test")
    if exists("Gemfile", ".rspec"):
        if any(f.endswith("_spec.rb") for f in test_files):
            fw.add("rspec")
    if exists("pom.xml", "build.gradle", "build.gradle.kts"):
        if any(re.search(r"Tests?\.java$", f) for f in test_files):
            fw.add("junit")

    # --- pyproject / requirements ------------------------------------------
    for cfg in ("pyproject.toml", "requirements.txt", "requirements-dev.txt",
                "setup.cfg"):
        cp = os.path.join(path, cfg)
        if os.path.isfile(cp):
            try:
                with open(cp, encoding="utf-8", errors="replace") as fh:
                    txt = fh.read().lower()
                if "pytest" in txt:
                    fw.add("pytest")
                if re.search(r"\bunittest\b", txt):
                    fw.add("unittest")
            except OSError:
                pass

    # --- Fallback: peek at a few Python test files for imports -------------
    if not fw:
        for tf in test_files[:25]:
            if tf.endswith(".py"):
                try:
                    with open(os.path.join(path, tf), encoding="utf-8",
                              errors="replace") as fh:
                        head = fh.read(2000)
                    if "import pytest" in head:
                        fw.add("pytest")
                    elif "import unittest" in head or "from unittest" in head:
                        fw.add("unittest")
                except OSError:
                    pass

    return sorted(fw)


def detect_test_command(path):
    """Find the documented test command from package.json / Makefile / tox."""
    cmds = []
    pkg_path = os.path.join(path, "package.json")
    try:
        with open(pkg_path, encoding="utf-8") as fh:
            pkg = json.load(fh)
        scripts = pkg.get("scripts", {}) if isinstance(pkg, dict) else {}
        for name, body in scripts.items():
            if "test" in name.lower():
                cmds.append(f"npm run {name}  →  {body}")
    except (OSError, ValueError):
        pass

    mk = os.path.join(path, "Makefile")
    if os.path.isfile(mk):
        try:
            with open(mk, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if line and not line[0].isspace() and ":" in line:
                        target = line.split(":", 1)[0].strip()
                        if target.lower() in ("test", "tests", "check"):
                            cmds.append(f"make {target}")
        except OSError:
            pass

    if os.path.isfile(os.path.join(path, "tox.ini")):
        cmds.append("tox")
    return cmds


def survey(path):
    source_files = []
    test_files = []
    # Track which top-level (and second-level) source dirs contain tests.
    dirs_with_source = set()
    dirs_with_tests = set()

    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if d not in NOISE_DIRS]
        for name in files:
            ap = os.path.join(root, name)
            if os.path.islink(ap):
                continue
            rel = os.path.relpath(ap, path)
            ext = os.path.splitext(name)[1].lower()
            testish = is_test_file(rel)
            # Group key = first two path components (or the single root file).
            parts = rel.replace("\\", "/").split("/")
            group = "/".join(parts[:2]) if len(parts) > 1 else "(root)"
            if testish:
                test_files.append(rel)
                dirs_with_tests.add(group)
            elif ext in SOURCE_EXTS:
                source_files.append(rel)
                dirs_with_source.add(group)

    untested = sorted(dirs_with_source - dirs_with_tests)
    frameworks = detect_framework(path, test_files)
    commands = detect_test_command(path)

    n_src = len(source_files)
    n_test = len(test_files)
    ratio = round(n_test / n_src, 3) if n_src else None

    # Test-file extension breakdown for a quick at-a-glance.
    test_ext = Counter(os.path.splitext(f)[1].lower() or "(none)"
                       for f in test_files)

    return {
        "root": os.path.abspath(path),
        "source_file_count": n_src,
        "test_file_count": n_test,
        "test_to_source_ratio": ratio,
        "frameworks": frameworks,
        "test_commands": commands,
        "test_file_extensions": test_ext.most_common(),
        "untested_dirs": untested,
        "dirs_with_tests": sorted(dirs_with_tests),
    }


COVERAGE_NOTE = """\
## For REAL coverage numbers, run a coverage tool

This survey is STRUCTURAL ONLY — file counts and a heuristic ratio, not line
or branch coverage. The "untested dirs" list is a naming-convention heuristic
and can produce false positives (e.g. a dir covered by tests located
elsewhere). For ground truth:

| Stack  | Command |
|--------|---------|
| Python | `pytest --cov=. --cov-report=term-missing` |
| JS/TS  | `jest --coverage`  or  `vitest run --coverage` |
| Go     | `go test -cover ./...` |
| Rust   | `cargo tarpaulin`  or  `cargo llvm-cov` |
| Ruby   | SimpleCov (require in `spec_helper.rb`) |
"""


def render_markdown(s):
    L = []
    a = L.append
    a(f"# Test Survey — `{s['root']}`\n")

    a("## Summary\n")
    a(f"- **Source files:** {s['source_file_count']:,}")
    a(f"- **Test files:** {s['test_file_count']:,}")
    if s["test_to_source_ratio"] is None:
        a("- **Test-to-source ratio:** n/a (no source files counted)")
    else:
        a(f"- **Test-to-source file ratio:** {s['test_to_source_ratio']} "
          f"(test files ÷ source files)")
    a("")

    a("## Frameworks detected\n")
    if s["frameworks"]:
        for f in s["frameworks"]:
            a(f"- {f}")
    else:
        a("- (none detected — repo may have no formal test setup)")
    a("")

    a("## Test command\n")
    if s["test_commands"]:
        for c in s["test_commands"]:
            a(f"- `{c}`")
    else:
        a("- (no test command found in package.json / Makefile / tox.ini)")
    a("")

    if s["test_file_extensions"]:
        a("## Test files by extension\n")
        a("| Ext | Count |")
        a("|---|--:|")
        for ext, n in s["test_file_extensions"]:
            a(f"| `{ext}` | {n} |")
        a("")

    a("## Source areas with NO co-located tests (heuristic)\n")
    if not s["source_file_count"]:
        a("- (no source files to assess)")
    elif s["untested_dirs"]:
        a("These top-level/second-level source areas have source files but no "
          "test files by naming convention. Verify before trusting — tests may "
          "live in a central `tests/` tree.\n")
        for d in s["untested_dirs"]:
            a(f"- `{d}`")
    else:
        a("- None — every source area has at least one co-located test file.")
    a("")

    a(COVERAGE_NOTE)
    return "\n".join(L)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Structural test-landscape survey (read-only).")
    p.add_argument("--path", default=".", help="Target repo path (default: .)")
    p.add_argument("--json", action="store_true", help="Emit JSON")
    args = p.parse_args(argv)

    if not os.path.isdir(args.path):
        sys.stderr.write(f"error: not a directory: {args.path}\n")
        return 2

    result = survey(args.path)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(render_markdown(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
