#!/bin/bash

# Note: Gemini wrote this, it's untested. Could be trash.

# Ensure system has a place to store apt keys
sudo install -d -m 0755 /etc/apt/keyrings

# Import Mozilla's key
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null

# Add the repo
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | sudo tee /etc/apt/sources.list.d/mozilla.list > /dev/null

# Pin priority
echo '
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
' | sudo tee /etc/apt/preferences.d/mozilla

# Install firefox. This won't remove ESR.
sudo apt update && sudo apt install firefox
