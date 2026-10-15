#!/usr/bin/env python3
"""Fixture test for scripts/session-audit.py and its relay (open-items.py, open-items-gate.cjs) — both directions.

The must-report cases are the operator's order of 2026-10-11 itself: a session killed
without the session-close skill, and a session start cancelled by its timeout, must be
loud at the next start, on every machine. The must-stay-silent cases are what would make
the check noise: a closed session, a session without a single prompt, a headless run, the
running session itself, a transcript that may still be live, anything before the window,
anything acknowledged. Synthetic transcripts only.
Usage: python3 scripts/session-audit-test.py   (exit 0 = pass)
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SA = HERE / "session-audit.py"
OI = HERE / "open-items.py"
GATE = HERE.parent / "helpers" / "open-items-gate.cjs"
BOOT_CMD = 'bash "$CLAUDE_PROJECT_DIR/core/helpers/session-bootup.sh"'
fails = 0


def ok(c, name):
    global fails
    print(("  OK   " if c else "  FAIL ") + name)
    if not c:
        fails += 1


def rec(**kw):
    return json.dumps(kw)


def boot(kind="ok", source="startup", text="x\n=== END BOOTUP ===\n"):
    if kind == "cancelled":
        a = {"type": "hook_cancelled", "hookName": f"SessionStart:{source}", "hookEvent": "SessionStart",
             "command": BOOT_CMD, "durationMs": 30026, "timedOut": True}
    else:
        a = {"type": "hook_success", "hookName": f"SessionStart:{source}", "hookEvent": "SessionStart",
             "command": BOOT_CMD, "content": text, "durationMs": 9000}
    return rec(type="attachment", attachment=a, timestamp="2026-10-05T08:00:00Z", entrypoint="cli")


def user(text, ts="2026-10-05T08:01:00Z"):
    return rec(type="user", message={"role": "user", "content": text}, timestamp=ts, entrypoint="cli")


def close_skill(ts="2026-10-05T09:00:00Z"):
    return rec(type="assistant", timestamp=ts, message={"role": "assistant", "content": [
        {"type": "tool_use", "name": "Skill", "input": {"skill": "brain-core:session-close"}}]})


def write(d, sid, lines, age_h=5):
    p = d / f"{sid}.jsonl"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    t = time.time() - age_h * 3600
    os.utime(p, (t, t))
    return p


def run(args, root, hook=None, env=None):
    e = dict(os.environ, **(env or {}))
    e.pop("CLAUDE_SESSION_ID", None)
    cmd = [sys.executable, str(SA), "--root", str(root)] + args
    if hook is not None:
        cmd += ["--hook-input", json.dumps(hook)]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", env=e)
    return p.returncode, p.stdout


def main():
    tmp = Path(tempfile.mkdtemp())
    try:
        root = tmp / "brain"; root.mkdir()
        tdir = tmp / "transcripts"; tdir.mkdir()
        write(tdir, "aaaa0001-closed", [boot(), user("work"), close_skill()])
        write(tdir, "aaaa0002-killed", [boot(), user("work"), user("more", "2026-10-05T10:00:00Z")])
        write(tdir, "aaaa0003-empty", [boot()])
        write(tdir, "aaaa0004-headless", [boot().replace('"cli"', '"sdk-cli"'),
                                          user("scan").replace('"cli"', '"sdk-cli"')])
        write(tdir, "aaaa0005-cancelled", [boot("cancelled"), user("work"), close_skill()])
        write(tdir, "aaaa0006-incomplete", [boot(text="x\n!! session-bootup aborted early"), user("w"), close_skill()])
        write(tdir, "aaaa0007-live", [boot(), user("still typing")], age_h=0)
        write(tdir, "aaaa0008-current", [boot(), user("me")])
        write(tdir, "aaaa0009-old", [boot("cancelled"), user("w")], age_h=24 * 30)
        full, cut = tmp / "boot-full.txt", tmp / "boot-cut.txt"
        full.write_text("x\n=== END BOOTUP ===\n", encoding="utf-8")
        cut.write_text("x\n!! session-bootup aborted early", encoding="utf-8")
        preview = "<persisted-output>\nOutput too large (10.1KB). Full output saved to: {}\n\nPreview (first 2KB):\nx\n...\n</persisted-output>"
        write(tdir, "aaaa0010-persisted", [boot(text=preview.format(full)), user("w"), close_skill()])
        # the incomplete start of aaaa0006 again, its output saved to a file: still reported
        write(tdir, "aaaa0006-incomplete", [boot(text=preview.format(cut)), user("w"), close_skill()])
        # a start that ran through but hit the bootup's own 32 KiB cap (2026-10-14): not a failure
        capped = tmp / "boot-capped.txt"
        capped.write_text("x\n   --classify 'a=ai|h\n[... truncated at 32 KiB]", encoding="utf-8")
        write(tdir, "aaaa0011-capped", [boot(text=preview.format(capped)), user("w"), close_skill()])
        hook = {"session_id": "aaaa0008-current", "transcript_path": str(tdir / "aaaa0008-current.jsonl")}

        rc, out = run(["--json"], root, hook)
        found = {f["id"] for f in json.loads(out.strip().splitlines()[-1])}
        ok(rc == 0, "runs (exit 0)")
        ok("end:aaaa0002-killed" in found, "a killed session is reported")
        ok("start:aaaa0005-cancelled" in found, "a cancelled session start is reported (even when the session was closed)")
        ok("start:aaaa0006-incomplete" in found, "an incomplete session start is reported")
        ok(not any("aaaa0010" in f for f in found), "a complete start whose output was saved to a file stays silent")
        ok(not any("aaaa0011" in f for f in found), "a start cut by the 32 KiB cap without an abort note stays silent")
        ok(not any("aaaa0001" in f for f in found), "a closed session stays silent (negative control)")
        ok(not any("aaaa0003" in f for f in found), "a session without a prompt stays silent")
        ok(not any("aaaa0004" in f for f in found), "a headless run is not 'ended without close'")
        ok(not any("aaaa0007" in f for f in found), "a transcript touched minutes ago is left for later")
        ok(not any("aaaa0008" in f for f in found), "the running session is skipped")
        ok(not any("aaaa0009" in f for f in found), "a session before the window is not reported")
        ok(len(found) == 3, f"exactly three findings (got {len(found)})")

        rc, out = run([], root, hook)
        ok(out.startswith("!! session audit: 1 session(s) ended without session-close · 2 session start(s) failed"),
           "the bootup summary is its own loud line")

        # The relay: open-items lists them as agent items (the transcript holds the cause), the gate makes the first reply name them.
        rc2 = subprocess.run([sys.executable, str(OI), "--root", str(root), "--repo", str(tmp / "no-shared"),
                              "--hook-input", json.dumps(hook)], capture_output=True, text=True, encoding="utf-8")
        oi = rc2.stdout
        lines = [l for l in oi.splitlines() if l.startswith("- [session|ai]")]
        ok(len(lines) == 3, f"open-items lists the three as agent items (got {len(lines)})")
        ok("!! open for us: 1 past session(s) ended without session-close · 2 session start(s) failed" in oi,
           "open-items prints the loud summary")

        if shutil.which("node"):
            block = "open for us: 3 — ai 3 · human 0 · unclassified 0\n" + "\n".join(lines) + "\n=== END BOOTUP ==="
            tp = tdir.parent / "gate.jsonl"

            def gate(reply):
                tp.write_text("\n".join([boot(text=block), user("hi"),
                                         rec(message={"role": "assistant", "content": [{"type": "text", "text": reply}]})]) + "\n",
                              encoding="utf-8")
                p = subprocess.run(["node", str(GATE)], input=json.dumps({"transcript_path": str(tp), "cwd": str(root)}),
                                   capture_output=True, text=True, encoding="utf-8")
                return p.stdout
            ok('"decision":"block"' in gate("All fine, nothing to report."), "the gate blocks a first reply that names none")
            dates = sorted({l.split()[2] for l in lines})
            named = "Cleared from the transcripts: " + "; ".join(f"{d} hook timeout, session closed" for d in dates) + "."
            ok(gate(named).strip() == "", "the gate lets a reply through that names each by its date, without asking anyone")
        else:
            print("  SKIP gate cases: node not found")

        # Ack: a hand run lists nothing (no session id), so `--ack listed` clears nothing.
        run([], root, None)
        st = json.loads((root / ".claude-state" / "session-audit.json").read_text(encoding="utf-8"))
        ok(len(st.get("listed", [])) == 3, "the bootup run (with a session id) recorded what it listed")
        run(["--ack", "listed"], root)
        rc, out = run(["--json"], root, hook)
        ok(json.loads(out.strip().splitlines()[-1]) == [], "the close's --ack listed clears what the start listed")

        # A new kill after the ack is loud again.
        write(tdir, "aaaa0010-killed2", [boot(), user("x")])
        rc, out = run(["--json"], root, hook)
        ok([f["id"] for f in json.loads(out.strip().splitlines()[-1])] == ["end:aaaa0010-killed2"],
           "a new finding after the ack is reported (and only it)")

        # Dry run writes nothing.
        before = (root / ".claude-state" / "session-audit.json").read_text(encoding="utf-8")
        rc, out = run(["--dry-run", "--all", "--dir", str(tdir)], root)
        after = (root / ".claude-state" / "session-audit.json").read_text(encoding="utf-8")
        ok(rc == 0 and before == after and json.loads(out)["sessions"] >= 9, "--dry-run --all counts and writes no state")

        rc, out = run(["--dir", str(tmp / "missing")], root, {"session_id": "x"})
        ok(rc == 2 and "NOT checked" in out, "a missing transcript dir says NOT checked, never 'nothing'")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("session-audit:", "all checks passed" if not fails else f"{fails} check(s) FAILED")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
