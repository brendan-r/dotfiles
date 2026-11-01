#!/bin/bash

# Install the unity tweak tool
sudo apt-get install unity-tweak-tool

# Install the flattr theme
mkdir ~/.themes
git clone https://github.com/anmoljagetia/Flatabulous.git ~/.themes/Flatabulous


# Get flat icons
sudo add-apt-repository ppa:noobslab/icons
sudo apt-get update
sudo apt-get install ultra-flat-icons

# You now need to go to the unity tweak tool gui, and select the theme
# and icons set
