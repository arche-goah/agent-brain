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
from pathlib import Path

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
        open(p, "w", encoding="utf-8").write("{not json")
    else:
        json.dump({"workflowName": name, "status": status, "timestamp": iso,
                   "totalTokens": tokens}, open(p, "w", encoding="utf-8"))
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
    json.dump({"workflows": {"big-audit": {"thresholdDays": 0.5}}}, open(cfgp, "w", encoding="utf-8"))
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

    # AA-9 (audit-audit 2026-11-10): a dated report counts as a run, a failed run with its report counts,
    # a resumed run is not a cheap probe. Each case has a neighbour that must stay silent.
    def day(age):
        return time.strftime("%Y-%m-%d", time.localtime(time.time() - age * 86400))

    def repo_with(sub, *files):
        r = Path(tmp) / sub
        for f in files:
            p = r / f
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("# report\n", encoding="utf-8")
        return str(r)

    def record(rec, agent_mtime=None):
        sess = Path(tmp) / "aa9-state" / "session-1"
        wf = sess / "workflows"
        wf.mkdir(parents=True, exist_ok=True)
        (wf / "wf_aa9-1.json").write_text(json.dumps(rec), encoding="utf-8")
        adir = sess / "subagents" / "workflows" / "wf_aa9-1"
        adir.mkdir(parents=True, exist_ok=True)
        for old in adir.glob("agent-*.jsonl"):
            old.unlink()
        if agent_mtime is not None:
            a = adir / "agent-x.jsonl"
            a.write_text("{}\n", encoding="utf-8")
            os.utime(a, (agent_mtime, agent_mtime))
        return str(Path(tmp) / "aa9-state")

    no_state = str(Path(tmp) / "aa9-no-records")
    r = repo_with("aa9-a1", f"docs/research/big-audit/register-{day(3)}.md")
    res = run({"script": SCRIPT}, no_state, r)
    cases.append(("a dated report without a record denies (another machine's run)", res is not None
                  and "report:" in res["hookSpecificOutput"]["permissionDecisionReason"]))
    r = repo_with("aa9-a2", f"docs/research/big-audit/register-{day(30)}.md")
    cases.append(("control: an old dated report allows", run({"script": SCRIPT}, no_state, r) is None))
    r = repo_with("aa9-a3", "docs/research/big-audit/notes.md", f"docs/research/other-audit/scan-{day(1)}.md")
    cases.append(("control: an undated file or another workflow's report allows", run({"script": SCRIPT}, no_state, r) is None))
    r = repo_with("aa9-a4", f"docs/research/big-audit-{day(2)}/synthesis.md")
    cases.append(("a dated report folder denies", run({"script": SCRIPT}, no_state, r) is not None))

    iso2 = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime(time.time() - 2 * 86400))
    failed = {"workflowName": "big-audit", "status": "failed", "timestamp": iso2, "totalTokens": 900000,
              "args": json.dumps({"date": day(2)})}
    st = record(failed)
    r = repo_with("aa9-b1", f"docs/research/big-audit/register-{day(2)}.md")
    res = run({"script": SCRIPT}, st, r)
    cases.append(("a failed run that wrote its report denies", res is not None
                  and "ended failed" in res["hookSpecificOutput"]["permissionDecisionReason"]))
    r = repo_with("aa9-b2", f"docs/research/big-audit/register-{day(9)}.md")
    res = run({"name": "big-audit"}, st, r)
    cases.append(("control: a failed run without its report does not count, the older report does",
                  res is not None and "ended failed" not in res["hookSpecificOutput"]["permissionDecisionReason"]))
    r = repo_with("aa9-b3")
    cases.append(("control: a failed run with no report at all allows", run({"script": SCRIPT}, st, r) is None))

    start_ms = int((time.time() - 3600) * 1000)
    resumed = {"workflowName": "big-audit", "status": "completed", "timestamp": iso2, "totalTokens": 800,
               "startTime": start_ms}
    st = record(resumed, agent_mtime=time.time() - 7200)
    res = run({"script": SCRIPT}, st, repo_with("aa9-c1"))
    cases.append(("a resumed run below the token floor still denies (the record holds only the resumed part)",
                  res is not None and "after a resume" in res["hookSpecificOutput"]["permissionDecisionReason"]))
    st = record(resumed, agent_mtime=time.time() - 60)
    cases.append(("control: the same record without an earlier attempt stays a cheap probe",
                  run({"script": SCRIPT}, st, repo_with("aa9-c2")) is None))

    # 12b coherence-scan partial run (operator decision 2026-11-02) passes under the cadence; a full run does not
    st = make_state(tmp, "coherence-scan", age_days=6)
    res = run({"name": "coherence-scan", "args": {"date": "2026-11-08", "scratch": "/x", "partial": {"since": "2026-11-02"}}}, st, root)
    cases.append(("coherence-scan partial run under 14 days allows", res is None))
    res = run({"name": "coherence-scan", "args": {"date": "2026-11-08", "scratch": "/x"}}, st, root)
    cases.append(("coherence-scan full run under 14 days denies (control)", res is not None))
    res = run({"name": "coherence-scan", "args": {"date": "2026-11-08", "partial": {"since": "last week"}}}, st, root)
    cases.append(("a partial without a date is no partial run", res is not None))

    # 13 brain-scan: the core floor is 7 days, not the 14-day default -> day 8 ALLOWS
    scan = "export const meta = { name: 'brain-scan', description: 'x' }\nphase('a')"
    st = make_state(tmp, "brain-scan", age_days=8)
    res = run({"script": scan}, st, root)
    cases.append(("brain-scan at day 8 allows (7-day core floor)", res is None))

    # 14 control: brain-scan at day 5 is under the floor -> DENY
    st = make_state(tmp, "brain-scan", age_days=5)
    res = run({"script": scan}, st, root)
    cases.append(("brain-scan at day 5 denies (control)", res is not None))

    # 14b the operator's clear word (marker) passes under the floor
    res = run({"script": scan + "\n// FRESHNESS-OK: operator asked for a scan now"}, st, root)
    cases.append(("brain-scan under the floor passes with the marker", res is None))

    # 15 an instance entry replaces the core cadence
    json.dump({"workflows": {"brain-scan": {"thresholdDays": 10}}}, open(cfgp, "w", encoding="utf-8"))
    st = make_state(tmp, "brain-scan", age_days=8)
    res = run({"script": scan}, st, root)
    cases.append(("instance entry replaces the brain-scan default", res is not None))

    # 16 an instance entry below the core floor does not lower it (a brain once set 6; the floor is 7)
    json.dump({"workflows": {"brain-scan": {"thresholdDays": 6}}}, open(cfgp, "w", encoding="utf-8"))
    st = make_state(tmp, "brain-scan", age_days=6.5)
    res = run({"script": scan}, st, root)
    cases.append(("instance entry below the floor does not lower it", res is not None))

    # 17 the global fallback below the floor does not lower it either (macOS review of #539)
    json.dump({"thresholdDays": 1, "workflows": {"brain-scan": {"minTokens": 0}}}, open(cfgp, "w", encoding="utf-8"))
    st = make_state(tmp, "brain-scan", age_days=3)
    res = run({"script": scan}, st, root)
    cases.append(("global fallback below the floor does not lower it", res is not None))
    os.unlink(cfgp)

fails = [n for n, ok in cases if not ok]
for n, ok in cases:
    print(("PASS" if ok else "FAIL"), n)
print(f"\n{len(cases) - len(fails)}/{len(cases)} passed")
sys.exit(1 if fails else 0)
