#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Game Mode. Turning off shell effects that still apply in Niri.

notif="$HOME/.config/swaync/images/ja.png"
SCRIPTSDIR="$HOME/.config/niri/scripts"


STATE_FILE="$HOME/.cache/.gamemode_state"
state="off"
[[ -f "$STATE_FILE" ]] && state="$(cat "$STATE_FILE" 2>/dev/null || echo off)"

if [[ "$state" == "on" ]]; then
    echo off > "$STATE_FILE"
    ${SCRIPTSDIR}/Refresh.sh
    notify-send -e -u low -i "$notif" " Gamemode:" " disabled"
else
    echo on > "$STATE_FILE"
    awww kill
    notify-send -e -u low -i "$notif" " Gamemode:" " enabled"
fi
