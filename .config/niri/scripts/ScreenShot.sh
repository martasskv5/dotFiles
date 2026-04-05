#!/usr/bin/env bash
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# Screenshots scripts

# variables
time=$(date "+%d-%b_%H-%M-%S")
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
dir="$PICTURES_DIR/Screenshots"
file="Screenshot_${time}_${RANDOM}.png"

get_focused_window() {
	niri msg -j focused-window 2>/dev/null || true
}

get_focused_output() {
	niri msg -j focused-output 2>/dev/null || true
}

sanitize_name() {
	printf '%s' "$1" | tr '/:<>"\\|?*' '_' | tr -s '[:space:]' '_'
}

iDIR="$HOME/.config/swaync/icons"
iDoR="$HOME/.config/swaync/images"
sDIR="$HOME/.config/niri/scripts"

focused_window_json=$(get_focused_window)
active_window_class=$(printf '%s' "$focused_window_json" | jq -r '.app_id // .title // "window"' 2>/dev/null | head -n1)
active_window_class=$(sanitize_name "$active_window_class")
active_window_file="Screenshot_${time}_${active_window_class}.png"
active_window_path="${dir}/${active_window_file}"

notify_cmd_base="notify-send -t 10000 -A action1=Open -A action2=Delete -h string:x-canonical-private-synchronous:shot-notify"
notify_cmd_shot="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_shot_win="${notify_cmd_base} -i ${iDIR}/picture.png "
notify_cmd_NOT="notify-send -u low -i ${iDoR}/note.png "

# notify and view screenshot
notify_view() {
    if [[ "$1" == "active" ]]; then
        if [[ -e "${active_window_path}" ]]; then
			"${sDIR}/Sounds.sh" --screenshot        
            resp=$(timeout 5 ${notify_cmd_shot_win} " Screenshot of:" " ${active_window_class} Saved.")
            case "$resp" in
				action1)
					xdg-open "${active_window_path}" &
					;;
				action2)
					rm "${active_window_path}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot of:" " ${active_window_class} NOT Saved."
            "${sDIR}/Sounds.sh" --error
        fi

    elif [[ "$1" == "swappy" ]]; then
		"${sDIR}/Sounds.sh" --screenshot
		resp=$(${notify_cmd_shot} " Screenshot:" " Captured by Swappy")
		case "$resp" in
			action1)
				swappy -f - <"$tmpfile"
				;;
			action2)
				rm "$tmpfile"
				;;
		esac

    else
        local check_file="${dir}/${file}"
        if [[ -e "$check_file" ]]; then
            "${sDIR}/Sounds.sh" --screenshot
            resp=$(timeout 5 ${notify_cmd_shot} " Screenshot" " Saved")
			case "$resp" in
				action1)
					xdg-open "${check_file}" &
					;;
				action2)
					rm "${check_file}" &
					;;
			esac
        else
            ${notify_cmd_NOT} " Screenshot" " NOT Saved"
            "${sDIR}/Sounds.sh" --error
        fi
    fi
}

# countdown
countdown() {
	for sec in $(seq $1 -1 1); do
		notify-send -h string:x-canonical-private-synchronous:shot-notify -t 1000 -i "$iDIR"/timer.png  " Taking shot" " in: $sec secs"
		sleep 1
	done
}

# take shots
shotnow() {
	cd ${dir} && grim - | tee "$file" | wl-copy
	sleep 2
	notify_view
}

shot5() {
	countdown '5'
	sleep 1 && cd ${dir} && grim - | tee "$file" | wl-copy
	sleep 1
	notify_view
}

shot10() {
	countdown '10'
	sleep 1 && cd ${dir} && grim - | tee "$file" | wl-copy
	notify_view
}

shotwin() {
	focused_output_json=$(get_focused_output)
	focused_output_name=$(printf '%s' "$focused_output_json" | jq -r '.name // empty' 2>/dev/null)
	if [[ -n "$focused_output_name" ]]; then
		cd ${dir} && grim -o "$focused_output_name" - | tee "$file" | wl-copy
	else
		cd ${dir} && grim - | tee "$file" | wl-copy
	fi
	notify_view
}

shotarea() {
	tmpfile=$(mktemp)
	grim -g "$(slurp)" - >"$tmpfile"

  # Copy with saving
	if [[ -s "$tmpfile" ]]; then
		wl-copy <"$tmpfile"
		mv "$tmpfile" "$dir/$file"
	fi
	notify_view
}

shotactive() {
	focused_output_json=$(get_focused_output)
	focused_output_name=$(printf '%s' "$focused_output_json" | jq -r '.name // empty' 2>/dev/null)

	if [[ -n "$focused_output_name" ]]; then
		grim -o "$focused_output_name" "${active_window_path}"
	else
		grim "${active_window_path}"
	fi
	sleep 1
	notify_view "active"
}

shotswappy() {
	tmpfile=$(mktemp)
	grim -g "$(slurp)" - >"$tmpfile" 

  # Copy without saving
  if [[ -s "$tmpfile" ]]; then
		wl-copy <"$tmpfile"
    notify_view "swappy"
  fi
}

if [[ ! -d "$dir" ]]; then
	mkdir -p "$dir"
fi

if [[ "$1" == "--now" ]]; then
	shotnow
elif [[ "$1" == "--in5" ]]; then
	shot5
elif [[ "$1" == "--in10" ]]; then
	shot10
elif [[ "$1" == "--win" ]]; then
	shotwin
elif [[ "$1" == "--area" ]]; then
	shotarea
elif [[ "$1" == "--active" ]]; then
	shotactive
elif [[ "$1" == "--swappy" ]]; then
	shotswappy
else
	echo -e "Available Options : --now --in5 --in10 --win --area --active --swappy"
fi

exit 0
