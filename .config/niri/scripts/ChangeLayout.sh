#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Niri uses columns instead of Hyprland master/dwindle layouts.

notif="$HOME/.config/swaync/images/ja.png"

if command -v niri >/dev/null 2>&1; then
  niri msg action toggle-column-tabbed-display >/dev/null 2>&1 || true
  notify-send -e -u low -i "$notif" " Layout" " Toggled column tabbed display"
else
  notify-send -e -u low -i "$notif" " Layout" " Niri layout toggle unavailable"
fi
