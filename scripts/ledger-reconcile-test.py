#!/usr/bin/env python3
"""Fixtures for ledger-reconcile.py — every report class proven, plus its negative."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import time

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = os.environ.get("LEDGER_RECONCILE_SCRIPT") or str(HERE / "ledger-reconcile.py")

LEDGER = """# Orders

- [ ] **done in passing, still open** — derived (2026-10-15)
  check: test -f marker-present
  id: done-but-open

- [ ] **really open** — derived (2026-10-15)
  check: test -f marker-absent
  id: really-open

- [x] **ticked, but broke again** — derived (2026-10-10)
  check: test -f marker-absent
  id: ticked-regressed

- [x] **ticked and holds** — derived (2026-10-10)
  check: test -f marker-present
  id: ticked-holds

- [ ] **judgement only** — derived (2026-10-18)
  check: none — needs the operator's eye
  id: declared-none

- [ ] **new and no check** — derived (2026-10-20)
  id: new-no-check · class: todo · reach: brain

- [ ] **old and no check** — derived (2026-09-01)
  id: old-no-check

- [ ] **check that hangs** — derived (2026-10-15)
  check: sleep 5
  id: hangs

- [ ] **check that would write** — derived (2026-10-15)
  check: touch written-by-check
  id: writes

- [ ] **check with a redirection** — derived (2026-10-15)
  check: grep -q x marker-present > written-by-redirect
  id: redirects

- [ ] **git that is not a read** — derived (2026-10-15)
  check: test -f marker-present && git push
  id: git-push

Prose after the list.
- [ ] **entry without an id field** — derived (2026-10-21)
  check: test -f marker-present
"""


def run(root, *args):
    r = subprocess.run([sys.executable, SCRIPT, "--root", root, *args],
                       capture_output=True, text=True, encoding="utf-8")
    return r.returncode, r.stdout + r.stderr


def main():
    fails = 0

    def ok(cond, label, out=""):
        nonlocal fails
        if cond:
            print(f"  OK   {label}")
        else:
            fails += 1
            print(f"  FAIL {label}")
            if out:
                print("       " + out.replace("\n", "\n       "))

    with tempfile.TemporaryDirectory() as root:
        R = pathlib.Path(root)
        (R / "marker-present").write_text("")
        (R / "docs").mkdir()
        (R / "docs" / "orders.md").write_text(LEDGER, encoding="utf-8")
        (R / ".claude" / "rules").mkdir(parents=True)
        cfg = R / ".claude" / "rules" / "ledgers.json"

        rc, out = run(root)
        ok("no ledgers registered" in out and rc == 0, "no config: says nothing is registered, exit 0", out)
        rc, out = run(root, "--brief")
        ok(out.strip() == "" and rc == 0, "no config, --brief: silent", out)

        allowed = ["test", "sleep"]   # sleep only so the fixture can provoke a timeout
        json.dump({"ledgers": ["docs/orders.md"], "ratchet_since": "2026-10-19", "timeout_s": 1,
                   "budget_s": 30, "allowed": allowed},
                  open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        done_line = next((l for l in out.splitlines() if "done but still open" in l), "")
        ok("done-but-open" in done_line, "open entry whose check passes = DONE-OPEN", out)
        ok("really-open" not in out, "open entry whose check fails is not reported", out)
        ok("docs/orders.md:" in done_line, "an entry without an id is named by file:line", out)
        reg = next((l for l in out.splitlines() if "whose check fails" in l), "")
        ok("ticked-regressed" in reg and "ticked-holds" not in reg, "ticked entry whose check fails = REGRESSED, the holding one not", out)
        ok("declared-none" not in out, "`check: none — <why>` is a declaration, never reported", out)
        nc = next((l for l in out.splitlines() if "without a `check:`" in l), "")
        ok("new-no-check" in nc and "old-no-check" not in nc, "ratchet: only open entries dated on/after ratchet_since", out)
        ok("class: todo" not in nc, "fields kept on one line: the id is its first word", out)
        br = next((l for l in out.splitlines() if "could not give an answer" in l), "")
        ok("hangs (timeout)" in br, "a check that times out is reported as such", out)
        ok("hangs" not in done_line, "a timed-out check is never counted as done", out)
        rf = next((l for l in out.splitlines() if "refused, not run" in l), "")
        ok("writes" in rf and not (R / "written-by-check").exists(),
           "`touch x` is refused and never runs (the file does not appear)", out)
        ok("redirects" in rf and not (R / "written-by-redirect").exists(),
           "a redirection is refused and never runs", out)
        ok("git-push" in rf, "a part after && that is not on the list (git push) refuses the whole check", out)

        # budget: two hanging checks against a 1.5 s budget -> the second is not reached
        two = LEDGER.split("Prose after the list.")[0] + (
            "\n- [ ] **second hang** — derived (2026-10-15)\n  check: sleep 5\n  id: hangs-too\n")
        (R / "docs" / "orders.md").write_text(two, encoding="utf-8")
        json.dump({"ledgers": ["docs/orders.md"], "timeout_s": 1, "budget_s": 1.5, "allowed": allowed},
                  open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        nr = next((l for l in out.splitlines() if "not reached within" in l), "")
        ok("hangs-too" in nr, "budget: a check the budget does not reach is named as not run", out)
        ok("hangs-too" not in next((l for l in out.splitlines() if "done but still open" in l), ""),
           "budget: a check not run is never counted as done", out)
        (R / "docs" / "orders.md").write_text(LEDGER, encoding="utf-8")
        json.dump({"ledgers": ["docs/orders.md"], "ratchet_since": "2026-10-19", "timeout_s": 1,
                   "budget_s": 30, "allowed": allowed}, open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        ok(rc == 0, "--brief without --strict exits 0", out)
        rc, _ = run(root, "--strict")
        ok(rc == 1, "--strict exits 1 while DONE-OPEN or REGRESSED exist")
        rc, out = run(root, "--brief", "--shell", str(R / "no-such-shell"))
        ok("done but still open" not in out and "done-but-open (error)" in out,
           "no usable shell: checks are unanswered, never done", out)

        clean = LEDGER.split("Prose after the list.")[0]
        clean = "\n\n".join(b for b in clean.split("\n\n")
                            if "done-but-open" not in b and "ticked-regressed" not in b
                            and "new-no-check" not in b and "hangs" not in b
                            and "writes" not in b and "redirects" not in b and "git-push" not in b)
        (R / "docs" / "orders.md").write_text(clean, encoding="utf-8")
        rc, out = run(root, "--brief")
        ok(out.strip() == "", "clean ledger, --brief: silent", out)
        rc, out = run(root)
        ok("every check agrees" in out, "clean ledger, full form: says so", out)
        rc, _ = run(root, "--strict")
        ok(rc == 0, "--strict exits 0 when clean")

        # --cached: the session start's mode — previous result now, next run in the background
        (R / "docs" / "orders.md").write_text(LEDGER.split("- [ ] **check that hangs**")[0], encoding="utf-8")
        json.dump({"ledgers": ["docs/orders.md"]}, open(cfg, "w", encoding="utf-8"))
        t0 = time.monotonic()
        rc, out = run(root, "--cached")
        ok(out.strip() == "" and rc == 0, "--cached, first start: silent (no earlier result)", out)
        ok(time.monotonic() - t0 < 5, "--cached returns without waiting for the checks")
        brief = R / ".claude-state" / "ledger-reconcile.brief"
        for _ in range(100):
            if brief.exists():
                break
            time.sleep(0.1)
        ok(brief.exists() and "done-but-open" in brief.read_text(encoding="utf-8"),
           "--cached: the background run writes its brief result")
        rc, out = run(root, "--cached")
        ok("done-but-open" in out and "result of" in out, "--cached, next start: shows that result with its time", out)
        brief.write_text("", encoding="utf-8")
        rc, out = run(root, "--cached")
        ok(out.strip() == "", "--cached after a clean run: silent", out)
        for _ in range(100):
            if brief.read_text(encoding="utf-8").strip():
                break
            time.sleep(0.1)

        # the default allow list (no "allowed" in the config)
        (R / "docs" / "orders.md").write_text(
            "- [ ] **reads** — derived (2026-10-15)\n  check: grep -q . marker-present || test -f marker-present\n  id: default-read\n\n"
            "- [ ] **writes** — derived (2026-10-15)\n  check: touch written-by-default\n  id: default-write\n\n"
            "- [ ] **find deletes** — derived (2026-10-15)\n  check: find . -name victim -delete\n  id: bypass-find\n\n"
            "- [ ] **single amp** — derived (2026-10-15)\n  check: test -f victim & rm -f victim\n  id: bypass-amp\n\n"
            "- [ ] **process substitution** — derived (2026-10-15)\n  check: diff <(rm -f victim) marker-present\n  id: bypass-procsub\n",
            encoding="utf-8")
        (R / "victim").write_text("keep me")
        json.dump({"ledgers": ["docs/orders.md"]}, open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        ok("default-read" in out and "done but still open" in out, "default list: grep/test run", out)
        ok("default-write" in next((l for l in out.splitlines() if "refused" in l), "")
           and not (R / "written-by-default").exists(), "default list: touch is refused", out)
        refl = next((l for l in out.splitlines() if "refused" in l), "")
        ok(all(i in refl for i in ("bypass-find", "bypass-amp", "bypass-procsub")) and (R / "victim").exists(),
           "default list: find -delete, a single & and <(...) are refused, the file they target still exists", out)

        json.dump({"ledgers": ["docs/gone.md"]}, open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        ok("not found" in out and "docs/gone.md" in out, "a registered ledger that is missing is named", out)

    # The allow list against known bypasses (review of this PR, 2026-10-19: the first list let
    # the four writers below through). The shell grammar is closed, so these are refused by
    # shape, not by name; the reading forms stay allowed.
    import importlib.util
    spec = importlib.util.spec_from_file_location("lr", SCRIPT)
    lr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(lr)
    for cmd in ["find . -name x -delete", "find . -name x -exec rm {} ;", "find . -exec rm {} +",
                "test -f a & rm -f b", "diff <(rm -f b) a", "git diff --output=out.txt",
                "git log --output out.txt", "git grep -Ovi x", "test -f a; rm -f b",
                "grep x a > b", "cat $(rm -f b)", "cat `rm -f b`", "test -f a\nrm -f b",
                "git -c core.pager=rm log", "git push", "touch x"]:
        ok(not lr.permitted(cmd, lr.ALLOWED), f"refused: {cmd!r}")
    for cmd in ["grep -q x file", "test -f a && git log -1 --format=%H", "git log --oneline | grep -q fix",
                "! grep -q TODO notes.md", "ls docs || test -d docs", "git diff --quiet HEAD -- a.md"]:
        ok(lr.permitted(cmd, lr.ALLOWED), f"allowed: {cmd!r}")

    print()
    if fails:
        print(f"ledger-reconcile-test: {fails} FAILURE(S)")
        return 1
    print("ledger-reconcile-test: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
