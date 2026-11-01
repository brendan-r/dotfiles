#!/bin/bash

#  - - -  Show every present battery, including the T480's removable pack  - - -

set -eo pipefail

# The override lets the VM tests supply synthetic power-supply devices.
supplies=${DOTFILES_POWER_SUPPLY_DIR:-/sys/class/power_supply}
separator=''

for device in "$supplies"/*; do
    [ -f "$device/type" ] || continue
    [ "$(cat "$device/type")" = Battery ] || continue
    [ ! -f "$device/present" ] || [ "$(cat "$device/present")" = 1 ] || continue
    [ -f "$device/capacity" ] || continue

    capacity=$(cat "$device/capacity")
    case "$capacity" in ''|*[!0-9]*) continue ;; esac
    [ "$capacity" -le 100 ] || continue

    charging=''
    if [ -f "$device/status" ] && [ "$(cat "$device/status")" = Charging ]; then
        charging='+'
    fi

    printf '%s%s %s%%%s' "$separator" "${device##*/}" "$capacity" "$charging"
    separator='  '
done

# No batteries (a desktop or VM) means an empty, harmless bar module.
[ -z "$separator" ] || printf '\n'
