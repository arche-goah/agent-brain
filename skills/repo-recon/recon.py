#!/usr/bin/env python3
"""
repo-recon — rapid orientation report for a large, unfamiliar codebase.

READ-ONLY: this script only reads the target repo and writes a report to
stdout. It never modifies the target. Zero third-party dependencies
(Python 3.8+ stdlib only); runs fully offline. `git` is used opportunistically
via subprocess and degrades gracefully when the target is not a git repo.

Usage:
    python3 recon.py [--path DIR] [--top N] [--json]
"""

import argparse
import json
import os
import subprocess
import sys
from collections import Counter, defaultdict

# Directories that are noise in almost every ecosystem. Skipped during the walk.
NOISE_DIRS = {
    ".git", "node_modules", "venv", ".venv", "dist", "build", "__pycache__",
    "target", ".next", "vendor", ".idea", ".gradle",
}

# Map of file extensions -> human-readable language label. Used for the
# language breakdown. Extensions not listed fall back to the bare extension.
LANG_BY_EXT = {
    ".py": "Python", ".js": "JavaScript", ".jsx": "JavaScript (JSX)",
    ".ts": "TypeScript", ".tsx": "TypeScript (TSX)", ".mjs": "JavaScript (ESM)",
    ".cjs": "JavaScript (CJS)", ".go": "Go", ".rs": "Rust", ".java": "Java",
    ".kt": "Kotlin", ".rb": "Ruby", ".php": "PHP", ".c": "C", ".h": "C/C++ header",
    ".cpp": "C++", ".cc": "C++", ".cxx": "C++", ".hpp": "C++ header",
    ".cs": "C#", ".swift": "Swift", ".m": "Objective-C", ".scala": "Scala",
    ".sh": "Shell", ".bash": "Shell", ".zsh": "Shell", ".pl": "Perl",
    ".lua": "Lua", ".r": "R", ".dart": "Dart", ".ex": "Elixir", ".exs": "Elixir",
    ".clj": "Clojure", ".hs": "Haskell", ".sql": "SQL", ".html": "HTML",
    ".css": "CSS", ".scss": "SCSS", ".sass": "Sass", ".less": "Less",
    ".vue": "Vue", ".svelte": "Svelte", ".json": "JSON", ".yaml": "YAML",
    ".yml": "YAML", ".toml": "TOML", ".xml": "XML", ".md": "Markdown",
    ".rst": "reStructuredText", ".txt": "Text", ".proto": "Protobuf",
    ".tf": "Terraform", ".gradle": "Gradle", ".cmake": "CMake",
}

# Extensions we treat as "source/text" for LOC counting. Binary/asset files are
# counted toward file totals but not toward LOC.
TEXT_EXTS = set(LANG_BY_EXT.keys()) | {
    ".cfg", ".ini", ".conf", ".env", ".gitignore", ".dockerignore", ".lock",
    ".gradle", ".properties", ".gql", ".graphql", ".ipynb",
}

# Files whose mere presence signals a stack / tool. label -> filename(s).
STACK_FILES = {
    "Node.js (package.json)": "package.json",
    "Python (pyproject.toml)": "pyproject.toml",
    "Python (requirements.txt)": "requirements.txt",
    "Python (setup.py)": "setup.py",
    "Go modules (go.mod)": "go.mod",
    "Rust (Cargo.toml)": "Cargo.toml",
    "Maven (pom.xml)": "pom.xml",
    "Gradle (build.gradle)": "build.gradle",
    "Gradle Kotlin (build.gradle.kts)": "build.gradle.kts",
    "Ruby (Gemfile)": "Gemfile",
    "PHP Composer (composer.json)": "composer.json",
    "Docker (Dockerfile)": "Dockerfile",
    "Docker Compose (docker-compose.yml)": "docker-compose.yml",
    "Make (Makefile)": "Makefile",
    "GitLab CI (.gitlab-ci.yml)": ".gitlab-ci.yml",
    "Travis CI (.travis.yml)": ".travis.yml",
    "CircleCI (.circleci/config.yml)": os.path.join(".circleci", "config.yml"),
}

# Candidate entry-point paths (relative to repo root) commonly used as the
# program's start. Globs handled separately for cmd/ and bin/.
ENTRY_CANDIDATES = [
    "main.py", "__main__.py", "app.py", "manage.py", "wsgi.py", "asgi.py",
    "index.js", "index.ts", "server.js", "server.ts",
    "src/main.py", "src/main.js", "src/main.ts", "src/main.go", "src/main.rs",
    "src/index.js", "src/index.ts", "main.go",
]

DOC_PREFIXES = ("readme", "contributing", "changelog", "license", "authors",
                "code_of_conduct", "security", "notice")


def run_git(path, args):
    """Run a git command in `path`; return stdout str or None on any failure."""
    try:
        out = subprocess.run(
            ["git", "-C", path, *args],
            capture_output=True, text=True, timeout=20,
        )
        if out.returncode != 0:
            return None
        return out.stdout
    except (OSError, subprocess.SubprocessError):
        return None


def is_git_repo(path):
    out = run_git(path, ["rev-parse", "--is-inside-work-tree"])
    return out is not None and out.strip() == "true"


def count_lines(filepath):
    """Count lines in a text file. Returns 0 on any read error (binary, perms)."""
    try:
        with open(filepath, "rb") as fh:
            # Read in chunks; bail out if the file looks binary (NUL byte).
            lines = 0
            tail = b""
            chunk = fh.read(65536)
            if b"\x00" in chunk:
                return 0
            while chunk:
                lines += chunk.count(b"\n")
                tail = chunk
                chunk = fh.read(65536)
            # Account for a final line without trailing newline.
            if tail and not tail.endswith(b"\n"):
                lines += 1
            return lines
    except OSError:
        return 0


def walk_repo(path):
    """Walk the repo, skipping noise dirs. Yields (abspath, relpath, size)."""
    for root, dirs, files in os.walk(path):
        # Prune noise dirs in-place so os.walk does not descend into them.
        dirs[:] = [d for d in dirs if d not in NOISE_DIRS]
        for name in files:
            ap = os.path.join(root, name)
            if os.path.islink(ap):
                continue
            try:
                size = os.path.getsize(ap)
            except OSError:
                continue
            rel = os.path.relpath(ap, path)
            yield ap, rel, size


def collect(path, top):
    """Walk once and build every metric the report needs."""
    ext_files = Counter()
    ext_loc = Counter()
    lang_files = Counter()
    lang_loc = Counter()
    total_files = 0
    total_loc = 0
    total_bytes = 0
    # Per top-level dir aggregate stats.
    dir_files = Counter()
    dir_bytes = Counter()
    # Per second-level dir aggregate stats ("a/b").
    subdir_files = Counter()
    subdir_bytes = Counter()
    file_loc = []  # (loc, relpath) for largest-files hotspot
    docs = []
    config_files = []

    for ap, rel, size in walk_repo(path):
        total_files += 1
        total_bytes += size
        ext = os.path.splitext(rel)[1].lower()
        base = os.path.basename(rel)
        if not ext and base.startswith("."):
            ext = base.lower()  # treat dotfiles like .gitignore as their name
        ext_files[ext or "(none)"] += 1

        loc = count_lines(ap) if (ext in TEXT_EXTS or base.startswith(".")) else 0
        if loc:
            ext_loc[ext or "(none)"] += loc
            lang = LANG_BY_EXT.get(ext, ext or "(none)")
            lang_files[lang] += 1
            lang_loc[lang] += loc
            total_loc += loc
            file_loc.append((loc, rel))

        # Directory aggregation by first and second path component.
        parts = rel.split(os.sep)
        if len(parts) == 1:
            top_dir = "(root)"
        else:
            top_dir = parts[0]
        dir_files[top_dir] += 1
        dir_bytes[top_dir] += size
        if len(parts) >= 3:
            sub = parts[0] + os.sep + parts[1]
            subdir_files[sub] += 1
            subdir_bytes[sub] += size

        # Docs and notable config (root-level + docs/ tree).
        low = base.lower()
        if low.startswith(DOC_PREFIXES):
            docs.append(rel)
        if low in (".env.example", ".env.sample", ".env.template"):
            config_files.append(rel)

    file_loc.sort(reverse=True)
    return {
        "total_files": total_files,
        "total_loc": total_loc,
        "total_bytes": total_bytes,
        "ext_files": ext_files,
        "ext_loc": ext_loc,
        "lang_files": lang_files,
        "lang_loc": lang_loc,
        "dir_files": dir_files,
        "dir_bytes": dir_bytes,
        "subdir_files": subdir_files,
        "subdir_bytes": subdir_bytes,
        "largest_files": file_loc[:top],
        "docs": sorted(set(docs)),
        "config_files": sorted(set(config_files)),
    }


def git_summary(path):
    """Return a dict of git facts, or None when not a git repo."""
    if not is_git_repo(path):
        return None
    info = {}
    remote = run_git(path, ["remote", "get-url", "origin"])
    info["remote"] = remote.strip() if remote else None
    branch = run_git(path, ["rev-parse", "--abbrev-ref", "HEAD"])
    info["branch"] = branch.strip() if branch else None
    count = run_git(path, ["rev-list", "--count", "HEAD"])
    info["commit_count"] = count.strip() if count else None
    log = run_git(path, ["log", "-5", "--pretty=format:%h|%an|%ar|%s"])
    commits = []
    if log:
        for line in log.splitlines():
            parts = line.split("|", 3)
            if len(parts) == 4:
                commits.append({
                    "hash": parts[0], "author": parts[1],
                    "when": parts[2], "subject": parts[3],
                })
    info["recent_commits"] = commits
    return info


def git_churn(path, top):
    """Most-churned files over the last 500 commits. Returns list or None."""
    out = run_git(path, ["log", "-n", "500", "--pretty=format:", "--name-only"])
    if out is None:
        return None
    churn = Counter()
    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        # Skip files living in noise dirs.
        if any(part in NOISE_DIRS for part in line.split("/")):
            continue
        churn[line] += 1
    return churn.most_common(top)


def detect_stack(path):
    """Return list of detected stack/tooling labels by presence checks."""
    found = []
    for label, rel in STACK_FILES.items():
        if os.path.exists(os.path.join(path, rel)):
            found.append(label)
    # GitHub Actions: any file under .github/workflows/
    wf = os.path.join(path, ".github", "workflows")
    if os.path.isdir(wf):
        try:
            if any(f.endswith((".yml", ".yaml")) for f in os.listdir(wf)):
                found.append("GitHub Actions (.github/workflows/)")
        except OSError:
            pass
    return found


def safe_load_json(filepath):
    try:
        with open(filepath, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def extract_commands(path):
    """Pull build/test/run commands from package.json, Makefile, pyproject."""
    cmds = defaultdict(list)

    pkg = safe_load_json(os.path.join(path, "package.json"))
    if isinstance(pkg, dict):
        scripts = pkg.get("scripts")
        if isinstance(scripts, dict):
            for name, body in scripts.items():
                cmds["package.json scripts"].append(f"npm run {name}  →  {body}")

    mk = os.path.join(path, "Makefile")
    if os.path.isfile(mk):
        try:
            with open(mk, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    # A Makefile target: "name:" at column 0, not ".PHONY" etc.
                    if line and not line[0].isspace() and ":" in line:
                        target = line.split(":", 1)[0].strip()
                        if target and not target.startswith(".") and " " not in target:
                            cmds["Makefile targets"].append(f"make {target}")
        except OSError:
            pass

    pyproj = os.path.join(path, "pyproject.toml")
    if os.path.isfile(pyproj):
        # Minimal scan for [project.scripts] / console_scripts entries without
        # a TOML parser (tomllib is 3.11+; we target 3.8+).
        try:
            with open(pyproj, encoding="utf-8", errors="replace") as fh:
                in_scripts = False
                for line in fh:
                    s = line.strip()
                    if s.startswith("[") and s.endswith("]"):
                        in_scripts = "scripts" in s and "project" in s
                        continue
                    if in_scripts and "=" in s and not s.startswith("#"):
                        cmds["pyproject scripts"].append(s)
        except OSError:
            pass
    return dict(cmds)


def find_entry_points(path):
    found = []
    for cand in ENTRY_CANDIDATES:
        if os.path.isfile(os.path.join(path, cand)):
            found.append(cand)
    # cmd/* and bin/* directories (Go / CLI convention).
    for d in ("cmd", "bin"):
        dp = os.path.join(path, d)
        if os.path.isdir(dp):
            try:
                for entry in sorted(os.listdir(dp))[:20]:
                    found.append(os.path.join(d, entry))
            except OSError:
                pass
    return found


def count_manifest_deps(path):
    """Cheap dependency counts for a few common manifests."""
    counts = {}
    pkg = safe_load_json(os.path.join(path, "package.json"))
    if isinstance(pkg, dict):
        prod = len(pkg.get("dependencies") or {})
        dev = len(pkg.get("devDependencies") or {})
        counts["package.json"] = f"{prod} prod, {dev} dev"
    req = os.path.join(path, "requirements.txt")
    if os.path.isfile(req):
        try:
            with open(req, encoding="utf-8", errors="replace") as fh:
                n = sum(1 for l in fh
                        if l.strip() and not l.strip().startswith("#"))
            counts["requirements.txt"] = f"{n} packages"
        except OSError:
            pass
    return counts


def find_docs_dir(path):
    return os.path.isdir(os.path.join(path, "docs"))


def human_bytes(n):
    size = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{int(size)} B"
        size /= 1024


def build_report(path, top):
    data = collect(path, top)
    report = {
        "path": os.path.abspath(path),
        "summary": {
            "total_files": data["total_files"],
            "total_loc": data["total_loc"],
            "total_size": human_bytes(data["total_bytes"]),
        },
        "git": git_summary(path),
        "languages_by_files": data["lang_files"].most_common(top),
        "languages_by_loc": data["lang_loc"].most_common(top),
        "language_file_counts": dict(data["lang_files"]),
        "extensions_by_files": data["ext_files"].most_common(top),
        "directory_map_top": [
            (d, data["dir_files"][d], human_bytes(data["dir_bytes"][d]))
            for d, _ in data["dir_files"].most_common()
        ],
        "directory_map_sub": [
            (d, data["subdir_files"][d], human_bytes(data["subdir_bytes"][d]))
            for d, _ in data["subdir_files"].most_common(top)
        ],
        "stack": detect_stack(path),
        "commands": extract_commands(path),
        "entry_points": find_entry_points(path),
        "dependency_manifests": count_manifest_deps(path),
        "largest_files": [(loc, rel) for loc, rel in data["largest_files"]],
        "most_churned": git_churn(path, top),
        "docs": data["docs"],
        "has_docs_dir": find_docs_dir(path),
        "config_files": data["config_files"],
    }
    return report


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def render_markdown(r):
    L = []
    a = L.append
    a(f"# Repo Recon — `{r['path']}`\n")

    s = r["summary"]
    a("## Summary\n")
    a(f"- **Files:** {s['total_files']:,}")
    a(f"- **Lines of code:** {s['total_loc']:,}")
    a(f"- **On-disk size (excl. noise dirs):** {s['total_size']}")
    g = r["git"]
    if g:
        a(f"- **Git remote:** {g.get('remote') or '(none)'}")
        a(f"- **Branch:** {g.get('branch') or '(unknown)'}")
        a(f"- **Total commits:** {g.get('commit_count') or '(unknown)'}")
    else:
        a("- **Git:** not a git repository")
    a("")

    if g and g.get("recent_commits"):
        a("### Last 5 commits\n")
        for c in g["recent_commits"]:
            a(f"- `{c['hash']}` {c['subject']} — {c['author']}, {c['when']}")
        a("")

    a("## Languages (by lines of code)\n")
    a("| Language | Files | LOC |")
    a("|---|--:|--:|")
    files_by_lang = r.get("language_file_counts", {})
    for lang, loc in r["languages_by_loc"]:
        a(f"| {lang} | {files_by_lang.get(lang, '')} | {loc:,} |")
    a("")

    a("## Top extensions (by file count)\n")
    a("| Ext | Files |")
    a("|---|--:|")
    for ext, n in r["extensions_by_files"]:
        a(f"| `{ext}` | {n} |")
    a("")

    a("## Directory map (top level)\n")
    a("| Directory | Files | Size |")
    a("|---|--:|--:|")
    for d, n, sz in r["directory_map_top"]:
        a(f"| `{d}` | {n} | {sz} |")
    a("")
    if r["directory_map_sub"]:
        a("### Second level (top by file count)\n")
        a("| Directory | Files | Size |")
        a("|---|--:|--:|")
        for d, n, sz in r["directory_map_sub"]:
            a(f"| `{d}` | {n} | {sz} |")
        a("")

    a("## Detected stack & tooling\n")
    if r["stack"]:
        for label in r["stack"]:
            a(f"- {label}")
    else:
        a("- (none detected)")
    a("")

    a("## Build / test / run commands\n")
    if r["commands"]:
        for source, items in r["commands"].items():
            a(f"**{source}:**\n")
            for it in items:
                a(f"- `{it}`")
            a("")
    else:
        a("- (none found)\n")

    a("## Entry points\n")
    if r["entry_points"]:
        for e in r["entry_points"]:
            a(f"- `{e}`")
    else:
        a("- (none of the common entry points found)")
    a("")

    a("## Dependency manifests\n")
    if r["dependency_manifests"]:
        for m, c in r["dependency_manifests"].items():
            a(f"- `{m}`: {c}")
    else:
        a("- (none parsed)")
    a("")

    a("## Hotspots — largest source files (by LOC)\n")
    if r["largest_files"]:
        a("| LOC | File |")
        a("|--:|---|")
        for loc, rel in r["largest_files"]:
            a(f"| {loc:,} | `{rel}` |")
    else:
        a("- (no source files counted)")
    a("")

    a("## Hotspots — most-churned files (last 500 commits)\n")
    if r["most_churned"] is None:
        a("- (not a git repo — churn unavailable)")
    elif not r["most_churned"]:
        a("- (no churn data)")
    else:
        a("| Changes | File |")
        a("|--:|---|")
        for rel, n in r["most_churned"]:
            a(f"| {n} | `{rel}` |")
    a("")

    a("## Config & docs\n")
    a(f"- **docs/ directory:** {'present' if r['has_docs_dir'] else 'absent'}")
    if r["docs"]:
        a("- **Doc files:** " + ", ".join(f"`{d}`" for d in r["docs"]))
    if r["config_files"]:
        a("- **Env templates:** " + ", ".join(f"`{c}`" for c in r["config_files"]))
    a("")

    return "\n".join(L)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Read-only orientation report for an unfamiliar repo.")
    p.add_argument("--path", default=".", help="Target repo path (default: .)")
    p.add_argument("--top", type=int, default=15,
                   help="How many items in each top-N list (default: 15)")
    p.add_argument("--json", action="store_true",
                   help="Emit JSON instead of Markdown")
    args = p.parse_args(argv)

    if not os.path.isdir(args.path):
        sys.stderr.write(f"error: not a directory: {args.path}\n")
        return 2

    report = build_report(args.path, args.top)
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render_markdown(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())
