#!/usr/bin/env python3
"""Fixtures for ledger-reconcile.py — every report class proven, plus its negative."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

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

        json.dump({"ledgers": ["docs/orders.md"], "ratchet_since": "2026-10-19", "timeout_s": 1},
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
        ok(rc == 0, "--brief without --strict exits 0", out)
        rc, _ = run(root, "--strict")
        ok(rc == 1, "--strict exits 1 while DONE-OPEN or REGRESSED exist")
        rc, out = run(root, "--brief", "--shell", str(R / "no-such-shell"))
        ok("done but still open" not in out and "done-but-open (error)" in out,
           "no usable shell: checks are unanswered, never done", out)

        clean = LEDGER.split("Prose after the list.")[0]
        clean = "\n\n".join(b for b in clean.split("\n\n")
                            if "done-but-open" not in b and "ticked-regressed" not in b
                            and "new-no-check" not in b and "hangs" not in b)
        (R / "docs" / "orders.md").write_text(clean, encoding="utf-8")
        rc, out = run(root, "--brief")
        ok(out.strip() == "", "clean ledger, --brief: silent", out)
        rc, out = run(root)
        ok("every check agrees" in out, "clean ledger, full form: says so", out)
        rc, _ = run(root, "--strict")
        ok(rc == 0, "--strict exits 0 when clean")

        json.dump({"ledgers": ["docs/gone.md"]}, open(cfg, "w", encoding="utf-8"))
        rc, out = run(root, "--brief")
        ok("not found" in out and "docs/gone.md" in out, "a registered ledger that is missing is named", out)

    print()
    if fails:
        print(f"ledger-reconcile-test: {fails} FAILURE(S)")
        return 1
    print("ledger-reconcile-test: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
