#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##

set -euo pipefail

current_profile_file="$(mktemp -t niri-lock-kanshi-profile.XXXXXX)"
current_profile="$(kanshictl status 2>/dev/null | sed -n 's/^Current profile: //p' | head -n1)"

if [[ -z "$current_profile" || "$current_profile" == '<anonymous profile '* ]]; then
	current_profile="docked"
fi

printf '%s\n' "$current_profile" > "$current_profile_file"

# Ensure weather cache is up-to-date before locking (Waybar/lockscreen readers)
bash "$HOME/.config/niri/UserScripts/WeatherWrap.sh" >/dev/null 2>&1

kanshictl switch lock >/dev/null 2>&1 || true

loginctl lock-session

NIRI_LOCK_OUTPUT_STATE_FILE="$current_profile_file" nohup "$HOME/.config/niri/scripts/RestoreExternalOutputs.sh" >/dev/null 2>&1 &
