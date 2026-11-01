#!/bin/bash

#  - - -  Rotate the built-in display and integrated Wacom tablet together  - - -

set -eo pipefail

# X200T panels are normally LVDS; newer internal panels use eDP names.
line=$(xrandr --query | awk '$2 == "connected" && $1 ~ /^(LVDS|eDP)/ { print; exit }')
[ -n "$line" ] || { printf 'No connected internal display found.\n' >&2; exit 1; }
output=${line%% *}

# The parenthesized list contains supported rotations, not the active rotation.
orientation=$(printf '%s\n' "${line%%(*}" | awk '
    { rotation = "normal"; for (i = 1; i <= NF; i++)
        if ($i == "left" || $i == "right" || $i == "inverted") rotation = $i;
      print rotation }
')
case "$orientation" in
    normal) next=left; tablet=ccw ;;
    left) next=inverted; tablet=half ;;
    inverted) next=right; tablet=cw ;;
    right) next=normal; tablet=none ;;
esac

xrandr --output "$output" --rotate "$next"

# Match integrated ISDv4 tools only; leave external drawing tablets alone.
# Rotate before mapping to the display, as required by xsetwacom.
if command -v xsetwacom >/dev/null 2>&1; then
    devices=$(xsetwacom list devices | awk '/ISDv4/ && /type: (STYLUS|ERASER|TOUCH)/ {
        for (i = 1; i <= NF; i++) if ($i == "id:") print $(i + 1)
    }')
    while IFS= read -r device; do
        [ -n "$device" ] || continue
        xsetwacom set "$device" Rotate "$tablet"
        xsetwacom set "$device" MapToOutput "$output"
    done <<< "$devices"
fi

printf 'Internal display rotated %s.\n' "$next"
