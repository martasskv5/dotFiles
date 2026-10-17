#!/usr/bin/env bash
# /* ---- Hyprlock Theme & Wallpaper Selector ---- */
# This script for selecting hyprlock themes and wallpapers
# To make hyprlock screenshot hyprlock & sleep 1 && grim ~/Pictures/hyprlock_screenshot.png

set -e

# ======================== CONFIGURATION ========================

HYPRLOCK_DIR="$HOME/.config/hyprlock"
THEMES_DIR="$HYPRLOCK_DIR/themes"
WALLPAPER_CONF="$HYPRLOCK_DIR/wallpaper.conf"
COLORS_CONF="$HYPRLOCK_DIR/colors.conf"
HYPRLOCK_CONF="$HOME/.config/hypr/hyprlock.conf"
MUSIC_WIDGET_CONF="$HYPRLOCK_DIR/music-widget.conf"

PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
WALLPAPER_DIR="$PICTURES_DIR/wallpapers"
WALLUST_PROFILE="$HOME/.config/wallust/profiles/hyprlock-only"

iDIR="$HOME/.config/swaync/images"
iDIRi="$HOME/.config/swaync/icons"

# ======================== ROFI THEME WITH GRID OVERRIDE ========================

# Create a temp rasi file that imports user's theme + forces grid layout
# This guarantees grid layout works regardless of what config-hyprlock.rasi contains
prepare_rofi_theme() {
    local user_theme="$HOME/.config/rofi/config-hyprlock.rasi"
    local fallback_theme="$HOME/.config/rofi/config-wallpaper.rasi"
    local temp_theme="/tmp/hyprlock-theme-selector.rasi"

    # Determine which user theme to base on
    local base_theme=""
    if [[ -f "$user_theme" ]]; then
        base_theme="$user_theme"
    elif [[ -f "$fallback_theme" ]]; then
        base_theme="$fallback_theme"
    fi

    if [[ -n "$base_theme" ]]; then
        # Copy user's theme and append grid overrides at the end
        # Later CSS rules override earlier ones
        cp "$base_theme" "$temp_theme"
        cat >> "$temp_theme" <<'RASI_EOF'

/* === Grid layout override (appended by hyprlock-theme-selector) === */
window {
    width: 100%;
}

listview {
    columns: 6;
    lines: 2;
    flow: horizontal;
    fixed-columns: true;
    spacing: 15px;
}

element {
    orientation: vertical;
    spacing: 5px;
}

element-text {
    horizontal-align: 0.5;
}
RASI_EOF
    else
        # Create minimal theme from scratch
        cat > "$temp_theme" <<'RASI_EOF'
configuration {
    font: "JetBrainsMono Nerd Font 10";
    show-icons: true;
}

window {
    width: 100%;
    height: 60%;
    border-radius: 12px;
    background-color: #1e1e2e;
    border: 2px solid #313244;
    padding: 20px;
}

mainbox {
    background-color: transparent;
    children: [inputbar, listview];
    spacing: 20px;
}

inputbar {
    background-color: #313244;
    border-radius: 8px;
    padding: 10px 15px;
    children: [prompt, entry];
    spacing: 10px;
}

prompt {
    background-color: transparent;
    text-color: #cdd6f4;
}

entry {
    background-color: transparent;
    text-color: #cdd6f4;
    placeholder: "Search";
    placeholder-color: #6c7086;
}

listview {
    background-color: transparent;
    columns: 6;
    lines: 2;
    flow: horizontal;
    fixed-columns: true;
    spacing: 15px;
    cycle: true;
    dynamic: true;
}

element {
    background-color: transparent;
    border-radius: 8px;
    padding: 10px;
    orientation: vertical;
    spacing: 5px;
}

element-icon {
    size: 20%;
    background-color: transparent;
    border-radius: 6px;
}

element-text {
    background-color: transparent;
    text-color: #cdd6f4;
    horizontal-align: 0.5;
    vertical-align: 0.5;
}

element selected {
    background-color: #313244;
    border: 2px solid #89b4fa;
}
RASI_EOF
    fi

    echo "$temp_theme"
}

# ======================== HELPERS ========================

notify() {
    local icon="$1" title="$2" message="$3"
    if [[ -f "$iDIR/$icon" ]]; then
        notify-send -i "$iDIR/$icon" "$title" "$message"
    elif [[ -f "$iDIRi/$icon" ]]; then
        notify-send -i "$iDIRi/$icon" "$title" "$message"
    else
        notify-send "$title" "$message"
    fi
}

# ======================== MONITOR / ICON SIZE ========================

get_focused_monitor() {
    local mon=""
    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        mon=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null | head -n1)
    fi
    echo "$mon"
}

get_icon_size_override() {
    local scale_factor="1"
    local monitor_height="1080"

    if command -v hyprctl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
        local focused_monitor=$(get_focused_monitor)
        if [[ -n "$focused_monitor" ]]; then
            scale_factor=$(hyprctl monitors -j 2>/dev/null | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .scale // 1' 2>/dev/null)
            monitor_height=$(hyprctl monitors -j 2>/dev/null | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .height // 1080' 2>/dev/null)
        fi
    fi

    if command -v bc &>/dev/null; then
        local icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc 2>/dev/null || echo "20")
        local adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
        echo "element-icon{size:${adjusted_icon_size}%;}"
    else
        echo "element-icon{size:20%;}"
    fi
}

# ======================== PREVIEW IMAGES ========================

get_theme_preview() {
    local theme_file="$1"
    local theme_name=$(basename "$theme_file" .conf)

    local possible_previews=(
        "$THEMES_DIR/${theme_name}.png"
        "$THEMES_DIR/previews/${theme_name}.png"
        "$THEMES_DIR/preview/${theme_name}.png"
        "$HYPRLOCK_DIR/previews/${theme_name}.png"
        "$HYPRLOCK_DIR/preview/${theme_name}.png"
    )

    for preview in "${possible_previews[@]}"; do
        if [[ -f "$preview" ]]; then
            echo "$preview"
            return 0
        fi
    done
    echo ""
}

# ======================== WALLPAPER MENU ========================

get_wallpapers() {
    find -L "$WALLPAPER_DIR" -type f \( \
        -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o \
        -iname "*.gif" -o -iname "*.bmp" -o -iname "*.tiff" -o \
        -iname "*.webp" \) -print0 2>/dev/null | sort -z
}

wallpaper_menu() {
    local current_wallpaper=""

    if [[ -f "$WALLPAPER_CONF" ]]; then
        current_wallpaper=$(grep -oP 'path\s*=\s*\K[^#]+' "$WALLPAPER_CONF" | xargs 2>/dev/null)
    fi

    mapfile -d '' WALLPAPERS < <(get_wallpapers)

    for wp_path in "${WALLPAPERS[@]}"; do
        [[ -z "$wp_path" ]] && continue
        local wp_name=$(basename "$wp_path")
        if [[ "$wp_path" == "$current_wallpaper" ]]; then
            printf "● %s\x00icon\x1f%s\n" "$wp_name" "$wp_path"
        else
            printf "  %s\x00icon\x1f%s\n" "$wp_name" "$wp_path"
        fi
    done
}

# ======================== THEME MENU ========================

get_normal_themes() {
    find "$THEMES_DIR" -maxdepth 1 -type f -name "*.conf" ! -name "static_*" -print0 2>/dev/null | sort -z
}

get_static_themes() {
    find "$THEMES_DIR" -maxdepth 1 -type f -name "static_*.conf" -print0 2>/dev/null | sort -z
}

theme_menu() {
    local current_theme=""

    if [[ -f "$HYPRLOCK_CONF" ]]; then
        current_theme=$(grep -oP 'source=\s*\K.*themes/[^\s]+' "$HYPRLOCK_CONF" | head -n1 | xargs 2>/dev/null)
    fi

    local has_normal=false
    local has_static=false

    # ─── Normal Themes ───
    mapfile -d '' NORMAL_THEMES < <(get_normal_themes)

    if [[ ${#NORMAL_THEMES[@]} -gt 0 ]]; then
        has_normal=true
        printf "📁 Normal Themes\x00nonselectable\x1ftrue\n"

        for theme_file in "${NORMAL_THEMES[@]}"; do
            [[ -z "$theme_file" ]] && continue
            local theme_name=$(basename "$theme_file" .conf)
            local preview=$(get_theme_preview "$theme_file")
            local display_name="$theme_name"

            if [[ "$theme_file" == "$current_theme" ]] || [[ "$THEMES_DIR/$theme_name.conf" == "$current_theme" ]]; then
                display_name="● $theme_name"
            fi

            if [[ -n "$preview" ]]; then
                printf "%s\x00icon\x1f%s\n" "$display_name" "$preview"
            else
                printf "%s\x00icon\x1fpreferences-desktop-theme\n" "$display_name"
            fi
        done
    fi

    # ─── Static Themes ───
    mapfile -d '' STATIC_THEMES < <(get_static_themes)

    if [[ ${#STATIC_THEMES[@]} -gt 0 ]]; then
        has_static=true

        if [[ "$has_normal" == true ]]; then
            printf " \x00nonselectable\x1ftrue\n"
        fi

        printf "🔒 Static Themes\x00nonselectable\x1ftrue\n"

        for theme_file in "${STATIC_THEMES[@]}"; do
            [[ -z "$theme_file" ]] && continue
            local theme_name=$(basename "$theme_file" .conf)
            local preview=$(get_theme_preview "$theme_file")
            local display_name="$theme_name"

            if [[ "$theme_file" == "$current_theme" ]] || [[ "$THEMES_DIR/$theme_name.conf" == "$current_theme" ]]; then
                display_name="● $theme_name"
            fi

            if [[ -n "$preview" ]]; then
                printf "%s\x00icon\x1f%s\n" "$display_name" "$preview"
            else
                printf "%s\x00icon\x1fpreferences-desktop-theme\n" "$display_name"
            fi
        done
    fi

    if [[ "$has_normal" == false && "$has_static" == false ]]; then
        printf "No themes found\x00nonselectable\x1ftrue\n"
    fi

    echo "DEBUG: normal=${#NORMAL_THEMES[@]}, static=${#STATIC_THEMES[@]}" >&2
}

# ======================== CONFIG UPDATERS ========================

update_wallpaper_conf() {
    local wallpaper_path="$1"
    mkdir -p "$(dirname "$WALLPAPER_CONF")"

    cat > "$WALLPAPER_CONF" <<EOF
\$wallpaper = $wallpaper_path  # Auto-generated by hyprlock-theme-selector
EOF
    echo "Updated wallpaper.conf"
}

generate_colors() {
    local wallpaper_path="$1"

    if ! command -v wallust &>/dev/null; then
        notify "error.png" "wallust missing" "Install wallust to generate color schemes"
        return 1
    fi

    if [[ ! -d "$WALLUST_PROFILE" ]]; then
        notify "error.png" "Wallust profile missing" "Profile not found at: $WALLUST_PROFILE"
        return 1
    fi

    wallust -d "$WALLUST_PROFILE" run -s "$wallpaper_path"

    if [[ $? -eq 0 ]]; then
        echo "Generated colors.conf"
        return 0
    else
        notify "error.png" "Wallust failed" "Failed to generate colors"
        return 1
    fi
}

update_hyprlock_conf() {
    local theme_file="$1"
    local theme_name=$(basename "$theme_file")
    local is_static="$2"

    if [[ ! -f "$HYPRLOCK_CONF.bak" ]]; then
        cp "$HYPRLOCK_CONF" "$HYPRLOCK_CONF.bak"
    fi

    local temp_conf=$(mktemp)
    local in_auto_block=false

    # Read line by line and skip auto-managed blocks
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "# === Hyprlock Theme & Wallpaper (Auto-managed) ===" ]] || \
           [[ "$line" == "# === Hyprlock Static Theme (Auto-managed) ===" ]]; then
            in_auto_block=true
            continue
        fi

        if [[ "$in_auto_block" == true ]]; then
            # Check if this line is part of the auto block
            if [[ "$line" == source=* ]] && \
               ([[ "$line" == *"hyprlock/themes/"* ]] || \
                # [[ "$line" == *"hyprlock/wallpaper.conf"* ]] || \
                [[ "$line" == *"hyprlock/colors.conf"* ]]) || \
                [[ "$line" == *"hyprlock/music-widget.conf"* ]]; then
                continue
            else
                in_auto_block=false
            fi
        fi

        # If we get here, the line is not in an auto block
        if [[ "$in_auto_block" == false ]]; then
            echo "$line" >> "$temp_conf"
        fi
    done < "$HYPRLOCK_CONF"

    # Add new auto-managed block
    if [[ "$is_static" != "true" ]]; then
        {
            echo ""
            echo "# === Hyprlock Theme & Wallpaper (Auto-managed) ==="
            echo "source= $theme_file"
            # echo "source= $WALLPAPER_CONF"
            echo "source= $COLORS_CONF"
            echo "source= $MUSIC_WIDGET_CONF"
        } >> "$temp_conf"
    else
        {
            echo ""
            echo "# === Hyprlock Static Theme (Auto-managed) ==="
            echo "source= $theme_file"
        } >> "$temp_conf"
    fi

    mv "$temp_conf" "$HYPRLOCK_CONF"
    echo "Updated hyprlock.conf with: $theme_name (static=$is_static)"
}

# ======================== APPLY FUNCTIONS ========================

apply_normal_theme() {
    local theme_file="$1"
    local theme_name=$(basename "$theme_file" .conf)

    echo "Selected: $theme_name"

    local rofi_config=$(prepare_rofi_theme)
    local rofi_override=$(get_icon_size_override)
    local rofi_cmd="rofi -i -show -dmenu -config $rofi_config -theme-str $rofi_override"

    local wallpaper_choice=$(wallpaper_menu | $rofi_cmd -p "🖼️ Wallpaper")

    if [[ -z "$wallpaper_choice" ]]; then
        echo "No wallpaper selected. Aborting."
        return 1
    fi

    wallpaper_choice=$(echo "$wallpaper_choice" | sed 's/^● //' | sed 's/^  //')

    local wallpaper_path=$(find -L "$WALLPAPER_DIR" -type f -iname "$wallpaper_choice" -print -quit)

    if [[ -z "$wallpaper_path" ]]; then
        wallpaper_path=$(find -L "$WALLPAPER_DIR" -type f -iname "$(basename "$wallpaper_choice")" -print -quit)
    fi

    if [[ -z "$wallpaper_path" || ! -f "$wallpaper_path" ]]; then
        notify "error.png" "Wallpaper not found" "$wallpaper_choice"
        return 1
    fi

    update_wallpaper_conf "$wallpaper_path"
    generate_colors "$wallpaper_path"
    update_hyprlock_conf "$theme_file" "false"
    notify "success.png" "Hyprlock Updated" "Theme: $theme_name\nWallpaper: $(basename "$wallpaper_path")"

    return 0
}

apply_static_theme() {
    local theme_file="$1"
    local theme_name=$(basename "$theme_file" .conf)

    echo "Selected static: $theme_name"

    update_hyprlock_conf "$theme_file" "true"

    # Verify the file was written
    if grep -qF "$theme_file" "$HYPRLOCK_CONF"; then
        echo "DEBUG: Static theme written to hyprlock.conf ✓" >&2
        tail -n 3 "$HYPRLOCK_CONF" >&2
    else
        echo "DEBUG: ERROR - Static theme NOT found in hyprlock.conf!" >&2
        echo "DEBUG: File contents:" >&2
        cat "$HYPRLOCK_CONF" >&2
    fi

    notify "success.png" "Hyprlock Updated" "Static theme: $theme_name"

    return 0
}

# ======================== MAIN ========================

main_menu() {
    local rofi_config=$(prepare_rofi_theme)
    local rofi_override=$(get_icon_size_override)
    local rofi_cmd="rofi -i -show -dmenu -config $rofi_config -theme-str $rofi_override"

    local choice=$(theme_menu | $rofi_cmd -p "🔒 Hyprlock Theme")

    if [[ -z "$choice" ]]; then
        echo "No selection. Exiting."
        exit 0
    fi

    # Skip headers and spacers
    if [[ "$choice" == "📁 Normal Themes" ]] || \
       [[ "$choice" == "🔒 Static Themes" ]] || \
       [[ "$choice" == " " ]] || \
       [[ "$choice" == "No themes found"* ]]; then
        echo "Header/spacer selected. Exiting."
        exit 0
    fi

    # Strip indicator and whitespace
    choice=$(echo "$choice" | sed 's/^● //' | sed 's/^  //' | xargs)

    echo "DEBUG: choice='$choice'" >&2

    local theme_file=""

    if [[ "$choice" == static_* ]]; then
        theme_file=$(find "$THEMES_DIR" -maxdepth 1 -type f -name "${choice}.conf" -print -quit)
        if [[ -n "$theme_file" && -f "$theme_file" ]]; then
            apply_static_theme "$theme_file"
        else
            notify "error.png" "Not found" "${choice}.conf"
            exit 1
        fi
    else
        theme_file=$(find "$THEMES_DIR" -maxdepth 1 -type f -name "${choice}.conf" -print -quit)
        if [[ -n "$theme_file" && -f "$theme_file" ]]; then
            apply_normal_theme "$theme_file"
        else
            notify "error.png" "Not found" "${choice}.conf"
            exit 1
        fi
    fi
}

setup_check() {
    [[ ! -d "$HYPRLOCK_DIR" ]] && mkdir -p "$HYPRLOCK_DIR"
    [[ ! -d "$THEMES_DIR" ]] && mkdir -p "$THEMES_DIR"

    if [[ ! -d "$WALLPAPER_DIR" ]]; then
        notify "error.png" "Wallpaper dir missing" "$WALLPAPER_DIR"
        exit 1
    fi

    if [[ ! -f "$HYPRLOCK_CONF" ]]; then
        notify "error.png" "hyprlock.conf missing" "$HYPRLOCK_CONF"
        exit 1
    fi

    if ! command -v rofi &>/dev/null; then
        notify "error.png" "rofi missing" "Install rofi"
        exit 1
    fi
}

main() {
    setup_check
    main_menu
}

if pidof rofi >/dev/null; then
    pkill rofi
    exit 0
fi

main
