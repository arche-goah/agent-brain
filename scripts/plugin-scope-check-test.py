#!/usr/bin/env python3
"""Fixtures for plugin-scope-check.py — both directions, plus the input the checker must
refuse to call green.

The positive control is the point of this file: the inline predecessor of the checker
stayed green on a fed-in duplicate because it never parsed. A checker that can only say
"ok" is not a checker (onboarding-contract, negative control).

Usage: python3 scripts/plugin-scope-check-test.py   (exit 0 = all fixtures pass)
"""
import importlib.util
import io
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("psc", HERE / "plugin-scope-check.py")
psc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(psc)

fails = []


def ok(n, cond, detail=""):
    print(f"  {'ok  ' if cond else 'FAIL'}  {n}{'' if cond else ': ' + detail}")
    if not cond:
        fails.append(n)


def run(payload, *args):
    out = io.StringIO()
    real = sys.stdout
    sys.stdout = out
    try:
        rc = psc.main(["plugin-scope-check.py", *args], io.StringIO(payload))
    finally:
        sys.stdout = real
    return rc, out.getvalue().strip()


def entry(pid, scope, enabled=True):
    return {"id": pid, "scope": scope, "enabled": enabled, "version": "1.3.35"}


# 1. The shape `claude plugin list --json` prints (measured 2.1.x): a bare list.
single = json.dumps([entry("brain-core@arche-goah", "user"),
                     entry("brain-internal@arche-goah", "user")])
rc, note = run(single)
ok("single scope is green", rc == 0 and note == "brain-core@arche-goah:user", f"rc={rc} {note!r}")

# 2. POSITIVE CONTROL — the case the inline predecessor missed.
dup = json.dumps([entry("brain-core@arche-goah", "user"),
                  entry("brain-core@arche-goah", "project")])
rc, note = run(dup)
ok("duplicate scope is red", rc == 1, f"rc={rc}")
ok("duplicate note names both scopes", note == "brain-core@arche-goah:user+project", note)

# 3. A disabled second copy loads nothing — not a duplicate.
disabled = json.dumps([entry("brain-core@arche-goah", "user"),
                       entry("brain-core@arche-goah", "project", enabled=False)])
rc, note = run(disabled)
ok("disabled copy in another scope is green", rc == 0 and note == "brain-core@arche-goah:user", f"rc={rc} {note!r}")

# 4. Beta channel counts as core, and two different ids in the same scope are fine
#    (a machine mid-switch has brain-core disabled and brain-core-next enabled).
channels = json.dumps([entry("brain-core@arche-goah", "user", enabled=False),
                       entry("brain-core-next@arche-goah", "user")])
rc, note = run(channels)
ok("beta channel alone is green", rc == 0 and note == "brain-core-next@arche-goah:user", f"rc={rc} {note!r}")

# 5. Object-wrapped form is accepted too.
wrapped = json.dumps({"plugins": [entry("brain-core@arche-goah", "project")]})
rc, note = run(wrapped)
ok("{plugins: [...]} form is read", rc == 0 and note == "brain-core@arche-goah:project", f"rc={rc} {note!r}")

# 6. Input not understood is exit 2, never 0 — the caller must report "unchecked".
for name, bad in (("garbage", "not json"), ("wrong shape", json.dumps({"x": 1})),
                  ("empty", "")):
    rc, note = run(bad)
    ok(f"{name} input is exit 2", rc == 2, f"rc={rc} {note!r}")

# 7. Custom prefixes via argv.
rc, note = run(json.dumps([entry("other@org", "user"), entry("other@org", "project")]), "other@")
ok("custom prefix is honoured", rc == 1 and note == "other@org:user+project", f"rc={rc} {note!r}")

print()
if fails:
    print(f"plugin-scope-check-test: {len(fails)} FAIL — {', '.join(fails)}")
    sys.exit(1)
print("plugin-scope-check-test: all fixtures pass")
