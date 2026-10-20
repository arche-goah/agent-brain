#!/usr/bin/env bash
# OS-17 (docs/os-traps.md): every shell file that picks `python3` as its interpreter also probes that it RUNS
# (`"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python`). On Windows `python3` can be the Microsoft Store stub:
# it exists (so `command -v python3` succeeds) but prints "Python was not found" and exits non-zero, so a
# script that only checks existence runs every Python step against the stub - silently, in hooks.
# Rule per file: number of probe lines >= number of python3 choices. Plus a negative control on fixtures.
# Usage: bash scripts/test-python-probe.sh   (exit 0 = no site without a probe)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHOICE='^[[:space:]]*[A-Za-z_]+=["'"'"']?(\$\()?(command -v )?python3'
PROBE="-c ['\"]import sys['\"]"
fail=0

# scan <dir...>: prints "<file>: <choices> choice(s), <probes> probe(s)" for every shell file short of probes
scan() {
  local f n p list
  list="$(grep -rlE "$CHOICE" "$@" 2>/dev/null)"
  [ -n "$list" ] || return 0
  # line by line: a Windows profile path has spaces (OS-10)
  while IFS= read -r f; do
    case "$f" in
      *.sh) ;;
      *.md|*.py|*.cjs|*.js|*.json|*.txt) continue ;;
      *) head -1 "$f" | grep -aqE '^#!.*(ba)?sh' || continue ;;
    esac
    n=$(grep -acE "$CHOICE" "$f")
    p=$(grep -acE -- "$PROBE" "$f")
    [ "$p" -lt "$n" ] && echo "$f: $n choice(s), $p probe(s)"
  done <<< "$list"
  return 0
}

# --- negative control: the scanner must flag a bad file and pass a good one
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
printf '#!/usr/bin/env bash\npy=python3; command -v "$py" >/dev/null 2>&1 || py=python\n' > "$T/bad-hook"
printf '#!/usr/bin/env bash\nPY="$(command -v python3 || command -v python)"\n' > "$T/bad.sh"
printf '#!/usr/bin/env bash\nPY=python3\n"$PY" -c '"'"'import sys'"'"' >/dev/null 2>&1 || PY=python\n' > "$T/good.sh"
printf 'PY=python3 in prose\n' > "$T/notes.md"
got="$(scan "$T")"
case "$got" in *bad-hook*) echo "  OK  control: an extension-less hook without probe is flagged";; *) echo "  FAIL control: bad-hook not flagged"; fail=1;; esac
case "$got" in *bad.sh*) echo "  OK  control: a .sh without probe is flagged";; *) echo "  FAIL control: bad.sh not flagged"; fail=1;; esac
case "$got" in *good.sh*|*notes.md*) echo "  FAIL control: a good file or prose was flagged: $got"; fail=1;; *) echo "  OK  control: probed file and prose pass";; esac

# --- the tree
dirs=()
for d in scripts helpers templates skills; do [ -d "$ROOT/$d" ] && dirs+=("$ROOT/$d"); done
found="$(scan "${dirs[@]}")"
if [ -n "$found" ]; then
  echo "  FAIL python3 picked without a run probe (OS-17):"
  printf '%s\n' "$found" | sed 's/^/       /'
  fail=1
else
  echo "  OK  every python3 choice in scripts/ helpers/ templates/ skills/ has its run probe"
fi

[ "$fail" -eq 0 ] && echo "python-probe: all checks passed" || echo "python-probe: FAILURE"
exit "$fail"
