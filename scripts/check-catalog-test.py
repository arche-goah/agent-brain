#!/usr/bin/env python3
"""Fixture for check-catalog.py: the catalog is read from the files that wire the checks, on the real core and on a
small fake core (a new hook appears, a file without a header says so, a non-check skill stays out)."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(HERE, "check-catalog.py")
fails = 0


def check(label, cond):
    global fails
    print(("  OK   " if cond else "  FAIL ") + label)
    fails += 0 if cond else 1


def run(root):
    p = subprocess.run([sys.executable, TOOL, "--root", root], capture_output=True, text=True, encoding="utf-8")
    return p.returncode, p.stdout


rc, out = run(ROOT)
check("real core: exit 0", rc == 0)
for title in ("## Every tool call", "## Every turn end", "## Every commit and push", "## Session start", "## On the operator's OK", "## Self-tests"):
    check(f"real core: section {title[3:]}", title in out)
check("real core: a wired gate is listed with its trigger", "`helpers/merge-request-gate.cjs` | PreToolUse" in out)
check("real core: a stop-check row is listed with its mode", "CLASS-GATE (helpers/class-gate.cjs)` | block" in out)
check("real core: the audit-audit skill is a deep check", "`skill audit-audit`" in out)
check("real core: this fixture is a self-test", "`check-catalog-test.py`" in out)
# Windows review of #479
check("real core: a pre-commit check is listed", "`scripts/leak-scan.py` | git pre-commit" in out)
check("real core: a CI lint step is listed", "CI step: english-only ratchet" in out)
check("real core: memory-dream is a deep check", "`skill memory-dream`" in out)
check("real core: code-audit is no deep check", "`skill code-audit`" not in out)
check("real core: verification-before-completion is no deep check", "skill verification-before-completion" not in out)
check("real core: a gate named only in a bootup comment is no session-start section", "`helpers/open-items-gate.cjs` | section of session-bootup.sh" not in out)
check("real core: checks and self-tests are counted apart", "self-tests that test them" in out)

with tempfile.TemporaryDirectory() as t:
    for d in ("hooks", "helpers", "helpers/git-hooks", "rules", ".github/workflows", "scripts", "workflows", "skills/fake-audit", "skills/fake-writer", "templates/rules-instance"):
        os.makedirs(os.path.join(t, d))
    json.dump({"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": 'node "$CLAUDE_PROJECT_DIR/core/helpers/new-gate.cjs"'}]}]}},
              open(os.path.join(t, "hooks", "hooks.json"), "w", encoding="utf-8"))
    open(os.path.join(t, "helpers", "new-gate.cjs"), "w", encoding="utf-8").write("#!/usr/bin/env node\n/**\n * PreToolUse Hook (Bash): holds a fake call. More text.\n */\n")
    open(os.path.join(t, "helpers", "bare.cjs"), "w", encoding="utf-8").write("#!/usr/bin/env node\nconst x = 1;\n")
    open(os.path.join(t, "helpers", "session-bootup.sh"), "w", encoding="utf-8").write("#!/usr/bin/env bash\nnode core/helpers/bare.cjs\n# see helpers/commented.cjs\necho \"run scripts/advice.sh\"\n")
    open(os.path.join(t, "helpers", "git-hooks", "pre-push"), "w", encoding="utf-8").write('#!/bin/sh\n# scripts/not-run.py\npython3 "$root/scripts/push-check.py"\n')
    open(os.path.join(t, "scripts", "push-check.py"), "w", encoding="utf-8").write('"""Checks a push."""\n')
    open(os.path.join(t, ".github", "workflows", "ci.yml"), "w", encoding="utf-8").write("jobs:\n  lint:\n    steps:\n      - name: fake lint\n        run: true\n")
    open(os.path.join(t, "rules", "intelligence.md"), "w", encoding="utf-8").write("(3) **deep check** — only on a reason: `fake-audit`. The AI tells.\n")
    json.dump({"checks": [{"marker": "FAKE-GATE", "cmd": "core/helpers/new-gate.cjs", "mode": "record", "required": True}]},
              open(os.path.join(t, "templates", "rules-instance", "stop-checks.json"), "w", encoding="utf-8"))
    open(os.path.join(t, "workflows", "fake-scan.js"), "w", encoding="utf-8").write("export const meta = {\n  name: 'fake-scan',\n  description: 'Fake scan of nothing',\n}\n")
    open(os.path.join(t, "skills", "fake-audit", "SKILL.md"), "w", encoding="utf-8").write("---\nname: fake-audit\ndescription: Audit of fakes. Use rarely.\n---\n")
    open(os.path.join(t, "skills", "fake-writer", "SKILL.md"), "w", encoding="utf-8").write("---\nname: fake-writer\ndescription: Writes letters.\n---\n")
    open(os.path.join(t, "scripts", "test-fake.sh"), "w", encoding="utf-8").write("#!/usr/bin/env bash\n")
    rc, out = run(t)
    check("fake core: exit 0", rc == 0)
    check("fake core: the new hook is listed, its prefix cut", "`helpers/new-gate.cjs` | PreToolUse `Bash` | holds a fake call. |" in out)
    check("fake core: a file without a header says so", "`helpers/bare.cjs` | section of session-bootup.sh | (no header) |" in out)
    check("fake core: a template stop row with mode and required", "FAKE-GATE (helpers/new-gate.cjs)` | record, required" in out)
    check("fake core: the workflow is a deep check", "`workflow fake-scan` | Workflow tool | Fake scan of nothing |" in out)
    check("fake core: an audit skill is a deep check", "`skill fake-audit`" in out)
    check("fake core: a non-check skill stays out", "fake-writer" not in out)
    check("fake core: a pre-push script is listed", "`scripts/push-check.py` | git pre-push | Checks a push." in out)
    check("fake core: a commented script in a git hook stays out", "not-run.py" not in out)
    check("fake core: a CI step is listed", "CI step: fake lint" in out)
    check("fake core: bootup comments and advice texts are no sections", "commented.cjs" not in out and "advice.sh" not in out)
    check("fake core: the self-test is counted", "## Self-tests (1)" in out and "`test-fake.sh`" in out)

print("check-catalog-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
