#!/usr/bin/env bash
# covers: git-target
# Fixture for helpers/git-target.cjs - the one reader of where a command's git calls run.
# Every form the seven gates met: plain/quoted/no-space -C, chained -C, ~ and $HOME, cd <dir> &&, env -C, a VAR= prefix,
# git.exe, PowerShell Set-Location, the Git Bash drive form, and -C INSIDE a quoted message (measured 2026-11-23: the old
# regex reader blocked a commit on it). Control: the old regex reader gets the quoted-message case wrong.
# Usage: bash scripts/test-git-target.sh   (exit 0 = pass)
set -u
_D="$(cd "$(dirname "$0")" && pwd)"
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
GT="$(native "$_D/../helpers/git-target.cjs")"
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
H=/fixture-home
# $1 name, $2 command, $3 expected "dir|sub" of the first git call ("" = no git call), $4 ps (true|false)
# Windows review of #635 (2026-11-23): the command and HOME travel through stdin and inside node, never argv or the shell's
# env - Git Bash rewrites an argv `/a b` or `/fixture-home` to `C:/Program Files/Git/...` before node sees it; and the
# top folders have two or more letters - a one-letter `/r` IS drive R: in Git Bash (the reader is right to read it so).
probe() {
  out=$(printf '%s' "$2" | node -e '
    process.env.HOME = process.env.USERPROFILE = "/" + process.argv[2];
    let cmd = ""; process.stdin.on("data", (c) => { cmd += c; }); process.stdin.on("end", () => {
      const {gitCalls}=require(process.argv[1]); const c=(gitCalls(cmd,"/cwd",process.argv[3]==="true")||[])[0];
      process.stdout.write(c ? c.dir.replace(/\\/g,"/").replace(/^[A-Za-z]:/,"")+"|"+c.sub : ""); })' "$GT" "fixture-home" "${4:-false}")
  # Windows re-check of #635 (2026-11-23/24): in Git Bash an absolute POSIX path IS a path under the MSYS root
  # (`cygpath -m /repo` = `C:/Program Files/Git/repo`), and the reader is right to return it - so the expected value is
  # built the way the shell sees it. The session cwd (`/cwd`, passed inside node) is not converted.
  local want="$3" d="${3%%|*}"
  case "${OSTYPE:-}" in msys*|cygwin*)
    [ -n "$d" ] && [ "$d" != /cwd ] && want="$(cygpath -m "$d" | sed 's/^[A-Za-z]://')|${3#*|}" ;; esac
  [ "$out" = "$want" ] && ok "$1" || bad "$1: got '$out', want '$want'"
}
probe "plain -C" "git -C /repo status" "/repo|status"
probe "quoted -C with a space" 'git -C "/top b" commit -m x' "/top b|commit"
probe "-C without a space" "git -C/repo log" "/repo|log"
probe "chained -C, each relative to the last" "git -C /work -C sub status" "/work/sub|status"
probe "-c before -C" "git -c a=b -C /repo push" "/repo|push"
probe "~ in -C is the home folder" "git -C ~/p commit -m x" "$H/p|commit"
probe "\$HOME in -C is the home folder" 'git -C $HOME/p push' "$H/p|push"
probe "cd <dir> && git" "cd /tree && git commit -m x" "/tree|commit"
probe "cd then a relative -C" "cd /tree && git -C sub status" "/tree/sub|status"
probe "env -C before git" "env -C /envdir git push" "/envdir|push"
probe "a VAR= prefix" "FOO=1 git -C /vardir push" "/vardir|push"
probe "git.exe by path" 'C:/Git/cmd/git.exe -C /wdir status' "/wdir|status"
probe "no -C: the cwd" "git status" "/cwd|status"
probe "PowerShell Set-Location" 'Set-Location /pdir; git commit -m x' "/pdir|commit" true
probe "the incident: -C inside a quoted commit message is no option" 'git commit -m "ledger: git -C reader in train" -- docs/x.md' "/cwd|commit"
probe "a commit -C <sha> after the verb is no directory" "git commit -C HEAD -- a" "/cwd|commit"
probe "git as an argument of another command is no call" "echo git -C /nodir status" ""
probe "a call after if is a call (2026-11-25: it was not read)" 'if git -C /kwdir commit -q -m x; then echo ok; fi' "/kwdir|commit"
probe "a call after do is a call" 'for f in a; do git -C /kwdir push; done' "/kwdir|push"
probe "a call after ! is a call" '! git -C /kwdir diff --quiet' "/kwdir|diff"
probe "a git -C in a comment line is no call" "$(printf '# see git -C /nodir status\ngit status')" "/cwd|status"
case "${OSTYPE:-}" in
  msys*|cygwin*)
    out=$(node -e 'const {gitCalls}=require(process.argv[1]);process.stdout.write((gitCalls("git -C /c/work/r status","C:/cwd")||[])[0].dir.replace(/\\/g,"/"))' "$GT")
    [ "$out" = "C:/work/r" ] && ok "the Git Bash drive form becomes native" || bad "drive form: got '$out'" ;;
  *) grep -q 'nativePath(s)' "$_D/../helpers/git-target.cjs" && ok "every path goes through nativePath (the drive form is checked on Windows)" || bad "path not translated" ;;
esac
node -e 'const {gitCalls}=require(process.argv[1]);process.exit(gitCalls("git commit -m \"open quote","/c")===null?0:1)' "$GT" && ok "an unreadable command gives null (the caller decides)" || bad "unreadable command not null"
# Control: the old regex reader (watch-gate, content-review-gate, public-text-guard before 2026-11-23)
old=$(node -e 'const m=/\bgit\s+-C\s+("[^"]+"|'"'"'[^'"'"']+'"'"'|\S+)/.exec(process.argv[1]);process.stdout.write(m?m[1]:"")' 'git commit -m "ledger: git -C reader in train" -- docs/x.md')
[ "$old" = "reader" ] && ok "control: the old regex reader took 'reader' inside the message for the repo" || bad "control: old reader gave '$old'"
[ "$fail" = 0 ] && echo "test-git-target: all checks passed" || { echo "test-git-target: FAILED"; exit 1; }
