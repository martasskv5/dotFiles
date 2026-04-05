#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  #
# Wallpaper Effects using ImageMagick (SUPER SHIFT W)

# Variables
terminal=kitty
wallpaper_current="$HOME/.config/niri/wallpaper_effects/.wallpaper_current"
wallpaper_output="$HOME/.config/niri/wallpaper_effects/.wallpaper_modified"
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
rofi_theme="$HOME/.config/rofi/config-wallpaper-effect.rasi"

# Directory for swaync
iDIR="$HOME/.config/swaync/images"
iDIRi="$HOME/.config/swaync/icons"

# awww transition config
FPS=60
TYPE="wipe"
DURATION=2
BEZIER=".43,1.19,1,.4"
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION --transition-bezier $BEZIER"

# Define ImageMagick effects
declare -A effects=(
    ["No Effects"]="no-effects"
    ["Black & White"]="magick $wallpaper_current -colorspace gray -sigmoidal-contrast 10,40% $wallpaper_output"
    ["Blurred"]="magick $wallpaper_current -blur 0x10 $wallpaper_output"
    ["Charcoal"]="magick $wallpaper_current -charcoal 0x5 $wallpaper_output"
    ["Edge Detect"]="magick $wallpaper_current -edge 1 $wallpaper_output"
    ["Emboss"]="magick $wallpaper_current -emboss 0x5 $wallpaper_output"
    ["Frame Raised"]="magick $wallpaper_current +raise 150 $wallpaper_output"
    ["Frame Sunk"]="magick $wallpaper_current -raise 150 $wallpaper_output"
    ["Negate"]="magick $wallpaper_current -negate $wallpaper_output"
    ["Oil Paint"]="magick $wallpaper_current -paint 4 $wallpaper_output"
    ["Posterize"]="magick $wallpaper_current -posterize 4 $wallpaper_output"
    ["Polaroid"]="magick $wallpaper_current -polaroid 0 $wallpaper_output"
    ["Sepia Tone"]="magick $wallpaper_current -sepia-tone 65% $wallpaper_output"
    ["Solarize"]="magick $wallpaper_current -solarize 80% $wallpaper_output"
    ["Sharpen"]="magick $wallpaper_current -sharpen 0x5 $wallpaper_output"
    ["Vignette"]="magick $wallpaper_current -vignette 0x3 $wallpaper_output"
    ["Vignette-black"]="magick $wallpaper_current -background black -vignette 0x3 $wallpaper_output"
    ["Zoomed"]="magick $wallpaper_current -gravity Center -extent 1:1 $wallpaper_output"
)

# Function to apply no effects
no-effects() {
    awww img "$wallpaper_current" $SWWW_PARAMS
    wait $!
    wallust run "$wallpaper_current" -s &&
    wait $!
    # Refresh rofi, waybar, wallust palettes
	sleep 2
	"$SCRIPTSDIR/Refresh.sh"

    notify-send -u low -i "$iDIR/ja.png" "No wallpaper" "effects applied"
    # copying wallpaper for rofi menu
    cp "$wallpaper_current" "$wallpaper_output"
    mkdir -p "$(dirname "$state_file")"
    printf '%s\n' "$wallpaper_current" > "$state_file"
}

# Function to run rofi menu
main() {
    # Populate rofi menu options
    options=("No Effects")
    for effect in "${!effects[@]}"; do
        [[ "$effect" != "No Effects" ]] && options+=("$effect")
    done

    choice=$(printf "%s\n" "${options[@]}" | LC_COLLATE=C sort | rofi -dmenu -i -config $rofi_theme)

    # Process user choice
    if [[ -n "$choice" ]]; then
        if [[ "$choice" == "No Effects" ]]; then
            no-effects
        elif [[ "${effects[$choice]+exists}" ]]; then
            # Apply selected effect
            notify-send -u normal -i "$iDIR/ja.png"  "Applying:" "$choice effects"
            eval "${effects[$choice]}"
            
            # intial kill process
            for pid in swaybg mpvpaper; do
            killall -SIGUSR1 "$pid"
            done

            sleep 1
            awww img "$wallpaper_output" $SWWW_PARAMS &

            sleep 2
  
            wallust run "$wallpaper_output" -s &
            sleep 1
            # Refresh rofi, waybar, wallust palettes
            "${SCRIPTSDIR}/Refresh.sh"
            mkdir -p "$(dirname "$state_file")"
            printf '%s\n' "$wallpaper_output" > "$state_file"
            notify-send -u low -i "$iDIR/ja.png" "$choice" "effects applied"
        else
            echo "Effect '$choice' not recognized."
        fi
    fi
}

# Check if rofi is already running and kill it
if pidof rofi > /dev/null; then
    pkill rofi
fi

main

sleep 1
