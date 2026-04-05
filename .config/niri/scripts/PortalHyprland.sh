#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For manually starting the xdg-desktop-portal backend used by the session

set -euo pipefail

kill_quietly() {
  killall -q "$1" 2>/dev/null || true
}

start_portal_binary() {
  local description="$1"
  shift
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      "$candidate" &
      return 0
    fi
  done
  echo "Warning: no $description binary found (checked: $*)" >&2
  return 1
}

sleep 1
kill_quietly xdg-desktop-portal-hyprland
kill_quietly xdg-desktop-portal-wlr
kill_quietly xdg-desktop-portal-gnome
kill_quietly xdg-desktop-portal
sleep 1

if command -v niri >/dev/null 2>&1; then
  start_portal_binary "xdg-desktop-portal-wlr" \
    /usr/lib/xdg-desktop-portal-wlr \
    /usr/libexec/xdg-desktop-portal-wlr
  sleep 1
  start_portal_binary "xdg-desktop-portal" \
    /usr/lib/xdg-desktop-portal \
    /usr/libexec/xdg-desktop-portal
else
  start_portal_binary "xdg-desktop-portal-hyprland" \
    /usr/lib/xdg-desktop-portal-hyprland \
    /usr/libexec/xdg-desktop-portal-hyprland
  sleep 2
  start_portal_binary "xdg-desktop-portal" \
    /usr/lib/xdg-desktop-portal \
    /usr/libexec/xdg-desktop-portal
fi

