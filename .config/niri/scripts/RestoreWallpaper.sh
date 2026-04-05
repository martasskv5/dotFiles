#!/usr/bin/env bash
set -euo pipefail

state_file="$HOME/.config/niri/wallpaper_effects/.wallpaper_startup_last"

[[ -f "$state_file" ]] || exit 0
wallpaper=$(head -n1 "$state_file" | xargs)
[[ -n "$wallpaper" && -f "$wallpaper" ]] || exit 0

if [[ "$wallpaper" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
  if command -v mpvpaper >/dev/null 2>&1; then
    pkill mpvpaper 2>/dev/null || true
    mpvpaper '*' -o "load-scripts=no no-audio --loop" "$wallpaper" &
  fi
  exit 0
fi

if ! pgrep -x "awww-daemon" >/dev/null 2>&1; then
  awww-daemon --format xrgb &
  sleep 0.4
fi

awww img "$wallpaper" --transition-fps 60 --transition-type any --transition-duration 1
"$HOME/.config/niri/scripts/WallustSwww.sh" "$wallpaper" || true
"$HOME/.config/niri/scripts/Refresh.sh" || true
