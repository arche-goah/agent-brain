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

r = run([say("From now on I start the CI watch in the same turn as every pull request."),
         write("/b/rules/working-rules.md", "whoever opens a pull request arms the CI watch in the same turn")])
check(r["found"] == 1 and r["carried"] == 1 and not r["loose"], "rule write sharing its words carries it")

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
check(r["carried"] == 1, "a carrier written later (today's rule text) counts")
r = run_with_rule([c], "- Shell commands are atomic and must match a permission pattern; no heredocs anywhere.\n")
check(len(r["loose"]) == 1, "an unrelated rule paragraph does not carry")

saved = cm.FIRST_PERSON
cm.FIRST_PERSON = [r"."]
r = run([say("The detector will report near-duplicates from now on.")])
check(r["found"] == 1, "negative control: without the first-person filter the tool sentence is caught")
cm.FIRST_PERSON = saved

print("commitments-test: " + ("all checks passed" if not fails else f"{fails} FAILED"))
sys.exit(1 if fails else 0)
