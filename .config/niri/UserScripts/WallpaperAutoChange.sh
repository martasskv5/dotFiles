#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# source https://wiki.archlinux.org/title/Hyprland#Using_a_script_to_change_wallpaper_every_X_minutes

# This script will randomly go through the files of a directory, setting it
# up as the wallpaper at regular intervals
#
# NOTE: this script uses bash (not POSIX shell) for the RANDOM variable

wallust_refresh=$HOME/.config/niri/scripts/RefreshNoWaybar.sh

get_focused_monitor() {
	local mon=""
	if command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
		mon=$(niri msg -j outputs 2>/dev/null | jq -r '.[] | select((.is_focused // .focused // false) == true) | .name' | head -n1)
		if [[ -z "$mon" ]]; then
			mon=$(niri msg -j outputs 2>/dev/null | jq -r '.[0].name // empty' | head -n1)
		fi
	fi
	if [[ -z "$mon" ]] && command -v hyprctl >/dev/null 2>&1; then
		mon=$(hyprctl monitors | awk '/^Monitor/{name=$2} /focused: yes/{print name}')
	fi
	echo "$mon"
}

focused_monitor=$(get_focused_monitor)
state_file="$HOME/.config/niri/wallpaper_effects/.wallpaper_startup_last"

if [[ $# -lt 1 ]] || [[ ! -d $1   ]]; then
	echo "Usage:
	$0 <dir containing images>"
	exit 1
fi

# Edit below to control the images transition
export SWWW_TRANSITION_FPS=60
export SWWW_TRANSITION_TYPE=simple

# This controls (in seconds) when to switch to the next image
INTERVAL=1800

while true; do
	find "$1" \
		| while read -r img; do
			echo "$((RANDOM % 1000)):$img"
		done \
		| sort -n | cut -d':' -f2- \
		| while read -r img; do
			awww img "$img"
			mkdir -p "$(dirname "$state_file")"
			printf '%s\n' "$img" > "$state_file"
			# Regenerate colors from the exact image path to avoid cache races
			$HOME/.config/niri/scripts/WallustSwww.sh "$img"
			# Refresh UI components that depend on wallust output
			$wallust_refresh
			sleep $INTERVAL
			
		done
done
