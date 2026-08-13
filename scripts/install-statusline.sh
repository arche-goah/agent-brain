#!/bin/sh
# install-statusline.sh — wire the usage statusline (5h/7d rate-limit windows + context %)
# into the USER-level Claude Code config. Idempotent, no input, no dependencies beyond node.
#
# What it does:
#   1. copies helpers/statusline.cjs -> ~/.claude/helpers/statusline.cjs
#   2. sets "statusLine" in ~/.claude/settings.json (absolute path, rest untouched)
#
# Re-running is safe: it just refreshes the copy and rewrites the same setting.
set -eu

CORE_SRC="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.claude/helpers/statusline.cjs"
SETTINGS="$HOME/.claude/settings.json"

mkdir -p "$HOME/.claude/helpers"
cp "$CORE_SRC/helpers/statusline.cjs" "$DEST"

# Windows (Git Bash): node.exe cannot resolve the POSIX /c/... form, and bash strips the
# backslashes from an unquoted C:\... form — cygpath -m yields the mixed form C:/...,
# which node, bash and PowerShell all accept. The path is quoted either way, so a home
# directory whose name contains a space survives both shells.
CMD_PATH="$DEST"
command -v cygpath >/dev/null 2>&1 && CMD_PATH="$(cygpath -m "$DEST")"

[ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
node -e 'const fs=require("fs");const[settings,dest]=process.argv.slice(1);const s=JSON.parse(fs.readFileSync(settings,"utf8"));s.statusLine={type:"command",command:"node \""+dest+"\"",padding:0};fs.writeFileSync(settings,JSON.stringify(s,null,2)+"\n");' "$SETTINGS" "$CMD_PATH"

echo "statusline installed: $DEST"
echo "statusLine wired in:  $SETTINGS (takes effect on next Claude Code start)"
