#!/bin/bash

# Install the Debian i3 desktop and validate the user's configuration.
# Desktop-specific settings and bindings are maintained in the dotfiles.
# configuration_args contains options not consumed by setup.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

if [ "${#configuration_args[@]}" -gt 0 ]; then
    printf 'Unknown option: %s\n' "${configuration_args[0]}" >&2
    exit 2
fi

#  - - -  Install the desktop and its supporting tools  - - -

sudo apt-get update --error-on=any
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    i3 rofi polybar dunst picom autorandr i3lock xss-lock \
    wmctrl network-manager-gnome light xserver-xorg xinit dbus-x11 \
    kitty dex hsetroot gnome-keyring mate-polkit alsa-utils playerctl \
    xinput xserver-xorg-input-wacom pipewire-audio libnotify-bin \
    xdg-utils fonts-dejavu-core

#  - - -  Validate the linked configuration  - - -

# Do not start or change the user's current desktop session.
i3 -C
printf 'i3 configuration parsed successfully. Choose i3 at your next graphical login.\n'
