#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

set -euo pipefail

# --- WAYLAND DISPLAY FIX ---
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

# --- DEBUG LOG ---
DEBUG_LOG="/tmp/niri-lockscreen-debug.log"
exec >> "$DEBUG_LOG" 2>&1
set -x

echo "=== LockScreen started at $(date) ==="

# --- STATE FILES ---
current_profile_file="$(mktemp -t niri-lock-kanshi-profile.XXXXXX)"
outputs_state_file="$(mktemp -t niri-lock-outputs-state.XXXXXX.json)"

echo "Profile file: $current_profile_file"
echo "Outputs state file: $outputs_state_file"

# Save current kanshi profile
current_profile="$(kanshictl status 2>/dev/null | sed -n 's/^Current profile: //p' | head -n1)"
if [[ -z "$current_profile" || "$current_profile" == '<anonymous profile '* ]]; then
	current_profile="docked"
fi
printf '%s\n' "$current_profile" > "$current_profile_file"
echo "Current kanshi profile: $current_profile"

# Save FULL output state for all outputs
outputs_json="$(niri msg --json outputs 2>/dev/null || echo '{}')"
echo "$outputs_json" > "$outputs_state_file"
echo "Saved outputs state to $outputs_state_file"

# Ensure weather cache is up-to-date before locking
bash "$HOME/.config/niri/UserScripts/WeatherWrap.sh" >/dev/null 2>&1 || true

# Switch kanshi to lock profile
kanshictl switch lock >/dev/null 2>&1 || true
echo "Switched kanshi to lock profile"

# --- DETECT TARGET MONITOR ---
outputs_json="$(niri msg --json outputs 2>/dev/null || echo '{}')"
all_enabled_outputs="$(echo "$outputs_json" | jq -r 'to_entries[] | select(.value.logical != null) | .key' 2>/dev/null || true)"

edp_enabled="$(echo "$outputs_json" | jq -r 'to_entries[] | select(.key | test("^eDP-"; "i")) | select(.value.logical != null) | .key' 2>/dev/null | head -n1 || true)"
edp_exists="$(echo "$outputs_json" | jq -r 'to_entries[] | select(.key | test("^eDP-"; "i")) | .key' 2>/dev/null | head -n1 || true)"

focused_output_json="$(niri msg --json focused-output 2>/dev/null || echo '{}')"
focused_output=""
if echo "$focused_output_json" | jq -e '.name' >/dev/null 2>&1; then
	focused_output="$(echo "$focused_output_json" | jq -r '.name' 2>/dev/null || true)"
elif echo "$focused_output_json" | jq -e 'to_entries[0].key' >/dev/null 2>&1; then
	focused_output="$(echo "$focused_output_json" | jq -r 'to_entries[0].key' 2>/dev/null || true)"
fi
if [[ -z "$focused_output" || "$focused_output" == "null" ]]; then
	focused_output="$(niri msg focused-output 2>/dev/null | grep -oP '\(([^)]+)\)' | tr -d '()' | head -n1 || true)"
fi

# Determine target and outputs to disable
TARGET_MONITOR=""
OUTPUTS_TO_DISABLE=""

if [[ -n "$edp_enabled" ]]; then
	TARGET_MONITOR="$edp_enabled"
	OUTPUTS_TO_DISABLE="$(echo "$all_enabled_outputs" | grep -iv "^eDP-" || true)"
elif [[ -n "$edp_exists" && -n "$focused_output" ]]; then
	TARGET_MONITOR="$focused_output"
	OUTPUTS_TO_DISABLE="$(echo "$all_enabled_outputs" | grep -ivx "$focused_output" || true)"
elif [[ -n "$focused_output" ]]; then
	TARGET_MONITOR="$focused_output"
	OUTPUTS_TO_DISABLE="$(echo "$all_enabled_outputs" | grep -ivx "$focused_output" || true)"
else
	TARGET_MONITOR="$(echo "$all_enabled_outputs" | head -n1 || true)"
	OUTPUTS_TO_DISABLE="$(echo "$all_enabled_outputs" | grep -ivx "$TARGET_MONITOR" || true)"
fi

echo "Target monitor: $TARGET_MONITOR"
echo "Outputs to disable: $OUTPUTS_TO_DISABLE"

# Write target for hyprlock
echo "\$TARGET_MONITOR = $TARGET_MONITOR" > "$HOME/.config/hyprlock/target-monitor.conf"

# Disable non-target outputs using wlopm
echo "Disabling non-target outputs..."
while IFS= read -r out; do
	[[ -n "$out" ]] || continue
	echo "Disabling $out..."
	wlopm --off "$out" 2>&1 || echo "wlopm --off failed for $out"
done <<< "$OUTPUTS_TO_DISABLE"

sleep 0.3

# --- START HYPRLOCK IN BACKGROUND ---
echo "Starting hyprlock in background..."
hyprlock -c "$HOME/.config/hypr/hyprlock.conf" >/dev/null 2>&1 &
HYPRLOCK_PID=$!
echo "Hyprlock PID: $HYPRLOCK_PID"

# Wait for hyprlock to actually start
sleep 0.5
if ! kill -0 "$HYPRLOCK_PID" 2>/dev/null; then
	echo "Hyprlock failed to start, restoring outputs..."
else
	echo "Waiting for hyprlock to exit..."
	while kill -0 "$HYPRLOCK_PID" 2>/dev/null; do
		sleep 0.5
	done
	echo "Hyprlock exited at $(date)"
fi

# --- RESTORE OUTPUTS ---
echo "=== Restoring outputs ==="

if [[ -f "$outputs_state_file" ]]; then
	echo "Restoring exact output configuration from saved state..."

	# current_mode is an INDEX into the modes array, not an object
	while IFS= read -r entry_json; do
		[[ -n "$entry_json" ]] || continue

		out_name="$(echo "$entry_json" | jq -r '.key')"
		logical="$(echo "$entry_json" | jq -r '.value.logical')"
		current_mode_idx="$(echo "$entry_json" | jq -r '.value.current_mode')"
		transform="$(echo "$entry_json" | jq -r '.value.transform // "normal"')"

		echo "--- Restoring $out_name ---"

		# Power on the output first (safe even if already on, e.g. target monitor)
		wlopm --on "$out_name" 2>&1 || echo "wlopm --on failed for $out_name"
		sleep 0.3

		x="$(echo "$logical" | jq -r '.x // 0')"
		y="$(echo "$logical" | jq -r '.y // 0')"
		scale="$(echo "$logical" | jq -r '.scale // 1')"

		# Look up mode from modes array using current_mode index
		if [[ -n "$current_mode_idx" && "$current_mode_idx" != "null" ]]; then
			mode_json="$(echo "$entry_json" | jq -r ".value.modes[$current_mode_idx] // empty")"
			if [[ -n "$mode_json" && "$mode_json" != "null" ]]; then
				mode_w="$(echo "$mode_json" | jq -r '.width')"
				mode_h="$(echo "$mode_json" | jq -r '.height')"
				mode_refresh="$(echo "$mode_json" | jq -r '.refresh_rate')"
				if [[ -n "$mode_w" && "$mode_w" != "null" && -n "$mode_h" && "$mode_h" != "null" && -n "$mode_refresh" && "$mode_refresh" != "null" ]]; then
					# Convert refresh_rate from mHz to Hz (niri uses Hz with decimal)
					mode_refresh_hz="$(echo "scale=3; $mode_refresh / 1000" | bc)"
					echo "  Mode: ${mode_w}x${mode_h}@${mode_refresh_hz}"
					niri msg output "$out_name" mode "${mode_w}x${mode_h}@${mode_refresh_hz}" 2>&1 || echo "  Mode failed"
					sleep 0.3
				fi
			fi
		fi

		# Apply position
		echo "  Position: ${x},${y}"
		niri msg output "$out_name" position "${x},${y}" 2>&1 || echo "  Position failed"
		sleep 0.3

		# Apply scale
		echo "  Scale: $scale"
		niri msg output "$out_name" scale "$scale" 2>&1 || echo "  Scale failed"
		sleep 0.3

		# Apply transform
		transform_lower="$(echo "$transform" | tr '[:upper:]' '[:lower:]')"
		if [[ "$transform_lower" != "normal" ]]; then
			echo "  Transform: $transform_lower"
			niri msg output "$out_name" transform "$transform_lower" 2>&1 || echo "  Transform failed"
			sleep 0.3
		fi

		echo "  Done with $out_name"
		sleep 0.3
	done < <(jq -r 'to_entries[] | select(.value.logical != null) | @json' "$outputs_state_file" 2>/dev/null)

	echo "Output restore complete"
fi

# Switch kanshi back
previous_profile="$(cat "$current_profile_file" 2>/dev/null || true)"
if [[ -n "$previous_profile" ]]; then
	echo "Switching kanshi to $previous_profile"
	kanshictl switch "$previous_profile" 2>&1 || echo "kanshictl switch failed"
	sleep 0.5
fi

# Verify
outputs_json="$(niri msg --json outputs 2>/dev/null || echo '{}')"
echo "Final output state:"
echo "$outputs_json" | jq -r 'to_entries[] | select(.value.logical != null) | "\(.key): pos=\(.value.logical.x),\(.value.logical.y) size=\(.value.logical.width)x\(.value.logical.height)"' 2>/dev/null || true

# Clean up
rm -f "$current_profile_file"
rm -f "$outputs_state_file"

echo "=== LockScreen finished at $(date) ==="