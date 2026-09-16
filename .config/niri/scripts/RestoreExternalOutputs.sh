#!/usr/bin/env bash

set -euo pipefail

# --- DEBUG LOG ---
DEBUG_LOG="/tmp/niri-restore-debug.log"
exec >> "$DEBUG_LOG" 2>&1
set -x

echo "=== RestoreExternalOutputs started at $(date) ==="

session_id="${XDG_SESSION_ID:-}"
profile_file="${NIRI_LOCK_KANSHI_PROFILE:-}"
outputs_state_file="${NIRI_LOCK_OUTPUTS_STATE:-}"

echo "Session ID: $session_id"
echo "Profile file: $profile_file"
echo "Outputs state file: $outputs_state_file"

if [[ -z "$session_id" || -z "$profile_file" || ! -f "$profile_file" ]]; then
	echo "Missing required files, exiting"
	exit 0
fi

# --- WAIT FOR LOCK ---
# Hyprlock doesn't use loginctl lock-session, so LockedHint stays "no".
# Instead, we detect lock by checking if hyprlock process is running.
# We wait up to 30 seconds for hyprlock to start.

echo "Waiting for hyprlock to start..."
lock_attempts=0
while (( lock_attempts < 300 )); do
	if pgrep -x hyprlock >/dev/null 2>&1; then
		echo "Hyprlock detected as running"
		break
	fi
	sleep 0.1
	((lock_attempts += 1))
done

if ! pgrep -x hyprlock >/dev/null 2>&1; then
	echo "Hyprlock not detected after $lock_attempts attempts, cleaning up"
	rm -f "$profile_file"
	rm -f "$outputs_state_file"
	exit 0
fi

# --- WAIT FOR UNLOCK ---
# Wait for hyprlock process to exit (user unlocked)
echo "Waiting for hyprlock to exit (user unlock)..."
while pgrep -x hyprlock >/dev/null 2>&1; do
	sleep 0.5
done

echo "User unlocked at $(date)"

# --- RESTORE SEQUENCE ---
# For outputs disabled with "niri msg output off", we need a FULL MODESET:
# 1. Set MODE first (this implicitly enables the output)
# 2. Set POSITION
# 3. Set SCALE
# 4. Set TRANSFORM
# We do NOT use "niri msg output on" - it doesn't work for DRM-disabled outputs.

if [[ -f "$outputs_state_file" ]]; then
	echo "Restoring outputs from saved state..."

	# Read each output's saved configuration and restore it
	jq -r 'to_entries[] | select(.value.logical != null) | @json' "$outputs_state_file" 2>/dev/null | \
	while IFS= read -r entry_json; do
		[[ -n "$entry_json" ]] || continue

		out_name="$(echo "$entry_json" | jq -r '.key')"
		logical="$(echo "$entry_json" | jq -r '.value.logical')"
		current_mode="$(echo "$entry_json" | jq -r '.value.current_mode // empty')"
		transform="$(echo "$entry_json" | jq -r '.value.transform // "normal"')"

		echo "=== Restoring $out_name ==="

		# Extract values
		x="$(echo "$logical" | jq -r '.x // 0')"
		y="$(echo "$logical" | jq -r '.y // 0')"
		scale="$(echo "$logical" | jq -r '.scale // 1')"

		# Step 1: Set MODE (this implicitly enables the output if it was disabled)
		if [[ -n "$current_mode" && "$current_mode" != "null" ]]; then
			mode_w="$(echo "$current_mode" | jq -r '.width')"
			mode_h="$(echo "$current_mode" | jq -r '.height')"
			mode_refresh="$(echo "$current_mode" | jq -r '.refresh_rate')"
			if [[ -n "$mode_w" && "$mode_w" != "null" && -n "$mode_h" && "$mode_h" != "null" && -n "$mode_refresh" && "$mode_refresh" != "null" ]]; then
				echo "Setting mode: ${mode_w}x${mode_h}@${mode_refresh}"
				niri msg output "$out_name" mode "${mode_w}x${mode_h}@${mode_refresh}" 2>&1 || echo "  Failed to set mode for $out_name"
				sleep 0.3
			fi
		fi

		# Step 2: Set POSITION
		echo "Setting position: ${x},${y}"
		niri msg output "$out_name" position "${x},${y}" 2>&1 || echo "  Failed to set position for $out_name"
		sleep 0.3

		# Step 3: Set SCALE
		echo "Setting scale: $scale"
		niri msg output "$out_name" scale "$scale" 2>&1 || echo "  Failed to set scale for $out_name"
		sleep 0.3

		# Step 4: Set TRANSFORM (if not normal)
		transform_lower="$(echo "$transform" | tr '[:upper:]' '[:lower:]')"
		if [[ "$transform_lower" != "normal" ]]; then
			echo "Setting transform: $transform_lower"
			niri msg output "$out_name" transform "$transform_lower" 2>&1 || echo "  Failed to set transform for $out_name"
			sleep 0.3
		fi

		echo "Done restoring $out_name"
		sleep 0.5
	done

	echo "All outputs restored from saved state"
fi

# Step 5: Switch kanshi profile to keep it in sync
previous_profile="$(cat "$profile_file" 2>/dev/null || true)"
echo "Previous kanshi profile: $previous_profile"

if [[ -n "$previous_profile" ]]; then
	echo "Switching kanshi to $previous_profile"
	kanshictl switch "$previous_profile" 2>&1 || echo "kanshictl switch failed"
	sleep 0.5
fi

# Verify outputs are restored with correct positions
outputs_json="$(niri msg --json outputs 2>/dev/null || echo '{}')"
echo "Currently enabled outputs and positions:"
echo "$outputs_json" | jq -r 'to_entries[] | select(.value.logical != null) | "\(.key): pos=\(.value.logical.x),\(.value.logical.y) size=\(.value.logical.width)x\(.value.logical.height) scale=\(.value.logical.scale)"' 2>/dev/null || true

# Clean up
rm -f "$profile_file"
rm -f "$outputs_state_file"

echo "=== RestoreExternalOutputs finished at $(date) ==="