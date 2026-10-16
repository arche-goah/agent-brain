#!/usr/bin/env python3
"""Session audit: every past session either ended with the session-close skill, or the next
session start says so — and a session start that failed says so too.

WHY (operator order 2026-10-11): "record sessions that ended improperly and report at the
session start when past sessions ended without a close — that has to be loud, for everyone;
and a failed session start has to be loud as well." Measured the same day on the proving
brain: the session-start hook was cancelled after 30 s (its budget) and the first reply went
out without the open points — nothing at the next start would ever have said so. And
`helpers/session-closing.sh` only notices a missing close in its SessionEnd fallback, which
does not run on a hard kill, a crash or a closed terminal; nothing reported those either.

WHAT IT READS — the harness transcripts, the one record that survives any kill:
`~/.claude/projects/<munged project path>/<session-id>.jsonl` (the hook input's
`transcript_path` gives the directory exactly; the munged cwd is the fallback). Per past
session:
  * CLOSED   — the transcript shows the close: a Skill call of `session-close` (any plugin
               namespace) or the skill's own step `session-closing.sh --pre-commit`;
  * UNCLOSED — real prompts, but no close mark;
  * EMPTY    — no real prompt at all (opened and closed again): counted, never reported —
               nothing can have been lost;
  * the session START: `hook_cancelled` on the bootup hook (timeout) or a `hook_success`
    whose output lacks the bootup's closing marker = FAILED START, reported on its own.
A transcript touched in the last LIVE_MIN minutes may be a parallel session still running:
it is left for a later start (said in the summary, never reported as unclosed).

LOUD UNTIL ACKNOWLEDGED. Findings are handed to `scripts/open-items.py` as items of kind
`session` with class `ai` — the cause is in the transcript, so the AI reads it and says
it; the operator knows no more than the record (operator 2026-10-15) — so the
open-items Stop gate forces them into the first reply and the repeat counter makes them
louder at every start. The bootup also prints one `!!` summary line. A finding leaves the
list only by `--ack`: the session-close skill runs `--ack listed`, which acknowledges what
was listed at THIS session's start (it was put in front of the operator, and the session
ended properly); `--ack <id>` / `--ack all` by hand.

FIRST RUN on a brain: findings start at the window (default 7 days back,
SESSION_AUDIT_WINDOW_DAYS) — a brain with months of history must not open with a wall.
The window start is stored once and never moves forward by itself.

State (per machine, untracked): `.claude-state/session-audit.json` — window start, a verdict
cache per transcript (size + mtime, so a start parses only new or grown transcripts),
acknowledged ids, what the last start listed.

Usage:
  session-audit.py [--root R] [--hook-input JSON] [--dir D]     summary + findings (bootup)
  session-audit.py --json ...                                    findings as JSON (open-items)
  session-audit.py --dry-run --all ...                           counts over every transcript, writes nothing
  session-audit.py --ack listed|all|<session-id> [...]
Stdlib only; runs under `python3` or `python`.
"""
import argparse
import datetime
import json
import os
import re
import sys
from pathlib import Path

LIVE_MIN = 10
END_MARK = "=== END BOOTUP ==="
TRUNC = "[... truncated at 32 KiB]"
ABORT = "session-bootup aborted early"
BOOTUP = re.compile(r"session-bootup\.sh")
CLOSE_SKILL = re.compile(r'"name"\s*:\s*"Skill"\s*,\s*"input"\s*:\s*\{\s*"skill"\s*:\s*"(?:[\w.-]+:)?session-close"')
CLOSE_STEP = re.compile(r"session-closing\.sh[^\"\n]{0,80}--pre-commit")
# A large hook output is stored as a preview plus a file; the end marker lives in the file.
PERSISTED = re.compile(r"<persisted-output>\s*Output too large[^\n]*?Full output saved to:\s*(\S+)")
NOT_A_PROMPT = re.compile(r"^\s*(<task-notification|<system-reminder|<local-command|<command-name>/(clear|exit|resume)|Stop hook feedback|\[Request interrupted)")


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def save_json(path, data):
    try:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
        return True
    except OSError:
        return False


def transcript_dir(root, hook):
    if hook.get("transcript_path"):
        return Path(hook["transcript_path"]).parent
    return Path.home() / ".claude" / "projects" / re.sub(r"[^A-Za-z0-9]", "-", str(Path(root).resolve()))


def prompt_text(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if not isinstance(c, list):
        return None
    if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
        return None
    t = "\n".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    return t or None


def judge(path):
    """One pass over one transcript. Cheap substring tests first; JSON only where needed."""
    closed, prompts, first_ts, last_ts, start, entry = False, 0, "", "", None, ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if not entry:
                m = re.search(r'"entrypoint"\s*:\s*"([^"]+)"', line)
                entry = m.group(1) if m else ""
            if not closed and ("session-close" in line or "session-closing" in line):
                closed = bool(CLOSE_SKILL.search(line) or CLOSE_STEP.search(line))
            m = re.search(r'"timestamp"\s*:\s*"([^"]+)"', line)
            if m:
                first_ts = first_ts or m.group(1)
                last_ts = m.group(1)
            if '"SessionStart' in line and "session-bootup" in line:
                try:
                    a = json.loads(line).get("attachment") or {}
                except ValueError:
                    a = {}
                if a.get("hookEvent") == "SessionStart" and BOOTUP.search(a.get("command") or ""):
                    src = str(a.get("hookName") or "").split(":")[-1]
                    # The bootup runs again after every context compaction (hookName
                    # `SessionStart:compact`), under load and often past its budget. Measured
                    # 2026-10-15: two sessions that started fine, ran for hours and closed were
                    # reported as "start cancelled" because their compaction re-run timed out
                    # and overwrote the real start. Only the session's first start counts.
                    if start is not None and src == "compact":
                        continue
                    if a.get("type") == "hook_cancelled":
                        start = {"state": "cancelled", "ms": a.get("durationMs") or 0, "source": src}
                    elif a.get("type") == "hook_success":
                        text = str(a.get("content") or a.get("stdout") or "")
                        p = PERSISTED.search(text)
                        if p and END_MARK not in text:
                            try:
                                text = Path(p.group(1)).read_text(encoding="utf-8", errors="replace")
                            except OSError:
                                pass
                        # The bootup's own 32 KiB cap cuts the end marker off a start that ran
                        # through (measured 2026-10-14: 77 classify lines filled the cap) — a cut
                        # without the abort note is a long report, not a failed start.
                        done = END_MARK in text or (TRUNC in text and ABORT not in text)
                        start = {"state": "ok" if done else "incomplete", "ms": a.get("durationMs") or 0,
                                 "source": src}
                continue
            if '"type":"user"' not in line.replace(" ", "") or "tool_result" in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            msg = d.get("message") or {}
            if msg.get("role") != "user" or d.get("isMeta"):
                continue
            t = prompt_text(msg)
            if t and not NOT_A_PROMPT.search(t):
                prompts += 1
    # A headless run (`claude -p`, entrypoint sdk-cli — scheduled scans, scripted calls) has no
    # operator who could run the close: it is not "ended without close", only its start counts.
    if entry.startswith("sdk"):
        end = "headless"
    else:
        end = "closed" if closed else ("empty" if prompts == 0 else "unclosed")
    return {"end": end, "prompts": prompts, "first": first_ts, "last": last_ts, "start": start, "entry": entry}


def local(ts):
    """ISO timestamp (UTC 'Z') -> local 'YYYY-MM-DD HH:MM'."""
    try:
        t = datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone()
        return t.strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return ts[:16].replace("T", " ")


def scan(tdir, state, current, window_start, use_cache=True, now=None):
    now = now or datetime.datetime.now().timestamp()
    cache = state.setdefault("cache", {}) if use_cache else {}
    out, live = [], 0
    if not tdir.is_dir():
        return None, 0
    for p in sorted(tdir.glob("*.jsonl")):
        sid = p.stem
        if sid == current:
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        if window_start is not None and st.st_mtime < window_start:
            continue
        if now - st.st_mtime < LIVE_MIN * 60:
            live += 1
            continue
        key = f"{st.st_size}:{int(st.st_mtime)}"
        hit = cache.get(sid)
        if hit and hit.get("key") == key:
            v = hit["v"]
        else:
            try:
                v = judge(p)
            except OSError:
                continue
            cache[sid] = {"key": key, "v": v}
        out.append((sid, v))
    return out, live


def findings(verdicts):
    items = []
    for sid, v in verdicts:
        s = v.get("start")
        if s and s["state"] != "ok":
            # The finding carries what the transcript says, so nobody has to be asked
            # (operator 2026-10-15: "I don't know that either — it has to be cleared up").
            what = (f"its session start was cancelled by the hook timeout after {round((s['ms'] or 0) / 1000)} s — the start report never arrived"
                    if s["state"] == "cancelled" else
                    "its session-bootup script aborted partway — checks after the break did not run")
            what += ("; the session itself ended with session-close, so its work was saved" if v["end"] == "closed"
                     else "; the session itself ended without session-close — see its own line")
            items.append({"id": f"start:{sid}", "sid": sid, "kind": "start", "when": local(v["first"]), "text": what})
        if v["end"] == "unclosed":
            items.append({"id": f"end:{sid}", "sid": sid, "kind": "end", "when": local(v["last"]),
                          "text": f"ended without session-close ({v['prompts']} prompts, last activity {local(v['last'])[11:]})"})
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.environ.get("CLAUDE_PROJECT_DIR", "."))
    ap.add_argument("--hook-input", default="")
    ap.add_argument("--dir", default="")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--details", action="store_true", help="one line per finding (hand runs)")
    ap.add_argument("--dry-run", action="store_true", help="write no state")
    ap.add_argument("--all", action="store_true", help="ignore the window (with --dry-run: baseline counts)")
    ap.add_argument("--since", default="", help="YYYY-MM-DD: count from this date (with --dry-run)")
    ap.add_argument("--ack", nargs="+")
    a = ap.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", newline="\n")  # OS-9: parsed by the bootup and open-items

    root = Path(a.root)
    state_file = root / ".claude-state" / "session-audit.json"
    state = load_json(state_file, {})
    hook = {}
    if a.hook_input.strip():
        try:
            hook = json.loads(a.hook_input)
        except ValueError:
            pass
    current = hook.get("session_id") or os.environ.get("CLAUDE_SESSION_ID", "")
    tdir = Path(a.dir) if a.dir else transcript_dir(root, hook)

    if a.ack:
        acked = state.setdefault("acked", {})
        today = datetime.date.today().isoformat()
        ids = set()
        for x in a.ack:
            if x == "listed":
                ids |= set(state.get("listed", []))
            elif x == "all":
                ids |= {f["id"] for f in state.get("open", [])}
            else:
                ids |= {f["id"] for f in state.get("open", []) if f["sid"].startswith(x) or f["id"] == x} or {x}
        for i in ids:
            acked[i] = today
        if not save_json(state_file, state):
            print(f"!! session audit: acknowledgement NOT saved ({state_file})")
            return 1
        print(f"session audit: {len(ids)} finding(s) acknowledged")
        return 0

    now = datetime.datetime.now()
    if a.all:
        window_start = None
    elif a.since:
        window_start = datetime.datetime.fromisoformat(a.since).timestamp()
    else:
        if "since" not in state:
            days = int(os.environ.get("SESSION_AUDIT_WINDOW_DAYS", "7") or 7)
            state["since"] = (now - datetime.timedelta(days=days)).isoformat(timespec="seconds")
        window_start = datetime.datetime.fromisoformat(state["since"]).timestamp()

    verdicts, live = scan(tdir, state, current, window_start, use_cache=not a.dry_run)
    if verdicts is None:
        print(f"!! session audit: NOT checked — no transcript directory ({tdir.name})")
        return 2
    acked = state.get("acked", {})
    found = [f for f in findings(verdicts) if f["id"] not in acked]

    if a.dry_run:
        ends = {k: sum(1 for _, v in verdicts if v["end"] == k) for k in ("closed", "unclosed", "empty", "headless")}
        starts = {k: sum(1 for _, v in verdicts if (v.get("start") or {}).get("state") == k)
                  for k in ("ok", "cancelled", "incomplete")}
        nostart = sum(1 for _, v in verdicts if not v.get("start"))
        dates = sorted(v["first"][:10] for _, v in verdicts if v["first"])
        print(json.dumps({"sessions": len(verdicts), "from": dates[0] if dates else "", "to": dates[-1] if dates else "",
                          "end": ends, "start": starts, "no_start_record": nostart, "live_skipped": live,
                          "findings": len(found)}, indent=1))
        return 0

    state["open"] = found
    if current:  # only a real session start lists — a hand run must not ack-arm anything
        state["listed"] = [f["id"] for f in found]
    state["last_run"] = now.isoformat(timespec="seconds")
    # keep the cache bounded to what the window can still see
    state["cache"] = {k: v for k, v in state.get("cache", {}).items() if (tdir / f"{k}.jsonl").exists()}
    saved = save_json(state_file, state)

    if a.json:
        print(json.dumps(found, ensure_ascii=False))
        return 0
    ends = sum(1 for f in found if f["kind"] == "end")
    starts = sum(1 for f in found if f["kind"] == "start")
    if found:
        parts = ([f"{ends} session(s) ended without session-close"] if ends else []) + \
                ([f"{starts} session start(s) failed"] if starts else [])
        # One summary line here; each finding is an item of the open-items list right below,
        # where the Stop gate makes the first reply name it (no second copy of each line).
        print("!! session audit: " + " · ".join(parts) + " — each one is in 'open for us' below")
        if a.details:
            for f in found:
                print(f"!! {f['when']} session {f['sid'][:8]}: {f['text']}")
    if live:
        print(f"session audit: {live} transcript(s) touched in the last {LIVE_MIN} min left for a later start (may still run)")
    if not saved:
        print(f"!! session audit: state NOT saved ({state_file}) — findings will repeat but acks are lost")
    return 0


if __name__ == "__main__":
    sys.exit(main())
