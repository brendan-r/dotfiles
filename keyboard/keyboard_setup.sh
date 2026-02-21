# Note: At least on Debian Trixie, the binary will be accessible as
# 'keyd.rvaiya' at /usr/bin/keyd.rvaiya
sudo apt install keyd

# The config file has to live under /etc/ to act system wide.
sudo ln -s ~/projects/dotfiles/config/keyd/default.conf /etc/keyd/default.conf

# Load the config
sudo keyd.rvaiya reload
