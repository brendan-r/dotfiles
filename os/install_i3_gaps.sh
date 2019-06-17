#!/bin/bash

# Taken from https://github.com/Airblader/i3/wiki/Compiling-&-Installing

# Dependencies --------------------------------------------------------------

sudo add-apt-repository ppa:aguignard/ppa
sudo apt-get update
sudo apt-get install -y libxcb-xrm-dev

# Install loads of stuff
sudo apt-get install -y libxcb1-dev libxcb-keysyms1-dev libpango1.0-dev      \
     libxcb-util0-dev libxcb-icccm4-dev libyajl-dev                          \
     libstartup-notification0-dev libxcb-randr0-dev libev-dev                \
     libxcb-cursor-dev  libxcb-xinerama0-dev libxcb-xkb-dev libxkbcommon-dev \
     libxkbcommon-x11-dev autoconf libxcb-xrm-dev i3status libxcb-shape0-dev \
     libxcb-composite0-dev

# Other stuff that you like
sudo apt-get install -y dunst wmctrl compton i3lock xautolock

# Download and build the project ---------------------------------------------

cd ~/projects
rm -rf i3-gaps

# clone the repository
git clone https://www.github.com/Airblader/i3 i3-gaps
cd i3-gaps

# compile & install
autoreconf --force --install
rm -rf build/
mkdir -p build && cd build/

# Disabling sanitizers is important for release versions!
# The prefix and sysconfdir are, obviously, dependent on the distribution.
../configure --prefix=/usr --sysconfdir=/etc --disable-sanitizers
make
sudo make install

# Let X know that you want to use this -----------------------------------------
echo "exec i3" > ~/.xinitrc

# Stop GNOME messing with it when you opnen Nautilus ---------------------------
gsettings set org.gnome.desktop.background show-desktop-icons false
