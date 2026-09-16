#!/bin/bash
FONT="${FONT:-/usr/share/figlet/fonts/Delta Corps Priest 1 w numbers.flf}"

# 1. Generate FIGlet output
# 2. Escape XML tokens for Pango
# 3. head -n -1 cleanly drops the absolute final trailing row without touching internal spacing
figlet -f "$FONT" -W "$(date +"%H : %M")" | \
sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g;' | \
head -n -1 | \
while IFS= read -r line; do
    echo "<span line_height=\"0.84\" width=\"650000\" allow_breaks=\"true\">$line</span>"
done
