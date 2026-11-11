"""The ONE reader of ledger fields in Python; the JavaScript twin is helpers/ledger-fields.cjs. Both build their
patterns from ledger-fields.json at the core root, so the two languages cannot read a field differently.

WHY (content review of agent-brain #475, 2026-11-10): four readers of `id:` used four patterns; one of them read only
line starts and called mid-line ids (`... | id: x | class: todo`) absent, so tracked findings read as "vanished".

  field_values(text, name)  every value of the field in the text, in order
  first_value(text, name)   the first one, or None
"""
import json
import os
import re

_SPEC = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ledger-fields.json")
_CACHE = {}


def pattern(name):
    if name not in _CACHE:
        with open(_SPEC, encoding="utf-8") as fh:
            f = json.load(fh)["fields"][name]
        _CACHE[name] = re.compile(f["lead"] + re.escape(name) + r":\s*`?" + f["value"] + f["end"], re.M)
    return _CACHE[name]


def field_values(text, name):
    return [m.group(1) for m in pattern(name).finditer(text or "")]


def first_value(text, name):
    m = pattern(name).search(text or "")
    return m.group(1) if m else None
