#!/usr/bin/env bash
# covers: pr-ball session-bootup
# test-pr-ball.sh — the bootup line "PR waiting on you" must fire for a move that is really
# the viewer's and stay silent for everything else. Synthetic GraphQL JSON, fixed clock,
# no network.
#
# WHY (2026-09-15): a changes-requested review on a collaborator's core PR sat two days
# without a reply. Both sides' session starts named the open PRs and the new shared-memory
# commits — newness, not obligation — so each side believed it was waiting on the other.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BALL="$ROOT/scripts/pr-ball.py"
PY=python3
"$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
[ -f "$BALL" ] || { bad "pr-ball.py not found"; exit 1; }
# Every case reads an empty throwaway shared memory, never this machine's real clone.
# OS-3: python is native, so the path it reads is handed over in native form.
SM="$(mktemp -d)"; trap 'rm -rf "$SM"' EXIT
export SHARED_MEMORY_REPO; SHARED_MEMORY_REPO="$(command -v cygpath >/dev/null 2>&1 && cygpath -m "$SM" || printf %s "$SM")"

NOW="2026-09-15T08:00:00Z"   # 40 h after 2026-09-13T16:00Z
run() { printf '%s' "$2" | "$PY" "$BALL" --now "$NOW"; }
expect_line() { # $1 label, $2 json, $3 substring that must appear
  out="$(run "$1" "$2")"
  case "$out" in *"$3"*) ok "$1" ;; *) bad "$1 — got: ${out:-<silence>}" ;; esac
}
expect_silent() { # $1 label, $2 json
  out="$(run "$1" "$2")"
  [ -z "$out" ] && ok "$1" || bad "$1 — expected silence, got: $out"
}
pr() { # $1 viewer, $2 one PR node
  printf '{"data":{"viewer":{"login":"%s"},"search":{"nodes":[%s]}}}' "$1" "$2"
}

# 1. the measured case, from the author's side: changes requested after the last commit
expect_line "author: changes requested after the last commit, 40 h" \
  "$(pr author '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"Author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#143 yours - changes requested, 40 h"

# 2. the author answered with a commit: the move went back, silence
expect_silent "author: a commit after the review hands the move back" \
  "$(pr author '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T17:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 3. the reviewer's side: new commits after my last review
expect_line "reviewer: new commits after my review, 40 h" \
  "$(pr maint '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T10:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#143 review - new commits since your last look"

# 4. asked by @-mention in the body (the only channel before write access), case-insensitive
expect_line "reviewer: @-mentioned in the body, never looked" \
  "$(pr Reviewer '{"number":145,"isDraft":false,"body":"review/OK please @REVIEWER","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#145 review - asked, not looked at yet"

# 5. a comment by me after the last commit counts as a look
expect_silent "reviewer: my comment after the last commit is a look" \
  "$(pr reviewer '{"number":145,"isDraft":false,"body":"@reviewer","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"reviewer"},"createdAt":"2026-09-13T18:00:00Z"}]},"reviewRequests":{"nodes":[]}}')"

# 6. not involved at all: someone else's PR in a suite they lead — not my move
expect_silent "bystander: foreign PR without review, request or mention" \
  "$(pr maint '{"number":112,"isDraft":false,"body":"fix","repository":{"name":"suite"},"author":{"login":"lead"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-09T12:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 7. a formal review request is an ask too, without any mention in the body
expect_line "reviewer: a formal review request fires without a mention" \
  "$(pr reviewer '{"number":7,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[{"requestedReviewer":{"login":"reviewer"}}]}}')" \
  "core#7 review - asked"

# 8. under 24 h: a fresh move is NAMED (2026-09-22: a 4 h old "OK for merge" went unseen
#    behind the old 24 h floor), only without the stall marker
out="$(run fresh "$(pr author '{"number":9,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-15T05:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-15T06:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')")"
case "$out" in
  "PR waiting on you: core#9 yours - changes requested, 2 h") ok "fresh: a 2 h move is named, without !!" ;;
  *) bad "fresh: expected the move without !!, got: ${out:-<silence>}" ;;
esac

# 8b. the stall marker is there once a move is 24 h old
expect_line "stall: a 40 h move carries !!" \
  "$(pr author '{"number":143,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "!! PR waiting on you:"

# 13. the measured case 2026-09-22: my PR, a collaborator COMMENTS "OK for merge" after my
#     last commit (no formal review — the ruleset leaves them none) — the move is mine
expect_line "author: a comment by someone else after my last commit" \
  "$(pr author '{"number":150,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T20:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"peer"},"createdAt":"2026-09-15T04:00:00Z"}]},"reviewRequests":{"nodes":[]}}')" \
  "core#150 yours - reply since your last commit, 4 h"

# 14. I answered the comment: the move went back
expect_silent "author: my own comment after theirs hands the move back" \
  "$(pr author '{"number":150,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T20:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"peer"},"createdAt":"2026-09-15T04:00:00Z"},{"author":{"login":"author"},"createdAt":"2026-09-15T05:00:00Z"}]},"reviewRequests":{"nodes":[]}}')"

# 15. a comment older than my last commit is answered by that commit
expect_silent "author: a comment before my last commit is not a move" \
  "$(pr author '{"number":150,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-15T06:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"peer"},"createdAt":"2026-09-15T04:00:00Z"}]},"reviewRequests":{"nodes":[]}}')"

# 16. a bot comment is nobody's move
expect_silent "author: a bot comment is not a reply" \
  "$(pr author '{"number":150,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T20:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"github-actions"},"createdAt":"2026-09-15T04:00:00Z"}]},"reviewRequests":{"nodes":[]}}')"

# 17. an APPROVED review after my last commit is a move too (merge is next)
expect_line "author: an approval after my last commit" \
  "$(pr author '{"number":151,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T20:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"peer"},"state":"APPROVED","submittedAt":"2026-09-15T02:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "core#151 yours - reply since your last commit, 6 h"

# 18-22. ONE login, several instances (measured 2026-10-11: the operator's other machine
#     opened a test fix under the same account and waited for a second OK that this line
#     never showed — it read the PR as our own). Each text carries the poster's instance key.
KMAC="$(PYTHONPATH="$ROOT/scripts" "$PY" -c 'import instance_key as k; print(k.key_for("mac"))')"
KWS="$(PYTHONPATH="$ROOT/scripts" "$PY" -c 'import instance_key as k; print(k.key_for("ws"))')"
krun() { printf '%s' "$2" | SHARED_MEMORY_SELF=mac "$PY" "$BALL" --now "$NOW"; }
kexpect_line() { out="$(krun "$1" "$2")"; case "$out" in *"$3"*) ok "$1" ;; *) bad "$1 — got: ${out:-<silence>}" ;; esac; }
kexpect_silent() { out="$(krun "$1" "$2")"; [ -z "$out" ] && ok "$1" || bad "$1 — expected silence, got: $out"; }

kexpect_line "sibling: a PR by the other instance under our login is our review" \
  "$(pr acct '{"number":117,"isDraft":false,"body":"fix <!-- instance-key: '"$KWS"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T08:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" \
  "suite#117 review - asked, not looked at yet"

kexpect_silent "self: a PR carrying our own key stays ours (no reply yet)" \
  "$(pr acct '{"number":115,"isDraft":false,"body":"fix <!-- instance-key: '"$KMAC"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T08:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

kexpect_line "sibling reply: an OK from the other instance under our login is a move on our PR" \
  "$(pr acct '{"number":115,"isDraft":false,"body":"<!-- instance-key: '"$KMAC"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T08:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"acct"},"createdAt":"2026-09-15T04:00:00Z","body":"Windows: OK <!-- instance-key: '"$KWS"' -->"}]},"reviewRequests":{"nodes":[]}}')" \
  "suite#115 yours - reply since your last commit"

kexpect_line "sibling review: our comment on the other instance's PR is a look, a newer commit asks again" \
  "$(pr acct '{"number":117,"isDraft":false,"body":"<!-- instance-key: '"$KWS"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-15T06:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"acct"},"createdAt":"2026-09-15T04:00:00Z","body":"looked <!-- instance-key: '"$KMAC"' -->"}]},"reviewRequests":{"nodes":[]}}')" \
  "suite#117 review - new commits since your last look"

# Negative control: without SHARED_MEMORY_SELF the old login-only rule holds — the sibling
# PR reads as our own and stays silent. This is exactly the blindness the key removes.
out="$(printf '%s' "$(pr acct '{"number":117,"isDraft":false,"body":"fix <!-- instance-key: '"$KWS"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-14T08:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')" | env -u SHARED_MEMORY_SELF "$PY" "$BALL" --now "$NOW")"
[ -z "$out" ] && ok "no own key: login-only rule unchanged (sibling PR silent)" || bad "no own key: expected the old silence, got: $out"

# The check was answered in the shared memory, not on the PR (measured 2026-10-11: the
# bootup said "agent-brain#279 review - asked, not looked at yet" after the Windows check of
# that head had been answered there). Our text naming THIS head is the look; an older head
# or someone else's text naming it is not.
mkdir -p "$SM/.git" "$SM/core"
SIB='{"number":117,"isDraft":false,"body":"fix <!-- instance-key: '"$KWS"' -->","repository":{"name":"suite"},"author":{"login":"acct"},"commits":{"nodes":[{"commit":{"oid":"abcdef1234567890abcdef1234567890abcdef12","committedDate":"2026-09-14T08:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}'
printf '%s\n' '---' 'name: a' 'metadata:' '  von: mac' '---' 'Checked at head `abcdef1`: OK.' > "$SM/core/antwort.md"
kexpect_silent "shared-memory answer at this head: the sibling PR is looked at" "$(pr acct "$SIB")"
printf '%s\n' '---' 'name: a' 'metadata:' '  von: ws' '---' 'please check `abcdef1`' > "$SM/core/antwort.md"
kexpect_line "negative control: a foreign text naming the head is no look of ours" "$(pr acct "$SIB")" \
  "suite#117 review - asked, not looked at yet"
rm -rf "$SM/core" "$SM/.git"

# 9. drafts never count
expect_silent "draft: never a move" \
  "$(pr author '{"number":10,"isDraft":true,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')"

# 10. offline / gh error: no JSON on stdin is silence, exit 0
out="$(printf '' | "$PY" "$BALL" --now "$NOW")"; rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok "no input: silence and exit 0" || bad "no input: rc=$rc out=$out"

# 12. the line is pure ASCII, separator included. Measured 2026-09-15 on the Windows
#     runner: Python prints through the console code page there, and an em dash in the
#     line arrived as a replacement character — on a collaborator's Windows bootup too,
#     not only in this fixture. Two moves, so the separator is in the output.
out="$(run two "$(pr author '{"number":1,"isDraft":false,"body":"","repository":{"name":"core"},"author":{"login":"author"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T15:00:00Z"}}]},"reviews":{"nodes":[{"author":{"login":"maint"},"state":"CHANGES_REQUESTED","submittedAt":"2026-09-13T16:00:00Z"}]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}},{"number":2,"isDraft":false,"body":"@author","repository":{"name":"core"},"author":{"login":"maint"},"commits":{"nodes":[{"commit":{"committedDate":"2026-09-13T16:00:00Z"}}]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewRequests":{"nodes":[]}}')")"
if [ -n "$out" ] && LC_ALL=C awk '/[^\t -~]/ { bad = 1 } END { exit bad }' <<EOF
$out
EOF
then ok "two moves in one line, all ASCII: $out"
else bad "line empty or not pure ASCII (breaks on a Windows code page): ${out:-<silence>}"
fi

# 11. the bootup actually calls it (a carrier without a trigger is no carrier)
if grep -q 'scripts/pr-ball.py' "$ROOT/helpers/session-bootup.sh"; then
  ok "session-bootup.sh calls pr-ball.py"
else
  bad "session-bootup.sh does not call pr-ball.py — the line would never appear"
fi

[ "$fail" -eq 0 ] && echo "test-pr-ball: all checks passed"
exit "$fail"
