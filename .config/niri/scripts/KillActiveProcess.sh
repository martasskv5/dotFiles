#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

# Copied from Discord post. Thanks to @Zorg


# Get id of the focused window
active_pid=$(niri msg -j focused-window 2>/dev/null | jq -r '.pid // empty')

if [[ -z "$active_pid" || ! "$active_pid" =~ ^[0-9]+$ ]]; then
  notify-send -u low -i "$HOME/.config/swaync/images/error.png" "Kill Active Window" "No active window PID found."
  exit 1
fi

# Close active window
kill "$active_pid"
