#!/bin/bash

# Exercise the installed desktop in an isolated X server, inside a disposable VM.
set -eo pipefail
[ -r /etc/dotfiles-test-image ] && [ "${DOTFILES_TEST_GUEST:-}" = 1 ]

if [ "${1:-}" = --inside ]; then
    i3 > "$SESSION_LOG/i3.log" 2>&1 &
    wm=$!
    trap 'kill "$wm" 2>/dev/null || true' EXIT

    # Wait for the actual IPC socket, not a fixed desktop startup delay.
    for ((attempt = 0; attempt < 100; attempt++)); do
        i3-msg -t get_version >/dev/null 2>&1 && break
        sleep 0.1
    done
    i3-msg -t get_version

    xterm -fa 'DejaVu Sans Mono' -title dotfiles-test-window -e sleep 60 > "$SESSION_LOG/xterm.log" 2>&1 &
    for ((attempt = 0; attempt < 100; attempt++)); do
        i3-msg -t get_tree > "$SESSION_LOG/tree.json"
        grep -q dotfiles-test-window "$SESSION_LOG/tree.json" && break
        sleep 0.1
    done
    grep -q dotfiles-test-window "$SESSION_LOG/tree.json"
    i3-msg '[title="dotfiles-test-window"] move container to workspace "dotfiles-test"'
    i3-msg 'workspace "dotfiles-test"'
    i3-msg -t get_workspaces > "$SESSION_LOG/workspaces.json"
    python3 - "$SESSION_LOG/workspaces.json" <<'VERIFY'
import json, sys
assert any(w['name'] == 'dotfiles-test' and w['focused'] for w in json.load(open(sys.argv[1])))
VERIFY
    notify-send 'Dotfiles test' 'Desktop notification delivery'
    # i3 may close IPC before acknowledging exit; its process status is definitive.
    i3-msg exit || true
    wait "$wm"
    exit 0
fi

SESSION_LOG=$(mktemp -d /tmp/dotfiles-i3-session.XXXXXX)
export SESSION_LOG
Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp 3> "$SESSION_LOG/display" > "$SESSION_LOG/xvfb.log" 2>&1 &
xserver=$!
trap 'kill "$xserver" 2>/dev/null || true; printf "Desktop test logs: %s\n" "$SESSION_LOG"' EXIT

for ((attempt = 0; attempt < 100; attempt++)); do
    [ -s "$SESSION_LOG/display" ] && break
    sleep 0.1
done
[ -s "$SESSION_LOG/display" ]
DISPLAY=":$(cat "$SESSION_LOG/display")"
export DISPLAY
dbus-run-session -- /bin/bash "$0" --inside
