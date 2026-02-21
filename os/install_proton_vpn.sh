#!/bin/bash

# 1. Install Trixie-compatible background services
echo "Installing background services for i3 (Trixie compatible)..."
sudo apt update
sudo apt install -y mate-polkit gnome-keyring seahorse network-manager-gnome dunst curl wget

# 2. Find the latest Proton VPN repository package
REPO_URL="https://repo.protonvpn.com/debian/dists/stable/main/binary-all/"
LATEST_DEB=$(curl -s $REPO_URL | grep -oP 'protonvpn-stable-release_[\d\.\-]+_all\.deb' | sort -V | tail -1)

if [ -z "$LATEST_DEB" ]; then
    LATEST_DEB="protonvpn-stable-release_1.0.8_all.deb"
fi

# 3. Download and install the repository
echo "Downloading latest repo: $LATEST_DEB"
wget -q "${REPO_URL}${LATEST_DEB}" -O "/tmp/$LATEST_DEB"
sudo dpkg -i "/tmp/$LATEST_DEB"
sudo apt update

# 4. Install the official Proton VPN app
sudo apt install -y proton-vpn-gnome-desktop
rm "/tmp/$LATEST_DEB"

echo "Installation complete!"
