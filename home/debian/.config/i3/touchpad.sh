#!/bin/bash

#  - - -  Find the touchpad instead of assuming one Synaptics product name  - - -

set -eo pipefail

case "${1:-}" in
    on) action=enable ;;
    off) action=disable ;;
    *) printf 'Usage: touchpad.sh on|off\n' >&2; exit 2 ;;
esac

# Device names differ between the X1 Carbon, T480 and older ThinkPads.
devices=$(xinput list --name-only | awk 'tolower($0) ~ /touchpad|trackpad/')
[ -n "$devices" ] || { printf 'No X11 touchpad found.\n' >&2; exit 1; }

while IFS= read -r device; do
    xinput "$action" "$device"
done <<< "$devices"

notify-send 'Touchpad' "Turned $1" || true
