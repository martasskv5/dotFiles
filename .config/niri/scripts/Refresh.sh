#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Scripts for refreshing Noctalia (QuickShell), rofi, swaync, wallust

SCRIPTSDIR=$HOME/.config/niri/scripts
UserScripts=$HOME/.config/niri/UserScripts

# Define file_exists function
file_exists() {
  if [ -e "$1" ]; then
    return 0 # File exists
  else
    return 1 # File does not exist
  fi
}

# Kill already running processes
_ps=(rofi swaync ags)
for _prs in "${_ps[@]}"; do
  if pidof "${_prs}" >/dev/null; then
    pkill "${_prs}"
  fi
done

# quit ags & relaunch ags
#ags -q && ags &

# quit quickshell & relaunch Noctalia shell
pkill -x quickshell >/dev/null 2>&1 || pkill -x qs >/dev/null 2>&1 || true
sleep 0.1
qs -c noctalia-shell >/dev/null 2>&1 &

# some process to kill
for pid in $(pidof rofi swaync ags swaybg 2>/dev/null); do
  kill -SIGUSR1 "$pid"
  sleep 0.1
done

# relaunch swaync
sleep 0.3
swaync >/dev/null 2>&1 &
# reload swaync
swaync-client --reload-config

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  ${UserScripts}/RainbowBorders.sh &
fi

exit 0
