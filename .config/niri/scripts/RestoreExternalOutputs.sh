#!/usr/bin/env bash

set -euo pipefail

session_id="${XDG_SESSION_ID:-}"
profile_file="${NIRI_LOCK_OUTPUT_STATE_FILE:-}"

if [[ -z "$session_id" || -z "$profile_file" || ! -f "$profile_file" ]]; then
	exit 0
fi

locked_hint=""
attempts=0

while (( attempts < 50 )); do
	locked_hint="$(loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null || true)"
	if [[ "$locked_hint" == "yes" ]]; then
		break
	fi

	sleep 0.1
	((attempts += 1))
done

if [[ "$locked_hint" != "yes" ]]; then
	exit 0
fi

while [[ "$(loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null || echo no)" == "yes" ]]; do
	sleep 1
done

previous_profile="$(cat "$profile_file" 2>/dev/null || true)"

if [[ -n "$previous_profile" ]]; then
	kanshictl switch "$previous_profile" >/dev/null 2>&1 || true
fi

rm -f "$profile_file"
