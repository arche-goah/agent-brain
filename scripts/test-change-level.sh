#!/usr/bin/env bash
# covers: change-level
#
# Fixture for helpers/change-level.cjs — every change declares its level (operator decision
# 2026-10-19). Both directions per rule; a stub that passes everything is the negative
# control for each must-fail case.
#
# Usage: bash scripts/test-change-level.sh   (exit 0 = all fixtures pass)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
CL=""
for c in "$ROOT/core/helpers/change-level.cjs" "$ROOT/helpers/change-level.cjs"; do [ -f "$c" ] && CL="$c"; done
[ -n "$CL" ] || { echo "  --  change-level.cjs not in this layout"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
STUB="$T/stub.cjs"; printf '%s\n' 'process.exit(0)' > "$STUB"

repo() { # $1 dir: a fresh repo layout with an empty changelog.d and a CHANGELOG
  rm -rf "$1"; mkdir -p "$1/changelog.d"
  printf 'how to\n' > "$1/changelog.d/README.md"
  printf '# Changelog\n\n' > "$1/CHANGELOG.md"
}
frag() { printf '%s\n' "$2" > "$R/changelog.d/$1.md"; }
check() { # $1 label, $2 want pass|fail, [$3 expected text in the output]
  local out rc
  out=$(node "$(native "$CL")" check --root "$(native "$R")" 2>&1); rc=$?
  if [ "$2" = pass ]; then [ "$rc" = 0 ] && ok "$1" || bad "$1 (rc=$rc: ${out:0:160})"
  else
    if [ "$rc" = 1 ] && case "$out" in *"${3:-FAIL}"*) true;; *) false;; esac; then ok "$1"; else bad "$1 (rc=$rc: ${out:0:160})"; fi
    node "$(native "$STUB")" check --root "$(native "$R")" >/dev/null 2>&1 || bad "$1: negative control failed"
  fi
}

R="$T/r"
B='- **x.** (test: T0)'
repo "$R"; frag a "$B";                                                                    check "fragment without the field fails, names the four questions" fail "four questions"
repo "$R"; frag a "$B (level: symptom; higher: reader — needs data first; debt: the class)"; check "symptom with a reason passes" pass
repo "$R"; frag a "$B (level: reader; higher: writer — the producer is not ours; debt: heuristic)"; check "reader with a reason passes" pass
repo "$R"; frag a "$B (level: writer; higher: design — one tool would still need the gate; debt: three parsers)"; check "writer (feature) passes" pass
repo "$R"; frag a "$B (level: design; higher: none; debt: none)";                           check "design, nothing above, no debt passes" pass
repo "$R"; frag a "$B (level: design; higher: none; debt: old readers stay until updated)"; check "design may still leave a debt" pass
repo "$R"; frag a "$B (level: reader; higher: writer; debt: x)";                           check "higher without a reason fails" fail "names no reason"
repo "$R"; frag a "$B (level: symptom; higher: none; debt: x)";                            check "higher: none below design fails" fail "only design"
repo "$R"; frag a "$B (level: writer; higher: reader — lower; debt: x)";                    check "higher that is not above fails" fail "not above"
repo "$R"; frag a "$B (level: guess; higher: none; debt: x)";                              check "unknown level word fails" fail "is not one of"
repo "$R"; frag a "$B (level: writer; higher: design — later)";                            check "missing debt fails" fail "debt: is missing"
repo "$R"; frag a "$B (level: writer; higher: design -- ascii dash works; debt: none)";      check "ascii dashes in the reason pass" pass
repo "$R"; frag a "$B (level: writer; higher: design — a (nested) reason; debt: none)";      check "parentheses inside the reason pass" pass
repo "$R"; frag a '- **x.** the form `(level: …; higher: …)` quoted in code is no field';   check "a quoted form in inline code is no field" fail "no (level"
repo "$R"; frag a "$B (level: design; higher: none; debt: none; settles-debt: nowhere)";    check "settles-debt naming nothing fails" fail "names no fragment"
repo "$R"; frag a "$B (level: design; higher: none; debt: none; settles-debt: b)"; frag b "$B (level: writer; higher: design — x; debt: y)"
check "settles-debt naming an open fragment passes" pass
repo "$R"; printf '# Changelog\n\n## 1.0.0 — 2026-01-01\n\n- **old.** (level: writer; higher: design — x; debt: y) <!-- fragment: old-one -->\n' > "$R/CHANGELOG.md"
frag a "$B (level: design; higher: none; debt: none; settles-debt: old-one)";              check "settles-debt naming a released fragment passes" pass
repo "$R"; frag a "$B (level: design; higher: none; debt: none)"; frag b "$B";              check "every fragment of a PR is checked" fail "b.md"
repo "$R";                                                                                  check "only a README passes" pass
rm -rf "$R"; mkdir -p "$R"
out=$(node "$(native "$CL")" check --root "$(native "$R")" 2>&1); rc=$?
[ "$rc" = 0 ] && case "$out" in *"no changelog.d"*) true;; *) false;; esac && ok "a repo without changelog.d passes with a note" || bad "no changelog.d (rc=$rc: $out)"

# --- debts ---
repo "$R"
printf '# Changelog\n\n## 1.1.0 — 2026-01-10\n\n- **settler.** (level: design; higher: none; debt: none; settles-debt: two) <!-- fragment: three -->\n\n## 1.0.0 — 2026-01-01\n\n- **one.** (level: reader; higher: writer — x; debt: debt one) <!-- fragment: one -->\n\n- **two.** (level: writer; higher: design — x; debt: debt two) <!-- fragment: two -->\n\n- **plain.** (test: T0)\n' > "$R/CHANGELOG.md"
frag four "$B (level: writer; higher: design — x; debt: debt four)"
out=$(node "$(native "$CL")" debts --root "$(native "$R")" 2>&1)
case "$out" in *"open level debts: 2"*) ok "debts: two open (one settled, one entry without a field ignored)";; *) bad "debts count: $out";; esac
case "$out" in *"debt one"*"debt four"*) ok "debts: oldest first, released and open fragment both found";; *) bad "debts order: $out";; esac
case "$out" in *"debt two"*) bad "debts: a settled debt is still listed";; *) ok "debts: the settled one is gone";; esac
out=$(node "$(native "$CL")" debts --root "$(native "$R")" --brief 2>&1)
case "$out" in *"older than 14 days"*"one"*) ok "debts --brief: one line for a debt older than 14 days";; *) bad "debts brief: $out";; esac
repo "$R"; frag four "$B (level: writer; higher: design — x; debt: fresh)"
out=$(node "$(native "$CL")" debts --root "$(native "$R")" --brief 2>&1)
[ -z "$out" ] && ok "debts --brief: silent while every debt is young" || bad "debts brief should be silent: $out"
repo "$R"
out=$(node "$(native "$CL")" debts --root "$(native "$R")" 2>&1)
case "$out" in *"no open debt"*) ok "debts: none says so";; *) bad "no debts: $out";; esac

# the repo's own fragments must declare their level (this PR included)
out=$(node "$(native "$CL")" check --root "$(native "$(dirname "$(dirname "$CL")")")" 2>&1) \
  && ok "this repo's fragments declare their level" || bad "this repo: $out"

[ "$fail" -eq 0 ] && echo "change-level: all checks passed" || echo "change-level: FAILURE"
exit "$fail"
