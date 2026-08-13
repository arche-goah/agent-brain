#!/usr/bin/env python3
"""Fixture tests for helpers/freshness-gate.cjs.

Both directions per detector discipline: cases that MUST deny and cases that
MUST stay silent (fail-open included). Builds a throwaway ~/.claude-style
project state dir with fabricated run records and feeds the hook via stdin.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HOOK = os.path.join(os.path.dirname(__file__), "..", "helpers", "freshness-gate.cjs")

DAY_MS = 86400000


def make_state(tmp, name, age_days, status="completed", tokens=500000, broken=False):
    """One session dir with one run record of the given age."""
    wf = os.path.join(tmp, "state", "session-1", "workflows")
    os.makedirs(wf, exist_ok=True)
    ts = time.time() * 1000 - age_days * DAY_MS
    iso = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(ts / 1000))
    p = os.path.join(wf, "wf_test-123.json")
    if broken:
        open(p, "w").write("{not json")
    else:
        json.dump({"workflowName": name, "status": status, "timestamp": iso,
                   "totalTokens": tokens}, open(p, "w"))
    return os.path.join(tmp, "state")


def run(tool_input, state_dir, project_root):
    inp = json.dumps({
        "tool_name": "Workflow",
        "tool_input": tool_input,
        "cwd": project_root,
        # transcript_path sits directly in the project state dir
        "transcript_path": os.path.join(state_dir, "current-session.jsonl"),
    })
    env = dict(os.environ, CLAUDE_PROJECT_DIR=project_root)
    r = subprocess.run(["node", HOOK], input=inp, capture_output=True,
                       text=True, timeout=15, env=env)
    out = r.stdout.strip()
    return json.loads(out) if out else None


SCRIPT = "export const meta = { name: 'big-audit', description: 'x' }\nphase('a')"

cases = []
with tempfile.TemporaryDirectory() as tmp:
    root = os.path.join(tmp, "repo")
    os.makedirs(os.path.join(root, ".claude", "rules"), exist_ok=True)

    # 1 fresh + expensive + completed -> DENY
    st = make_state(tmp, "big-audit", age_days=3)
    res = run({"script": SCRIPT}, st, root)
    cases.append(("fresh expensive run denies", res is not None
                  and "big-audit" in res["hookSpecificOutput"]["permissionDecisionReason"]))

    # 2 name given via input.name (no script) -> DENY
    res = run({"name": "big-audit"}, st, root)
    cases.append(("named workflow denies", res is not None))

    # 3 stale run (30d, threshold 14) -> ALLOW
    st = make_state(tmp, "big-audit", age_days=30)
    res = run({"script": SCRIPT}, st, root)
    cases.append(("stale run allows", res is None))

    # 4 killed run -> ALLOW (only completed counts)
    st = make_state(tmp, "big-audit", age_days=1, status="killed")
    res = run({"script": SCRIPT}, st, root)
    cases.append(("killed run allows", res is None))

    # 5 cheap probe below token floor -> ALLOW
    st = make_state(tmp, "big-audit", age_days=1, tokens=800)
    res = run({"script": SCRIPT}, st, root)
    cases.append(("below token floor allows", res is None))

    # 6 FRESHNESS-OK marker -> ALLOW
    st = make_state(tmp, "big-audit", age_days=1)
    res = run({"script": SCRIPT + "\n// FRESHNESS-OK: verify stage missing"}, st, root)
    cases.append(("marker allows", res is None))

    # 7 resumeFromRunId -> ALLOW
    res = run({"script": SCRIPT, "resumeFromRunId": "wf_abc-123"}, st, root)
    cases.append(("resume allows", res is None))

    # 8 different name -> ALLOW
    res = run({"name": "other-workflow"}, st, root)
    cases.append(("different name allows", res is None))

    # 9 per-workflow override: threshold below age -> ALLOW
    cfgp = os.path.join(root, ".claude", "rules", "freshness-gate.json")
    json.dump({"workflows": {"big-audit": {"thresholdDays": 0.5}}}, open(cfgp, "w"))
    st = make_state(tmp, "big-audit", age_days=1)
    res = run({"script": SCRIPT}, st, root)
    cases.append(("instance override allows", res is None))
    os.unlink(cfgp)

    # 10 broken record JSON -> ALLOW (fail open)
    st = make_state(tmp, "big-audit", age_days=1, broken=True)
    res = run({"script": SCRIPT}, st, root)
    cases.append(("broken record fails open", res is None))

    # 11 no state dir at all -> ALLOW
    res = run({"script": SCRIPT}, os.path.join(tmp, "nowhere"), root)
    cases.append(("missing state dir allows", res is None))

    # 12 script without meta name -> ALLOW
    st = make_state(tmp, "big-audit", age_days=1)
    res = run({"script": "phase('a')"}, st, root)
    cases.append(("nameless script allows", res is None))

fails = [n for n, ok in cases if not ok]
for n, ok in cases:
    print(("PASS" if ok else "FAIL"), n)
print(f"\n{len(cases) - len(fails)}/{len(cases)} passed")
sys.exit(1 if fails else 0)
