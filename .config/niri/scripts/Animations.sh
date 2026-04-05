#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For applying Niri animation presets from different users

# Check if rofi is already running
if pidof rofi > /dev/null; then
  pkill rofi
fi

# Variables
iDIR="$HOME/.config/swaync/images"
SCRIPTSDIR="$HOME/.config/niri/scripts"
animations_dir="$HOME/.config/niri/animations"
UserConfigs="$HOME/.config/niri/configs/user"
rofi_theme="$HOME/.config/rofi/config-Animations.rasi"
msg='❗NOTE:❗ This will copy animations into configs/user/Animations.kdl'
# list of animation files, sorted alphabetically with numbers first
animations_list=$(find -L "$animations_dir" -maxdepth 1 -type f | sed 's/.*\///' | sed 's/\.conf$//' | sort -V)

# Rofi Menu
chosen_file=$(echo "$animations_list" | rofi -i -dmenu -config $rofi_theme -mesg "$msg")

# Check if a file was selected
if [[ -n "$chosen_file" ]]; then
    full_path="$animations_dir/$chosen_file.conf"    
    cp "$full_path" "$UserConfigs/Animations.kdl"
    notify-send -u low -i "$iDIR/ja.png" "$chosen_file" "Niri animation preset loaded"
fi

sleep 1
"$SCRIPTSDIR/RefreshNoWaybar.sh"
