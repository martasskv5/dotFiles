#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Script for Random Wallpaper ( CTRL ALT W)

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallDIR="$PICTURES_DIR/wallpapers"
SCRIPTSDIR="$HOME/.config/niri/scripts"

get_focused_monitor() {
	local mon=""
	if command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		mon=$(niri msg -j outputs 2>/dev/null | jq -r '.[] | select((.is_focused // .focused // false) == true) | .name' | head -n1)
		if [[ -z "$mon" ]]; then
			mon=$(niri msg -j outputs 2>/dev/null | jq -r '.[0].name // empty' | head -n1)
		fi
	fi
	if [[ -z "$mon" ]] && command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1)
	fi
	echo "$mon"
}

focused_monitor=$(get_focused_monitor)
state_file="$HOME/.config/niri/wallpaper_effects/.wallpaper_startup_last"

PICS=($(find -L "${wallDIR}" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.pnm" -o -name "*.tga" -o -name "*.tiff" -o -name "*.webp" -o -name "*.bmp" -o -name "*.farbfeld" -o -name "*.gif" \)))
RANDOMPICS=${PICS[ $RANDOM % ${#PICS[@]} ]}


# Transition config
FPS=30
TYPE="random"
DURATION=1
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"


awww query || awww-daemon --format xrgb
awww img "${RANDOMPICS}" $SWWW_PARAMS
mkdir -p "$(dirname "$state_file")"
printf '%s\n' "${RANDOMPICS}" > "$state_file"

wait $!
"$SCRIPTSDIR/WallustSwww.sh" &&

wait $!
sleep 2
"$SCRIPTSDIR/Refresh.sh"

