#!/usr/bin/env bash
set -euo pipefail

# Windows-like behavior:
# - First press for a window+direction snaps to half width toward that side.
# - Repeating the same direction moves to the adjacent monitor.
# - Switching direction (left -> right or right -> left) re-snaps on the current monitor first.
# The state is only trusted while the focused column still looks half-sized on the same output.

dir="${1:-}"
case "$dir" in
  left|right|up|down) ;;
  *)
    echo "Usage: $0 <left|right|up|down>" >&2
    exit 1
    ;;
esac

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/niri"
state_file="$cache_dir/snap-move-state"
mkdir -p "$cache_dir"

focused_json="$(niri msg -j focused-window 2>/dev/null || true)"
win_id="$(printf '%s' "$focused_json" | jq -r '.id // empty' 2>/dev/null || true)"
current_width="$(printf '%s' "$focused_json" | jq -r '.layout.window_size[0] // empty' 2>/dev/null || true)"

focused_output_json="$(niri msg -j focused-output 2>/dev/null || true)"
output_name="$(printf '%s' "$focused_output_json" | jq -r '.name // empty' 2>/dev/null || true)"
output_width="$(printf '%s' "$focused_output_json" | jq -r '.logical.width // empty' 2>/dev/null || true)"
output_x="$(printf '%s' "$focused_output_json" | jq -r '.logical.x // empty' 2>/dev/null || true)"
output_y="$(printf '%s' "$focused_output_json" | jq -r '.logical.y // empty' 2>/dev/null || true)"
output_height="$(printf '%s' "$focused_output_json" | jq -r '.logical.height // empty' 2>/dev/null || true)"
outputs_json="$(niri msg -j outputs 2>/dev/null || true)"
monitor_count="$(niri msg -j outputs 2>/dev/null | jq 'length' 2>/dev/null || echo 1)"

# If nothing is focused, do nothing.
[ -n "$win_id" ] || exit 0

last_id=""
last_dir=""
last_phase="snap"
last_output=""
last_output_width=""
if [ -f "$state_file" ]; then
  IFS=' ' read -r last_id last_dir last_phase last_output last_output_width < "$state_file" || true
fi

is_half_sized() {
  case "$current_width:$output_width" in
    ("":*) return 1 ;;
    (*:"") return 1 ;;
  esac

  min_width=$((output_width * 30 / 100))
  max_width=$((output_width * 70 / 100))

  [ "$current_width" -ge "$min_width" ] && [ "$current_width" -le "$max_width" ]
}

is_maximized_like() {
  case "$current_width:$output_width" in
    ("":*) return 1 ;;
    (*:"") return 1 ;;
  esac

  # Heuristic: in maximized state the focused column is near full output width.
  [ "$current_width" -ge $((output_width * 85 / 100)) ]
}

refresh_focused_width() {
  focused_json="$(niri msg -j focused-window 2>/dev/null || true)"
  current_width="$(printf '%s' "$focused_json" | jq -r '.layout.window_size[0] // empty' 2>/dev/null || true)"
}

ensure_not_maximized() {
  if is_maximized_like; then
    niri msg action maximize-column >/dev/null 2>&1 || true
    sleep 0.03
    refresh_focused_width
  fi
}

snap_to_side() {
  # 1. Un-maximize if needed
  if is_maximized_like; then
    niri msg action maximize-column >/dev/null 2>&1 || true
    sleep 0.05 # Slightly longer sleep to ensure Niri registers the layout change
  fi

  # 2. Set the width to 50%
  niri msg action set-column-width "50%" >/dev/null 2>&1 || true

  # 3. Move the window relative to its neighbors
  # Instead of 'to-first/last', we move it in the direction you pressed.
  # This 'pushes' the window to the edge of the current viewport.
  if [ "$dir" = "left" ]; then
    niri msg action move-column-left >/dev/null 2>&1 || true
  else
    niri msg action move-column-right >/dev/null 2>&1 || true
  fi
}


move_to_monitor_side() {
  niri msg action "move-column-to-monitor-$dir" >/dev/null 2>&1 || \
    niri msg action "move-window-to-monitor-$dir" >/dev/null 2>&1 || true
}

has_monitor_in_direction() {
  case "$dir" in
    up)
      printf '%s' "$outputs_json" | jq -e --argjson x "$output_x" --argjson y "$output_y" --argjson w "$output_width" --argjson h "$output_height" '
        any(.[]; .logical.y < $y and (.logical.x < ($x + $w)) and ((.logical.x + .logical.width) > $x))
      ' >/dev/null 2>&1
      ;;
    down)
      printf '%s' "$outputs_json" | jq -e --argjson x "$output_x" --argjson y "$output_y" --argjson w "$output_width" --argjson h "$output_height" '
        any(.[]; .logical.y > $y and (.logical.x < ($x + $w)) and ((.logical.x + .logical.width) > $x))
      ' >/dev/null 2>&1
      ;;
    left)
      printf '%s' "$outputs_json" | jq -e --argjson x "$output_x" --argjson y "$output_y" --argjson w "$output_width" --argjson h "$output_height" '
        any(.[]; .logical.x < $x and (.logical.y < ($y + $h)) and ((.logical.y + .logical.height) > $y))
      ' >/dev/null 2>&1
      ;;
    right)
      printf '%s' "$outputs_json" | jq -e --argjson x "$output_x" --argjson y "$output_y" --argjson w "$output_width" --argjson h "$output_height" '
        any(.[]; .logical.x > $x and (.logical.y < ($y + $h)) and ((.logical.y + .logical.height) > $y))
      ' >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

maximize_or_move_vertical() {
  if ! is_maximized_like; then
    # From snapped/normal state, first vertical press maximizes.
    niri msg action maximize-column >/dev/null 2>&1 || true
    return
  fi

  if [ "$monitor_count" -gt 1 ] && has_monitor_in_direction; then
    niri msg action "move-column-to-monitor-$dir" >/dev/null 2>&1 || \
      niri msg action "move-window-to-monitor-$dir" >/dev/null 2>&1 || true
    return
  fi

  # No monitor above/below: move to workspace instead.
  niri msg action "move-column-to-workspace-$dir" >/dev/null 2>&1 || \
    niri msg action "move-window-to-workspace-$dir" >/dev/null 2>&1 || true
}

if [ "$dir" = "up" ] || [ "$dir" = "down" ]; then
  maximize_or_move_vertical
  printf '%s %s %s %s %s\n' "$win_id" "$dir" "vertical" "$output_name" "$output_width" > "$state_file"
  exit 0
fi

if [ "$monitor_count" -gt 1 ] && [ "$last_id" = "$win_id" ] && [ "$last_dir" = "$dir" ] && [ "$last_phase" = "snap" ] && [ "$last_output" = "$output_name" ] && [ "$last_output_width" = "$output_width" ] && is_half_sized; then
  move_to_monitor_side
  next_phase="monitor"
else
  snap_to_side
  next_phase="snap"
fi

printf '%s %s %s %s %s\n' "$win_id" "$dir" "$next_phase" "$output_name" "$output_width" > "$state_file"
