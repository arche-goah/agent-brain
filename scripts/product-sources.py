#!/usr/bin/env python3
"""A hardware plan and an order list are bound to exact product pages. Exit 1 on any gap, each one named.

Why (measured 2026-11-11 on the macOS instance): a board was planned and ordered while the shop for several of
its parts was still unknown - footprints drawn for parts no listed shop carried; the order list held article
numbers, and 81 order tabs opened from it were mostly shop SEARCH pages. The operator: a plan has to rest on the
exact link it was drawn for, and every order line needs that link and a product that is available. Two
instance tools carried it (an order-tab script, a board's source check); this is the one core tool for both.

  product-sources.py plan  <part-sources.csv> [--need <keys.txt>]
      one row per planned part: key,product_url,fit_evidence,verdict[,mfr_part]
      product_url = the product page of the exact part (no search or result page), fit_evidence = where the drawn
      geometry comes from (datasheet + the dimensions that decide), verdict = fits. --need: one key per line that
      must have a row (a design lists what it places).
  product-sources.py order <order-list.csv> [--max-age-h 24]
      one row per position: shop,position,qty,url,availability,read_at[,choose,page_title]
      url = a product page, availability = the shop's text read on that page, read_at = ISO time of that reading.
  product-sources.py open  <order-list.csv> [--max-age-h 24]
      order check, then the tabs in row order: Safari on macOS, the default browser elsewhere.

Instance data (optional) `.claude/rules/product-sources.json` in the brain (or --rules <file>):
  {"product_shapes": {"<host>": "<regex the product path must match>"}, "search_patterns": [...],
   "unavailable_patterns": [...]} - shapes per shop are instance knowledge; the built-ins hold for every brain.
"""
import csv
import datetime as dt
import json
import os
import re
import subprocess
import sys
import webbrowser

# Built-ins in English; the shops' own languages come from the instance data (search_patterns, unavailable_patterns).
SEARCH = [r"/search", r"/s\?", r"catalogsearch", r"search_dir", r"searchTerm=", r"[?&](?:q|k|exps|query|search|sw)="]
UNAVAILABLE = [r"currently unavailable", r"out of stock", r"sold out", r"not available", r"no longer available"]


def load_rules(path):
    """Instance data; a missing file is no error (the built-ins hold), a broken one is."""
    if not path or not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def compile_rules(data):
    search = re.compile("|".join(SEARCH + list(data.get("search_patterns", []))), re.I)
    unavailable = re.compile("|".join(UNAVAILABLE + list(data.get("unavailable_patterns", []))), re.I)
    shapes = {h: re.compile(s) for h, s in (data.get("product_shapes") or {}).items()}
    return search, unavailable, shapes


def url_problems(url, search, shapes):
    out = []
    if not url.startswith("https://"):
        out.append("url not https")
    if search.search(url):
        out.append("url is a search page, not a product page")
    path = url.split("?")[0]
    for host, shape in shapes.items():
        if host in url and not shape.search(path):
            out.append(f"url does not look like a {host} product page")
    return out


def read_rows(path):
    # utf-8-sig: a list saved as "CSV UTF-8" by Excel starts with a BOM, which would stick to the first header
    with open(path, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def check_plan(path, need_path, rules):
    search, _, shapes = rules
    rows = read_rows(path)
    by_key = {(r.get("key") or "").strip(): r for r in rows}
    bad = []
    for i, r in enumerate(rows, 2):
        key = (r.get("key") or "").strip() or f"line {i}"
        p = []
        url = (r.get("product_url") or "").strip()
        p += url_problems(url, search, shapes) if url else ["product_url empty"]
        if not (r.get("fit_evidence") or "").strip():
            p.append("no fit evidence")
        verdict = (r.get("verdict") or "").strip()
        if verdict != "fits":
            p.append(f"verdict {verdict!r}, not 'fits'")
        if p:
            bad.append(f"{key}: " + "; ".join(p))
    if need_path:
        with open(need_path, encoding="utf-8-sig") as f:
            need = [l.strip() for l in f if l.strip() and not l.startswith("#")]
        bad += [f"{k}: no source row" for k in need if k not in by_key]
    return rows, bad


def check_order(path, max_age_h, rules, now=None):
    search, unavailable, shapes = rules
    now = now or dt.datetime.now(dt.timezone.utc)
    rows = read_rows(path)
    bad = []
    for i, r in enumerate(rows, 2):
        p = [f"{k} empty" for k in ("shop", "position", "qty", "url", "availability", "read_at") if not (r.get(k) or "").strip()]
        url = (r.get("url") or "").strip()
        if url:
            p += url_problems(url, search, shapes)
        if unavailable.search(r.get("availability") or ""):
            p.append("availability says not available")
        ts = (r.get("read_at") or "").strip()
        if ts:
            try:
                t = dt.datetime.fromisoformat(ts.replace("Z", "+00:00"))
                if t.tzinfo is None:
                    t = t.astimezone()
                age = (now - t).total_seconds() / 3600
                if age > max_age_h:
                    p.append(f"availability read {age:.0f} h ago (> {max_age_h:g} h) - read it again")
            except ValueError:
                p.append("read_at not ISO")
        if p:
            bad.append(f"line {i} [{r.get('shop', '?')}] {r.get('position', '?')}: " + "; ".join(p))
    return rows, bad


def open_tabs(urls):
    if sys.platform == "darwin":
        script = ['tell application "Safari"', "make new document", "set w to front window",
                  f'set URL of tab 1 of w to "{urls[0]}"']
        script += [f'tell w to make new tab at end of tabs with properties {{URL:"{u}"}}' for u in urls[1:]]
        script += ["end tell"]
        subprocess.run(["osascript", "-e", "\n".join(script)], check=True)
    else:
        for u in urls:
            webbrowser.open_new_tab(u)
    print(f"opened {len(urls)} tabs")


def main(argv):
    if len(argv) < 3 or argv[1] not in ("plan", "order", "open"):
        print(__doc__)
        return 2
    mode, path = argv[1], argv[2]

    def opt(name, default=None):
        return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default

    brain = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    rules = compile_rules(load_rules(opt("--rules", os.path.join(brain, ".claude", "rules", "product-sources.json"))))
    if mode == "plan":
        rows, bad = check_plan(path, opt("--need"), rules)
    else:
        rows, bad = check_order(path, float(opt("--max-age-h", "24")), rules)
    for b in bad:
        print("FAIL " + b)
    print(f"{len(rows)} rows, {len(bad)} failing")
    if bad:
        return 1
    if mode == "open" and rows:
        open_tabs([r["url"].strip() for r in rows])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
