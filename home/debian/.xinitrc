#!/bin/sh

#  - - -  Start i3 when using startx instead of a display manager  - - -

export XDG_CURRENT_DESKTOP=i3
export XDG_SESSION_DESKTOP=i3

# A private session bus makes desktop notifications and keyring services usable.
exec dbus-run-session -- i3
