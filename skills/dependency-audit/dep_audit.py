#!/usr/bin/env python3
"""
dependency-audit — offline, cross-ecosystem dependency inventory.

READ-ONLY: parses manifest/lock files in the target repo and prints an
inventory to stdout. It NEVER modifies the target and NEVER reaches the
network. It does NOT invent CVEs, "outdated" claims, or vulnerability data —
it reports only what the manifests literally say, plus simple structural
heuristics (pinned vs unpinned, dev vs prod, duplicates). For real
vulnerability/outdated data, run the online scanners listed in SKILL.md.

Zero third-party dependencies (Python 3.8+ stdlib only).

Usage:
    python3 dep_audit.py [--path DIR] [--json]
"""

import argparse
import json
import os
import re
import sys
from collections import defaultdict

NOISE_DIRS = {
    ".git", "node_modules", "venv", ".venv", "dist", "build", "__pycache__",
    "target", ".next", "vendor", ".idea", ".gradle",
}


def safe_json(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def safe_lines(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read().splitlines()
    except OSError:
        return []


def is_pinned_npm(spec):
    """A version is 'pinned' if it's an exact version with no range operators."""
    if not isinstance(spec, str):
        return False
    spec = spec.strip()
    if not spec or spec in ("*", "latest"):
        return False
    if spec[0] in "^~><=" or " " in spec or "x" in spec.lower():
        return False
    if spec.startswith(("git", "http", "file:", "link:", "workspace:")):
        return False  # non-version refs; treated as unpinned for the count
    return bool(re.match(r"^\d", spec))


def add(deps, name, version, ecosystem, dev, pinned):
    deps.append({
        "name": name,
        "version": version,
        "ecosystem": ecosystem,
        "scope": "dev" if dev else "prod",
        "pinned": bool(pinned),
    })


# ---------------------------------------------------------------------------
# Ecosystem parsers — each returns a list of dependency dicts.
# ---------------------------------------------------------------------------

def parse_package_json(path, deps):
    data = safe_json(path)
    if not isinstance(data, dict):
        return
    for field, dev in (("dependencies", False),
                        ("devDependencies", True),
                        ("optionalDependencies", False),
                        ("peerDependencies", False)):
        block = data.get(field)
        if isinstance(block, dict):
            for name, spec in block.items():
                add(deps, name, spec, "npm", dev, is_pinned_npm(spec))


def parse_requirements_txt(path, deps):
    for raw in safe_lines(path):
        line = raw.strip()
        if not line or line.startswith("#") or line.startswith("-"):
            continue  # skip comments and pip flags (-r, -e, --hash, etc.)
        # Strip inline comments and environment markers.
        line = line.split(";", 1)[0].split(" #", 1)[0].strip()
        m = re.match(r"^([A-Za-z0-9._-]+)\s*(==|>=|<=|~=|!=|>|<|===)?\s*(.+)?$",
                     line)
        if not m:
            continue
        name, op, ver = m.group(1), m.group(2), (m.group(3) or "").strip()
        pinned = op in ("==", "===")
        add(deps, name, (op or "") + ver if op else "", "pip", False, pinned)


def parse_pyproject(path, deps):
    """Minimal pyproject scan (no TOML parser; tomllib is 3.11+)."""
    section = None
    for raw in safe_lines(path):
        s = raw.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s.strip("[]")
            continue
        if not s or s.startswith("#"):
            continue
        # PEP 621 style: dependencies = ["foo>=1.0", ...] (often multi-line)
        if section == "project" and ("dependencies" in s or s.startswith('"')):
            for dep in re.findall(r'"([^"]+)"', s):
                m = re.match(r"^([A-Za-z0-9._-]+)\s*(==|>=|<=|~=|!=|>|<)?\s*(.*)$",
                             dep)
                if m and m.group(1):
                    pinned = m.group(2) == "=="
                    ver = (m.group(2) or "") + (m.group(3) or "")
                    add(deps, m.group(1), ver, "pip", False, pinned)
        # Poetry style: name = "^1.2" under [tool.poetry.dependencies]
        if section and "poetry" in section and "dependencies" in section:
            m = re.match(r'^([A-Za-z0-9._-]+)\s*=\s*"?([^"]+)"?', s)
            if m and m.group(1).lower() != "python":
                spec = m.group(2)
                pinned = bool(re.match(r"^\d", spec)) and "^" not in spec and "~" not in spec
                add(deps, m.group(1), spec, "pip", "dev" in section, pinned)


def parse_poetry_lock(path, deps):
    name = version = None
    for raw in safe_lines(path):
        s = raw.strip()
        if s == "[[package]]":
            name = version = None
        elif s.startswith("name ="):
            name = s.split("=", 1)[1].strip().strip('"')
        elif s.startswith("version ="):
            version = s.split("=", 1)[1].strip().strip('"')
            if name and version:
                add(deps, name, version, "pip (poetry.lock)", False, True)
                name = version = None


def parse_go_mod(path, deps):
    in_block = False
    for raw in safe_lines(path):
        s = raw.strip()
        if s.startswith("require ("):
            in_block = True
            continue
        if in_block and s == ")":
            in_block = False
            continue
        if s.startswith("require ") and "(" not in s:
            s = s[len("require "):].strip()
        elif not in_block:
            continue
        if not s or s.startswith("//"):
            continue
        parts = s.split()
        if len(parts) >= 2:
            dev = "// indirect" in raw
            add(deps, parts[0], parts[1], "go", dev, True)


def parse_cargo_toml(path, deps):
    section = None
    for raw in safe_lines(path):
        s = raw.strip()
        if s.startswith("[") and s.endswith("]"):
            section = s.strip("[]")
            continue
        if not s or s.startswith("#") or "dependencies" not in (section or ""):
            continue
        dev = "dev-dependencies" in (section or "")
        m = re.match(r'^([A-Za-z0-9._-]+)\s*=\s*(.+)$', s)
        if not m:
            continue
        name, rhs = m.group(1), m.group(2).strip()
        if rhs.startswith("{"):
            vm = re.search(r'version\s*=\s*"([^"]+)"', rhs)
            version = vm.group(1) if vm else "(table)"
        else:
            version = rhs.strip('"')
        pinned = bool(re.match(r"^=?\d", version)) and "*" not in version
        add(deps, name, version, "cargo", dev, pinned)


def parse_cargo_lock(path, deps):
    name = version = None
    for raw in safe_lines(path):
        s = raw.strip()
        if s == "[[package]]":
            name = version = None
        elif s.startswith("name ="):
            name = s.split("=", 1)[1].strip().strip('"')
        elif s.startswith("version ="):
            version = s.split("=", 1)[1].strip().strip('"')
            if name and version:
                add(deps, name, version, "cargo (Cargo.lock)", False, True)
                name = version = None


def parse_gemfile_lock(path, deps):
    in_specs = False
    for raw in safe_lines(path):
        if raw.strip() == "specs:":
            in_specs = True
            continue
        if in_specs:
            # Direct gem lines are indented 4 spaces: "    name (1.2.3)"
            m = re.match(r"^ {4}([A-Za-z0-9._-]+) \(([^)]+)\)\s*$", raw)
            if m:
                add(deps, m.group(1), m.group(2), "bundler", False, True)
            elif raw and not raw[0].isspace():
                in_specs = False


def parse_composer_json(path, deps):
    data = safe_json(path)
    if not isinstance(data, dict):
        return
    for field, dev in (("require", False), ("require-dev", True)):
        block = data.get(field)
        if isinstance(block, dict):
            for name, spec in block.items():
                if name.lower() in ("php",) or name.startswith("ext-"):
                    continue
                pinned = bool(re.match(r"^\d", str(spec))) and \
                    not any(c in str(spec) for c in "^~*><| ")
                add(deps, name, spec, "composer", dev, pinned)


def parse_package_lock(path, deps):
    """Count resolved packages in package-lock.json (v2/v3 'packages' or v1)."""
    data = safe_json(path)
    if not isinstance(data, dict):
        return
    pkgs = data.get("packages")
    if isinstance(pkgs, dict):
        for key, meta in pkgs.items():
            if not key or key == "":
                continue  # root project entry
            name = key.split("node_modules/")[-1]
            ver = meta.get("version", "") if isinstance(meta, dict) else ""
            dev = bool(meta.get("dev")) if isinstance(meta, dict) else False
            add(deps, name, ver, "npm (lockfile)", dev, True)
    else:
        legacy = data.get("dependencies")
        if isinstance(legacy, dict):
            for name, meta in legacy.items():
                ver = meta.get("version", "") if isinstance(meta, dict) else ""
                add(deps, name, ver, "npm (lockfile)", False, True)


# Manifest filename -> parser. We look for these at any depth (minus noise).
PARSERS = {
    "package.json": parse_package_json,
    "package-lock.json": parse_package_lock,
    "requirements.txt": parse_requirements_txt,
    "pyproject.toml": parse_pyproject,
    "poetry.lock": parse_poetry_lock,
    "go.mod": parse_go_mod,
    "Cargo.toml": parse_cargo_toml,
    "Cargo.lock": parse_cargo_lock,
    "Gemfile.lock": parse_gemfile_lock,
    "composer.json": parse_composer_json,
}


def find_manifests(root):
    """Return {abspath: filename} for every recognized manifest, minus noise."""
    found = {}
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in NOISE_DIRS]
        for f in files:
            if f in PARSERS:
                found[os.path.join(dirpath, f)] = f
    return found


def build_inventory(root):
    manifests = find_manifests(root)
    deps = []
    # Lockfiles are the source of truth; if a lockfile exists for an ecosystem,
    # we still parse both but flag the manifest set found.
    parsed_files = []
    for ap, fname in sorted(manifests.items()):
        before = len(deps)
        PARSERS[fname](ap, deps)
        parsed_files.append({
            "file": os.path.relpath(ap, root),
            "count": len(deps) - before,
        })

    # Heuristic findings.
    unpinned = [d for d in deps if not d["pinned"] and d["scope"] == "prod"]

    by_name = defaultdict(set)
    for d in deps:
        by_name[d["name"]].add(d["ecosystem"].split(" ")[0])
    cross_ecosystem = {n: sorted(e) for n, e in by_name.items() if len(e) > 1}

    eco_counts = defaultdict(lambda: {"prod": 0, "dev": 0})
    for d in deps:
        eco = d["ecosystem"]
        eco_counts[eco][d["scope"]] += 1

    return {
        "root": os.path.abspath(root),
        "manifests": parsed_files,
        "total": len(deps),
        "prod": sum(1 for d in deps if d["scope"] == "prod"),
        "dev": sum(1 for d in deps if d["scope"] == "dev"),
        "pinned": sum(1 for d in deps if d["pinned"]),
        "unpinned": sum(1 for d in deps if not d["pinned"]),
        "by_ecosystem": {k: v for k, v in sorted(eco_counts.items())},
        "unpinned_prod": sorted(
            {(d["name"], d["version"], d["ecosystem"]) for d in unpinned}),
        "cross_ecosystem": cross_ecosystem,
        "dependencies": deps,
    }


SCANNER_TABLE = """\
## Run these online for real vulnerability / outdated data

This script does OFFLINE INVENTORY ONLY — it does not know which versions are
vulnerable or outdated. When you have network access, run the ecosystem's own
scanner:

| Ecosystem | Vulnerabilities | Outdated |
|-----------|-----------------|----------|
| npm       | `npm audit`     | `npm outdated` |
| pip       | `pip-audit`     | `pip list --outdated` |
| go        | `govulncheck ./...` | `go list -m -u all` |
| cargo     | `cargo audit`   | `cargo outdated` |
| any       | `osv-scanner --recursive .` | — |
"""


def render_markdown(inv):
    L = []
    a = L.append
    a(f"# Dependency Audit — `{inv['root']}`\n")
    if not inv["manifests"]:
        a("No recognized dependency manifests found.\n")
        a(SCANNER_TABLE)
        return "\n".join(L)

    a("## Manifests parsed\n")
    a("| File | Entries |")
    a("|---|--:|")
    for m in inv["manifests"]:
        a(f"| `{m['file']}` | {m['count']} |")
    a("")

    a("## Totals\n")
    a(f"- **Total entries:** {inv['total']}")
    a(f"- **Prod:** {inv['prod']}  |  **Dev:** {inv['dev']}")
    a(f"- **Pinned:** {inv['pinned']}  |  **Unpinned/floating:** {inv['unpinned']}")
    a("")

    a("## By ecosystem\n")
    a("| Ecosystem | Prod | Dev |")
    a("|---|--:|--:|")
    for eco, c in inv["by_ecosystem"].items():
        a(f"| {eco} | {c['prod']} | {c['dev']} |")
    a("")

    a("## Unpinned / floating production dependencies\n")
    if inv["unpinned_prod"]:
        a("These resolve to whatever is newest at install time — a supply-chain "
          "and reproducibility risk. Consider pinning or committing a lockfile.\n")
        a("| Name | Spec | Ecosystem |")
        a("|---|---|---|")
        for name, ver, eco in inv["unpinned_prod"]:
            a(f"| {name} | `{ver or '(any)'}` | {eco} |")
    else:
        a("- None — all production dependencies are pinned.")
    a("")

    a("## Names appearing in multiple ecosystems\n")
    if inv["cross_ecosystem"]:
        for name, ecos in sorted(inv["cross_ecosystem"].items()):
            a(f"- `{name}` — {', '.join(ecos)}")
    else:
        a("- None.")
    a("")

    a(SCANNER_TABLE)
    return "\n".join(L)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Offline cross-ecosystem dependency inventory (read-only).")
    p.add_argument("--path", default=".", help="Target repo path (default: .)")
    p.add_argument("--json", action="store_true", help="Emit JSON")
    args = p.parse_args(argv)

    if not os.path.isdir(args.path):
        sys.stderr.write(f"error: not a directory: {args.path}\n")
        return 2

    inv = build_inventory(args.path)
    if args.json:
        print(json.dumps(inv, indent=2))
    else:
        print(render_markdown(inv))
    return 0


if __name__ == "__main__":
    sys.exit(main())
