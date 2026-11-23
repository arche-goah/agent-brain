#!/usr/bin/env python3
"""Fixture for scripts/gate-health.py: a gate that timed out in two sessions is named; one session is not (below the
threshold); a gate's decision (a refusal with a reason) and an old transcript are no malfunction; --all lists every
gate. Usage: python3 scripts/gate-health-test.py   (exit 0 = pass)"""
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
fails = 0


def ok(c, label, out=""):
    global fails
    print(("  ok    " if c else "  FAIL  ") + label + ("" if c else f": {out!r}"))
    fails += 0 if c else 1


def result(text):
    return json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "t", "is_error": True, "content": text}]}}) + "\n"


TIMEOUT = 'PreToolUse:Bash hook error: [node "$CLAUDE_PROJECT_DIR/core/helpers/slow-gate.cjs"]: timed out; blocking because onFailure is "block"'
NUMBERED = 'PreToolUse:Bash hook error: [command hook 7]: timed out; blocking because onFailure is "block"'
DECISION = "PreToolUse:Bash hook error: MECHANISM CHECK (agent-brain): a heredoc"

with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    (d / "s1.jsonl").write_text(result(TIMEOUT) + result(DECISION), encoding="utf-8")
    (d / "s2.jsonl").write_text(result(TIMEOUT) + result(NUMBERED), encoding="utf-8")
    old = d / "s0.jsonl"
    old.write_text(result(TIMEOUT) * 5, encoding="utf-8")
    t = time.time() - 30 * 86400
    os.utime(old, (t, t))

    def run(*a):
        return subprocess.run([sys.executable, str(HERE / "gate-health.py"), "--dir", str(d), "--no-cache", *a],
                              capture_output=True, text=True, encoding="utf-8").stdout

    out = run()
    ok("slow-gate timed out 2x in 2 session(s)" in out, "a gate that timed out in two sessions is named, with count and sessions", out)
    ok("command hook 7" not in out, "one session is below the threshold", out)
    ok("MECHANISM" not in out, "a gate's decision is no malfunction", out)
    ok("7x" not in out, "a transcript older than the window is not counted", out)
    out = run("--all")
    ok("command hook 7 timed out 1x in 1 session(s)" in out, "--all lists every gate, a numbered hook too", out)
    empty = d / "empty"
    empty.mkdir()
    out = subprocess.run([sys.executable, str(HERE / "gate-health.py"), "--dir", str(empty), "--no-cache"],
                         capture_output=True, text=True, encoding="utf-8").stdout
    ok(out == "", "all quiet: silent", out)

# --- marker rate per gate (operator 2026-11-23: "a gate that errs is a finding"): >= 20 refusals, > 50 % by marker
def use(i, cmd):
    return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": f"u{i}", "name": "Bash", "input": {"command": cmd}}]}}) + "\n"


def res(i, err, text):
    return json.dumps({"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": f"u{i}", "is_error": err, "content": text}]}}) + "\n"


def say(text):
    return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}) + "\n"


NOISY = "PreToolUse:Bash hook error: NOISY GATE: the order has a condition. Add `# NOISY-NONE: <why>` to the call."
QUIET = "PreToolUse:Bash hook error: QUIET-GATE (core): no. Use the documented path."
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    lines, n = [], 0
    for k in range(24):                       # 24 refusals: 16 passed by the marker it names, 8 by another form
        cmd = f"gh pr comment {k} --body-file x"
        lines += [use(n, cmd), res(n, True, NOISY)]
        if k < 13:
            lines += [use(n + 1, cmd + " # NOISY-NONE: no condition"), res(n + 1, False, "ok")]
        elif k < 16:                          # the marker as a line in the answer, then the same call
            lines += [say("NOISY-NONE: the condition is met"), use(n + 1, cmd), res(n + 1, False, "ok")]
        else:                                 # an unrelated command passes first, then the same call without a marker
            lines += [use(n + 1, "ls"), res(n + 1, False, "ok"), use(n + 2, cmd + " --edit"), res(n + 2, False, "ok")]
        n += 3
    for k in range(25):                       # 25 refusals of a gate nobody overrides
        lines += [use(n, f"cat f{k}"), res(n, True, QUIET), use(n + 1, f"cat f{k} | head"), res(n + 1, False, "ok")]
        n += 2
    for k in range(21):                       # 21 refusals that name their way on, then a changed call: the gate followed
        lines += [use(n, f"git commit -a q{k}"), res(n, True, "PreToolUse:Bash hook error: WAYON-GATE: the form that passes is a commit by path."),
                  use(n + 1, f"git commit q{k} -- f{k}"), res(n + 1, False, "ok")]
        n += 2
    for k in range(21):                       # the same in another language as instance data (way_on_patterns): a language is data
        lines += [use(n, f"edit z{k}"), res(n, True, "PreToolUse:Bash hook error: LOCAL-GATE: primero mira, luego remite."),
                  use(n + 1, f"edit z{k} ref"), res(n + 1, False, "ok")]
        n += 2
    for k in range(21):                       # 21 refusals of a markerless gate that never pass (the step dropped)
        lines += [use(n, f"touch q{k}"), res(n, True, "PreToolUse:Bash hook error: NEVER-GATE: not now.")]
        n += 1
    for k in range(21):                       # 21 refusals passed by the identical retry (a step done in between)
        lines += [use(n, f"git pull q{k}"), res(n, True, "PreToolUse:Bash hook error: SAME-GATE: read first."),
                  use(n + 1, f"git pull q{k}"), res(n + 1, False, "ok")]
        n += 2
    for k in range(10):                       # 10 refusals, all by marker - under the 20-refusal floor
        lines += [use(n, f"rm t{k}"), res(n, True, NOISY.replace("NOISY GATE", "SMALL GATE")),
                  use(n + 1, f"rm t{k} # NOISY-NONE: ok"), res(n + 1, False, "ok")]
        n += 2
    for k in range(22):                       # 22 refusals of a read-then-confirm gate, all passed by its marker
        lines += [use(n, f"gh pr create t{k}"), res(n, True, NOISY.replace("NOISY GATE", "RULE GATE").replace("NOISY-NONE", "WAS-READ")),
                  use(n + 1, f"gh pr create t{k} # WAS-READ: read"), res(n + 1, False, "ok")]
        n += 2
    lines += [use(n, "git push # NOISY-NONE: before any refusal"), res(n, False, "ok")]   # a pre-emptive marker
    n += 1
    lines += [use(n, "make x"), res(n, True, "PreToolUse:Bash hook error: [command hook 29]: not here, use the target")]
    (d / "m.jsonl").write_text("".join(lines), encoding="utf-8")
    mk = d / "markers.json"
    mk.write_text(json.dumps({"gates": {
        "NOISY GATE": {"markers": ["NOISY-NONE"], "rule_path": False},
        "SMALL GATE": {"markers": ["NOISY-NONE"], "rule_path": False},
        "RULE GATE": {"markers": ["WAS-READ"], "rule_path": True},
        "QUIET-GATE": {"markers": ["QUIET-OK"], "rule_path": False}},
        "way_on": ["the form that passes"]}), encoding="utf-8")
    wroot = d / "wbrain"
    (wroot / ".claude" / "rules").mkdir(parents=True)
    (wroot / ".claude" / "rules" / "root-cause-patterns.json").write_text(json.dumps({"way_on_patterns": ["mira, luego remite"]}), encoding="utf-8")

    # the brain the script reads defaults to CLAUDE_PROJECT_DIR; a run inside a real brain must not see its instance
    # words (measured while building this: a real brain's way_on_patterns leaked into the no-data control)
    bare = d / "bare-brain"
    bare.mkdir()
    env = {**os.environ, "CLAUDE_PROJECT_DIR": str(bare)}

    def run2(*a):
        return subprocess.run([sys.executable, str(HERE / "gate-health.py"), "--dir", str(d), "--markers", str(mk), *a],
                              capture_output=True, text=True, encoding="utf-8", env=env).stdout

    out = run2("--no-cache")
    ok("NOISY GATE errs often - 16 of 24 refusals (67 %) passed by its override marker" in out,
       "an override gate with >= 20 refusals mostly passed by its marker errs often, the answer-line form counted", out)
    ok("QUIET-GATE is bypassed often - 25 of 25 refusals (100 %) passed in another form" in out,
       "a gate whose refusals pass in another form is reported too, with or without a marker (strand review)", out)
    ok("NEVER-GATE" not in out and "SAME-GATE" not in out,
       "refusals that never pass, or pass as the identical retry, are no finding", out)
    ok("SMALL GATE" not in out, "under 20 refusals is no finding (floor)", out)
    ok("RULE GATE" not in out, "a gate whose marker is its rule path never errs often, 100 % or not (data field)", out)
    out = run2("--rates", "--no-cache")
    ok("NOISY GATE | 24 | 16 | 67 % | no | NOISY-NONE 24" in out and "QUIET-GATE | 25 | 0 | 0 % | no" in out
       and "SMALL GATE | 10 | 10 | 100 % | no" in out and "RULE GATE | 22 | 22 | 100 % | yes | WAS-READ 22" in out,
       "--rates: gate · refusals · by own marker · rate · rule path · calls carrying it (a pre-emptive marker counted)", out)
    ok("QUIET-GATE | 25 | 0 | 0 % | no | QUIET-OK 0 | 25 | 0" in out and "NEVER-GATE | 21 | 0 | 0 % | - | - | 0 | 21" in out
       and "SAME-GATE | 21 | 0 | 0 % | - | - | 0 | 0" in out,
       "--rates: other form and never passed per gate, a markerless gate rated too", out)
    ok("WAYON-GATE | 21 | 0 | 0 % | - | - | 0 | 0" in out,
       "a changed call after a refusal that names its way on (gate-markers.json way_on) is the gate followed, not another form", out)
    ok("LOCAL-GATE | 21 | 0 | 0 % | - | - | 21 | 0" in out,
       "without the instance's way-on words the same refusal in another language counts as another form (control)", out)
    out = run2("--rates", "--no-cache", "--root", str(wroot))
    ok("LOCAL-GATE | 21 | 0 | 0 % | - | - | 0 | 0" in out,
       "with the instance's way_on_patterns (root-cause-patterns.json, the reader root-cause-gate uses) it is followed", out)
    ok("NOISY-NONE 24 (shared with SMALL GATE)" in out, "a marker two gates share says so in the column (Windows review of #646)", out)
    ok("command hook 29 | 1 |" in out and "a hook" not in out, "a refusal without a label is named by its hook number, not 'a hook' (Windows review)", out)
    # NOISY-NONE: 13 in calls + 10 SMALL + 1 pre-emptive = 24 calls carry it; the 3 answer lines are no calls
    # the cache: a second run reads it, a grown transcript is read again
    root = d / "brain"
    root.mkdir()
    first = run2("--rates", "--root", str(root))
    ok((root / ".claude-state" / "gate-health-cache.json").is_file(), "the counts are cached per transcript")
    ok(run2("--rates", "--root", str(root)) == first, "a run from the cache gives the same table", first)
    with (d / "m.jsonl").open("a", encoding="utf-8") as fh:
        fh.write(use(9999, "cat zz") + res(9999, True, QUIET))
    ok("QUIET-GATE | 26 |" in run2("--rates", "--root", str(root)), "a grown transcript is read again, not served from the cache")

print("gate-health-test: all checks passed" if not fails else f"gate-health-test: {fails} FAILURE(S)")
sys.exit(1 if fails else 0)
