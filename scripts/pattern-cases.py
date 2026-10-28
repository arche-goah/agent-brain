#!/usr/bin/env python3
"""pattern-cases.py — run a brain's OWN pattern data through the core reader that uses it.

WHY (measured 2026-10-28 on the macOS instance): a brain keeps its operator's wording as regex
lists in `.claude/rules/*-patterns.json` (and `ask_patterns` in `open-items.json`); the core
readers (helpers/*.cjs) merge them into their English built-ins. The core fixtures test every
reader with the fixture's OWN sample data, so nothing ever ran a brain's REAL data through its
reader. That brain's autonomous on-pattern carried a lookahead `(?![^.!?]{0,30}\\?)` that skips an
on-word inside a question. `answers()` in helpers/autonomous-mode.cjs tests the question-tool
question ("continue autonomously?" in the operator's language) against the on-words, so the
operator's "yes" set nothing, autonomous-gate read "interactive", and a permission-ask stopped an
autonomous run on the operator. A replay over 421 transcripts: 8 read differently once the data
was fixed. The brain wrote a one-off fixture; ten pattern files on that brain, eight of them never
run against their reader, are the class — this runner is its mechanism.

THE CONVENTION. Any known pattern file may carry real operator wording with the verdict the
reader must reach on it:

  "_cases": [
    {"text": "<the operator's / the reply's words>", "expect": "<verdict>"},
    ...
  ]

`text` plays the role the file's reader gives it (table READERS below); a case may add context:
  autonomous-patterns.json, open-items.json (reader autonomous-mode.cjs, the latch):
      "steps": ["<prompt>", {"q": "<question-tool question>", "a": "<the operator's answer>"}, ...]
      in place of `text` (a bare `text` is one prompt); expect "autonomous" | "interactive" =
      the mode after the last step. The question-tool answer is the path the 2026-10-28 data broke.
  condition-patterns.json (conditional-order-gate.cjs): text = the operator's message; the probe
      call is a Workflow. expect "block" (a condition is read) | "allow".
  root-cause-patterns.json (root-cause-gate.cjs): text = the operator's message that opens the
      turn; "reply" (default "Done.") = the answer. "block" = a correction read and no cause named.
  premise-patterns.json (premise-gate.cjs): text = the reply; the turn writes a file unless
      "writes": false (an instruction case). "block" = a generalisation carries an action.
  promise-patterns.json (promise-gate.cjs): text = the reply. "block" = a bounded promise.
  stop-patterns.json (stoppen-gate.cjs): text = the final reply. "block" = a closing question,
      a handoff or an announcement.
  secret-patterns.json (secret-guard.cjs): text = a shell command, or a path with "tool": "Read"
      (or "Edit"/"Write"). "block" = denied (or asked).
  commitments.json (commitment-carrier-gate.cjs): text = the final reply. "block" = a promise about
      future behaviour with no carrier built; "allow" = none, or one taken back (`retract_patterns`).

Each case runs the REAL reader as its hook runs it (node, a JSON payload on stdin or the CLI
form), against a throwaway copy of the brain's `.claude/rules/*.json` — the reader sees exactly the
brain's data, and nothing it writes (a promise record, a hook log) lands in the brain or in HOME.

REPORT. Per known file: its cases pass or fail (a failure names the case, the expected and the
measured verdict). A known file WITHOUT `_cases` is a finding, not a failure: brains fill them in
over time. A `*-patterns.json` file no core reader is known for is listed, never failed (an
instance's own hook reads it; its fixture belongs to that instance).

Usage: python3 scripts/pattern-cases.py [brain-root]     (default: the current directory)
exit 0 = every case passed (findings may stand) · 1 = a case failed, a case is malformed, or a
known file is not valid JSON · 2 = node not found, nothing was checked.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HELPERS = Path(__file__).resolve().parent.parent / "helpers"

# file -> (reader in helpers/, scenario kind). The scenario says what `text` is (module docstring).
READERS = {
    "autonomous-patterns.json": ("autonomous-mode.cjs", "mode"),
    "open-items.json": ("autonomous-mode.cjs", "mode"),
    "condition-patterns.json": ("conditional-order-gate.cjs", "order"),
    "root-cause-patterns.json": ("root-cause-gate.cjs", "correction"),
    "premise-patterns.json": ("premise-gate.cjs", "premise"),
    "promise-patterns.json": ("promise-gate.cjs", "reply"),
    "stop-patterns.json": ("stoppen-gate.cjs", "reply"),
    "secret-patterns.json": ("secret-guard.cjs", "tool"),
    # Not a `*-patterns.json` name, but the same kind of data: the instance's commitment words and
    # take-backs (measured 2026-10-28 on the macOS instance: this runner never saw the file, so a
    # German take-back that did not release the gate went untested).
    "commitments.json": ("commitment-carrier-gate.cjs", "reply"),
}
VERDICTS = {"mode": ("autonomous", "interactive")}
GATE_VERDICTS = ("block", "allow")


def user(text):
    return {"type": "user", "message": {"role": "user", "content": text}}


def asst(text):
    return {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}


def write_call():
    return {"type": "assistant", "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "toolu_pc1", "name": "Write", "input": {"file_path": "notes.md"}}]}}


def answer(q, a):
    body = f'Your questions have been answered: "{q}"="{a}". You can now continue'
    return {"type": "user", "message": {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_pc2", "content": body}]}}


def case_form(kind, case):
    """None when the case can be run, else what is wrong with it."""
    if not isinstance(case, dict):
        return "a case is an object"
    allowed = VERDICTS.get(kind, GATE_VERDICTS)
    if case.get("expect") not in allowed:
        return f"expect must be one of {'|'.join(allowed)}"
    if kind == "mode":
        steps = case.get("steps", [case.get("text")] if "text" in case else None)
        if not isinstance(steps, list) or not steps:
            return "needs text or steps"
        for s in steps:
            if not (isinstance(s, str) or (isinstance(s, dict) and isinstance(s.get("q"), str)
                                           and isinstance(s.get("a"), str))):
                return 'a step is a prompt string or {"q": ..., "a": ...}'
        return None
    if not isinstance(case.get("text"), str) or not case["text"].strip():
        return "needs text"
    return None


def scenario(kind, case):
    """(transcript records, extra hook payload) for one case."""
    text = case.get("text", "")
    if kind == "mode":
        recs = []
        for s in case.get("steps", [text]):
            recs.append(user(s) if isinstance(s, str) else answer(s["q"], s["a"]))
        return recs, None
    if kind == "order":
        return [user(text)], {"tool_name": "Workflow", "tool_input": {}}
    if kind == "correction":
        return [user("go on"), asst("ok"), user(text), asst(case.get("reply", "Done."))], {"stop_hook_active": False}
    if kind == "premise":
        recs = [user(case.get("prompt", "go on")), asst(text)]
        if case.get("writes", True):
            recs.append(write_call())
        return recs, {"stop_hook_active": False}
    if kind == "reply":
        return [user(case.get("prompt", "go on")), asst(text)], {"stop_hook_active": False}
    if kind == "tool":
        tool = case.get("tool", "Bash")
        ti = {"command": text} if tool in ("Bash", "PowerShell") else {"file_path": text}
        return [], {"tool_name": tool, "tool_input": ti}
    raise ValueError(kind)


def run_case(reader, kind, case, brain, work, n, env):
    """The reader's verdict on one case, or ('error', detail)."""
    recs, payload = scenario(kind, case)
    tp = work / f"case-{n}.jsonl"
    tp.write_bytes("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in recs).encode("utf-8"))
    script = str(HELPERS / reader)
    try:
        if kind == "mode":
            p = subprocess.run(["node", script, str(tp), str(brain)], capture_output=True,
                               text=True, encoding="utf-8", timeout=30, env=env)
            got = p.stdout.strip()
            return got if got in VERDICTS["mode"] else ("error", (p.stdout + p.stderr).strip()[:200])
        payload = dict(payload, transcript_path=str(tp), cwd=str(brain))
        p = subprocess.run(["node", script], input=json.dumps(payload), capture_output=True,
                           text=True, encoding="utf-8", timeout=30, env=env, cwd=str(brain))
    except (OSError, subprocess.TimeoutExpired) as e:
        return ("error", str(e))
    out = p.stdout
    blocked = ('"decision":"block"' in out or '"permissionDecision":"deny"' in out
               or '"permissionDecision":"ask"' in out)
    return "block" if blocked else "allow"


def short(case):
    if "steps" in case and isinstance(case["steps"], list):
        parts = [s if isinstance(s, str) else f'[{s.get("q")}] -> {s.get("a")}' for s in case["steps"]]
        t = " / ".join(str(p) for p in parts)
    else:
        t = str(case.get("text", ""))
    t = " ".join(t.split())
    return t if len(t) <= 90 else t[:87] + "..."


def main(argv):
    root = Path(argv[1] if len(argv) > 1 else ".").resolve()
    rules = root / ".claude" / "rules"
    print(f"pattern-cases - {root}")
    if not rules.is_dir():
        print("pattern-cases: 0 case(s) in 0 file(s), 0 failed; no .claude/rules here - nothing to check")
        return 0
    if shutil.which("node") is None:
        print("pattern-cases: node not found - nothing was checked")
        return 2

    known, unknown = [], []
    for f in sorted(rules.glob("*.json")):
        if f.name in READERS:
            if f.name == "open-items.json":
                try:
                    if "ask_patterns" not in json.loads(f.read_text(encoding="utf-8")):
                        continue
                except (OSError, ValueError):
                    pass
            known.append(f)
        elif f.name.endswith("-patterns.json"):
            unknown.append(f)

    work = Path(tempfile.mkdtemp(prefix="pattern-cases-"))
    brain = work / "brain"
    (brain / ".claude" / "rules").mkdir(parents=True)
    for f in rules.glob("*.json"):
        shutil.copyfile(f, brain / ".claude" / "rules" / f.name)
    home = work / "home"
    home.mkdir()
    env = dict(os.environ, CLAUDE_PROJECT_DIR=str(brain), HOME=str(home), USERPROFILE=str(home))

    ran = failed = missing = files_with = 0
    n = 0
    try:
        for f in known:
            reader, kind = READERS[f.name]
            try:
                data = json.loads(f.read_text(encoding="utf-8"))
            except (OSError, ValueError) as e:
                print(f"  !!  {f.name}: not valid JSON ({e}) - {reader} falls back to its built-ins in silence")
                failed += 1
                continue
            cases = data.get("_cases") if isinstance(data, dict) else None
            if not cases:
                print(f"  --  {f.name}: no _cases - add the operator's real wording with the verdict "
                      f"{reader} must reach")
                missing += 1
                continue
            if not isinstance(cases, list):
                print(f"  !!  {f.name}: _cases must be a list")
                failed += 1
                continue
            files_with += 1
            bad = 0
            for i, case in enumerate(cases, 1):
                why = case_form(kind, case)
                if why:
                    print(f"  !!  {f.name} case {i}: malformed - {why}")
                    bad += 1
                    continue
                n += 1
                ran += 1
                got = run_case(reader, kind, case, brain, work, n, env)
                if got != case["expect"]:
                    shown = f"error: {got[1]}" if isinstance(got, tuple) else got
                    print(f"  !!  {f.name} case {i}: expected {case['expect']}, {reader} says {shown}"
                          f' - "{short(case)}"')
                    bad += 1
            failed += bad
            if not bad:
                print(f"  ok  {f.name}: {len(cases)} case(s) pass ({reader})")
        for f in unknown:
            print(f"  ..  {f.name}: no core reader known - not checked here")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    print(f"pattern-cases: {ran} case(s) in {files_with} file(s), {failed} failed; "
          f"{missing} known file(s) without _cases; {len(unknown)} file(s) without a known core reader")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
