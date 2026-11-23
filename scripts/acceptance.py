#!/usr/bin/env python3
"""Acceptance before handover: a result (render, preview, screenshot, any image) reaches the operator only with an
acceptance file next to it.

WHY (operator order 2026-11-23, "make it work for everything, in the core"): in one session the operator was shown
images carrying dimension labels, helper light cones, candidate markers, spot lights of an old variant, round light
spots where a projector throws a rectangle, and a cabinet the operator had said does not exist. Cause: the agent
checked its own task list and its measurements, never the whole result with the operator's eyes. The skill
`acceptance-before-handover` holds the procedure; this script is its carrier.

The acceptance is `<result>.acceptance.json` next to the result, newer than the result, with three fields of
substance (each at least MIN_LEN characters):
  inventory    everything visible in the result, and what of it the agent added on the side (helpers, text, lights)
               - each removed, or kept with a reason
  facts        which facts file of the project (the operator's own statements about reality) was checked, and what
               it showed
  fresh_eyes   what an agent that got ONLY the result and the operator's words reported as wrong, odd or
               unrealistic, and what happened to each point

Usage:
  acceptance.py write <result> --inventory TEXT --facts TEXT --fresh-eyes TEXT
  acceptance.py check <result>            exit 0 = accepted, 1 = not
  acceptance.py open  <result>            opens the result in the default viewer ONLY when accepted
  acceptance.py selftest
"""
import json
import os
import sys
import tempfile
import time
import webbrowser
from pathlib import Path

FIELDS = ("inventory", "facts", "fresh_eyes")
MIN_LEN = 25  # fewer characters is a phrase, not a check


def side(path):
    return str(path) + ".acceptance.json"


def check(path):
    if not os.path.exists(path):
        return False, "result missing: %s" % path
    s = side(path)
    if not os.path.exists(s):
        return False, "no acceptance next to the result (%s)" % s
    if os.path.getmtime(s) < os.path.getmtime(path):
        return False, "acceptance is older than the result - the result changed after it"
    try:
        with open(s, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError) as e:
        return False, "acceptance unreadable: %s" % e
    for k in FIELDS:
        if len(str(d.get(k, "")).strip()) < MIN_LEN:
            return False, "field '%s' missing or too thin (under %d characters)" % (k, MIN_LEN)
    return True, "accepted"


def write(path, inventory, facts, fresh):
    d = {"result": os.path.abspath(path), "time": time.strftime("%Y-%m-%d %H:%M:%S"),
         "inventory": inventory, "facts": facts, "fresh_eyes": fresh}
    Path(side(path)).write_bytes(json.dumps(d, ensure_ascii=False, indent=2).encode("utf-8") + b"\n")
    return check(path)


def open_result(path):
    ok, why = check(path)
    if ok:
        webbrowser.open(Path(path).resolve().as_uri())  # browser, not the OS image viewer: it renders at once
    return ok, why


def selftest():
    d = tempfile.mkdtemp()
    p = str(Path(d) / "image.png")
    Path(p).write_bytes(b"x")
    assert not check(p)[0], "without acceptance it must not pass"
    write(p, "short", "f" * 30, "e" * 30)
    assert not check(p)[0], "a thin field must fail"
    write(p, "i" * 30, "f" * 30, "e" * 30)
    assert check(p)[0], "a full acceptance must pass"
    time.sleep(1.1)
    Path(p).write_bytes(b"changed")
    assert not check(p)[0], "a result changed after its acceptance must fail"
    print("acceptance selftest ok")


def arg(name):
    a = sys.argv
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else ""


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    cmd = sys.argv[1]
    if cmd == "selftest":
        selftest()
        return 0
    if len(sys.argv) < 3 or cmd not in ("write", "check", "open"):
        print(__doc__)
        return 2
    target = sys.argv[2]
    if cmd == "write":
        ok, why = write(target, arg("--inventory"), arg("--facts"), arg("--fresh-eyes"))
    elif cmd == "open":
        ok, why = open_result(target)
    else:
        ok, why = check(target)
    print(("ACCEPTED: " if ok else "NOT ACCEPTED: ") + why)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
