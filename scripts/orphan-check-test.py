#!/usr/bin/env python3
"""Fixture for scripts/orphan-check.py — both directions, no live processes.

Must report: the measured incident (2026-10-11) — a recorder from a session scratch folder,
16 h with no parent; a leaked test child under an instance path pattern; anything from the
brain root. Must stay silent: a parent still alive, younger than the threshold, an
unrelated system orphan, a declared wanted service. A declaration without a reason does
not count. Negative control: a stub that never reports misses the incident.
Usage: python3 scripts/orphan-check-test.py (exit 0 = pass)
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
S = os.path.join(HERE, "orphan-check.py")
fails = 0


def check(name, cond, detail=""):
    global fails
    print(f"  {'OK  ' if cond else 'FAIL'} {name}" + ("" if cond else f": {detail}"))
    if not cond:
        fails += 1


def run(ps_text, repo, script=S, extra=()):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
        f.write(ps_text)
        p = f.name
    try:
        r = subprocess.run([sys.executable, script, "--repo", repo, "--ps-file", p, *extra],
                           capture_output=True, text=True, encoding="utf-8")
        return r.returncode, r.stdout
    finally:
        os.unlink(p)


T = tempfile.mkdtemp()
REPO = os.path.join(T, "brain").replace("\\", "/")
os.makedirs(os.path.join(REPO, ".claude", "rules"))
BARE = os.path.join(T, "bare").replace("\\", "/")
os.makedirs(BARE)

RECORDER = "  4711     1    16:05:00 python /private/tmp/claude-501/-x-/8ff0c36e/scratchpad/app_all_log.py\n"
LIVES = "  5001     1 02-03:04:05 bash /var/folders/ab/T/tmp.Q1w2E3/lives.sh\n"
DASH = f"   826     1 03-10:49:59 Python {REPO}/src/rig-dashboard/server.py\n"
FROM_REPO = f"   900     1    02:00:00 node {REPO}/scripts/thing.js\n"
YOUNG = "  6000     1       45:00 python /private/tmp/claude-501/-x-/aa/scratchpad/new.py\n"
PARENT = "  6001  4242    20:00:00 python /private/tmp/claude-501/-x-/bb/scratchpad/kept.py\n"
SYSTEM = "  6002     1 05-00:00:00 /usr/sbin/somedaemon --flag\n"

rc, out = run(RECORDER, BARE)
check("the measured recorder (scratch folder, 16 h, no parent) is reported",
      "!! orphaned processes: 1" in out and "pid 4711" in out and "16 h" in out, out)
check("exit 0 always (a bootup line, not a gate)", rc == 0, rc)

rc, out = run(FROM_REPO, REPO)
check("a process started from the brain root is reported", "pid 900" in out, out)

for name, line in [("a live parent", PARENT), ("younger than 1 h", YOUNG),
                   ("an unrelated system orphan", SYSTEM)]:
    rc, out = run(line, BARE)
    check(f"{name} stays silent", out == "", out)

rc, out = run(LIVES, BARE)
check("a temp folder outside session paths stays silent without instance data", out == "", out)

with open(os.path.join(REPO, ".claude", "rules", "orphan-check.json"), "w", encoding="utf-8") as f:
    json.dump({"paths": [r"/var/folders/.*/tmp\.[A-Za-z0-9]+/"],
               "allow": [{"match": "rig-dashboard/server\\.py", "why": "the operator's dashboard"}]}, f)
rc, out = run(LIVES + DASH, REPO)
check("an instance path pattern reports the leaked test child", "pid 5001" in out, out)
check("a declared wanted service stays silent", "pid 826" not in out, out)
check("the count names only the leak", "!! orphaned processes: 1" in out, out)

with open(os.path.join(REPO, ".claude", "rules", "orphan-check.json"), "w", encoding="utf-8") as f:
    json.dump({"allow": [{"match": "rig-dashboard/server\\.py"}]}, f)
rc, out = run(DASH, REPO)
check("a declaration without a reason does not silence it", "pid 826" in out, out)

many = "".join(f"  {7000 + i}     1    03:00:00 python /private/tmp/claude-501/-x-/c/scratchpad/p{i}.py\n"
               for i in range(7))
rc, out = run(many, BARE)
check("more than five: five shown, the rest counted", "(+2 more)" in out and out.count("   pid ") == 5, out)

rc, out = run(RECORDER, BARE, extra=("--min-age", str(17 * 3600)))
check("--min-age moves the threshold", out == "", out)

r = subprocess.run([sys.executable, S, "--repo", BARE], capture_output=True, text=True,
                   encoding="utf-8", env={**os.environ, "PATH": T})
check("no ps on the system says NOT checked, never silence", "NOT checked" in r.stdout, r.stdout)

stub = os.path.join(T, "stub.py")
with open(stub, "w", encoding="utf-8") as f:
    f.write("import sys\nsys.exit(0)\n")
rc, out = run(RECORDER, BARE, script=stub)
check("a stub that never reports misses the incident (control)", "orphaned" not in out, out)

print("orphan-check: all checks passed" if not fails else f"orphan-check: {fails} FAILED")
sys.exit(1 if fails else 0)
