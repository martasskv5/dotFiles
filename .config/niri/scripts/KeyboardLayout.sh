#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# This is for changing keyboard layouts in Niri.

notif_icon="$HOME/.config/swaync/images/ja.png"

layouts_json=$(niri msg -j keyboard-layouts 2>/dev/null || true)
layout_count=$(printf '%s' "$layouts_json" | jq -r '.names | length' 2>/dev/null || echo 0)
current_index=$(printf '%s' "$layouts_json" | jq -r '.current_idx // 0' 2>/dev/null || echo 0)
mapfile -t layout_mapping < <(printf '%s' "$layouts_json" | jq -r '.names[]?' 2>/dev/null)

if [[ "$layout_count" -eq 0 ]]; then
  notify-send -u low -t 2000 'kb_layout' " Error:" " No keyboard layouts found"
  exit 1
fi

current_layout=${layout_mapping[$current_index]}
current_variant=""

if [[ "$1" == "status" ]]; then
  echo "$current_layout${current_variant:+($current_variant)}"
elif [[ "$1" == "switch" ]]; then
  echo "Current layout: $current_layout"

  layout_count=${#layout_mapping[@]}
  echo "Number of layouts: $layout_count"

  next_index=$(( (current_index + 1) % layout_count ))
  new_layout="${layout_mapping[$next_index]}"
  echo "Next layout: $new_layout"

  if niri msg action switch-layout >/dev/null 2>&1; then
    notify-send -u low -i "$notif_icon" " kb_layout: $new_layout"
    echo "Layout change notification sent."
  else
    notify-send -u low -t 2000 'kb_layout' " Error:" " Layout change failed"
    echo "Layout change failed." >&2
    exit 1
  fi
else
  echo "Usage: $0 {status|switch}"
fi
