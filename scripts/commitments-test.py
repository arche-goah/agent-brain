#!/usr/bin/env python3
"""covers: commitments

Both directions on synthetic transcripts: a first-person commitment without a rule write is
loose; the same with a rule write sharing its words is carried; a sentence about a tool, a
quoted mention, a non-rule write and other-language phrasing without instance data stay
correct. Negative control: with the first-person filter removed the tool sentence turns loud.

Run: scripts/commitments-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import io
import contextlib
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("cm", ROOT / "scripts" / "commitments.py")
cm = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(cm)

fails = 0


def check(cond, name):
    global fails
    print(f"  {'ok  ' if cond else 'FAIL'}  {name}")
    fails += 0 if cond else 1


def say(text, ts="2026-10-09T10:00:00Z"):
    return {"type": "assistant", "timestamp": ts, "message": {"content": [{"type": "text", "text": text}]}}


def write(path, content, ts="2026-10-09T10:01:00Z"):
    return {"type": "assistant", "timestamp": ts,
            "message": {"content": [{"type": "tool_use", "name": "Edit",
                                     "input": {"file_path": path, "new_string": content}}]}}


def run(records, data=None, sid="s1"):
    d = tempfile.mkdtemp()
    repo = Path(d) / "repo"
    (repo / ".claude" / "rules").mkdir(parents=True)
    if data is not None:
        (repo / ".claude" / "rules" / "commitments.json").write_text(json.dumps(data), encoding="utf-8")
    tdir = Path(d) / "t"
    tdir.mkdir()
    (tdir / f"{sid}.jsonl").write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cm.main(["--repo", str(repo), "--dir", str(tdir), "--session", sid, "--json"])
    return json.loads(buf.getvalue())


r = run([say("From now on I start the CI watch in the same turn as every pull request.")])
check(r["found"] == 1 and len(r["loose"]) == 1, "first-person commitment without carrier is loose")

# Since 2026-10-26 a rule-text write is PROSE, not a carrier (the operator: "a rule entered in the
# feedback amounts to an empty promise in the long run") — this was the passing case before.
r = run([say("From now on I start the CI watch in the same turn as every pull request."),
         write("/b/rules/working-rules.md", "whoever opens a pull request arms the CI watch in the same turn")])
check(r["found"] == 1 and r["carried"] == 0 and r["prose"] == 1 and len(r["loose"]) == 1,
      "a rule-TEXT write sharing its words is prose, not a carrier")

r = run([say("From now on I start the CI watch in the same turn as every pull request."),
         write("/b/core/helpers/watch-gate.cjs", "// refuse a turn end when a pull request has no CI watch armed in the same turn")])
check(r["carried"] == 1 and not r["loose"], "a MECHANISM write (a helper) sharing its words carries it")

r = run([say("From now on I never open a window on the operator's machine."),
         write("/b/.claude/rules/mechanism-rules.json", '{"rules":[{"id":"no-window","why":"never open a window on the machine"}]}')])
check(r["carried"] == 1, "a write to gate data (.claude/rules/*.json) carries it")

r = run([say("From now on I never open a window on the operator's machine."),
         write("/b/docs/maintenance/feedback-protokoll.md", "never open a window on the operator machine")])
check(r["carried"] == 0 and r["prose"] == 1, "real case 2026-10-26: a feedback-protocol entry is prose, not a carrier")

r = run([say("From now on I start the CI watch in the same turn as every pull request."),
         write("/b/notes/scratch.txt", "pull request CI watch same turn")])
check(len(r["loose"]) == 1, "a write outside rule locations does not carry")

r = run([say("The detector will report near-duplicates from now on.")])
check(r["found"] == 0, "a sentence about a tool is not a commitment")

r = run([say('The tool looks for phrases like "from now on I will" in replies.')])
check(r["found"] == 0, "a quoted mention is not a commitment")

r = run([say("Ab jetzt sage ich im Chat Tiefenpruefung.")])
check(r["found"] == 0, "German phrasing needs instance data")
check(r.get("phrasing") == "english-only", "a run without instance phrasing says it checked English only")

r = run([say("Ab jetzt sage ich im Chat Tiefenpruefung.")],
        data={"patterns": [r"\bab jetzt\b"], "first_person": [r"\b(ich|wir)\b"]})
check(len(r["loose"]) == 1, "instance data adds German phrasing")

def run_with_rule(records, rule_text):
    d = tempfile.mkdtemp()
    repo = Path(d) / "repo"
    (repo / ".claude" / "rules").mkdir(parents=True)
    (repo / ".claude" / "rules" / "feedback.md").write_text(rule_text, encoding="utf-8")
    tdir = Path(d) / "t"
    tdir.mkdir()
    (tdir / "s1.jsonl").write_text("\n".join(json.dumps(r) for r in records) + "\n", encoding="utf-8")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cm.main(["--repo", str(repo), "--dir", str(tdir), "--session", "s1", "--json"])
    return json.loads(buf.getvalue())


c = say("From now on I compare every rebuilt export against the accepted version before presenting it.")
r = run_with_rule([c], "- A rebuilt export is compared against the accepted version before presenting it to the operator.\n")
check(r["carried"] == 0 and r["prose"] == 1, "rule text written later is prose, not a carrier (since 2026-10-26)")
r = run_with_rule([c], "- Shell commands are atomic and must match a permission pattern; no heredocs anywhere.\n")
check(len(r["loose"]) == 1, "an unrelated rule paragraph does not carry")

# A take-back in the same turn clears the promise, as the gate does (2026-11-16: 19 of 41 "loose" promises over 20
# days had been held by the gate and taken back; the report still listed them), and is no promise itself.
op = {"type": "user", "message": {"content": "next order"}}
echo = {"type": "user", "message": {"content": "Stop hook feedback:\nEMPTY PROMISE ..."}}
p = say("From now on I start the CI watch in the same turn as every pull request.")
back = say("I take that back: from now on is not what I can promise, it is not guaranteed.", ts="2026-10-09T10:02:00Z")
r = run([p, echo, back])
check(not r["loose"] and r["retracted"] == 1, "a take-back later in the same turn clears the promise (the gate's way out)")
r = run([p, op, back])
check(len(r["loose"]) == 1 and r["retracted"] == 0, "negative control: a take-back after a new operator message does not reach back")
inst = {"patterns": [r"\bfrom today onward\b"], "retract_patterns": [r"\bstrike that sentence\b"]}
r = run([say("From today onward I announce the minute beforehand."), say("Please strike that sentence.")], data=inst)
check(not r["loose"] and r["retracted"] == 1, "the instance's retract_patterns count as a take-back")


# The loop brake let a held promise end the turn: listed with its own reason (8 of 41 on 2026-11-16).
def run_brake(lines):
    d = tempfile.mkdtemp()
    repo = Path(d) / "repo"
    (repo / ".claude-state").mkdir(parents=True)
    (repo / ".claude-state" / "stop-loops.jsonl").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")
    tdir = Path(d) / "t"
    tdir.mkdir()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        cm.main(["--repo", str(repo), "--dir", str(tdir), "--json"])
    return json.loads(buf.getvalue())


import datetime as _dt
now = _dt.datetime.now(_dt.timezone.utc).isoformat()
held = {"at": now, "marker": "COMMITMENT-CARRIER-GATE", "blocks": 3,
        "reason": "EMPTY PROMISE: conduct promised without a mechanism written this turn:\n  - From now on I review every PR twice.\nBuild the carrier now"}
r = run_brake([held])
check(len(r["loose"]) == 1 and "loop brake" in r["loose"][0]["why"], "a promise the loop brake let through is loose, with that reason")
r = run_brake([dict(held, marker="TIME-GATE"), dict(held, at="2020-01-01T00:00:00+00:00")])
check(not r["loose"], "negative control: another gate's brake entry or one outside the window is not counted")

saved = cm.FIRST_PERSON
cm.FIRST_PERSON = [r"."]
r = run([say("The detector will report near-duplicates from now on.")])
check(r["found"] == 1, "negative control: without the first-person filter the tool sentence is caught")
cm.FIRST_PERSON = saved

print("commitments-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
