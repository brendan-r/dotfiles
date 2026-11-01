#!/bin/bash

#  - - -  Replace this user's bar when i3 reloads  - - -

# Do not touch another user's processes or wait forever for a stale bar.
pkill -u "$(id -u)" -x polybar || true

# Keep the bar attached to this launch process, with its output in the i3 log.
exec polybar --reload example
