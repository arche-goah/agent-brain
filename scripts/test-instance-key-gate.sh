#!/usr/bin/env bash
# covers: instance-key-gate instance_key
# test-instance-key-gate.sh — a GitHub text an AI posts carries its instance key, or it is
# not sent; the reading side (instance_key.py) computes the SAME key. Both directions, no
# network: the gate only reads the command and the files it hands over.
#
# WHY (2026-10-11): one GitHub login carried two instances; the checks that decide whose move
# a PR is read the other machine's PR and its OK as their own and stayed silent.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$ROOT/helpers/instance-key-gate.cjs"
PY=python3; "$PY" -c 'import sys' >/dev/null 2>&1 || PY=python
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/brain/.claude"

KEY="$(node -e 'console.log(require(process.argv[1]).keyFor("mac"))' "$(native "$GATE")")"
PYKEY="$(PYTHONPATH="$(native "$ROOT/scripts")" "$PY" -c 'import instance_key as k; print(k.key_for("mac"))')"
[ -n "$KEY" ] && [ "$KEY" = "$PYKEY" ] && ok "gate and reader compute the same key ($KEY)" || bad "key mismatch: js=$KEY py=$PYKEY"

probe() { # $1 label, $2 command, $3 block|allow, [$4 SELF value, default mac]
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$T")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$2")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF="${4-mac}" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$3" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:120}"
  else [ "$3" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}

probe "comment without key" "gh pr comment 5 -R o/r --body \"OK to merge\"" block
probe "comment with own key" "gh pr comment 5 -R o/r --body \"OK <!-- instance-key: $KEY -->\"" allow
probe "comment with ANOTHER instance's key" "gh pr comment 5 -R o/r --body \"OK <!-- instance-key: 0123456789 -->\"" block
printf 'body\n<!-- instance-key: %s -->\n' "$KEY" > "$T/body.md"
probe "create with key in --body-file" "gh pr create --head x --title t --body-file $(native "$T/body.md")" allow
printf 'body without key\n' > "$T/nokey.md"
probe "create, --body-file without key" "gh pr create --head x --title t --body-file $(native "$T/nokey.md")" block
# `~` in --body-file: the shell expands it, so the gate must too — else the file stays unread and
# the key in it is never seen (2026-10-18, Windows instance). HOME points at the fixture.
HOME="$T" USERPROFILE="$T" probe "create, key in --body-file ~/<file>" "gh pr create --head x --title t --body-file ~/body.md" allow
# A Git Bash path (`/c/...`, `/tmp/...`): the shell reads it, node on Windows did not (2026-10-14).
# Elsewhere the POSIX path is the native one, so the case runs on every OS.
probe "create, key in --body-file as a POSIX path" "gh pr create --head x --title t --body-file $T/body.md" allow
# A variable in the path (2026-10-28, Windows instance of another brain: `--body-file "$S/x.md"` was
# read literally and the post blocked). Set in the same command, or in the environment.
G="g""h"
probe "key in --body-file \"\$S/<file>\", S set in the command" "S=$(native "$T"); $G pr comment 5 -R o/r --body-file \"\$S/body.md\"" allow
S2="$(native "$T")" probe "key in --body-file \"\${S2}/<file>\", S2 from the environment" "$G pr comment 5 -R o/r --body-file \"\${S2}/body.md\"" allow
out=$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh pr comment 5 --body-file \\\"\$NOSUCHVAR/body.md\\\"\"}}" \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$out" in *"write the path out"*) true ;; *) false ;; esac \
  && ok "unknown variable in the path blocks and says so" || bad "unknown variable: rc=$rc ${out:0:160}"
probe "issue comment without key" "gh issue comment 9 -R o/r --body hi" block
probe "review --approve without a body" "gh pr review 5 -R o/r --approve" block
probe "merge with a marker comment is not a post" "gh pr merge 5 -R o/r --squash # MECHANISM-OK: x" allow
probe "read-only gh is not a post" "gh pr view 5 -R o/r --json body" allow
# A message that QUOTES the post command is no post (2026-10-19: a plain commit was held).
G="g""h"
probe "commit message quoting the PR command is no post" "git commit -m \"check before $G pr create\"" allow
probe "the post after a ; is still found" "echo ok; $G pr comment 5 -R o/r --body hi" block
probe "key inside \$(cat <file>) is found" "$G pr comment 5 -R o/r --body \"\$(cat $(native "$T/body.md"))\"" allow
probe "a heredoc falls back to the whole line" "$G pr comment 5 -R o/r --body \"\$(cat <<'X'
hi
X
)\"" block
probe "no instance id: nothing to check" "gh pr comment 5 -R o/r --body hi" allow ""
# A local script the command runs is read one level deep (2026-11-12, both instances: posts made inside
# `bash <file>` went out unread - the gate saw only the outer command).
SC="$T/scripts"; mkdir -p "$SC"
printf '%s\n' '#!/usr/bin/env bash' "# don't forget the note" "$G pr comment \"\$1\" -R o/r --body \"fixed\"" > "$SC/nokey.sh"
printf '%s\n' '#!/usr/bin/env bash' "$G pr comment \"\$1\" -R o/r --body \"fixed <!-- instance-key: $KEY -->\"" > "$SC/key.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo nothing posted' > "$SC/quiet.sh"
printf '%s\n' '#!/usr/bin/env bash' "$G pr comment \"\$1\" -R o/r --body-file \"\$2\"" > "$SC/runtime.sh"
probe "a script run as bash <file> posting without the key" "bash $(native "$SC/nokey.sh") 5" block
probe "the same script with the key" "bash $(native "$SC/key.sh") 5" allow
probe "a script that posts nothing" "bash $(native "$SC/quiet.sh")" allow
probe "a script whose body file comes at run time" "bash $(native "$SC/runtime.sh") 5 body.md" allow
probe "a script the gate cannot read (variable path)" 'bash "$NOSUCHDIR/nokey.sh" 5' allow

# The block message names the exact line to add (an agent must not have to guess the key).
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 5 --body hi"}}' \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1)
case "$out" in *"<!-- instance-key: $KEY -->"*) ok "block message carries the exact marker" ;; *) bad "marker missing in: $out" ;; esac

# The id may come from the brain's settings env when the process env has none.
printf '{"env":{"SHARED_MEMORY_SELF":"mac, mac-alias"}}\n' > "$T/brain/.claude/settings.json"
out=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr comment 5 --body hi"}}' \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" env -u SHARED_MEMORY_SELF node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$out" in *"$KEY"*) true ;; *) false ;; esac && ok "id read from settings env (first token)" || bad "settings env: rc=$rc $out"

# The PowerShell tool is the same channel on Windows (2026-10-16): same command, same verdict.
out=$(printf '%s' '{"tool_name":"PowerShell","tool_input":{"command":"gh pr comment 5 --body hi"}}'       | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && case "$out" in *"instance-key"*) true ;; *) false ;; esac && ok "PowerShell write without the key blocks" || bad "PowerShell: rc=$rc $out"

# Every change declares its level (2026-10-19): `gh pr create` from a checkout whose changelog
# fragment lacks the field is held BEFORE the PR exists; other posts and repos without
# changelog.d/ are untouched.
lvprobe() { # $1 label, $2 checkout dir, $3 command, $4 block|allow
  local out rc
  out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$2")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$3")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${out:0:160}"
  else [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
CO="$T/checkout"; mkdir -p "$CO/changelog.d" "$CO/scripts"; git init -q "$CO"
printf '%s\n' '- **x.** (test: T0)' > "$CO/changelog.d/x.md"
lvprobe "pr create, fragment without level" "$CO/scripts" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" block
lvprobe "pr comment from the same checkout is no PR creation" "$CO" "gh pr comment 5 --body \"b <!-- instance-key: $KEY -->\"" allow
printf '%s\n' '- **x.** (test: T0) (level: writer; higher: design — not needed yet; debt: none)' > "$CO/changelog.d/x.md"
lvprobe "pr create, fragment with level" "$CO" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" allow
lvprobe "pr create, level fine but no key" "$CO" "gh pr create --title t --body b" block
NOCL="$T/nocl"; mkdir -p "$NOCL"; git init -q "$NOCL"
lvprobe "pr create in a repo without changelog.d" "$NOCL" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" allow
# --repo names another repo than the checkout the create runs in (measured 2026-11-03: a create
# from the brain folder for the core's branch saw no fragment and passed; CI went red after).
git -C "$CO" remote add origin https://github.com/o/core.git
printf '%s\n' '- **x.** (test: T0)' > "$CO/changelog.d/x.md"
lvprobe "pr create --repo for a repo this checkout is not" "$NOCL" "gh pr create -R o/core --head b --title t --body \"b <!-- instance-key: $KEY -->\"" block
lvprobe "pr create via env -C in the PR's checkout sees its fragment" "$NOCL" "env -C $(native "$CO") gh pr create -R o/core --head b --title t --body \"b <!-- instance-key: $KEY -->\"" block
printf '%s\n' '- **x.** (test: T0) (level: writer; higher: design — not needed yet; debt: none)' > "$CO/changelog.d/x.md"
lvprobe "negative control: env -C in the PR's checkout, fragment fine" "$NOCL" "env -C $(native "$CO") gh pr create --repo o/core --head b --title t --body \"b <!-- instance-key: $KEY -->\"" allow
# A shell variable in the -C path reaches the hook unexpanded (2026-11-06, Windows instance):
# the gate names that case instead of judging the session folder's checkout.
out=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$NOCL")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' 'env -C "$W/core-post" gh pr create --repo o/core --head b --title t --body "b <!-- instance-key: '"$KEY"' -->"')}}" \
      | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF=mac node "$(native "$GATE")" 2>&1); rc=$?
[ "$rc" -eq 2 ] && [[ "$out" == *"is a shell variable"* ]] && ok "env -C with a shell variable is named as such" || bad "env -C \$W: rc=$rc ${out:0:160}"
lvprobe "negative control: --repo matching the checkout's origin" "$CO" "gh pr create --repo=o/core --title t --body \"b <!-- instance-key: $KEY -->\"" allow
# The PR's own fragments, not the base's (2026-11-06, macOS instance, pin v2.1.3: a one-file suite PR
# was held for eleven fragments already on the suite's main). Base = origin/HEAD, else origin/main.
SU="$T/suite"; git init -q -b main "$SU"; mkdir -p "$SU/changelog.d"
printf '%s\n' '- **old.** (test: T0) (level: reader — the text the reader gets)' > "$SU/changelog.d/old.md"
git -C "$SU" add -A; git -C "$SU" -c user.email=t@t -c user.name=t commit -qm base
# The base as a remote-tracking ref, no push (a machine's own pre-push hook must not decide a fixture).
git -C "$SU" remote add origin https://github.com/o/suite.git; git -C "$SU" update-ref refs/remotes/origin/main HEAD
git -C "$SU" checkout -q -b feat
printf '%s\n' '- **new.** (test: T0) (level: writer; higher: design — not needed yet; debt: none)' > "$SU/changelog.d/new.md"
git -C "$SU" add -A; git -C "$SU" -c user.email=t@t -c user.name=t commit -qm new
lvprobe "a malformed fragment already on the base does not hold the PR" "$SU" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" allow
printf '%s\n' '- **bad.** (test: T0)' > "$SU/changelog.d/bad.md"
lvprobe "negative control: an untracked malformed fragment of the PR blocks" "$SU" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" block
rm "$SU/changelog.d/bad.md"
printf '%s\n' '- **new.** (test: T0)' > "$SU/changelog.d/new.md"
git -C "$SU" -c user.email=t@t -c user.name=t commit -qam bad
lvprobe "negative control: a committed malformed fragment of the PR blocks" "$SU" "gh pr create --title t --body \"b <!-- instance-key: $KEY -->\"" block

# A commit the text points at must be on the remote (2026-11-12, macOS instance: nine comments named
# a train commit that was only local; the Windows instance got 422 "No commit found"). gh is a node
# stand-in (INSTANCE_KEY_GATE_GH): FAKE_GH=missing answers 422, pushed answers, offline cannot connect.
printf '%s\n' "const a = process.argv.find((x) => x.startsWith('repos/')) || ''; const sha = a.split('/').pop();" \
  "const m = process.env.FAKE_GH || 'missing';" \
  "if (m === 'offline') { process.stderr.write('error connecting to api.github.com\n'); process.exit(1); }" \
  "if (m === 'pushed') { console.log(sha); process.exit(0); }" \
  "if (m === 'slow') Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 5000);" \
  "process.stderr.write('gh: No commit found for SHA: ' + sha + ' (HTTP 422)\n'); process.exit(1);" > "$T/gh.cjs"
shaprobe() { # $1 label, $2 cwd, $3 body file, $4 block|allow, [$5 SELF, default mac]; prints the gate's stderr into $SHAOUT
  local rc
  SHAOUT=$(printf '%s' "{\"tool_name\":\"Bash\",\"cwd\":\"$(native "$2")\",\"tool_input\":{\"command\":$(node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "gh pr comment 5 -R o/r --body-file $(native "$3")")}}" \
        | CLAUDE_PROJECT_DIR="$(native "$T/brain")" SHARED_MEMORY_SELF="${5-mac}" INSTANCE_KEY_GATE_GH="$(native "$T/gh.cjs")" node "$(native "$GATE")" 2>&1); rc=$?
  if [ "$rc" -eq 2 ]; then [ "$4" = block ] && ok "$1 blocks" || bad "$1 blocked: ${SHAOUT:0:160}"
  else [ "$4" = allow ] && ok "$1 allows" || bad "$1 did NOT block (rc=$rc)"; fi
}
# Held is only a commit of a local checkout that no remote branch of it contains (review 2026-11-13,
# Windows instance: a 422 also comes for another repo's sha and for a 10-hex instance key). Full
# 40-character shas, so the pointer rule (a letter and a digit) holds in every run.
mkcommit() { GIT_AUTHOR_DATE=2026-11-12T00:00:00Z GIT_COMMITTER_DATE=2026-11-12T00:00:00Z git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "$2"; git -C "$1" rev-parse HEAD; }
RC="$T/rc"; git init -q -b main "$RC"; git -C "$RC" remote add origin https://github.com/o/r.git
PUSHED="$(mkcommit "$RC" pushed)"; git -C "$RC" update-ref refs/remotes/origin/main HEAD
LOCAL="$(mkcommit "$RC" local)"
LOCAL2="$(mkcommit "$RC" local2)"
OTHER="$T/other"; git init -q -b main "$OTHER"; FOREIGN="$(mkcommit "$OTHER" foreign)"
printf 'fixed in the train at `%s`\n<!-- instance-key: %s -->\n' "$LOCAL" "$KEY" > "$T/sha.md"
FAKE_GH=missing shaprobe "a local-only commit the remote does not have" "$RC" "$T/sha.md" block
case "$SHAOUT" in *"$LOCAL"*"Push first, then post"*) ok "block message names the sha and says push first" ;; *) bad "sha message: ${SHAOUT:0:200}" ;; esac
FAKE_GH=pushed shaprobe "a local commit the API answers" "$RC" "$T/sha.md" allow
FAKE_GH=offline shaprobe "no network" "$RC" "$T/sha.md" allow
case "$SHAOUT" in *"not readable for $LOCAL"*) ok "no network says so on stderr" ;; *) bad "offline line missing: ${SHAOUT:0:200}" ;; esac
FAKE_GH=missing shaprobe "without an instance id the pointer still holds" "$RC" "$T/sha.md" block ""
printf 'fixed at `%s`\n<!-- instance-key: %s -->\n' "$PUSHED" "$KEY" > "$T/rc-pushed.md"
FAKE_GH=missing shaprobe "a sha on a remote branch of the checkout (API says 422)" "$RC" "$T/rc-pushed.md" allow
printf 'the other instance is `181fb5d93f`\n<!-- instance-key: %s -->\n' "$KEY" > "$T/key.md"
FAKE_GH=missing shaprobe "a backticked 10-hex instance key (API says 422)" "$RC" "$T/key.md" allow
printf 'the suite head is `%s`\n<!-- instance-key: %s -->\n' "$FOREIGN" "$KEY" > "$T/foreign.md"
FAKE_GH=missing shaprobe "a commit of another repo (API says 422)" "$RC" "$T/foreign.md" allow
FAKE_GH=missing shaprobe "a sha outside any checkout (cwd no repo)" "$T" "$T/sha.md" allow
printf 'see https://github.com/o/r/commit/`%s` and [x](https://github.com/o/r/blob/%s/a.md)\n<!-- instance-key: %s -->\n' "$LOCAL" "$LOCAL" "$KEY" > "$T/url.md"
FAKE_GH=missing shaprobe "hex inside a URL" "$RC" "$T/url.md" allow
printf 'measured on `20261112`, word `defaced`, not hex `4a560fz`\n<!-- instance-key: %s -->\n' "$KEY" > "$T/num.md"
FAKE_GH=missing shaprobe "a plain number, a hex-letter word, a non-hex word" "$RC" "$T/num.md" allow
# One API budget for all shas; the first timeout ends the asking (the hook's own 10 s timeout blocks).
printf 'at `%s` and `%s`\n<!-- instance-key: %s -->\n' "$LOCAL" "$LOCAL2" "$KEY" > "$T/two.md"
t0=$(date +%s)
FAKE_GH=slow shaprobe "a hanging network, two local shas" "$RC" "$T/two.md" allow
dt=$(( $(date +%s) - t0 ))
[ "$dt" -lt 4 ] && ok "a hanging network ends within the budget (${dt} s)" || bad "a hanging network took ${dt} s"
case "$SHAOUT" in *"did not answer within"*) ok "the timeout says so on stderr" ;; *) bad "timeout line missing: ${SHAOUT:0:200}" ;; esac

[ "$fail" -eq 0 ] && echo "test-instance-key-gate: all checks passed"
exit "$fail"
