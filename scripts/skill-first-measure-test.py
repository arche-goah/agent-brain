#!/usr/bin/env python3
"""Fixture tests for scripts/skill-first-measure.py.

Both directions of the two definitions the script must share with the gates:
- every gate tag in one Stop-hook block counts (a first-tag-only reader gets 1, not 2);
- a notification turn is ONLY harness frames with a task notification — a bare
  system-reminder record, and a frame plus operator words, are operator turns (the
  negative controls: a looser definition would count them as notifications).
Parity with helpers/turn-kind.cjs is checked by running the helper on the same strings
when node and the helper are present; otherwise the case says SKIP, never "ok".
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT = str(HERE / "skill-first-measure.py")
HELPER = HERE.parent / "helpers" / "turn-kind.cjs"

NOTIF = "<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"
REMINDER_ONLY = "<system-reminder>a hook said something</system-reminder>"
FRAME_PLUS_WORDS = NOTIF + "\nand please also check the log"
SAMPLES = {"notification": (NOTIF, True), "notification+reminder": (REMINDER_ONLY + NOTIF, True),
           "reminder only": (REMINDER_ONLY, False), "frame+words": (FRAME_PLUS_WORDS, False),
           "plain": ("do the thing", False)}


def u(text, ts="2026-03-02T10:00:00Z"):
    return {"type": "user", "timestamp": ts, "message": {"role": "user", "content": text}}


def skill_call(ts="2026-03-02T10:00:01Z"):
    return {"type": "assistant", "timestamp": ts, "message": {"role": "assistant", "content": [
        {"type": "tool_use", "id": "s", "name": "Skill", "input": {"skill": "x"}},
        {"type": "tool_use", "id": "r", "name": "Read", "input": {}}]}}


def fb(*tags):
    return u("Stop hook feedback:\n" + "\n".join(f"[{t}] something to fix" for t in tags))


IN_RANGE = [
    u("operator asks"), skill_call(), skill_call(),
    fb("ALPHA-GATE", "BETA-VERIFIER"),          # one block, two gates: both count
    u(NOTIF), fb("ALPHA-GATE"),                 # notification turn
    u(REMINDER_ONLY), fb("GAMMA-GATE"),         # NOT a notification (no task frame)
    u(FRAME_PLUS_WORDS), u("Stop hook feedback:\nno tag here"),  # operator turn, untagged
    {"type": "user", "timestamp": "2026-03-02T10:05:00Z",
     "message": {"content": [{"type": "tool_result", "tool_use_id": "r", "content": NOTIF}]}},
    fb("DELTA-GATE"),                           # a tool result opens no turn: still the operator's
]
OUT_OF_RANGE = [u("old session", "2026-01-01T09:00:00Z"), fb("ALPHA-GATE"), skill_call()]


def check(cond, title, detail=""):
    print(("ok  " if cond else "FAIL") + "  " + title + ("" if cond else f" - {detail}"))
    return cond


def parity():
    node = shutil.which("node")
    if not node or not HELPER.is_file():
        print("SKIP  parity with helpers/turn-kind.cjs - " + ("no node" if not node else "helper not in this tree"))
        return True
    spec = importlib_load()
    js = ("const {isNotification}=require(process.argv[1]);"
          "const s=JSON.parse(require('fs').readFileSync(0,'utf8'));"
          "process.stdout.write(JSON.stringify(s.map(isNotification)));")
    texts = [t for t, _ in SAMPLES.values()]
    p = subprocess.run([node, "-e", js, str(HELPER)], input=json.dumps(texts),
                       capture_output=True, text=True, encoding="utf-8")
    got_js = json.loads(p.stdout) if p.returncode == 0 else None
    got_py = [spec.is_notification(t) for t in texts]
    return check(got_js == got_py, "parity with helpers/turn-kind.cjs on every sample", (got_js, got_py))


def importlib_load():
    import importlib.util
    s = importlib.util.spec_from_file_location("sfm", SCRIPT)
    m = importlib.util.module_from_spec(s)
    s.loader.exec_module(m)
    return m


if __name__ == "__main__":
    res = []
    m = importlib_load()
    for name, (text, want) in SAMPLES.items():
        res.append(check(m.is_notification(text) is want, f"turn kind: {name} -> "
                         + ("notification" if want else "operator")))
    res.append(parity())
    with tempfile.TemporaryDirectory() as d:
        for name, recs in (("a.jsonl", IN_RANGE), ("b.jsonl", OUT_OF_RANGE)):
            with open(Path(d) / name, "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(json.dumps(r) for r in recs) + "\n")
        p = subprocess.run([sys.executable, SCRIPT, "--dir", d, "--since", "2026-03-01",
                            "--until", "2026-03-31"], capture_output=True, text=True, encoding="utf-8")
        rep = json.loads(p.stdout) if p.returncode == 0 else {}
        g, gn = rep.get("per_gate", {}), rep.get("per_gate_on_notification", {})
        res += [
            check(p.returncode == 0, "exit 0", p.stderr),
            check(rep.get("sessions") == 1, "the out-of-range session is excluded", rep),
            check(rep.get("skill_calls") == 2, "Skill calls counted, other tools not", rep),
            check(rep.get("stop_fires") == 5, "five Stop-hook blocks", rep),
            check(g.get("ALPHA-GATE") == 2 and g.get("BETA-VERIFIER") == 1,
                  "every tag in a block counts (negative control: first tag only = 0 for BETA)", g),
            check(g.get("untagged") == 1, "an untagged block is counted as untagged", g),
            check(rep.get("on_notification_turns") == 1 and gn == {"ALPHA-GATE": 1},
                  "only the task-notification turn is a notification turn", (rep, gn)),
            check(g.get("DELTA-GATE") == 1 and "DELTA-GATE" not in gn,
                  "a tool result carrying a frame does not open a notification turn", gn),
        ]
    p = subprocess.run([sys.executable, SCRIPT, "--dir", str(Path(tempfile.gettempdir()) / "no-such-dir-sfm")],
                       capture_output=True, text=True)
    res.append(check(p.returncode == 2, "no directory is exit 2"))
    sys.exit(0 if all(res) else 1)
