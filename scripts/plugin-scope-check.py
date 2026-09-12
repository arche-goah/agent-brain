#!/usr/bin/env python3
"""Scope check for the core plugin: read `claude plugin list --json` on stdin, report the
scope of every enabled core entry, refuse a duplicate.

Why a file and not an inline block in onboarding-verify.sh: the first version of this
check lived inline in single shell quotes and contained `'+'.join(...)` — the inner quotes
ended the shell literal, the script never parsed, and `2>/dev/null || true` turned the
parse error into a green line. The positive control (a fed-in duplicate) stayed green,
which is the one thing a checker must never do. A file has no quoting layer to break.

Contract (ONBOARDING.md step 2): the core is installed ONCE, in scope `user`. The same
plugin id enabled in two scopes at once loads every skill and hook twice and leaves
"which version wins" to the harness — measured on a collaborator's first day
(2026-09-12: brain-core 1.3.32 in user AND project, both enabled).

stdin   : JSON from `claude plugin list --json` — a list of entries, or an object with a
          `plugins` list (both shapes accepted; the list form is what 2.1.x prints)
argv[1:]: id prefixes that count as "the core" (default: brain-core@ brain-core-next@)
stdout  : one line — `<id>:<scope>[+<scope>...]` per enabled core entry, space-separated
exit    : 0 = no duplicate · 1 = same id enabled in more than one scope · 2 = input not
          understood (the caller must treat 2 as "unchecked", never as green)
"""
import json
import sys

DEFAULT_PREFIXES = ("brain-core@", "brain-core-next@")


def check(entries, prefixes=DEFAULT_PREFIXES):
    """Return (note, duplicates) for the enabled core entries in `entries`."""
    scopes = {}
    for p in entries:
        if not isinstance(p, dict):
            continue
        pid = str(p.get("id", ""))
        if not pid.startswith(tuple(prefixes)) or not p.get("enabled"):
            continue
        scopes.setdefault(pid, []).append(str(p.get("scope", "?")))
    note = " ".join(f"{i}:{'+'.join(s)}" for i, s in sorted(scopes.items()))
    dups = sorted(i for i, s in scopes.items() if len(s) > 1)
    return note, dups


def load(raw):
    """Accept the list form and the {plugins: [...]} form; anything else is not understood."""
    data = json.loads(raw)
    if isinstance(data, dict):
        data = data.get("plugins")
    if not isinstance(data, list):
        raise ValueError("expected a list of plugin entries")
    return data


def main(argv, stdin):
    prefixes = tuple(argv[1:]) or DEFAULT_PREFIXES
    try:
        entries = load(stdin.read())
    except (ValueError, TypeError) as e:  # json.JSONDecodeError is a ValueError
        print(f"plugin-scope-check: input not understood ({e})")
        return 2
    note, dups = check(entries, prefixes)
    print(note)
    return 1 if dups else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv, sys.stdin))
