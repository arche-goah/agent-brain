#!/bin/sh
# Print where this machine draws power from: `ac`, `battery` or `unknown`. Exit 0.
#
#     power-source.sh
#
# WHY. A scheduled run that starts on battery usually starts on a sleeping laptop: the
# scheduler fires inside a short maintenance wake, the machine goes back to sleep, and
# every agent of the run freezes with it. The workflow counts each freeze as a stall
# and restarts the agent — measured 2026-09-23: the weekly brain-scan fired at 09:12
# on a lid-closed MacBook on battery (pmset: only ~45 s dark wakes every 8-17 min),
# its agents stalled for 1026/1050/1505 s (= the sleep gaps), and after 90 min the run
# was killed with 2.34M tokens spent and no report. Launchers ask this helper first
# and skip on `battery`; the run stays due and fires on the next start on mains.
#
# POLICY. Only `battery` means skip. `unknown` (no reader on this OS, reader failed)
# means run — a desktop, a VM or a CI runner must never lose its scheduled runs to a
# detector that cannot see a battery. A machine WITHOUT a battery reports `ac`.
#
# PLATFORMS. macOS: `pmset -g batt`. Linux: /sys/class/power_supply. Windows (Git
# Bash/MSYS/Cygwin): Win32_Battery.BatteryStatus via PowerShell, where 1 = discharging
# and every other value = on mains; no battery object = desktop = `ac`.
set -u

case "$(uname -s 2>/dev/null)" in
  Darwin)
    line=$(pmset -g batt 2>/dev/null | head -1)
    case "$line" in
      *"'AC Power'"*)      echo ac ;;
      *"'Battery Power'"*) echo battery ;;
      *)                   echo unknown ;;
    esac
    ;;
  Linux)
    d=/sys/class/power_supply
    [ -d "$d" ] || { echo ac; exit 0; }
    mains=0; online=0; discharging=0
    for s in "$d"/*; do
      [ -r "$s/type" ] || continue
      case "$(cat "$s/type" 2>/dev/null)" in
        Mains|USB)
          mains=1
          [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && online=1 ;;
        Battery)
          [ "$(cat "$s/status" 2>/dev/null)" = Discharging ] && discharging=1 ;;
      esac
    done
    if [ "$online" = 1 ]; then echo ac
    elif [ "$discharging" = 1 ]; then echo battery
    elif [ "$mains" = 0 ]; then echo ac   # no supply listed at all: desktop/VM
    else echo unknown
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    # An empty answer means "no battery" only if PowerShell really ran — so check it
    # exists first (the pipeline's exit status is tr's, not PowerShell's).
    if command -v powershell.exe >/dev/null 2>&1; then
      st=$(powershell.exe -NoProfile -NonInteractive -Command \
        "(Get-CimInstance -ClassName Win32_Battery | Select-Object -First 1).BatteryStatus" \
        2>/dev/null | tr -d '\r[:space:]')
    else
      st=err
    fi
    case "$st" in
      err) echo unknown ;;
      "")  echo ac ;;        # no battery object: desktop
      1)   echo battery ;;
      *[!0-9]*) echo unknown ;;
      *)   echo ac ;;
    esac
    ;;
  *) echo unknown ;;
esac
exit 0
