#!/usr/bin/env python3
"""Content guard — malicious-content classes a text repo can carry. Deterministic,
stdlib, no network. Blocking in CI.

WHY: this repo ships hooks (helpers/) and scripts that run at every session start in
every consuming brain, plus skill and rule text that becomes model instruction. A
virus scanner sees none of that — the repo is text. What a review can miss in text
is exactly what this scans for: an invisible character that changes what a rule
says, a homoglyph that makes two paths look alike, a payload hidden in a base64
blob, a `curl | sh`, a hook that suddenly talks to the network, or a sentence that
tells the model to ignore its operator. The third collaborator joined on 2026-09-12;
from here on a PR is the normal way content arrives.

Classes (each one is a search, not a judgement):

  binary            NUL byte in a tracked file — nothing binary belongs here
  invisible         zero-width / bidi-control / mid-file BOM characters
  mixed-script      one word mixing Latin with Cyrillic or Greek letters (homoglyph)
  injection-marker  text that instructs a model to drop its instructions
  pipe-to-shell     remote content piped straight into a shell
  decode-exec       base64/atob decoded and executed
  dynamic-eval      eval / new Function / vm.runIn* / exec() in code
  network-in-hook   a network call inside helpers/ — hooks run silently and offline
  long-blob         an opaque run of >= 120 base64-ish characters in a text file

Suppression is explicit and visible, never silent: a line carrying
`content-guard-ok: <reason>` is skipped, and scripts/content-guard-allow.txt lists
`<path>:<class>` pairs that are reviewed and accepted (a ratchet — it should only
ever get shorter).

Usage: scripts/content-guard.py [--root DIR] [--json]
Exit 0 = clean, 1 = findings, 2 = usage error.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

SKIP_DIRS = {".git", "node_modules", "__pycache__", ".venv", "venv", ".claude-state"}
# The guard and its fixture carry every pattern by construction — scanning them would
# report the detector as the finding. Nothing else is exempt by name.
SELF = {"scripts/content-guard.py", "scripts/content-guard-test.py"}
CODE_SUFFIX = {".cjs", ".js", ".mjs", ".py", ".sh", ".ps1", ".zsh"}
TEXT_SUFFIX = CODE_SUFFIX | {".md", ".txt", ".json", ".yml", ".yaml", ".toml", ".cfg", ".ini", ".rsc"}
HOOK_DIRS = ("helpers",)
OK_MARKER = "content-guard-ok:"

INVISIBLE = re.compile("[​‌‍‎‏⁠⁡⁢⁣⁤"
                       "‪‫‬‭‮⁦⁧⁨⁩﻿]")
# A word that carries both a Latin letter and a Cyrillic or Greek one. Umlauts and
# accents are Latin-1/Latin Extended and do not trigger this.
MIXED = re.compile(r"\b(?=\w*[A-Za-z])(?=\w*[Ͱ-ϿЀ-ӿ])\w+\b")
INJECTION = re.compile(
    r"ignore\s+(all\s+|any\s+)?(previous|prior|above|earlier)\s+instructions"
    r"|disregard\s+(all\s+|your\s+)?(previous\s+|prior\s+)?(instructions|rules|guidelines)"
    r"|<\|im_start\|>|<\|im_end\|>|<\|system\|>"
    r"|do\s+not\s+(tell|inform|reveal\s+(this\s+)?to)\s+the\s+(user|operator|human)"
    r"|override\s+(your|all)\s+(system|safety)\s+(prompt|rules|instructions)",
    re.I)
PIPE_TO_SHELL = re.compile(r"\b(curl|wget)\b[^|\n]*\|\s*(sudo\s+)?(ba|z|da)?sh\b")
DECODE_EXEC = re.compile(
    r"base64\s+(-d|--decode)\b[^|\n]*\|\s*(sudo\s+)?(ba|z|da)?sh\b"
    r"|base64\s+(-d|--decode)\b[^|\n]*\|\s*(python3?|node|perl)\b"
    r"|\beval\s*\([^)]*\b(b64decode|atob|fromCharCode)\b"
    r"|\bexec\s*\([^)]*\bb64decode\b")
# `\beval\(` would also match Playwright's `page.$eval` / `$$eval` (DOM selectors, not
# code evaluation) — the lookbehind excludes a `$` or `.` right before the name.
DYNAMIC_EVAL = re.compile(r"(?<![\w.$])eval\s*\(|\bnew\s+Function\s*\(|\bvm\.runIn\w*\s*\(|(?<![\w.])exec\s*\(")
NETWORK = re.compile(
    r"\bcurl\b|\bwget\b|\bfetch\s*\(|\bhttps?\.(request|get)\s*\("
    r"|require\(\s*['\"]https?['\"]\s*\)|\burllib\.request\b|\bsocket\.(create_connection|socket)\b"
    r"|\bnet\.(connect|createConnection)\s*\(")
LONG_BLOB = re.compile(r"[A-Za-z0-9+/]{120,}={0,2}")
# Comment leads of the CODE languages only (this is applied to code files). HTML comment
# markers do not belong here: CodeQL reads any `<!--`/`-->` regex as an HTML filter
# (py/bad-tag-filter), and no code file in this repo carries HTML comments.
COMMENT_LEAD = re.compile(r"^\s*(#|//|\*|/\*)")


def load_allow(root: Path) -> set[tuple[str, str]]:
    f = root / "scripts" / "content-guard-allow.txt"
    out: set[tuple[str, str]] = set()
    if not f.is_file():
        return out
    for line in f.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path, _, cls = line.rpartition(":")
        if path and cls:
            out.add((path.replace("\\", "/"), cls))
    return out


def walk(root: Path):
    for p in sorted(root.rglob("*")):
        if any(part in SKIP_DIRS for part in p.relative_to(root).parts):
            continue
        if p.is_file():
            yield p


def scan_file(root: Path, p: Path, allow: set[tuple[str, str]]) -> list[dict]:
    rel = p.relative_to(root).as_posix()
    findings: list[dict] = []
    if rel in SELF:
        return findings

    def hit(cls: str, line: int, excerpt: str):
        if (rel, cls) in allow:
            return
        findings.append({"class": cls, "path": rel, "line": line, "excerpt": excerpt.strip()[:120]})

    raw = p.read_bytes()
    if b"\x00" in raw[:8192]:
        hit("binary", 0, f"{len(raw)} bytes, NUL byte present")
        return findings
    if p.suffix.lower() not in TEXT_SUFFIX and p.name not in ("CODEOWNERS", "LICENSE", "NOTICE"):
        return findings
    text = raw.decode("utf-8", errors="replace")
    is_code = p.suffix.lower() in CODE_SUFFIX
    in_hook = rel.split("/", 1)[0] in HOOK_DIRS

    for n, line in enumerate(text.splitlines(), 1):
        if OK_MARKER in line:
            continue
        # A BOM is only legitimate as the very first character of the file.
        probe = line[1:] if (n == 1 and line.startswith("﻿")) else line
        if INVISIBLE.search(probe):
            hit("invisible", n, repr(probe))
        if MIXED.search(line):
            hit("mixed-script", n, line)
        if INJECTION.search(line):
            hit("injection-marker", n, line)
        if PIPE_TO_SHELL.search(line):
            hit("pipe-to-shell", n, line)
        if DECODE_EXEC.search(line):
            hit("decode-exec", n, line)
        if LONG_BLOB.search(line):
            hit("long-blob", n, line)
        if is_code and not COMMENT_LEAD.match(line):
            if DYNAMIC_EVAL.search(line):
                hit("dynamic-eval", n, line)
            # A regex LITERAL that names curl (a guard describing what it blocks) is
            # not a call: `/\bcurl\b.../` — skip lines whose network word sits inside
            # a JS regex literal.
            if in_hook and NETWORK.search(line) and not re.search(r"/[^/\n]*\\b(curl|wget)\\b[^/\n]*/", line):
                hit("network-in-hook", n, line)
    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    root = Path(a.root).resolve()
    if not root.is_dir():
        print(f"content-guard: not a directory: {root}", file=sys.stderr)
        return 2
    allow = load_allow(root)
    findings: list[dict] = []
    files = 0
    for p in walk(root):
        files += 1
        findings.extend(scan_file(root, p, allow))
    if a.json:
        print(json.dumps({"files": files, "findings": findings}, indent=1))
    else:
        for f in findings:
            print(f"  {f['class']:<17} {f['path']}:{f['line']}: {f['excerpt']}")
        print(f"content-guard: {files} file(s), {len(findings)} finding(s)"
              + (f", {len(allow)} allow-listed" if allow else ""))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
