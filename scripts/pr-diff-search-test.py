#!/usr/bin/env python3
"""Fixture tests for scripts/pr-diff-search.py: the incident (an open PR already changes the pattern a new fix
targets) is found with PR, file and line; context lines, the other PRs and a bad regex are not hits."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "pr-diff-search.py"
fails = 0


def check(cond, name):
    global fails
    print(("  OK   " if cond else "  FAIL ") + name)
    if not cond:
        fails += 1


DIFF_618 = """diff --git a/helpers/x-gate.cjs b/helpers/x-gate.cjs
index 1..2 100644
--- a/helpers/x-gate.cjs
+++ b/helpers/x-gate.cjs
@@ -10,3 +10,3 @@ function judge(input) {
   const cmd = input.tool_input.command;
-  if (input.tool_name !== 'Bash') return null;
+  if (!SHELL_TOOLS.has(input.tool_name)) return null;
   return check(cmd);
"""
DIFF_620 = """diff --git a/scripts/y.py b/scripts/y.py
new file mode 100644
--- /dev/null
+++ b/scripts/y.py
@@ -0,0 +1,2 @@
+import sys
+print("tool_name context only")
"""
DIFF_621 = """diff --git a/docs/old.md b/docs/old.md
deleted file mode 100644
--- a/docs/old.md
+++ /dev/null
@@ -1,2 +0,0 @@
-line one
-tool_name !== 'Bash' in prose
"""


def run(args, prs):
    with tempfile.TemporaryDirectory() as d:
        fx = Path(d) / "fx.json"
        fx.write_text(json.dumps({"repo": "o/r", "prs": prs}), encoding="utf-8")
        env = dict(os.environ, PR_DIFF_FIXTURE=str(fx))
        r = subprocess.run([sys.executable, str(SCRIPT)] + args, capture_output=True, text=True, encoding="utf-8",
                           env=env, timeout=30)
        return r.returncode, r.stdout + r.stderr


PRS = [{"number": 618, "title": "fix: shell tools", "diff": DIFF_618},
       {"number": 620, "title": "feat: y", "diff": DIFF_620},
       {"number": 621, "title": "docs: drop old", "diff": DIFF_621}]

rc, out = run(["name !== 'Bash'"], PRS)
check(rc == 0, "the incident: a hit exits 0")
check("#618 helpers/x-gate.cjs:11 -" in out, "the removed line is named with PR, file and old-side line")
check("#621 docs/old.md:2 -" in out, "a deleted file keeps its old path")
check("#620" not in out.replace("of 3 open", ""), "a PR without the pattern is not named")
rc, out = run(["SHELL_TOOLS"], PRS)
check("#618 helpers/x-gate.cjs:11 +" in out, "an added line is named with its new-side line")
rc, out = run(["print"], PRS)
check("#620 scripts/y.py:2 +" in out, "a new file: path from the +++ side, line counted from 1")
rc, out = run(["const cmd"], PRS)
check(rc == 1 and "no hit" in out, "a context line is no hit (exit 1)")
rc, out = run(["shell_tools", "-i"], PRS)
check(rc == 0, "-i matches case-insensitively")
rc, out = run(["(unclosed"], PRS)
check(rc == 2 and "bad regex" in out, "a bad regex exits 2 and says so")
# Windows review 2026-11-26: a removed `-- comment` / an added `++ x` line inside a hunk is content, not a header
DIFF_SQL = """diff --git a/db/q.sql b/db/q.sql
--- a/db/q.sql
+++ b/db/q.sql
@@ -1,3 +1,3 @@
 select 1;
--- old needle comment
+++ new needle line
 select 2;
@@ -10,2 +10,2 @@
-tail needle a
+tail needle b
"""
rc, out = run(["needle"], [{"number": 700, "title": "sql", "diff": DIFF_SQL}])
check("#700 db/q.sql:2 - -- old needle comment" in out, "a removed `-- ` line inside a hunk is a hit with its path")
check("#700 db/q.sql:2 + ++ new needle line" in out, "an added `++ ` line inside a hunk is a hit with its path")
check("#700 db/q.sql:10 - tail needle a" in out and "#700 db/q.sql:10 + tail needle b" in out,
      "after such lines the path and the line numbers of the next hunk stay right")
rc, out = run(["needle"], [{"number": 701, "title": "crlf", "diff": DIFF_SQL.replace("\n", "\r\n")}])
check("#701 db/q.sql:10 + tail needle b" in out, "a CRLF diff reads the same")
rc, out = run(["x"], [])
check(rc == 1 and "0 open PR(s)" in out, "no open PR: exit 1, the count said")

print("pr-diff-search-test: " + ("PASS" if not fails else f"{fails} FAIL"))
sys.exit(1 if fails else 0)
