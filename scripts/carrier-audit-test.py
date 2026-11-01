#!/usr/bin/env python3
"""Tests for carrier-audit.py on the real cases that made it necessary.

The prose cases are taken from a live feedback protocol (2026-10-25/26, translated): a lesson whose
carrier is "prose, because …", one whose carrier is a ledger line, and one with no carrier line. The
binding cases name what really binds: a wired gate helper, a data file that helper reads, a
mechanism-rules id. Negative controls: a script that only reports must NOT count as binding, a PR
number alone is PENDING, an operator-ok with a quote is an accepted decision. --gate must exit 1 on a
new prose lesson and 0 when everything since the date binds.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "carrier-audit.py")
fails = 0


def check(cond, label):
    global fails
    print(("ok   " if cond else "FAIL ") + label)
    if not cond:
        fails += 1


PROTOCOL = """# Feedback protocol

## 2026-10-26 — An instrument for an unexplained failure runs while the failure can occur

Occasion: the watcher was let lapse; the third exit came without it.
Carrier: Ledger `docs/ma3/open-points.md` id `onpc-exit` (rule) + background log; prose, because no gate knows when a
failure is "unexplained".
Reach: this brain only.

## 2026-10-26 — A desk command that opens a window is a takeover of the device

Carrier: prose, because the rule needs judgement.
Reach: suite.

## 2026-10-19 — Clock times in the operator's local time

Rule: never UTC.

## 2026-10-26 — An announcement is no action: 90 minutes standstill

Carrier: core PR #136 (stoppen-gate) + `.claude/rules/stop-checks.json` STOPP `onReissue: run`.

## 2026-10-16 — Large downloads: ask first, with the network question

Rule: guard rule `download` in the instance mechanism rules.

## 2026-10-25 — A second beta tag on the same day is refused

Carrier: `scripts/release-preflight.sh` checks 6-10.

## 2026-10-24 — Tags only for a delivery

Carrier: core PR #121.

## 2026-10-23 — Shops for shopping lists

Carrier: prose — operator-ok: "a note is enough here, no lock needed" (2026-10-23).

## 2026-10-22 — Network drives: hard stop

Carrier: `helpers/network-drive-gate.cjs`.

## 2026-10-21 — No release without the operator's signature

Carrier: the version in `plugin.json` stays until the operator signs.

## 2026-10-20 — Merge with the rule quoted whole

Carrier: `permissions.allow` carries `Bash(gh pr merge * --match-head-commit *)`.

## 2026-10-20 — Merge only the reviewed head

Carrier: permission rule `--match-head-commit` in the settings.

## 2026-10-28 — A rule written as prose is caught at the write

Carrier: Stop check `scripts/hooks/prose-carrier-gate.cjs`.

## 2026-10-19 — Instance keys end a carrier block

Carrier: prose, because it is clear.
Grounds: the instance's own key, from the instance data.
`.claude/rules/stop-checks.json` named only in the reason.
"""


def build_brain(root):
    os.makedirs(os.path.join(root, ".claude", "rules"))
    os.makedirs(os.path.join(root, "core", "helpers"))
    os.makedirs(os.path.join(root, "core", "hooks"))
    os.makedirs(os.path.join(root, "core", "scripts"))
    os.makedirs(os.path.join(root, "scripts"))
    os.makedirs(os.path.join(root, "docs"))
    with open(os.path.join(root, "docs", "protocol.md"), "w", encoding="utf-8") as f:
        f.write(PROTOCOL)
    with open(os.path.join(root, ".claude", "rules", "lesson-carriers.json"), "w", encoding="utf-8") as f:
        json.dump({"protocol": "docs/protocol.md", "carrier_keys": ["Carrier"], "entry_heading": r"^## (\d{4}-\d{2}-\d{2})",
                   "other_keys": ["Reach", "Grounds"]}, f)
    # a manifest a wired helper reads (the bootup reads plugin.json for the version) is no gate
    with open(os.path.join(root, "core", "plugin.json"), "w", encoding="utf-8") as f:
        f.write('{"version": "1.0.0"}')
    with open(os.path.join(root, ".claude", "settings.json"), "w", encoding="utf-8") as f:
        json.dump({"permissions": {"allow": ["Bash(gh pr merge * --match-head-commit *)"]}}, f)
    # wired: stop-dispatcher (reads stop-checks.json) and mechanism-guard (reads mechanism-rules.json)
    with open(os.path.join(root, "core", "hooks", "hooks.json"), "w", encoding="utf-8") as f:
        json.dump({"hooks": {"Stop": [{"hooks": [{"command": "node \"${CLAUDE_PLUGIN_ROOT}/helpers/stop-dispatcher.cjs\""}]}],
                             "PreToolUse": [{"hooks": [{"command": "node \"${CLAUDE_PLUGIN_ROOT}/helpers/mechanism-guard.cjs\""}]}]}}, f)
    with open(os.path.join(root, "core", "helpers", "stop-dispatcher.cjs"), "w", encoding="utf-8") as f:
        f.write("const p = '.claude/rules/stop-checks.json'; const v = 'plugin.json';\n")
    with open(os.path.join(root, "core", "helpers", "mechanism-guard.cjs"), "w", encoding="utf-8") as f:
        f.write("const p = 'mechanism-rules.json';\n")
    # a Stop check wired ONLY as a row of stop-checks.json (the dispatcher runs it) - 2026-10-28
    os.makedirs(os.path.join(root, "scripts", "hooks"))
    with open(os.path.join(root, "scripts", "hooks", "prose-carrier-gate.cjs"), "w", encoding="utf-8") as f:
        f.write("// a stop check run by the dispatcher\n")
    with open(os.path.join(root, ".claude", "rules", "stop-checks.json"), "w", encoding="utf-8") as f:
        json.dump({"checks": [{"label": "PROSA", "cmd": "scripts/hooks/prose-carrier-gate.cjs", "mode": "block"}]}, f)
    with open(os.path.join(root, ".claude", "rules", "mechanism-rules.json"), "w", encoding="utf-8") as f:
        json.dump({"rules": [{"id": "download", "pattern": "curl"}]}, f)
    # NOT wired: a report script, and a gate helper nobody hooked up
    with open(os.path.join(root, "scripts", "release-preflight.sh"), "w", encoding="utf-8") as f:
        f.write("echo report\n")
    with open(os.path.join(root, "core", "helpers", "network-drive-gate.cjs"), "w", encoding="utf-8") as f:
        f.write("// a gate that exists but is wired nowhere\n")


# The audit also reads the USER settings (~/.claude/settings.json wires gates too). The fixture must not
# see the real machine's: measured 2026-10-26, network-drive-gate.cjs is wired there globally and turned
# the "wired nowhere" case GATE. Every run gets its own empty HOME.
ENV = dict(os.environ)
_home = tempfile.mkdtemp()
ENV["HOME"] = _home
ENV["USERPROFILE"] = _home

with tempfile.TemporaryDirectory() as d:
    build_brain(d)
    out = subprocess.run([sys.executable, SCRIPT, "--repo", d, "--json"], capture_output=True, text=True, encoding="utf-8", env=ENV)
    rows = {r["title"][:30]: r for r in json.loads(out.stdout)["entries"]}

    def cls(prefix):
        for t, r in rows.items():
            if t.startswith(prefix):
                return r["class"]
        return None

    # the real prose cases fly up
    check(cls("An instrument for an unexplain") == "PROSE", "ledger + 'prose, because' carrier is PROSE (real case 2026-10-26)")
    check(cls("A desk command that opens a wi") == "PROSE", "'prose, because' carrier is PROSE (real case 2026-10-26)")
    check(cls("Clock times in the operator's ") == "NONE", "no carrier line and no mechanism in the text is NONE")
    # what binds
    check(cls("An announcement is no action: ") == "GATE", "a data file a wired helper reads is GATE (stop-checks.json)")
    check(cls("Large downloads: ask first, wi") == "GATE", "a mechanism-rules id named in the text is GATE, even without a carrier line")
    # negative controls
    check(cls("A second beta tag on the same ") == "REPORT", "a script that only reports is REPORT, not binding")
    check(cls("Tags only for a delivery") == "PENDING", "a PR number alone is PENDING")
    check(cls("Network drives: hard stop") == "REPORT", "a gate file wired NOWHERE does not bind (REPORT)")
    check(cls("A rule written as prose is ca") == "GATE", "a Stop check wired only as a stop-checks.json row binds (2026-10-28)")
    check(cls("No release without the operato") != "GATE", "a manifest (plugin.json) a wired helper reads is no gate (Windows review)")
    check(cls("Merge with the rule quoted who") == "GATE", "a permission rule quoted whole, spaces included, binds (Windows re-check)")
    check(cls("Merge only the reviewed head") == "GATE", "a permission rule in the settings binds (Windows review)")
    check(cls("Instance keys end a carrier b") == "PROSE", "an instance key from other_keys ends the carrier block")
    check(cls("Shops for shopping lists") == "OPERATOR-OK", "prose with the operator's quoted ok is an accepted decision")

    g_bad = subprocess.run([sys.executable, SCRIPT, "--repo", d, "--gate", "--since", "2026-10-26"], capture_output=True, text=True, encoding="utf-8", env=ENV)
    check(g_bad.returncode == 1, "--gate exits 1 when a lesson since the date is prose")
    with open(os.path.join(d, "docs", "protocol.md"), "w", encoding="utf-8") as f:
        f.write("# p\n\n## 2026-10-27 — Bound one\n\nCarrier: `.claude/rules/stop-checks.json` row X.\n")
    g_ok = subprocess.run([sys.executable, SCRIPT, "--repo", d, "--gate", "--since", "2026-10-27"], capture_output=True, text=True, encoding="utf-8", env=ENV)
    check(g_ok.returncode == 0, "--gate exits 0 when every lesson since the date binds")

# --staged (the pre-commit form): only entries the commit ADDS are judged.
with tempfile.TemporaryDirectory() as d:
    build_brain(d)
    proto = os.path.join(d, "docs", "protocol.md")
    git = lambda *a: subprocess.run(["git", "-C", d, *a], capture_output=True, text=True, encoding="utf-8", env=ENV)
    git("init", "-q"); git("config", "user.email", "t@example.org"); git("config", "user.name", "t")
    git("add", "-A"); git("commit", "-q", "-m", "base with old prose entries")
    staged = lambda: subprocess.run([sys.executable, SCRIPT, "--repo", d, "--staged"], capture_output=True, text=True, encoding="utf-8", env=ENV).returncode

    check(staged() == 0, "--staged: old prose entries already in HEAD never block a commit")
    with open(proto, "a", encoding="utf-8") as f:
        f.write("\n## 2026-10-27 — A new lesson carried by the protocol itself\n\nCarrier: this protocol entry; prose, because it is clear.\n")
    git("add", proto)
    check(staged() == 1, "--staged: a NEW prose lesson blocks the commit")
    git("checkout", "--", "."); git("reset", "-q", "--hard")
    with open(proto, "a", encoding="utf-8") as f:
        f.write("\n## 2026-10-27 — A new lesson with a gate\n\nCarrier: `.claude/rules/mechanism-rules.json` rule `download`.\n")
    git("add", proto)
    check(staged() == 0, "--staged: a NEW lesson naming a wired gate passes")

print(f"carrier-audit-test: {'all passed' if not fails else f'{fails} FAILED'}")
sys.exit(1 if fails else 0)
