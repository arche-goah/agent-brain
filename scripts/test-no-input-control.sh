#!/usr/bin/env bash
# Fixture test for helpers/no-input-control.cjs — both directions.
# covers: no-input-control
# The words the hook looks for are assembled at RUN time (w … below): on a machine that runs the hook,
# a file or command holding them literally is denied — the alpha blocked its own pattern list (2026-10-26).
# Usage: bash scripts/test-no-input-control.sh (exit 0 = pass)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../helpers/no-input-control.cjs"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf %s "$1"; fi; }
fail=0
ok()  { echo "  OK   $1"; }
bad() { echo "  FAIL $1"; fail=1; }
w() { printf '%s' "$@"; }   # join parts into one word
js() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
# A Write input built by node, not by shell quoting: a literal {a,b} in a nested substitution is
# brace-expanded into two words (bash), which split the call.
wr() { node -e 'process.stdout.write(JSON.stringify({file_path: process.argv[1], content: process.argv[2]}))' "$1" "$2"; }
call() { # $1 tool name, $2 tool_input JSON, [$3 project dir]
  # JSON built by node from argv (escaping; a printf-built input broke on a double quote, 2026-11-02)
  node -e 'const a=process.argv;process.stdout.write(JSON.stringify({tool_name:a[1],tool_input:JSON.parse(a[2]),cwd:a[3]}))' "$1" "$2" "$(native "${3:-$T}")" \
    | CLAUDE_PROJECT_DIR="$(native "${3:-$T}")" node "$G" 2>&1
}
expect() { # $1 label, $2 deny|allow, $3 output
  case "$2:$3" in
    deny:*'"permissionDecision":"deny"'*) ok "$1 denied" ;;
    allow:'{}') ok "$1 allowed" ;;
    *) bad "$1: wanted $2, got '$3'" ;;
  esac
}
[ -f "$G" ] || { echo "  FAIL hook missing: $G"; exit 1; }

# --- the six cases of the alpha measurement (2026-10-26), both directions
expect "computer-use tool" deny "$(call "mcp__computer-use__left_click" '{"coordinate":[1,2]}')"
expect "computer-use tool, a double quote in the project path (escaping)" deny "$(call "mcp__computer-use__left_click" '{"coordinate":[1,2]}' "$T/q\"x")"
SE="$(w 'System ' 'Events')"; KS="$(w 'key' 'stroke')"
expect "command that sends keys" deny "$(call Bash "{\"command\":$(js "osascript -e 'tell application \"$SE\" to $KS \"a\"'")}")"
expect "file content with an input library" deny "$(call Write "$(wr "$(native "$T/x.py")" "import $(w py auto gui)")")"
printf 'from %s import %s\n' "$(w py nput)" "$(w mo use)" > "$T/drive.py"
expect "a script the command runs imports an input library" deny "$(call Bash "{\"command\":$(js "python3 $(native "$T/drive.py")")}")"
expect "harmless command" allow "$(call Bash '{"command":"git status"}')"
expect "harmless edit about keyboard shortcuts" allow "$(call Edit '{"file_path":"/x/doc.md","old_string":"a","new_string":"keyboard shortcuts doc"}')"

# --- the four gaps the Windows check found (2026-10-26): script hosts, focus switch, NirSoft tool, hotkey scripts
printf 'Set s = CreateObject("WScript.Shell")\ns.%s "x"\n' "$(w Send Keys)" > "$T/drive.vbs"
expect "a script-host file the command runs sends keys" deny "$(call Bash "{\"command\":$(js "cscript $(native "$T/drive.vbs")")}")"
printf '@echo off\n%s sendkeypress enter\n' "$(w nir cmd)" > "$T/drive.bat"
expect "a batch file the command runs uses the NirSoft tool" deny "$(call Bash "{\"command\":$(js "cmd /c $(native "$T/drive.bat")")}")"
expect "a call that switches the focused window" deny "$(call PowerShell "{\"command\":$(js "[W]::$(w SetForeground Window)(\$h)")}")"
expect "a NirSoft call in a command" deny "$(call Bash "{\"command\":$(js "$(w nir cmd) setcursor 10 10")}")"
expect "a hotkey script run directly" deny "$(call Bash "{\"command\":$(js "start C:/x/clicker$(w .a hk)")}")"
# --- documentation names the API, it calls nothing (operator 2026-11-02: check only what can run)
SK="$(w Send Keys)"
expect "a skill doc line naming the input API" allow "$(call Write "$(wr /x/skills/a/SKILL.md "the primitive uses Win32 Send Input / $SK")")"
expect "the same text into a script file" deny "$(call Write "$(wr /x/a.ps1 "[W]::$(w SetForeground Window)(\$h); $SK")")"
expect "the same text in a command (running stays checked)" deny "$(call Bash "{\"command\":$(js "echo x | $(w nir cmd) sendkeypress enter")}")"
# --- the two-step path (a collaborator's Windows check on #302): code written into a doc file, then run
printf 'import %s\n' "$(w py auto gui)" > "$T/notes.txt"
expect "an interpreter runs a doc file holding input code" deny "$(call Bash "{\"command\":$(js "python3 $(native "$T/notes.txt")")}")"
expect "an eval of a doc file holding input code" deny "$(call PowerShell "{\"command\":$(js "iex (Get-Content $(native "$T/notes.txt") -Raw)")}")"
expect "reading a doc file is no run (control)" allow "$(call Bash "{\"command\":$(js "cat $(native "$T/notes.txt")")}")"
N="$(native "$T/notes.txt")"
expect "a path before python.exe runs a doc file" deny "$(call PowerShell "{\"command\":$(js "C:/Python312/python.exe $N")}")"
expect "a backslash path before python.exe runs a doc file" deny "$(call PowerShell "{\"command\":$(js "C:\\Python312\\python.exe $N")}")"
expect "pythonw runs a doc file" deny "$(call PowerShell "{\"command\":$(js "pythonw $N")}")"
expect "py -3 runs a doc file" deny "$(call PowerShell "{\"command\":$(js "py -3 $N")}")"
P3="python""3"  # test data, never run; split so the bare-interpreter lint does not read it as a call
expect "a doc file piped into python3 - runs" deny "$(call Bash "{\"command\":$(js "cat $N | $P3 -")}")"
expect "cmd /c python runs a doc file" deny "$(call PowerShell "{\"command\":$(js "cmd /c python $N")}")"
expect "the call operator & python runs a doc file" deny "$(call PowerShell "{\"command\":$(js "& python $N")}")"
expect "Get-Content piped into Invoke-Expression runs a doc file" deny "$(call PowerShell "{\"command\":$(js "Get-Content $N -Raw | Invoke-Expression")}")"
expect "grep of a doc file is no run (control)" allow "$(call Bash "{\"command\":$(js "grep import $N")}")"
# 2026-11-06: a doc path inside a quoted -c string is read, not run; a redirect target is written, not run.
expect "a doc file opened for reading inside -c is no run" allow "$(call Bash "{\"command\":$(js "$P3 -c \"print(open('$N').read()[:10])\"")}")"
expect "a doc file as a redirect target, the runner named only in quoted text, is no run" allow "$(call Bash "{\"command\":$(js "printf '%s\\n' 'use $P3 here' >> $N")}")"
expect "negative control: the same doc handed to the interpreter still runs" deny "$(call Bash "{\"command\":$(js "$P3 $N")}")"
printf '@echo off\necho build done\n' > "$T/drive2.bat"
expect "a batch file without input calls" allow "$(call Bash "{\"command\":$(js "cmd /c $(native "$T/drive2.bat")")}")"

# --- instance data: a declared allow with a reason lifts one pattern; an empty reason does not
mkdir -p "$T/brain/.claude/rules"
printf '{"allow":{"py-gui-automation":"kiosk test rig, operator 2026-10-26"}}\n' > "$T/brain/.claude/rules/no-input-control.json"
expect "declared allow with a reason" allow "$(call Write "$(wr /x/y.py "import $(w py auto gui)")" "$T/brain")"
printf '{"allow":{"py-gui-automation":""}}\n' > "$T/brain/.claude/rules/no-input-control.json"
expect "declared allow without a reason" deny "$(call Write "$(wr /x/y.py "import $(w py auto gui)")" "$T/brain")"
# --- the hook's own data file is never a target (it holds the words by design)
expect "writing the hook's own data file" allow "$(call Write "$(wr /b/.claude/rules/no-input-control.json "$(w xdo tool)")")"
# --- an agent brief that names an API is text about it, not a call
expect "agent prompt naming an API" allow "$(call Agent "{\"prompt\":$(js "research $(w py auto gui) alternatives")}")"

[ "$fail" = 0 ] && echo "no-input-control: all cases pass" || { echo "no-input-control: FAILURES"; exit 1; }
