#!/usr/bin/env python3
"""Fixture tests for scripts/session-log-fold.py.

The fold moves protocol lines out of an append-only file, so the dangerous direction is
loss: every case that folds also proves the original bytes come back from log + fold
file. The other direction is noise: a fold that fires every session would scatter the
log into a hundred tiny files, so the threshold and its hysteresis are asserted too.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

FOLD = str(Path(__file__).resolve().parent / "session-log-fold.py")
PAD = "x" * 80


def entry(day, nl="\n"):
    return f"- 2026-01-{day:02d} 10:00:00 | main | close{nl}  topic {day} {PAD}{nl}"


def brain(d, text):
    log = Path(d) / "docs" / "maintenance" / "session-log.md"
    log.parent.mkdir(parents=True)
    log.write_bytes(text.encode("utf-8"))
    return log


def run(d, *args):
    p = subprocess.run([sys.executable, FOLD, "--root", d, "--today", "2026-01-20", *args],
                       capture_output=True, text=True)
    return p.returncode, p.stdout


def reassembled(d, log):
    """Put every fold file's children back in place of its marker line."""
    text = log.read_bytes().decode("utf-8")
    for f in sorted((Path(d) / "docs" / "maintenance" / "session-log-folds").glob("*.md")):
        raw = f.read_bytes().decode("utf-8")
        nl = "\r\n" if "\r\n" in raw else "\n"
        children = raw.split(nl + nl, 1)[1]
        marker = next(l for l in text.splitlines(keepends=True) if f.stem in l)
        text = text.replace(marker, children, 1)
    return text


def case(title, fn):
    with tempfile.TemporaryDirectory() as d:
        ok, why = fn(d)
        print(("ok  " if ok else "FAIL") + "  " + title + ("" if ok else f" - {why}"))
        return ok


def t_under_threshold_noop(d):
    text = "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    rc, out = run(d, "--max-bytes", "100000", "--apply")
    return (rc == 0 and log.read_bytes().decode() == text and "no-op" in out, out)


def t_over_threshold_folds_lossless(d):
    text = "# preamble\n" + "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    rc, out = run(d, "--max-bytes", "1200", "--apply")
    new = log.read_bytes().decode()
    ok = (rc == 0 and "- FOLD " in new and len(new.encode()) <= 600
          and new.startswith("# preamble\n") and reassembled(d, log) == text)
    return (ok, out + f" | size={len(new.encode())}")


def t_hysteresis_keeps_newest(d):
    # down to N/2, not to "just under N": the newest days stay in the log
    text = "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    run(d, "--max-bytes", "1200", "--apply")
    new = log.read_bytes().decode()
    heads = [l for l in new.splitlines() if l.startswith("- 2026-")]
    return (heads[-1].startswith("- 2026-01-10 ") and not heads[0].startswith("- 2026-01-01 "),
            new[:200])


def t_idempotent(d):
    text = "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    run(d, "--max-bytes", "1200", "--apply")
    once = log.read_bytes()
    files = sorted(os.listdir(Path(d) / "docs" / "maintenance" / "session-log-folds"))
    rc, out = run(d, "--max-bytes", "1200", "--apply")
    again = sorted(os.listdir(Path(d) / "docs" / "maintenance" / "session-log-folds"))
    return (rc == 0 and log.read_bytes() == once and files == again, out)


def t_today_never_folded(d):
    text = "".join(entry(20) for _ in range(12))  # all entries dated --today
    log = brain(d, text)
    rc, out = run(d, "--max-bytes", "500", "--apply")
    return (rc == 0 and log.read_bytes().decode() == text, out)


def t_crlf_kept(d):
    text = "".join(entry(i, "\r\n") for i in range(1, 11))
    log = brain(d, text)
    rc, out = run(d, "--max-bytes", "1200", "--apply")
    new = log.read_bytes().decode()
    lone_lf = new.replace("\r\n", "").count("\n")
    return (rc == 0 and "- FOLD " in new and lone_lf == 0 and reassembled(d, log) == text,
            out + f" | lone LF={lone_lf}")


def t_out_of_order_refused(d):
    text = entry(5) + entry(1) + entry(9) + entry(2)
    log = brain(d, text)
    rc, out = run(d, "--before", "2026-01-03", "--apply")
    return (rc == 1 and "refused" in out and log.read_bytes().decode() == text, out)


def t_preview_writes_nothing(d):
    text = "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    rc, out = run(d, "--max-bytes", "1200")
    folds = Path(d) / "docs" / "maintenance" / "session-log-folds"
    return (rc == 0 and log.read_bytes().decode() == text and not folds.exists()
            and "preview" in out, out)


def t_second_fold_keeps_first_marker(d):
    text = "".join(entry(i) for i in range(1, 11))
    log = brain(d, text)
    run(d, "--before", "2026-01-04", "--apply")
    run(d, "--before", "2026-01-08", "--apply")
    new = log.read_bytes().decode()
    return (new.count("- FOLD ") == 2 and reassembled(d, log) == text, new[:300])


# --- decision log: same engine, `--log decision` ---------------------------------------
DHEAD = ("# Decision log\n\n> Pillar decisions, newest first.\n\nEntry format:\n\n"
         "```\n## YYYY-MM-DD — title\n```\n\n")


def dentry(day):
    return f"## 2026-01-{day:02d} — decision {day}\n\nwhy and what was discarded {PAD}\n\n"


def dlog(d, text):
    log = Path(d) / "docs" / "maintenance" / "decision-log.md"
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_bytes(text.encode("utf-8"))
    return log


def dreassembled(d, log):
    text = log.read_bytes().decode("utf-8")
    for f in sorted((Path(d) / "docs" / "maintenance" / "decision-log-folds").glob("*.md")):
        children = f.read_bytes().decode("utf-8").split("\n\n", 1)[1]
        marker = next(l for l in text.splitlines(keepends=True) if l.startswith("## FOLD " + f.stem))
        text = text.replace(marker, children, 1)
    return text


def t_decision_newest_first_lossless(d):
    text = DHEAD + "".join(dentry(i) for i in range(10, 0, -1))
    log = dlog(d, text)
    rc, out = run(d, "--log", "decision", "--before", "2026-01-05", "--apply")
    new = log.read_bytes().decode()
    ok = (rc == 0 and new.startswith(DHEAD) and new.count("## FOLD ") == 1
          and "| 2026-01-01 .. 2026-01-04 |" in new and "## 2026-01-05" in new
          and "## 2026-01-04" not in new and dreassembled(d, log) == text)
    return (ok, out + " | " + new[-300:])


def t_decision_guard_refused(d):
    # negative control: a non-entry heading between old entries is a guard, never folded
    text = DHEAD + dentry(9) + dentry(3) + "## Notes on the format\n\nkept\n\n" + dentry(2)
    log = dlog(d, text)
    rc, out = run(d, "--log", "decision", "--before", "2026-01-05", "--apply")
    return (rc == 1 and "refused" in out and log.read_bytes().decode() == text
            and not (Path(d) / "docs" / "maintenance" / "decision-log-folds").exists(), out)


def t_decision_max_bytes_keeps_newest(d):
    text = DHEAD + "".join(dentry(i) for i in range(10, 0, -1))
    log = dlog(d, text)
    rc, out = run(d, "--log", "decision", "--max-bytes", "1200", "--apply")
    new = log.read_bytes().decode()
    return (rc == 0 and "## 2026-01-10" in new and "## 2026-01-01" not in new
            and dreassembled(d, log) == text, out)


def t_profiles_do_not_cross(d):
    # the session default never touches the decision log, and vice versa
    stext = "".join(entry(i) for i in range(1, 11))
    dtext = DHEAD + "".join(dentry(i) for i in range(10, 0, -1))
    slog, dl = brain(d, stext), dlog(d, dtext)
    run(d, "--before", "2026-01-05", "--apply")
    d_untouched = dl.read_bytes().decode() == dtext
    s_after = slog.read_bytes()
    run(d, "--log", "decision", "--before", "2026-01-05", "--apply")
    return (d_untouched and slog.read_bytes() == s_after and "## FOLD " in dl.read_bytes().decode(),
            "a profile wrote into the other log")


if __name__ == "__main__":
    results = [
        case("decision log, newest first: folds old entries, head and template intact, lossless",
             t_decision_newest_first_lossless),
        case("decision log: a guard heading between entries is refused (negative control)",
             t_decision_guard_refused),
        case("decision log: --max-bytes folds the oldest, keeps the newest",
             t_decision_max_bytes_keeps_newest),
        case("session and decision profiles never write into each other's log", t_profiles_do_not_cross),
        case("under the threshold: no-op", t_under_threshold_noop),
        case("over the threshold: folds, byte-exact reassembly", t_over_threshold_folds_lossless),
        case("hysteresis: folds oldest days, keeps the newest", t_hysteresis_keeps_newest),
        case("second run is a no-op", t_idempotent),
        case("entries of today are never folded", t_today_never_folded),
        case("CRLF log stays CRLF", t_crlf_kept),
        case("out-of-order entries refused, nothing written", t_out_of_order_refused),
        case("preview writes nothing", t_preview_writes_nothing),
        case("a second fold keeps the first marker (no fold-of-folds)", t_second_fold_keeps_first_marker),
    ]
    sys.exit(0 if all(results) else 1)
