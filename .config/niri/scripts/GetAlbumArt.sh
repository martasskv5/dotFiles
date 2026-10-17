#!/bin/bash
TARGET_PNG="/tmp/hyprlock_album_art.png"
FALLBACK_PNG="$HOME/.config/hypr/fallback_art.png" # Create or point to a default blank image

# Get art URL from playerctl
ART_URL=$(playerctl metadata mpris:artUrl 2>/dev/null)

if [ -z "$ART_URL" ]; then
    # No media playing or no art available, copy fallback
    if [ -f "$FALLBACK_PNG" ]; then
        cp "$FALLBACK_PNG" "$TARGET_PNG"
    else
        # If no fallback image exists, clear target
        rm -f "$TARGET_PNG"
    fi
elif [[ "$ART_URL" == file://* ]]; then
    # It's a local file path (e.g. Amberol or local MP3s)
    LOCAL_PATH="${ART_URL#file://}"
    ffmpeg -y -i "$LOCAL_PATH" "$TARGET_PNG" >/dev/null 2>&1
elif [[ "$ART_URL" == http://* || "$ART_URL" == https://* ]]; then
    # It's a remote URL (e.g. Spotify or Firefox)
    curl -s -o /tmp/raw_art "$ART_URL"
    ffmpeg -y -i /tmp/raw_art "$TARGET_PNG" >/dev/null 2>&1
fi

# Hyprlock reload_cmd expects the literal path printed to stdout
echo "$TARGET_PNG"
