#!/bin/bash

# On Trixie, the apt version of libfprint is too old...
# But we can install from source
sudo apt build-dep libfprint
git clone https://gitlab.freedesktop.org/libfprint/libfprint.git
cd libfprint
meson setup build
ninja -C build
sudo ninja -C build install

# Restart the service
sudo systemctl restart fprintd

# To configure, you can see if it sees anything after running this:
# You should see something like: /net/reactivated/Fprint/Device/0
busctl tree net.reactivated.Fprint

# And if it does, you just run
fprintd-enroll
