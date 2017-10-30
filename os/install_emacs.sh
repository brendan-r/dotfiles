#!/usr/bin/bash

# Install a particular version of Emacs 25.x and make some changes to how the OS
# references and uses it, specifically:
#
# - Use Kevin Kelley's PPA for the latest stable version of Emacs 25
#
# - Use Emacs in a client-server fashion. This means
#     - Starting the emacs daemon on startup
#     - Changing the Emacs .desktop file to use emacsclient25 as apposed to
#        emacs25
#
# - Set Emacs as the default application for various types of text file

# Install Emacs 25.x -----------------------------------------------------------

sudo add-apt-repository --yes ppa:kelleyk/emacs
sudo apt-get update --yes
sudo apt-get install --yes emacs25


# Symlink alternate CLI --------------------------------------------------------

sudo ln -fs $(cd .. && pwd)/bin/emacs-gui-client \
   /usr/bin/emacs-gui-client


# Clone Emacs dotfiles ---------------------------------------------------------

# You're not doing this here, because of the GitHub SSH key complexity. You may
# want to consider merging your dotemacs and dotfiles repositories


# Configure Client Server relationships ----------------------------------------

# Copy over the autostart file. This will mean that an Emacs server begins
# whenever the computer starts up
ln -fs $(cd .. && pwd)/emacs/emacs-server.desktop \
   $HOME/.config/autostart/emacs-server.desktop

# Replace desktop file which is used for Emacs within the GUI. Instead of
# opening a new emacs25 instance, the shortcut will now create a new GUI frame
# which exists to en existing Emacs server (and start one if it does not exist)
sudo ln -fs $(cd .. && pwd)/emacs/emacs25.desktop \
   /usr/share/applications/emacs25.desktop
