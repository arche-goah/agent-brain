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
probe() {
  out=$(HOME="$H" USERPROFILE="$H" node -e '
    const {gitCalls}=require(process.argv[1]); const c=(gitCalls(process.argv[2],"/cwd",process.argv[3]==="true")||[])[0];
    process.stdout.write(c ? c.dir.replace(/\\/g,"/").replace(/^[A-Za-z]:/,"")+"|"+c.sub : "")' "$GT" "$2" "${4:-false}")
  [ "$out" = "$3" ] && ok "$1" || bad "$1: got '$out', want '$3'"
}
probe "plain -C" "git -C /r status" "/r|status"
probe "quoted -C with a space" 'git -C "/a b" commit -m x' "/a b|commit"
probe "-C without a space" "git -C/r log" "/r|log"
probe "chained -C, each relative to the last" "git -C /x -C sub status" "/x/sub|status"
probe "-c before -C" "git -c a=b -C /r push" "/r|push"
probe "~ in -C is the home folder" "git -C ~/p commit -m x" "$H/p|commit"
probe "\$HOME in -C is the home folder" 'git -C $HOME/p push' "$H/p|push"
probe "cd <dir> && git" "cd /t && git commit -m x" "/t|commit"
probe "cd then a relative -C" "cd /t && git -C sub status" "/t/sub|status"
probe "env -C before git" "env -C /e git push" "/e|push"
probe "a VAR= prefix" "FOO=1 git -C /v push" "/v|push"
probe "git.exe by path" 'C:/Git/cmd/git.exe -C /w status' "/w|status"
probe "no -C: the cwd" "git status" "/cwd|status"
probe "PowerShell Set-Location" 'Set-Location /p; git commit -m x' "/p|commit" true
probe "the incident: -C inside a quoted commit message is no option" 'git commit -m "ledger: git -C reader in train" -- docs/x.md' "/cwd|commit"
probe "a commit -C <sha> after the verb is no directory" "git commit -C HEAD -- a" "/cwd|commit"
probe "git as an argument of another command is no call" "echo git -C /no status" ""
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
