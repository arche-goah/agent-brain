#!/usr/bin/env bash
# effect-check.sh — does the declared configuration actually DO anything?
#
# WHY: every check the brain had until 2026-08-03 asked "is the file there?". Measured on
# the Windows brain that day: the onboarding verifier reported the caveman output style
# green because SOME caveman.md existed in a plugin cache (the stale 1.0.2 one), and
# session-bootup.sh reported it green because the string stood in settings.json — while
# the style demonstrably never reached a single response. Same class, same day: the
# statusline helper shipped and was never wired, docs/memory-snapshot/ (the channel that
# carries memory between machines) had never been written once, and a core rule pointed
# at a skill file that does not exist in this brain.
#
# A presence check cannot see any of that, because in all four cases the file WAS there —
# just not where the thing that consumes it looks. These five checks compare declaration
# against the consuming side.
#
# Usage:  scripts/effect-check.sh [brain-dir]     # default: $BRAIN_DIR, else $PWD
# Exit 0 = all green, 1 = at least one ROT. INFO never fails the run.

set -u

# Resolve the Python interpreter: the python.org installer on Windows ships ONLY
# `python`, and the Microsoft Store ships a `python3` STUB that resolves in PATH but
# does not run — so probe by RUNNING it, never with `command -v` (measured 2026-08-14:
# a colleague brain had no working `python3`, every reader below returned empty and
# brain-update.sh printed DONE without having done anything).
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python

BRAIN="${1:-${BRAIN_DIR:-$PWD}}"
CORE="$(cd "$(dirname "$0")/.." && pwd)"
PROJ_SET="$BRAIN/.claude/settings.json"
USER_SET="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
fail=0

say() { # $1 = OK|ROT|WARN|INFO, $2 = id, $3 = name, $4 = detail — only ROT fails the run
  printf '%-4s %-3s %s — %s\n' "$1" "$2" "$3" "$4"
  [ "$1" = "ROT" ] && fail=1
  return 0
}

jget() { # $1 = file, $2 = top-level key -> value as string ("" if absent/unparsable)
  [ -f "$1" ] || return 0
  "$PY" -c 'import json,sys
try: d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception: sys.exit(0)
v = d.get(sys.argv[2])
print(v if isinstance(v, str) else ("" if v is None else json.dumps(v)))' "$1" "$2" 2>/dev/null
}

echo "=== EFFECT CHECK $(date '+%F %T') — $BRAIN ==="

# E1 Output-Style: the declared name must resolve somewhere Claude Code actually reads
#    styles from. Two legitimate homes: a local output-styles/ dir, or the cache of an
#    installed plugin — the plugin channel is the designed one (CONVENTIONS §13.2). What
#    stays caught is the stale copy: only the installPath recorded in
#    installed_plugins.json counts, and only when the plugin.json sitting there agrees on
#    the version. An older cache dir left behind from a previous release resolves nothing.
#    Resolvable is not applied. Measured on Windows AND macOS 2026-08-04: a plugin style
#    without `force-for-plugin: true` resolved at the recorded installPath with a matching
#    version — E1 green — and reached no session on either platform. The earlier v1.1.2
#    claim "plugin channel works on macOS without the flag" was itself presence-not-effect
#    (the macOS brain talks caveman because CLAUDE.md describes the rules in prose; the
#    running session's system prompt did not contain the style). Docs agree: the flag is
#    the only documented way a plugin style reaches a session; the outputStyle settings
#    field resolves user/project/managed dirs only. Hence ROT, not WARN — there is no
#    known-legal bare-plugin-style case left.
#    NOT visible to any static check: an untrusted workspace or a session started outside
#    the brain silences project settings wholesale, style present or not.
style=$(jget "$PROJ_SET" outputStyle); [ -n "$style" ] || style=$(jget "$USER_SET" outputStyle)
if [ -z "$style" ]; then
  say INFO E1 "Output-Style" "none declared"
else
  hit=""; hit_file=""
  for d in "$BRAIN/.claude/output-styles" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/output-styles"; do
    [ -f "$d/$style.md" ] && { hit="$d/$style.md"; break; }
    [ -d "$d" ] && hit=$(grep -lE "^name: *$style *$" "$d"/*.md 2>/dev/null | head -1) && [ -n "$hit" ] && break
  done
  if [ -z "$hit" ]; then
    inst="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json"
    while IFS='	' read -r pid ppath pver; do
      [ -n "${pid:-}" ] || continue
      pver=${pver%$'\r'}     # python writes CRLF on Windows; the CR lands in the last field
      ppath=${ppath//\\//}   # installPath is stored in platform notation; test needs '/'
      grep -q "\"$pid\"" "$PROJ_SET" "$USER_SET" 2>/dev/null || continue   # enabled somewhere
      [ -f "$ppath/output-styles/$style.md" ] || continue
      mver=$(jget "$ppath/.claude-plugin/plugin.json" version)
      [ -z "$mver" ] || [ "$mver" = "$pver" ] || continue                  # stale cache dir
      hit_file="$ppath/output-styles/$style.md"
      hit="$hit_file (plugin $pid ${pver:-?})"; break
    done <<EOF
$("$PY" -c 'import json,sys
try: d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception: sys.exit(0)
for pid, entries in (d.get("plugins") or {}).items():
    for e in entries or []:
        print("\t".join([pid, e.get("installPath",""), e.get("version","")]))' "$inst" 2>/dev/null)
EOF
  fi
  if [ -n "$hit" ] && [ -n "${hit_file:-}" ] && ! grep -qE '^force-for-plugin: *true[[:space:]]*$' "$hit_file" 2>/dev/null; then
    say ROT E1 "Output-Style" "'$style' resolvable, but only as a plugin style without 'force-for-plugin: true' — measured on Windows AND macOS 2026-08-04: reaches no response this way ($hit)"
  elif [ -n "$hit" ]; then say OK E1 "Output-Style" "'$style' resolvable: $hit"
  else say ROT E1 "Output-Style" "'$style' declared, but resolves neither in an output-styles/ dir nor in the cache of an installed plugin at the matching version"; fi
fi

# E2 Statusline: wired means a command whose script exists. Not wired at all is WARN,
#    not INFO, since 2026-08-04: the usage statusline is ordered for every brain and the
#    installer travels in core/scripts — a brain that never ran it looked legal for two
#    days (measured on the Windows brain 2026-08-03, one of effect-check's birth defects).
sl=$(jget "$PROJ_SET" statusLine); [ -n "$sl" ] || sl=$(jget "$USER_SET" statusLine)
if [ -z "$sl" ]; then
  if [ -f "$CORE/helpers/statusline.cjs" ]; then
    say WARN E2 "Statusline" "helper sits in core/helpers, but no statusLine in the settings — install: bash core/scripts/install-statusline.sh + restart"
  else
    say INFO E2 "Statusline" "not set up"
  fi
else
  # Quoted form first (the installer quotes the path since 2026-08-04, so a home dir
  # with a space survives) — in the JSON text a quote inside the value appears as \".
  p=$(printf '%s' "$sl" | grep -oE '\\"[^"\\]*statusline[^"\\]*\.(cjs|js|sh)\\"' | head -1 | sed 's/^\\"//;s/\\"$//')
  [ -n "$p" ] || p=$(printf '%s' "$sl" | grep -oE '[^ "]*statusline[^ "]*\.(cjs|js|sh)' | head -1)
  p=${p/\$CLAUDE_PROJECT_DIR/$BRAIN}
  if [ -n "$p" ] && [ ! -f "$p" ]; then say ROT E2 "Statusline" "statusLine points to $p — file missing"
  else say OK E2 "Statusline" "wired up${p:+: $p}"; fi
fi

# E3 Hook targets: a hook whose script is missing fails silently, per event, forever.
missing=""
count=0
for p in $(grep -oE '\$CLAUDE_PROJECT_DIR/[^" \\]+' "$PROJ_SET" 2>/dev/null | sort -u); do
  count=$((count + 1))
  rel=${p#\$CLAUDE_PROJECT_DIR/}
  [ -f "$BRAIN/$rel" ] || missing="$missing $rel"
done
if [ "$count" -eq 0 ]; then say INFO E3 "Hook Targets" "no \$CLAUDE_PROJECT_DIR hooks declared"
elif [ -n "$missing" ]; then say ROT E3 "Hook Targets" "$count declared, missing:$missing"
else say OK E3 "Hook Targets" "$count/$count present"; fi

# E4 Memory transport: the snapshot dir is written by `memory-sync.cjs export`.
#    Absent = export has never completed, so memory has never travelled.
snap="$BRAIN/docs/memory-snapshot"
if [ ! -d "$snap" ]; then
  say ROT E4 "Memory Transport" "$snap missing — memory-sync export has never run"
else
  newest=$(ls -t "$snap"/*.md 2>/dev/null | head -1)
  if [ -z "$newest" ]; then say ROT E4 "Memory Transport" "$snap is empty"
  else
    # `date -r <FILE>` is portable here — verified on both sides 2026-08-08 (PR #27 thread):
    # GNU reads -r as --reference=FILE, macOS accepts a file the same way (mtime == stat -f %m).
    # Do NOT confuse with `date -r <epoch>` (BSD-only, broke in loop-watchdog on GNU).
    age=$(( ( $(date +%s) - $(date -r "$newest" +%s) ) / 86400 ))
    say OK E4 "Memory Transport" "$(ls "$snap"/*.md | wc -l | tr -d ' ') file(s), newest $age day(s) old"
  fi
fi

# E5 Rule pointers: a rule that names a file the brain does not have is an instruction
#    the agent cannot follow. Deliberately narrow, because a noisy check trains people to
#    ignore it: only backticked paths that carry a '/' AND start on a known brain top-level
#    are candidates. A bare `AGENTS.md` or a suite-relative `grandma3/SKILL.md` says nothing
#    about where it lives, and paths a brain documents as "does not exist yet, create on
#    demand" are legitimate. WARN, not ROT — a pointer can be aspirational, a missing hook
#    script cannot.
dangling=""
checked=0
for f in "$BRAIN/CLAUDE.md" "$BRAIN"/.claude/rules/*.md "$CORE"/rules/*.md; do
  [ -f "$f" ] || continue
  for p in $(grep -oE '`[A-Za-z0-9_.@/-]+\.(md|json|sh|cjs|py)`' "$f" 2>/dev/null | tr -d '`' | sort -u); do
    case "$p" in
      docs/*|config/*|scripts/*|src/*|.claude/*|core/*) ;;
      *) continue ;;
    esac
    checked=$((checked + 1))
    [ -e "$BRAIN/$p" ] || [ -e "$CORE/$p" ] || dangling="$dangling $p"
  done
done
dangling=$(printf '%s' "$dangling" | tr ' ' '\n' | sort -u | tr '\n' ' ')
if [ -n "${dangling// /}" ]; then say WARN E5 "Rule Pointers" "$checked checked, resolve nowhere:$dangling"
else say OK E5 "Rule Pointers" "$checked/$checked resolvable"; fi

echo "=== EFFECT: $([ $fail -eq 0 ] && echo "ALL GREEN" || echo "AT LEAST ONE ROT") ==="
exit $fail
