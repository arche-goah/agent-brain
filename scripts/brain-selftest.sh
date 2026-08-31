#!/usr/bin/env bash
# Does this brain's own machinery still work — or does it only exist?
#
# WHY (operator, 2026-08-20, translated): problems like this one probably exist far
# more often on the other instance and nobody knows, so basic brain sanity has to be
# assured somehow — otherwise that instance keeps running into inexplicable,
# frustrating trouble. The trigger was self-inflicted: consolidating seven Stop hooks
# one dispatcher silently turned hook-coverage.py into a permanent false alarm, because
# it matches helper FILENAMES in settings.json and cannot know a dispatcher runs them.
# Nobody would have found that by reading; it showed up because one command was run.
#
# The class: a change to one mechanism degrades another, and the degradation is SILENT.
# Presence proves nothing — a wired hook, a shipped helper, a green syntax check all
# look identical whether the thing fires or not.
#
# What this does, in one pass, on any brain:
#   1. every hook wired in settings.json: does its file exist?
#   2. every fixture in scripts/test-*.sh: does it pass?  <- the only effect proof
#   3. core self-checks: hook-coverage (wiring gaps), invariant-check (open classes)
#   4. what has NO fixture at all — reported, never failed
#
# Deliberately: unproven mechanisms are a REPORT, not a failure. A runner that is red
# forever gets ignored, and takes the working checks down with it. Exit 1 means
# something that HAS a proof failed it.
#
# Usage: bash scripts/brain-selftest.sh [brain-root]
set -u
PY="${PYTHON:-python3}"
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
# Same off-by-one as brain-check.sh's ROOT (core/scripts vs bare scripts/) —
# only matters when this runs standalone, without $1; brain-check.sh now passes
# its own resolved ROOT explicitly.
SELFDIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(basename "$(dirname "$SELFDIR")")" = "core" ]; then
  DEFAULT_ROOT="$(cd "$SELFDIR/../.." && pwd)"
else
  DEFAULT_ROOT="$(cd "$SELFDIR/.." && pwd)"
fi
ROOT="${1:-${CLAUDE_PROJECT_DIR:-$DEFAULT_ROOT}}"
cd "$ROOT" || exit 1
fail=0
unproven=0

echo "brain self-test — $ROOT"
echo

# --- 1. wired hooks point at files that exist --------------------------------
echo "hooks wired in settings.json:"
"$PY" - "$ROOT" <<'PY' 2>/dev/null || echo "  (settings unreadable)"
import json, os, re, sys
root = sys.argv[1]
missing = 0
for scope in (".claude/settings.json", ".claude/settings.local.json"):
    p = os.path.join(root, scope)
    if not os.path.exists(p):
        continue
    try:
        cfg = json.load(open(p, encoding="utf-8"))
    except Exception:
        print(f"  !! {scope} is not valid JSON")
        missing += 1
        continue
    for event, groups in (cfg.get("hooks") or {}).items():
        for g in groups:
            for h in g.get("hooks", []):
                cmd = h.get("command", "")
                m = re.search(r'\$CLAUDE_PROJECT_DIR/([^"\s]+)', cmd) or \
                    re.search(r'([\w./-]+\.(?:cjs|sh|py))', cmd)
                if not m:
                    continue
                rel = m.group(1)
                ok = os.path.exists(os.path.join(root, rel))
                print(f"  {'ok ' if ok else '!! '} {event:18} {os.path.basename(rel)}")
                if not ok:
                    missing += 1
sys.exit(1 if missing else 0)
PY
[ $? -ne 0 ] && fail=1
echo

# --- 2. fixtures: the only proof that a mechanism actually fires -------------
echo "fixtures (effect proof):"
shopt -s nullglob
# Fixtures live in BOTH places: a brain carries its own under scripts/, and the
# consumed core ships its suites under core/scripts/. Measured 2026-08-20: run against
# a brain, this found only the brain's own and reported every core mechanism as
# unproven — the suites were right there and never ran.
# Three naming shapes are in use and all three must be discovered: `test-<thing>.sh`,
# `<thing>-test.sh`, and the python suites `<thing>-test.py`. Measured 2026-08-31: the
# python suites ran in CI (linux) only, and they are the ones carrying the path and
# file-writing classes — the classes that behave differently per OS. Registered as OS-4
# in the core's docs/os-traps.md.
for t in scripts/test-*.sh core/scripts/test-*.sh \
         scripts/*-test.sh core/scripts/*-test.sh; do
  name=$(basename "$t" .sh)
  if out=$(bash "$t" 2>&1); then
    echo "  ok  $name"
  else
    echo "  !!  $name FAILED"
    echo "$out" | tail -5 | sed 's/^/        /'
    fail=1
  fi
done
for t in scripts/*-test.py core/scripts/*-test.py; do
  name=$(basename "$t")
  if out=$("$PY" "$t" 2>&1); then
    echo "  ok  $name"
  else
    echo "  !!  $name FAILED"
    echo "$out" | grep -E 'FAIL' | tail -5 | sed 's/^/        /'
    fail=1
  fi
done
shopt -u nullglob
echo

# --- 3. core self-checks -----------------------------------------------------
echo "core checks:"
if [ -f core/scripts/hook-coverage.py ]; then
  hc=$("$PY" core/scripts/hook-coverage.py . 2>&1)
  if [ -z "$hc" ]; then
    echo "  ok  hook-coverage (no wiring gap)"
  else
    # hook-coverage matches helper FILENAMES in settings.json, so a helper that runs
    # via a dispatcher looks missing to it. Resolving that here is not papering over
    # the gap: it is only accepted when the helper is actually REGISTERED in the
    # dispatcher config AND the dispatcher itself is wired. Anything else stays red.
    rest=$("$PY" - "$hc" <<'PY'
import json, os, re, sys
lines = [l for l in sys.argv[1].splitlines() if l.strip()]
try:
    checks = json.load(open(".claude/rules/stop-checks.json", encoding="utf-8"))["checks"]
    registered = {os.path.basename(c["cmd"]) for c in checks}
except Exception:
    registered = set()
try:
    settings = json.load(open(".claude/settings.json", encoding="utf-8"))
    wired = json.dumps(settings.get("hooks", {}))
except Exception:
    wired = ""
dispatcher_wired = "stop-dispatcher" in wired
covered, left = [], []
for line in lines:
    m = re.search(r'([\w.-]+\.(?:cjs|sh|py))', line)
    name = m.group(1) if m else ""
    (covered if (dispatcher_wired and name in registered) else left).append((name, line))
for name, _ in covered:
    print(f"COVERED {name}")
for _, line in left:
    print(f"OPEN {line}")
PY
)
    open_gaps=$(printf '%s' "$rest" | grep -c '^OPEN' || true)
    printf '%s' "$rest" | grep '^COVERED' | sed 's/^COVERED /  ok  hook-coverage: /' \
      | sed 's/$/ runs via the dispatcher (registered in stop-checks.json)/'
    if [ "$open_gaps" -gt 0 ]; then
      echo "  !!  hook-coverage reports $open_gaps real gap(s):"
      printf '%s' "$rest" | grep '^OPEN' | sed 's/^OPEN /        /'
      fail=1
    fi
  fi
fi
if [ -f core/scripts/effect-check.sh ]; then
  # The core's own presence-vs-effect check (output style, statusline, hook targets,
  # memory transport, rule pointers). It is the closest thing to "does this brain do
  # what it claims" and belongs in a self-test rather than in someone's memory.
  if ec=$(bash core/scripts/effect-check.sh 2>&1); then
    echo "  ok  effect-check (presence vs effect)"
  else
    echo "  !!  effect-check reports:"
    printf '%s\n' "$ec" | grep -Ei '(fail|rot|red|!!|missing)' | head -5 | sed 's/^/        /'
    fail=1
  fi
fi
# Deterministic linters that existed WITHOUT a trigger until 2026-08-20 — written into
# rules and checklists, invoked by nothing. That is the same class this whole script is
# about: a promise nobody keeps looks exactly like a working mechanism. They run here
# because they are cheap, deterministic and their findings are actionable; the ones that
# are tools by design stay in .claude/rules/manual-tools.json instead.
for lint in "core/scripts/lint-placeholders.sh:placeholders in skills/rules" \
            "core/scripts/memory-lint.py:memory index, links, limits, snapshot" \
            "scripts/claim-lint.py:claim blocks against the schema" \
            "scripts/hardcode-lint.py:show-network parameters in code"; do
  f="${lint%%:*}"; what="${lint#*:}"
  [ -f "$f" ] || continue
  case "$f" in *.py) runner="$PY";; *) runner="bash";; esac
  if out=$("$runner" "$f" 2>&1); then
    echo "  ok  $(basename "$f") — $what"
  else
    echo "  !!  $(basename "$f") reports findings ($what):"
    printf '%s\n' "$out" | grep -E '^\s*\{|^!!' | head -4 | sed 's/^/        /'
    fail=1
  fi
done
if [ -f core/scripts/invariant-check.py ] && [ -f docs/maintenance/invariants.md ]; then
  ic=$("$PY" core/scripts/invariant-check.py docs/maintenance/invariants.md 2>&1)
  drift=$(printf '%s' "$ic" | grep -c 'NEW site' || true)
  echo "  ok  invariant-check ran ($drift new sites — open classes are normal)"
fi
echo

# --- 4. what has no proof at all --------------------------------------------
# A fixture may cover SEVERAL mechanisms — one file per gate would mean fifteen files
# that all set up the same transcript scaffolding. So a fixture declares its subjects in
# a `# covers:` line, and the filename is only the fallback. Without that declaration,
# grouping a fixture would silently look like deleting one.
echo "mechanisms without a fixture (presence only, not proven):"
covered=$(grep -h '^# covers:' scripts/test-*.sh core/scripts/test-*.sh 2>/dev/null | sed 's/^# covers://')
for f in scripts/hooks/*.cjs scripts/hooks/*.sh core/helpers/*.cjs; do
  [ -e "$f" ] || continue
  base=$(basename "$f"); base=${base%.*}
  if printf '%s' "$covered" | grep -qw -- "$base"; then continue; fi
  # each glob on its own: `ls a b` fails as soon as ONE of them is empty, which would
  # make the second location make the check stricter instead of broader
  if ! ls scripts/test-*"${base}"*.sh >/dev/null 2>&1 \
     && ! ls core/scripts/test-*"${base}"*.sh >/dev/null 2>&1; then
    echo "  ??  $base"
    unproven=$((unproven + 1))
  fi
done
echo

# --- 5. mechanisms nothing calls --------------------------------------------
# The wider half of the same class (operator, 2026-08-20: "das betrifft womoeglich
# irgendwelche ganz anderen kern-funktionen schon immer"). A check that exists but has
# no trigger is a promise nobody keeps — and it is invisible, because the file is
# there, passes every syntax check and reads like a working mechanism. Which of these
# are tools BY DESIGN cannot be derived, so that split is operator data:
# .claude/rules/manual-tools.json.
echo "executables nothing calls (checks without a trigger):"
"$PY" - <<'PY'
import json, os
try:
    manual = set(json.load(open(".claude/rules/manual-tools.json",
                                encoding="utf-8")).get("manual", []))
except Exception:
    manual = set()
targets = []
for d in ("core/scripts", "core/helpers", "scripts", "scripts/hooks"):
    if os.path.isdir(d):
        targets += [os.path.join(d, f) for f in sorted(os.listdir(d))
                    if f.endswith((".sh", ".py", ".cjs", ".js"))]
# A fixture suite is triggered BY CONSTRUCTION: the runners discover it by glob, which
# is exactly why nothing names it any more. Matching on name references alone reported
# six of them as "nothing references it at all" the moment discovery replaced the hand-
# kept lists — the same indirection blind spot hook-coverage had with the dispatcher.
# Three naming shapes are in use; all three are the fixture layer, not a mechanism.
def is_fixture(name):
    return (name.startswith("test-")
            or name.endswith(("-test.sh", "-test.py")))


names = {os.path.basename(t): t for t in targets
         if os.path.basename(t) not in manual and not is_fixture(os.path.basename(t))}

# ONE pass over the setup instead of one grep per file: the per-file version took 18 s,
# and a check that slow gets skipped, which is the same as not having it.
refs = {n: set() for n in names}
for base in (".claude", "core", "scripts", "docs", "config"):
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules", "__pycache__")]
        for fn in filenames:
            p = os.path.join(dirpath, fn)
            if fn.endswith((".png", ".jpg", ".pdf", ".tosc", ".zip")):
                continue
            # A MENTION is not a call. Two traps, both hit while building this: the file
            # that documents a finding names the scripts (this very allowlist did), and
            # a JSON that merely lists a name is not wiring.
            if fn == "manual-tools.json":
                continue
            try:
                text = open(p, encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            for n in names:
                if n in text and os.path.basename(p) != n:
                    refs[n].add(p)

found = 0
for n, t in sorted(names.items(), key=lambda kv: kv[1]):
    kinds = {("wired" if r.endswith("settings.json") or "stop-checks" in r else
              "ci" if r.endswith((".yml", ".yaml")) else
              "called" if r.endswith((".sh", ".py", ".cjs", ".js")) else "doc")
             for r in refs[n]}
    if not refs[n]:
        print(f"  ??  {t} — nothing references it at all")
        found += 1
    elif kinds == {"doc"}:
        print(f"  ??  {t} — mentioned in documentation only, never invoked")
        found += 1
print(f"  ({found} without a trigger; tools meant for hand use are listed in "
      f".claude/rules/manual-tools.json)")
PY
echo
echo "$unproven mechanism(s) without an effect proof — a report, not a failure."
echo "A fixture is two runs: one input that MUST trigger it, one that must stay silent."
[ "$fail" -eq 0 ] && echo "SELF-TEST: everything that has a proof passed it" \
  || echo "SELF-TEST: FAILURE — something with a proof failed it"
exit "$fail"
