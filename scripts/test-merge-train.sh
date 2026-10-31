#!/usr/bin/env bash
# Fixture for scripts/merge-train.sh: a bare origin with main and three PR branches (two clean, one that
# conflicts with the first), a stub gh that maps PR numbers to branches. Both directions.
# covers: merge-train
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
S="$ROOT/scripts/merge-train.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
g() { git -c user.email=t@t -c user.name=t "$@" >/dev/null 2>&1; }

g init --bare -b main "$T/origin.git"
g clone "$T/origin.git" "$T/seed"
printf 'a\n' > "$T/seed/f.txt"; g -C "$T/seed" add f.txt; g -C "$T/seed" commit -m base; g -C "$T/seed" push origin HEAD:main
g -C "$T/seed" checkout -b feat/one; printf 'one\n' > "$T/seed/one.txt"; g -C "$T/seed" add one.txt; g -C "$T/seed" commit -m one; g -C "$T/seed" push origin feat/one
g -C "$T/seed" checkout main; g -C "$T/seed" checkout -b feat/two; printf 'two\n' > "$T/seed/two.txt"; g -C "$T/seed" add two.txt; g -C "$T/seed" commit -m two; g -C "$T/seed" push origin feat/two
g -C "$T/seed" checkout main; g -C "$T/seed" checkout -b feat/clash; printf 'clash\n' > "$T/seed/one.txt"; g -C "$T/seed" add one.txt; g -C "$T/seed" commit -m clash; g -C "$T/seed" push origin feat/clash
TWO_HEAD="$(git -C "$T/seed" rev-parse feat/two)"

# a working clone whose origin URL looks like github (the script reads owner/repo from it)
g clone "$T/origin.git" "$T/work"
git -C "$T/work" remote set-url origin "https://github.com/o/r.git"
git -C "$T/work" config "url.$(native "$T")/origin.git.insteadOf" "https://github.com/o/r.git"

stub="$T/gh"
cat > "$stub" <<'EOF'
#!/bin/sh
case "$3" in 1) echo feat/one ;; 2) echo feat/two ;; 3) echo feat/clash ;; *) exit 1 ;; esac
EOF
chmod +x "$stub"

out="$(MERGE_TRAIN_GH="$stub" bash "$S" --repo "$T/work" --name train/test 1 2 3 9 2>&1)"; rc=$?
[ $rc -eq 0 ] && ok "a train with at least one PR exits 0" || bad "rc=$rc: $out"
printf '%s' "$out" | grep -aq -- "- #1 feat/one" && ok "PR 1 joins" || bad "PR 1 missing: $out"
printf '%s' "$out" | grep -aq -- "- #2 feat/two $TWO_HEAD" && ok "PR 2 joins with its exact branch head" || bad "PR 2 head missing: $out"
printf '%s' "$out" | grep -aq -- "#3 (conflicts with the train so far)" && ok "a PR conflicting with the train is left out and named" || bad "clash not named: $out"
printf '%s' "$out" | grep -aq -- "#9 (not an open same-repo PR)" && ok "an unknown PR is left out and named" || bad "unknown PR not named: $out"
git -C "$T/work" merge-base --is-ancestor "$TWO_HEAD" train/test && ok "the train holds PR 2's head unchanged (reachable)" || bad "PR 2 head not in the train"
[ -z "$(git -C "$T/work" status --porcelain)" ] && ok "no merge left half-done" || bad "working tree dirty after a left-out PR"
out="$(MERGE_TRAIN_GH="$stub" bash "$S" --repo "$T/work" --name train/none 9 2>&1)"; rc=$?
[ $rc -eq 1 ] && ok "a train no PR could join exits 1 (negative control)" || bad "rc=$rc for an empty train"

[ $fail -eq 0 ] && echo "merge-train: all cases pass" || { echo "merge-train: FAILURE"; exit 1; }
