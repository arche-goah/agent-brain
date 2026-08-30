#!/usr/bin/env python3
"""covers: invariant-check

The runner had no fixture at all until now, which made it an instance of an invariant its
own register carries: "a mechanism without a fixture is an assertion about itself".

Both directions, and the negative half carries the weight — this report is read to decide
whether a class is still held, so a false "all quiet" is the expensive failure.

Run: scripts/invariant-check-test.py    Exit 0 = all green.
"""
from __future__ import annotations

import importlib.util
import io
import contextlib
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("ic", ROOT / "scripts" / "invariant-check.py")
ic = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ic)

fails = 0


def ok(m):
    print(f"  ok    {m}")


def bad(m):
    global fails
    fails += 1
    print(f"  FAIL  {m}")


def run(register: Path) -> tuple[str, int]:
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = ic.main([str(register)])
    return buf.getvalue(), rc


def write(tmp: Path, body: str) -> Path:
    reg = tmp / "invariants.md"
    reg.write_text("root: .\n\n" + body, encoding="utf-8")
    return reg


def main() -> int:
    print("invariant-check:")
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        (tmp / "src").mkdir()
        (tmp / "src" / "a.py").write_text("value = FORBIDDEN_CALL()\n", encoding="utf-8")

        # 1. a pattern whose baseline matches reality is quiet
        reg = write(tmp, """## X-1 — a mechanized invariant
invariant: the thing must not spread
pattern: FORBIDDEN_CALL
paths: --include=*.py src
known: src/a.py=1
instances: 1
repeat: no
status: closed
""")
        out, rc = run(reg)
        if "  ok  X-1" in out and rc == 0:
            ok("1 pattern with a matching baseline reports ok")
        else:
            bad(f"1 expected ok, got rc={rc}: {out.strip()[:160]}")

        # 2. a NEW site is drift and must fail loudly — the whole point of the register
        (tmp / "src" / "b.py").write_text("FORBIDDEN_CALL()\n", encoding="utf-8")
        out, rc = run(reg)
        if "NEW site" in out and rc == 1:
            ok("2 a new site fails loudly")
        else:
            bad(f"2 expected NEW site + rc 1, got rc={rc}")
        (tmp / "src" / "b.py").unlink()

        # 3. NO pattern and NO reason -> '??' and counted in the closing summary. This is
        #    the case the report used to hide: 35 of 43 entries printed as plain '--'.
        reg = write(tmp, """## Y-1 — held by prose alone
invariant: something a grep cannot span
check: think about it
instances: 2
repeat: no
status: closed
""")
        out, rc = run(reg)
        if "  ??  Y-1" in out and "1 invariant(s) with neither" in out:
            ok("3 no pattern, no reason -> ?? and counted as backlog")
        else:
            bad(f"3 backlog not surfaced: {out.strip()[:200]}")

        # 4. NEGATIVE: the same entry with a STATED reason is a decision, not a backlog
        #    item — it must NOT appear in the summary.
        reg = write(tmp, """## Y-2 — deliberately external
invariant: the search term differs every time
check: grep whatever just changed
mechanizable: no — the search word is in the change, never in the register
instances: 2
repeat: no
status: closed
""")
        out, rc = run(reg)
        if "  --  Y-2" in out and "external by decision" in out \
                and "with neither" not in out:
            ok("4 stated reason -> external by decision, not counted")
        else:
            bad(f"4 stated reason mishandled: {out.strip()[:200]}")

        # 5. NEGATIVE: 'mechanizable' must not be a magic word that silences a REAL
        #    pattern — an entry with both keeps being checked.
        reg = write(tmp, """## Y-3 — has both
invariant: still mechanized
pattern: FORBIDDEN_CALL
paths: --include=*.py src
known: src/a.py=1
mechanizable: no — should be ignored here
instances: 1
repeat: no
status: closed
""")
        out, rc = run(reg)
        if "  ok  Y-3" in out and "external by decision" not in out:
            ok("5 a pattern wins over the mechanizable field")
        else:
            bad(f"5 pattern was skipped: {out.strip()[:200]}")

        # 6. NEGATIVE: an open status still prints its verdict in every branch, so a
        #    backlog entry that is ALSO open cannot hide behind the new symbol
        reg = write(tmp, """## Y-4 — open and unmechanized
invariant: two problems at once
check: manual
instances: 3
repeat: yes
status: open
""")
        out, rc = run(reg)
        if "  ??  Y-4" in out and "->" in out:
            ok("6 open + unmechanized shows both the symbol and the verdict")
        else:
            bad(f"6 verdict missing: {out.strip()[:200]}")


        # 7. the THIRD state: a named TOOL re-checks it, not a grep. Measured on the real
        #    register — several entries name effect-check.sh or an MCP verb in check:.
        #    Deliberate, so it must not be counted as backlog either.
        reg = write(tmp, """## Y-5 — checked by a tool
invariant: a tool re-runs this
check: core/scripts/effect-check.sh
mechanizable: tool — effect-check.sh bundles the four effect probes
instances: 4
repeat: no
status: closed
""")
        out, rc = run(reg)
        if "  --  Y-5" in out and "mechanized by a tool" in out \
                and "with neither" not in out:
            ok("7 tool-checked invariant is deliberate, not backlog")
        else:
            bad(f"7 tool state mishandled: {out.strip()[:200]}")

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
