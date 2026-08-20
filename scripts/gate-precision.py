#!/usr/bin/env python3
"""How often does a Stop gate cost a round WITHOUT changing anything?

A gate is not judged by how often it fires but by how often the answer AFTER the
block differs from the answer BEFORE it. A block that ends in an unchanged
re-issue cost tokens, latency and the operator's attention for nothing — and a gate
whose precision stays at zero over a session is due for a higher threshold or for
deletion, not for another rule about it.

    python3 scripts/gate-precision.py [<n transcripts>]

Reads the session transcripts of this project. For every gate block it compares the
last assistant text before the block with the first assistant text after it:
  changed   — the gate caused a correction (it earned the round)
  unchanged — the answer was re-issued as it stood (the round was overhead)
The comparison ignores the gate-answer lines the gates themselves demand (a leading
marker line), so answering a gate does not count as a correction by itself."""
import difflib
import glob
import json
import os
import re
import sys

def project_dir(root=None):
    """Where this project's transcripts live, derived — never hardcoded.

    Claude Code stores them under ~/.claude/projects/<slug>, where the slug is the
    project path with every separator replaced by a dash. Deriving it is what lets the
    same script run in another brain, on another OS, under another user; the earlier
    version carried one machine's path and would have measured nothing anywhere else.
    """
    root = os.path.abspath(root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd())
    slug = root.replace(os.sep, "-").replace(":", "").replace("/", "-")
    return os.path.join(os.path.expanduser("~"), ".claude", "projects", slug)
GATE = re.compile(r'\b([A-Z][A-Z-]{2,}-GATE|CLASS-GATE|KLASSEN-GATE)\b')
# Lines a gate ASKS FOR are not a correction — answering a gate must not read as one.
# The markers are instance data (they are written in the operator's language), so they
# come from a file when there is one; the built-in is the shape every brain uses.
def _answer_markers(root):
    patterns = [r'⚙']
    try:
        path = os.path.join(root, ".claude", "rules", "gate-answer-markers.json")
        with open(path, encoding="utf-8") as fh:
            extra = json.load(fh).get("patterns", [])
        patterns += [p for p in extra if isinstance(p, str)]
    except Exception:
        pass
    return re.compile(r'^\s*(' + '|'.join(patterns) + ')', re.M)


def norm(text, markers):
    """Compare the substance: drop the lines a gate answer adds."""
    return ' '.join(markers.sub('', text).split())


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    root = sys.argv[2] if len(sys.argv) > 2 else None
    markers = _answer_markers(os.path.abspath(
        root or os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()))
    project = project_dir(root)
    if not os.path.isdir(project):
        print(f"no transcripts found for this project: {project}")
        return 1
    files = sorted(glob.glob(os.path.join(project, "*.jsonl")),
                   key=os.path.getmtime)[-n:]
    stats = {}
    for path in files:
        events = []
        for line in open(path):
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message") or {}
            if m.get("role") == "user" and isinstance(m.get("content"), str):
                if m["content"].startswith("Stop hook feedback:"):
                    names = sorted(set(GATE.findall(m["content"])))
                    events.append(("block", names))
                else:
                    events.append(("operator", None))
            elif m.get("role") == "assistant" and isinstance(m.get("content"), list):
                for b in m["content"]:
                    if b.get("type") == "text" and b.get("text", "").strip():
                        events.append(("text", b["text"]))

        for i, (kind, payload) in enumerate(events):
            if kind != "block":
                continue
            before = next((e[1] for e in reversed(events[:i]) if e[0] == "text"), None)
            after = next((e[1] for e in events[i + 1:] if e[0] == "text"), None)
            if before is None or after is None:
                continue
            a, b = norm(before, markers), norm(after, markers)
            same = a == b
            ratio = difflib.SequenceMatcher(None, a, b).ratio()
            for g in payload or ["<unnamed>"]:
                s = stats.setdefault(g, {"blocks": 0, "unchanged": 0, "ratios": []})
                s["blocks"] += 1
                s["ratios"].append(ratio)
                if same or ratio > 0.97:
                    s["unchanged"] += 1

    print(f"{len(files)} transcripts\n")
    print(f"{'gate':16} {'blocks':>7} {'unchanged':>10} {'waste':>7}  protocol")
    for g in sorted(stats, key=lambda k: -stats[k]["blocks"]):
        s = stats[g]
        rs = sorted(s["ratios"])
        med = rs[len(rs) // 2]
        # Two protocols, and only one of them is measurable this way. A gate that
        # asks for an ANSWER (a class line, a diagnosis) is followed by a short new
        # text — "changed" is then trivially true and says nothing. A gate that asks
        # for a RE-ISSUE is followed by the same answer again, so a high similarity
        # means the block changed nothing and cost a round for it.
        reissue = med > 0.5
        waste = f"{100.0 * s['unchanged'] / s['blocks']:.0f}%" if reissue else "n/a"
        kind = ("re-issue — waste = blocks that changed nothing"
                if reissue else "answer-gate — not measurable by text diff")
        print(f"{g:16} {s['blocks']:7d} {s['unchanged']:10d} {waste:>7}  {kind}")
    print("\nOnly re-issue gates are judgeable here. For answer-gates the question is "
          "whether the answer produced a register line, and that lives in the register, "
          "not in the transcript.")


if __name__ == "__main__":
    main()
