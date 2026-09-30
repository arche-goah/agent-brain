"""Shared logging utilities for last30days skill."""

import os
import re
import sys

DEBUG = os.environ.get("LAST30DAYS_DEBUG", "").lower() in ("1", "true", "yes")

# A value after a secret-looking name, a Bearer token, or an sc_/sk-/xai- style key.
# Output from this skill runs inside an agent session and lands in its transcript
# (brain core, 2026-09-30): nothing that looks like a credential leaves unmasked.
_SECRET = re.compile(
    r"(?i)((?:token|key|secret|password|passwd|auth|cookie|ct0|bearer)[\"']?\s*[:=]?\s*[\"']?)[^\s\"',}]{6,}"
    r"|\b(?:sc|sk|xai|ghp|gho|github_pat)[_-][A-Za-z0-9_\-]{8,}"
)


def redact(msg: str) -> str:
    return _SECRET.sub(lambda m: (m.group(1) or "") + "***", str(msg))


def debug(msg: str) -> None:
    """Log debug message to stderr (only when LAST30DAYS_DEBUG is set), secrets masked."""
    if DEBUG:
        sys.stderr.write(f"[DEBUG] {redact(msg)}\n")
        sys.stderr.flush()


def source_log(prefix: str, msg: str, *, tty_only: bool = True) -> None:
    """Log a source module message to stderr.

    Args:
        prefix: Source label (e.g. "Reddit", "Bird").
        msg: Message text.
        tty_only: If True, only log when stderr is a TTY (avoids cluttering
                  non-interactive output like Claude Code).
    """
    if tty_only and not sys.stderr.isatty():
        return
    sys.stderr.write(f"[{prefix}] {msg}\n")
    sys.stderr.flush()
