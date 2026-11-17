#!/usr/bin/env bash
# covers: os-review merge-request-gate post-os-ok
# test-os-ok-form.sh — the structured OS-OK form (`<!-- os-review: os=… verdict=… head=… -->`) is the verdict of its
# text alone: no word of the prose cancels or creates it. Reader (os-review CLI), merge gate and poster, both
# directions, no network.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OSR="$(native "$ROOT/helpers/os-review.cjs")"
KEY="$(node -e 'console.log(require(process.argv[1]).keyFor("mac"))' "$(native "$ROOT/helpers/instance-key-gate.cjs")")"
MARK="<!-- instance-key: $KEY -->"
H=abc1234def5678

review() { # $1 label, $2 text, $3 OS, $4 head, $5 0|1 expected rc
  local rc
  printf '%s' "$2" | node "$OSR" "$3" --head "$4" >/dev/null; rc=$?
  [ "$rc" -eq "$5" ] && ok "$1" || bad "$1 (rc=$rc, want $5)"
}
# The incident shape (2026-10-28): an OK whose evidence names "open", "pending", "0 missing" on the same line.
PROSE="**macOS OK at head \`abc1234\`**: fixture test-open-items.sh passed, 0 missing, nothing pending"
review "prose OK with negation words in its line is lost (the old reader, unchanged)" "$MARK
$PROSE" macOS abc1234 1
review "the same text with the form counts" "$MARK
<!-- os-review: os=macOS verdict=ok head=$H -->
$PROSE" macOS abc1234 0
review "a fail form beats a prose OK" "$MARK
<!-- os-review: os=macOS verdict=fail head=$H -->
**macOS OK at head \`abc1234\`**" macOS abc1234 1
review "an OK form at another head is no OK here" "$MARK
<!-- os-review: os=macOS verdict=ok head=9999999 -->
**macOS OK at head \`abc1234\`**" macOS abc1234 1
review "a macOS form says nothing for Windows" "$MARK
<!-- os-review: os=macOS verdict=ok head=$H -->" Windows abc1234 1
review "fields in another order" "$MARK
<!-- os-review: head=$H verdict=ok os=macos -->" macOS abc1234 0
review "a void form (unknown verdict) leaves the prose reader" "$MARK
<!-- os-review: os=macOS verdict=maybe head=$H -->
**macOS OK at head \`abc1234\`**" macOS abc1234 0
review "the form without the instance key is no hand review" "<!-- os-review: os=macOS verdict=ok head=$H -->" macOS abc1234 1
review "the last form for an OS counts" "$MARK
<!-- os-review: os=macOS verdict=fail head=$H -->
<!-- os-review: os=macOS verdict=ok head=$H -->" macOS abc1234 0

# The merge gate reads the same form (suite seam: required OS from a deps file).
GATE="$(native "$ROOT/helpers/merge-request-gate.cjs")"
mkdir -p "$T/brain/.claude"
printf 'process.stdout.write(require("fs").readFileSync(process.env.PR_JSON, "utf8"))\n' > "$T/gh.js"
printf '{"required_os": ["macOS"]}\n' > "$T/deps.json"
spr() { node -e 'process.stdout.write(JSON.stringify({headRefOid: "abc1234def5678", body: "x", comments: [{body: process.argv[1]}]}))' "$1" > "$T/pr.json"; }
gate() { # $1 label, $2 block|allow
  local rc
  printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":\"gh pr merge 67 -R o/r --merge\"}}" \
    | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac PR_JSON="$(native "$T/pr.json")" \
      MERGE_REQUEST_GATE_GH="$(native "$T/gh.js")" MERGE_REQUEST_GATE_OS=win32 MERGE_REQUEST_GATE_DEPS="$(native "$T/deps.json")" \
      node "$GATE" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 2 ]; then [ "$2" = block ] && ok "$1 blocks" || bad "$1 blocked"
  else [ "$2" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
spr "$MARK
$PROSE"
gate "merge gate: prose OK with a negation word on its line" block
spr "$MARK
<!-- os-review: os=macOS verdict=ok head=$H -->
$PROSE"
gate "merge gate: the same OK with the form" allow
spr "$MARK
<!-- os-review: os=macOS verdict=fail head=$H -->
**macOS OK at head \`abc1234\`**"
gate "merge gate: a fail form beats the prose OK" block

# The poster writes the form the readers accept; no key = nothing posted.
printf 'ran test-os-ok-form.sh: all passed, 0 missing, nothing open\n' > "$T/details.md"
body="$(SHARED_MEMORY_SELF=mac POST_OS_OK_DRY=1 POST_OS_OK_HEAD=$H bash "$ROOT/scripts/post-os-ok.sh" o/r 67 macOS "$T/details.md")"; rc=$?
[ "$rc" -eq 0 ] && ok "poster: dry run prints a body" || bad "poster: dry run rc=$rc"
review "poster: its body is a macOS hand review at the head" "$body" macOS abc1234 0
review "poster: its body is no Windows review" "$body" Windows abc1234 1
SHARED_MEMORY_SELF="" POST_OS_OK_DRY=1 POST_OS_OK_HEAD=$H bash "$ROOT/scripts/post-os-ok.sh" o/r 67 macOS "$T/details.md" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "poster: no instance key, nothing posted" || bad "poster: no key rc=$rc"
POST_OS_OK_DRY=1 POST_OS_OK_HEAD=$H SHARED_MEMORY_SELF=mac bash "$ROOT/scripts/post-os-ok.sh" o/r 67 BeOS "$T/details.md" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "poster: an unknown OS is refused" || bad "poster: unknown OS rc=$rc"
# Windows review 2026-11-17 (finding on #567): a post from inside a script passes the text guards unseen. The poster
# writes the body and prints the post line for the session to run; it never calls gh to post.
outp="$(SHARED_MEMORY_SELF=mac POST_OS_OK_HEAD=$H bash "$ROOT/scripts/post-os-ok.sh" o/r 67 macOS "$T/details.md")"; rc=$?
[ "$rc" -eq 0 ] && [ -s "$T/details.os-ok.md" ] && ok "poster: writes the body next to the details" || bad "poster: no body file rc=$rc"
case "$outp" in *"pr comment 67 -R o/r --body-file "*"details.os-ok.md"*) ok "poster: prints the post line" ;; *) bad "poster: post line missing: $outp" ;; esac
grep -anE '^[^#]*\bgh\s+pr\s+comment\b' "$ROOT/scripts/post-os-ok.sh" | grep -av printf >/dev/null \
  && bad "poster: the script itself still posts" || ok "poster: the script never posts (no gh pr comment call)"
[ $fail -eq 0 ] && echo "os-ok-form: all passed" || echo "os-ok-form: FAILED"
exit $fail
