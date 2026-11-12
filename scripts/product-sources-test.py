#!/usr/bin/env python3
"""Fixture for product-sources.py: a plan and an order list bound to exact product pages, both directions."""
import datetime as dt
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("ps", HERE / "product-sources.py")
ps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ps)

fails = 0


def check(name, ok):
    global fails
    print(("  OK   " if ok else "  FAIL ") + name)
    fails += 0 if ok else 1


NOW = dt.datetime(2026, 11, 11, 18, 0, tzinfo=dt.timezone.utc)
RULES = ps.compile_rules({"product_shapes": {"shop-a.example": r"/p/[a-z0-9-]+-\d+$"}})
BUILTIN = ps.compile_rules({})

with tempfile.TemporaryDirectory() as tmp:
    t = Path(tmp)

    def write(name, text):
        p = t / name
        p.write_text(text, encoding="utf-8")
        return str(p)

    # --- plan ---
    plan_ok = write("plan-ok.csv", "key,product_url,fit_evidence,verdict\n"
                    "J1,https://shop-a.example/p/terminal-2pole-1234,datasheet p3 pitch 5.08,fits\n")
    rows, bad = ps.check_plan(plan_ok, None, RULES)
    check("plan: a product page with fit evidence and 'fits' passes", bad == [])

    plan_search = write("plan-search.csv", "key,product_url,fit_evidence,verdict\n"
                        "J1,https://shop-a.example/search?q=terminal,datasheet,fits\n")
    _, bad = ps.check_plan(plan_search, None, RULES)
    check("plan: a search page is no source (the incident)", any("search page" in b for b in bad))

    plan_noev = write("plan-noev.csv", "key,product_url,fit_evidence,verdict\n"
                      "J1,https://shop-a.example/p/terminal-2pole-1234,,unverified\n")
    _, bad = ps.check_plan(plan_noev, None, RULES)
    check("plan: no fit evidence and verdict not 'fits' both named", len(bad) == 1 and "fit evidence" in bad[0] and "verdict" in bad[0])

    need = write("need.txt", "J1\nJ2\n")
    _, bad = ps.check_plan(plan_ok, need, RULES)
    check("plan: a needed part without a row fails", bad == ["J2: no source row"])

    plan_shape = write("plan-shape.csv", "key,product_url,fit_evidence,verdict\n"
                       "J1,https://shop-a.example/category/terminals,datasheet,fits\n")
    _, bad = ps.check_plan(plan_shape, None, RULES)
    check("plan: a shop's product shape from instance data is enforced", any("product page" in b for b in bad))
    _, bad = ps.check_plan(plan_shape, None, BUILTIN)
    check("plan: without instance data only the built-ins hold (control)", bad == [])

    # --- order ---
    head = "shop,position,qty,url,availability,read_at\n"
    fresh = (NOW - dt.timedelta(hours=2)).isoformat()
    stale = (NOW - dt.timedelta(hours=30)).isoformat()
    order_ok = write("order-ok.csv", head + f"shop-a,terminal 2-pole,6,https://shop-a.example/p/terminal-2pole-1234,In stock,{fresh}\n")
    _, bad = ps.check_order(order_ok, 24, RULES, NOW)
    check("order: product page, availability read 2 h ago passes", bad == [])

    order_stale = write("order-stale.csv", head + f"shop-a,terminal,6,https://shop-a.example/p/terminal-2pole-1234,In stock,{stale}\n")
    _, bad = ps.check_order(order_stale, 24, RULES, NOW)
    check("order: availability read 30 h ago fails", any("read it again" in b for b in bad))

    order_out = write("order-out.csv", head + f"shop-a,terminal,6,https://shop-a.example/p/terminal-2pole-1234,Currently unavailable · back soon,{fresh}\n")
    _, bad = ps.check_order(order_out, 24, RULES, NOW)
    check("order: 'not available' text fails (non-ASCII read as UTF-8)", any("not available" in b for b in bad))

    order_search = write("order-search.csv", head + f"shop-b,clip,10,https://shop-b.example/s?k=clip,In stock,{fresh}\n")
    _, bad = ps.check_order(order_search, 24, RULES, NOW)
    check("order: a search page as order line fails", any("search page" in b for b in bad))

    order_empty = write("order-empty.csv", head + "shop-a,terminal,6,,,\n")
    _, bad = ps.check_order(order_empty, 24, RULES, NOW)
    check("order: empty url, availability and read_at are each named", len(bad) == 1 and all(k in bad[0] for k in ("url empty", "availability empty", "read_at empty")))

    # --- BOM (a list saved as "CSV UTF-8" by Excel on Windows) ---
    bom = chr(0xFEFF)  # the byte-order mark, written as a code point (content guard: no invisible characters in source)
    plan_bom = write("plan-bom.csv", bom + "key,product_url,fit_evidence,verdict\n"
                     "J1,https://shop-a.example/p/terminal-2pole-1234,datasheet p3 pitch 5.08,fits\n")
    need_bom = write("need-bom.txt", bom + "J1\n")
    _, bad = ps.check_plan(plan_bom, need_bom, RULES)
    check("bom: a plan and a need list with a BOM read their first column", bad == [])
    order_bom = write("order-bom.csv", bom + head + f"shop-a,terminal 2-pole,6,https://shop-a.example/p/terminal-2pole-1234,In stock,{fresh}\n")
    rows, bad = ps.check_order(order_bom, 24, RULES, NOW)
    check("bom: an order list with a BOM keeps its 'shop' column", bad == [] and rows[0].get("shop") == "shop-a")

    # --- rules file and CLI ---
    rf = write("product-sources.json", json.dumps({"unavailable_patterns": ["on request only"]}))
    rules = ps.compile_rules(ps.load_rules(rf))
    order_req = write("order-req.csv", head + f"shop-a,x,1,https://shop-a.example/p/x-1,On request only,{fresh}\n")
    _, bad = ps.check_order(order_req, 24, rules, NOW)
    check("rules file: an instance unavailable pattern extends the built-ins", any("not available" in b for b in bad))
    check("rules file: a missing file is no error", ps.load_rules(str(t / "none.json")) == {})
    check("cli: plan with a failing row exits 1", ps.main(["x", "plan", plan_search, "--rules", rf]) == 1)
    check("cli: plan clean exits 0", ps.main(["x", "plan", plan_ok, "--rules", rf]) == 0)
    check("cli: unknown mode exits 2", ps.main(["x", "buy", plan_ok]) == 2)

    # --- register (operator 2026-11-12: one purchase register, no purchase with a deadline lost) ---
    import contextlib
    import io
    import os

    H = ",".join(ps.REGISTER_COLUMNS) + "\n"
    URL = "https://shop-a.example/p/terminal-2pole-1234"
    d = lambda n: (NOW.date() + dt.timedelta(days=n)).isoformat()  # noqa: E731

    def row(i, status="open", urgency="soon", need="", url=URL, av="In stock", at=fresh, item="terminal"):
        return f"{i},{item},board-x,6,2-pole 5.08,{url},shop-a,{av},{at},3 d,{need},{urgency},{status},,\n"

    reg_ok = write("reg-ok.csv", H + row("P1", need=d(5)) + row("P2", urgency="later", av="", at="")
                   + row("P3", status="ordered", url="", av="", at=""))
    _, bad = ps.check_register(reg_ok, 24, 14, RULES, NOW)
    check("register: open rows with product pages, a fresh read where needed, an ordered row without url pass", bad == [])

    reg_bad = write("reg-bad.csv", H + row("P1", url="https://shop-a.example/search?q=x") + row("P1", need="next week")
                    + row("P2", status="maybe", urgency="asap"))
    _, bad = ps.check_register(reg_bad, 24, 14, RULES, NOW)
    check("register: search page, duplicate id, bad need_by, bad status and urgency each named",
          len(bad) == 3 and "search page" in bad[0] and "duplicate id" in bad[1] and "need_by" in bad[1]
          and "status" in bad[2] and "urgency" in bad[2])

    reg_stale = write("reg-stale.csv", H + row("P1", need=d(3), at=stale) + row("P2", urgency="now", av="", at="")
                      + row("P3", need=d(30), at=stale) + row("P4", need=d(2), av="Sold out"))
    _, bad = ps.check_register(reg_stale, 24, 14, RULES, NOW)
    check("register: needed within 14 d with a stale read, 'now' without a read, sold out fail; 30 d out stays silent",
          len(bad) == 3 and "read it again" in bad[0] and "P2" in bad[1] and "not available" in bad[2])

    reg_head = write("reg-head.csv", "id,item,qty\nP1,x,1\n")
    _, bad = ps.check_register(reg_head, 24, 14, RULES, NOW)
    check("register: a header other than the fixed one fails", len(bad) == 1 and "header" in bad[0])

    reg_due = write("reg-due.csv", H + row("LATE", need=d(-2)) + row("SOON", need=d(4)) + row("FAR", need=d(20))
                    + row("DONE", status="ordered", need=d(-5)) + row("NONE"))
    rows, _ = ps.check_register(reg_due, 24, 14, BUILTIN, NOW)
    check("due: past and within 14 d, soonest first; ordered, far and dateless rows stay out",
          [r["id"] for _, r in ps.due_rows(rows, 14, NOW)] == ["LATE", "SOON"])

    def run(argv):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = ps.main(argv, NOW)
        return rc, buf.getvalue().strip()

    rc, out = run(["x", "register", "brief", "--register", reg_due])
    check("brief: one line, counts and every row due within 7 d or past",
          rc == 0 and len(out.splitlines()) == 1 and "4 open, 1 ordered" in out and "LATE" in out and "2 d late" in out
          and "SOON" in out and "FAR" not in out)
    reg_calm = write("reg-calm.csv", H + row("FAR", need=d(20)) + row("NONE"))
    check("brief: nothing due and a clean check is silent", run(["x", "register", "brief", "--register", reg_calm]) == (0, ""))
    rc, out = run(["x", "register", "brief", "--register", reg_bad])
    check("brief: a failing register check is named even with nothing due", rc == 0 and "3 failing" in out)
    check("brief: a brain without a register is silent", run(["x", "register", "brief", "--register", str(t / "none.csv")]) == (0, ""))
    check("cli: register check red exits 1, clean exits 0",
          run(["x", "register", "check", "--register", reg_bad])[0] == 1 and run(["x", "register", "check", "--register", reg_ok])[0] == 0)
    os.makedirs(t / "brain" / ".claude" / "rules")
    (t / "brain" / ".claude" / "rules" / "purchase-register.json").write_text(json.dumps({"register": "reg.csv"}), encoding="utf-8")
    (t / "brain" / "reg.csv").write_text(H + row("LATE", need=d(-1)), encoding="utf-8")
    old = os.environ.get("CLAUDE_PROJECT_DIR")
    os.environ["CLAUDE_PROJECT_DIR"] = str(t / "brain")
    rc, out = run(["x", "register", "due"])
    if old is None:
        os.environ.pop("CLAUDE_PROJECT_DIR")
    else:
        os.environ["CLAUDE_PROJECT_DIR"] = old
    check("cli: the register path comes from the instance data", rc == 0 and "LATE" in out and "1 due" in out)
    check("cli: unknown register subcommand exits 2", run(["x", "register", "buy"])[0] == 2)

print(f"\n{31 - fails}/31 passed")
sys.exit(1 if fails else 0)
