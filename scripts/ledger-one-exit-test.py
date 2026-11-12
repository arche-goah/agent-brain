#!/usr/bin/env python3
"""Fixtures for ledger-one-exit.py: the newest exit stays, the others become was-exit:, and the lint is quiet after.

    python3 scripts/ledger-one-exit-test.py
"""
import importlib.util
import json
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE / "ledger-one-exit.py"
spec = importlib.util.spec_from_file_location("reconcile", HERE / "ledger-reconcile.py")
fails = 0


def check(name, cond, detail=""):
    global fails
    print(("  OK  " if cond else "  FAIL") + f" {name}" + ("" if cond else f" - {detail}"))
    fails += 0 if cond else 1


LEDGER = "\n".join([
    "# Ledger",
    "- [ ] **three exits, newest in the middle**",
    "  id: a",
    "  exit: ai-does-it 2026-11-01 — old",
    "  exit: in-pr 2026-11-05 o/r#1 — newest",
    "  exit: later-at-system 2026-11-03 — middle",
    "- [ ] **same date twice: the later line wins**",
    "  id: b",
    "  exit: ai-does-it 2026-11-06 — first",
    "  exit: other-side 2026-11-06 — second",
    "- [ ] **one exit plus history (control)**",
    "  id: c",
    "  was-exit: ai-does-it 2026-11-01 — history",
    "  exit: in-pr 2026-11-02 o/r#2 — current",
    "- [x] **ticked entry with two exits (control)**",
    "  id: d",
    "  exit: ai-does-it 2026-11-01",
    "  exit: done 2026-11-02",
    "",
])

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "ledgers.json").write_text(json.dumps({"ledgers": ["docs/l.md"]}), encoding="utf-8")
    (root / "docs").mkdir()
    led = root / "docs" / "l.md"
    led.write_text(LEDGER, encoding="utf-8")

    r = subprocess.run([sys.executable, str(TOOL), "--root", str(root)], capture_output=True, text=True)
    check("preview: exit 1 and nothing written", r.returncode == 1 and led.read_text(encoding="utf-8") == LEDGER,
          r.stdout + r.stderr)
    check("preview counts 3 lines in 2 entries", "3 line(s) to rewrite" in r.stdout and "2 entr" in r.stdout, r.stdout)

    r = subprocess.run([sys.executable, str(TOOL), "--root", str(root), "--write"], capture_output=True, text=True)
    out = led.read_text(encoding="utf-8").split("\n")
    check("write: exit 0", r.returncode == 0, r.stdout + r.stderr)
    check("newest by date stays exit:", "  exit: in-pr 2026-11-05 o/r#1 — newest" in out
          and "  was-exit: ai-does-it 2026-11-01 — old" in out
          and "  was-exit: later-at-system 2026-11-03 — middle" in out, "\n".join(out))
    check("same date: the later line stays exit:", "  exit: other-side 2026-11-06 — second" in out
          and "  was-exit: ai-does-it 2026-11-06 — first" in out, "\n".join(out))
    check("one exit plus history unchanged (control)", "  exit: in-pr 2026-11-02 o/r#2 — current" in out
          and "  was-exit: ai-does-it 2026-11-01 — history" in out, "\n".join(out))
    check("ticked entry untouched (control)", "  exit: ai-does-it 2026-11-01" in out and "  exit: done 2026-11-02" in out,
          "\n".join(out))

    # the lint of the convention reads the same lines
    lint = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lint)
    open_texts = [b for b in "\n".join(out).split("\n- [") if b.startswith(" ]")]
    check("after the migration the lint's MULTI_EXIT finds one exit per open entry",
          all(len(lint.MULTI_EXIT.findall(t)) == 1 for t in open_texts), str([len(lint.MULTI_EXIT.findall(t)) for t in open_texts]))

    r = subprocess.run([sys.executable, str(TOOL), "--root", str(root)], capture_output=True, text=True)
    check("second preview: nothing left, exit 0", r.returncode == 0 and "0 line(s)" in r.stdout, r.stdout)

with tempfile.TemporaryDirectory() as tmp:
    r = subprocess.run([sys.executable, str(TOOL), "--root", tmp], capture_output=True, text=True)
    check("no registry: exit 2", r.returncode == 2, f"rc={r.returncode}")

# --staged (the pre-commit step): judges the index, not the working copy, and only registered ledgers
sys.path.insert(0, str(HERE))
import git_sandbox  # noqa: F401,E402  - the host's hooksPath must not run inside the fixture repo
CLEAN = "# Ledger\n- [ ] **one exit**\n  id: e\n  exit: ai-does-it 2026-11-08\n"
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    g = lambda *a: subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True)  # noqa: E731
    g("init", "-q")
    (root / ".claude" / "rules").mkdir(parents=True)
    (root / ".claude" / "rules" / "ledgers.json").write_text(json.dumps({"ledgers": ["docs/l.md"]}), encoding="utf-8")
    (root / "docs").mkdir()
    led = root / "docs" / "l.md"
    staged = lambda: subprocess.run([sys.executable, str(TOOL), "--root", str(root), "--staged"],  # noqa: E731
                                    capture_output=True, text=True)

    led.write_text(LEDGER, encoding="utf-8")
    r = staged()
    check("staged: an unstaged ledger with two exits does not block", r.returncode == 0, r.stdout + r.stderr)

    g("add", "docs/l.md")
    r = staged()
    check("staged: a staged ledger with two exits blocks and names --write", r.returncode == 1 and "--write" in r.stdout
          and led.read_text(encoding="utf-8") == LEDGER, r.stdout + r.stderr)

    led.write_text(CLEAN, encoding="utf-8")
    r = staged()
    check("staged: the STAGED content counts, not a clean working copy", r.returncode == 1, r.stdout + r.stderr)

    g("add", "docs/l.md")
    led.write_text(LEDGER, encoding="utf-8")
    r = staged()
    check("staged: a clean staged ledger passes although the working copy has two exits", r.returncode == 0,
          r.stdout + r.stderr)

    (root / "docs" / "other.md").write_text(LEDGER, encoding="utf-8")
    g("add", "docs/other.md")
    r = staged()
    check("staged: an unregistered file is not a ledger", r.returncode == 0, r.stdout + r.stderr)

    r = subprocess.run([sys.executable, str(TOOL), "--root", str(root), "--staged", "--write"], capture_output=True, text=True)
    check("staged + write is refused", r.returncode == 2, f"rc={r.returncode}")

    # 2026-11-08: an exit kind the aggregator does not know (open-items.py EXITS) is refused at commit time, open entries only
    led.write_text("# Ledger\n- [ ] **free text**\n  id: f\n  exit: ask-operator 2026-11-08\n"
                   "- [x] **ticked, old form**\n  id: g\n  exit: done 2026-11-08\n", encoding="utf-8")
    g("add", "docs/l.md")
    r = staged()
    check("staged: an unknown exit kind on an open entry blocks and names the kinds",
          r.returncode == 1 and "unknown exit kind 'ask-operator'" in r.stdout and "operator-decision" in r.stdout, r.stdout + r.stderr)
    check("staged: a ticked entry's exit kind is not judged", "'done'" not in r.stdout, r.stdout)
    led.write_text("# Ledger\n- [ ] **valid**\n  id: f\n  exit: operator-decision 2026-11-08\n", encoding="utf-8")
    g("add", "docs/l.md")
    r = staged()
    check("staged: a known exit kind passes", r.returncode == 0, r.stdout + r.stderr)

    # a prose line that starts with the field name in a code span is no exit (measured 2026-11-08, two such lines)
    led.write_text("# Ledger\n- [ ] **prose wrap**\n  id: p\n  text before the wrap, then the next line starts with\n"
                   "  `exit: ask-operator` and goes on as prose\n  exit: operator-decision 2026-11-08\n"
                   "- [ ] **span field (control)**\n  id: q\n  `exit: in-pr 2026-11-08 o/r#1`\n", encoding="utf-8")
    g("add", "docs/l.md")
    r = staged()
    check("staged: a prose line starting with `exit: …` is neither an unknown kind nor a second exit",
          r.returncode == 0, r.stdout + r.stderr)
    lint = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lint)
    body = led.read_text(encoding="utf-8")
    check("reconcile MULTI_EXIT counts one exit for the prose-wrapped entry and one for the span field",
          [len(lint.MULTI_EXIT.findall(t)) for t in body.split("\n- [")[1:]] == [1, 1], body)

# Windows review 2026-11-12: the repair command the hint hands out must run as printed under a root with a space
# (shlex.split = the shell's word split; argv[0] is this interpreter, not a bare python3 - OS-17)
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / "my brain"
    (root / ".claude" / "rules").mkdir(parents=True)
    g = lambda *a: subprocess.run(["git", "-C", str(root), *a], capture_output=True, text=True)  # noqa: E731
    g("init", "-q")
    (root / ".claude" / "rules" / "ledgers.json").write_text(json.dumps({"ledgers": ["docs/l.md"]}), encoding="utf-8")
    (root / "docs").mkdir()
    led = root / "docs" / "l.md"
    led.write_text(LEDGER, encoding="utf-8")
    g("add", "docs/l.md")
    r = subprocess.run([sys.executable, str(TOOL), "--root", str(root), "--staged"], capture_output=True, text=True)
    hint = [ln.strip() for ln in r.stdout.splitlines() if ln.strip().startswith("python3 ") and "--write" in ln]
    rr = subprocess.run([sys.executable] + shlex.split(hint[0])[1:], capture_output=True, text=True) if hint else None
    check("staged: the --write hint runs as printed under a root with a space",
          rr is not None and rr.returncode == 0 and "  was-exit: ai-does-it 2026-11-01 — old" in led.read_text(encoding="utf-8"),
          (r.stdout + (rr.stdout + rr.stderr if rr else "")))

    # an unreadable aggregator turns the exit-kind check off, and says so
    lone = Path(tmp) / "lone"
    lone.mkdir()
    (lone / "ledger-one-exit.py").write_text(TOOL.read_text(encoding="utf-8"), encoding="utf-8")
    led.write_text(CLEAN, encoding="utf-8")
    g("add", "docs/l.md")
    r = subprocess.run([sys.executable, str(lone / "ledger-one-exit.py"), "--root", str(root), "--staged"], capture_output=True, text=True)
    check("staged: without open-items.py the exit-kind check is off and says so on stderr",
          r.returncode == 0 and "exit-kind check off" in r.stderr, r.stdout + r.stderr)

print("ledger-one-exit fixtures:", "ALL passed" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
