#!/bin/bash

#  - - -  Control the selected desktop audio devices  - - -

set -eo pipefail

# Device numbers vary between ThinkPads and when a dock or USB headset is added.
# Resolve the current PipeWire defaults on each invocation, not a fixed ALSA card.
case "${1:-}" in
    up|down)
        change=5%+
        [ "$1" = up ] || change=5%-

        wpctl set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ "$change"
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        ;;
    mic-mute)
        wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
        ;;
    *)
        printf 'Usage: audio.sh up|down|mute|mic-mute\n' >&2
        exit 2
        ;;
esac
