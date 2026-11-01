#!/bin/bash

# Register the window manager and keyboard shortcut services.
set -e
# Use this script's checkout rather than a fixed path, so worktrees
# and custom clones read their own helpers and files.
script_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec /bin/bash "$script_directory/lib/launch_agents.sh" "$@" \
    yabai com.asmvik.yabai skhd com.koekeishiya.skhd
