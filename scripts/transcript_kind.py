"""Is a transcript a session, or a headless model call? — one answer for every reader of the history.

WHY (2026-11-02, macOS instance): a headless call (`claude -p`: the prompt classifier, a scripted check) leaves a
transcript of its own in the project folder, its first records carry `entrypoint: "sdk-cli"`, and its prompt quotes the
operator. 24 of the 40 newest transcripts were such calls; the root-cause review counted their quoted words as
corrections (63 instead of 16 in a week) and its newest-N window lost the real sessions. The Node reader with the same
rule is the `headless` filter in helpers/root-cause-gate.cjs (review). session-audit.py keeps its own entry reading (it
reports headless runs as such). Fixture: scripts/transcript-kind-test.py.
"""
from __future__ import annotations

import re
from pathlib import Path

# The first record of such a call is its whole prompt; the field can stand after it (measured: not within 4 KB).
_HEAD = 256 * 1024
_ENTRY = re.compile(rb'"entrypoint"\s*:\s*"([^"]+)"')


def is_headless(path: str | Path) -> bool:
    """True when the FIRST entrypoint value in the transcript is `sdk-cli` (a quoted field later does not count)."""
    try:
        with open(path, "rb") as fh:
            m = _ENTRY.search(fh.read(_HEAD))
    except OSError:
        return False
    return bool(m) and m.group(1) == b"sdk-cli"


def sessions(paths):
    """The given transcript paths without headless calls, order kept."""
    return [p for p in paths if not is_headless(p)]
