#!/usr/bin/env python3
"""Fixtures for ledger-one-exit.py: the newest exit stays, the others become was-exit:, and the lint is quiet after.

    python3 scripts/ledger-one-exit-test.py
"""
import importlib.util
import json
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

print("ledger-one-exit fixtures:", "ALL passed" if not fails else f"{fails} FAILED")
sys.exit(1 if fails else 0)
