#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Wallust: derive colors from the current wallpaper and update templates
# Usage: WallustSwww.sh [absolute_path_to_wallpaper]

set -euo pipefail

# Inputs and paths
passed_path="${1:-}"
rofi_link="$HOME/.config/rofi/.current_wallpaper"
wallpaper_current="$HOME/.config/niri/wallpaper_effects/.wallpaper_current"

read_wallpaper_from_query() {
  local monitor="$1"
  awww query | awk -v mon="$monitor" '
    /^Monitor/ {
      cur=$2
      gsub(":", "", cur)
    }
    /image:/ && cur==mon {
      sub(/^.*image: /,"")
      print
      exit
    }
  '
}

# Helper: get focused monitor name (prefer JSON)
get_focused_monitor() {
  if command -v niri >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    niri msg -j outputs 2>/dev/null | jq -r '.[] | select((.is_focused // .focused // false) == true) | .name' | head -n1
    return
  fi
  if command -v jq >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
    hyprctl monitors -j | jq -r '.[] | select(.focused) | .name' | head -n1
  elif command -v hyprctl >/dev/null 2>&1; then
    hyprctl monitors | awk '/^Monitor/{name=$2} /focused: yes/{print name}'
  fi
}

# Determine wallpaper_path
wallpaper_path=""
if [[ -n "$passed_path" && -f "$passed_path" ]]; then
  wallpaper_path="$passed_path"
else
  # Try to read from awww query output for the focused monitor
  current_monitor="$(get_focused_monitor)"
  wallpaper_path="$(read_wallpaper_from_query "$current_monitor")"
fi

if [[ -z "${wallpaper_path:-}" || ! -f "$wallpaper_path" ]]; then
  # Nothing to do; avoid failing loudly so callers can continue
  exit 0
fi

# Update helpers that depend on the path
ln -sf "$wallpaper_path" "$rofi_link" || true
mkdir -p "$(dirname "$wallpaper_current")"
cp -f "$wallpaper_path" "$wallpaper_current" || true

# Ensure Ghostty directory exists so Wallust can write target even if Ghostty isn't installed
mkdir -p "$HOME/.config/ghostty" || true
wait_for_templates() {
  local start_ts="$1"
  shift
  local files=("$@")
  for _ in {1..50}; do
    local ready=true
    for file in "${files[@]}"; do
      if [[ ! -s "$file" ]]; then
        ready=false
        break
      fi
      local mtime
      mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
      if (( mtime < start_ts )); then
        ready=false
        break
      fi
    done
    $ready && return 0
    sleep 0.1
  done
  return 1
}

# Run wallust (silent) to regenerate templates defined in ~/.config/wallust/wallust.toml
# -s is used in this repo to keep things quiet and avoid extra prompts
start_ts=$(date +%s)
wallust run -s "$wallpaper_path" || true
wallust_targets=(
  "$HOME/.config/rofi/wallust/colors-rofi.rasi"
)
wait_for_templates "$start_ts" "${wallust_targets[@]}" || true

# Normalize Ghostty palette syntax in case ':' was used by older files
if [ -f "$HOME/.config/ghostty/wallust.conf" ]; then
  sed -i -E 's/^(\s*palette\s*=\s*)([0-9]{1,2}):/\1\2=/' "$HOME/.config/ghostty/wallust.conf" 2>/dev/null || true
fi

# Light wait for Ghostty colors file to be present then signal Ghostty to reload (SIGUSR2)
for _ in 1 2 3; do
  [ -s "$HOME/.config/ghostty/wallust.conf" ] && break
  sleep 0.1
done
if pidof ghostty >/dev/null; then
  for pid in $(pidof ghostty); do kill -SIGUSR2 "$pid" 2>/dev/null || true; done
fi

# Refresh Noctalia / shell helpers if available
if [ -x "$HOME/.config/niri/scripts/Refresh.sh" ]; then
  "$HOME/.config/niri/scripts/Refresh.sh" >/dev/null 2>&1 || true
fi
