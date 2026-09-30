#!/usr/bin/env bash
# Fixture for scripts/code-scanning-alerts.sh with a fake `gh` on PATH. Both directions:
# open alerts are named with their folder, a clean owner stays silent, a repo without a
# scanner (404) is skipped, and a failed repo listing says NOT checked instead of silence.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/code-scanning-alerts.sh"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1 — $2"; fails=$((fails + 1)); }
has()   { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "missing [$2] in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "unexpected [$2]" ;; *) ok "$1" ;; esac; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
# fake gh: `repo list` prints $FAKE_REPOS (or fails when FAKE_LIST_FAIL=1); `api` answers
# from $T/alerts-<repo> — a missing file is a 404, the way a repo without a scanner answers.
cat > "$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = repo ]; then
  [ "${FAKE_LIST_FAIL:-0}" = 1 ] && exit 1
  printf '%s\n' $FAKE_REPOS; exit 0
fi
if [ "$1" = api ]; then
  repo=$(printf '%s' "$2" | cut -d/ -f3)
  f="$FAKE_DIR/alerts-$repo"
  [ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
  cat "$f"; exit 0
fi
exit 2
EOF
chmod +x "$T/bin/gh"
run() { PATH="$T/bin:$PATH" FAKE_DIR="$T" bash "$S" owner 2>&1; }

echo "open alerts are named, with their folder"
echo "3 skills/vendored" > "$T/alerts-core"
echo "0 " > "$T/alerts-clean"
out="$(FAKE_REPOS="core clean noscanner" run)"
has   "one line with the total" "!! code scanning: 3 open alert(s)" "$out"
has   "repo and folder named" "core 3 (skills/vendored)" "$out"
hasnt "a clean repo is not named" "clean" "$out"
hasnt "a repo without a scanner is skipped" "noscanner" "$out"

echo "negative control: nothing open -> silence"
out="$(FAKE_REPOS="clean noscanner" run)"
[ -z "$out" ] && ok "no output when all is clean" || bad "no output when all is clean" "$out"

echo "listing fails -> says NOT checked, never silence"
out="$(FAKE_LIST_FAIL=1 FAKE_REPOS="core" run)"
has "NOT checked line" "code scanning: NOT checked" "$out"

echo
if [ "$fails" -eq 0 ]; then echo "test-code-scanning-alerts: all checks passed"; exit 0; fi
echo "test-code-scanning-alerts: $fails check(s) FAILED"; exit 1
