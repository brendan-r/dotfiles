
# Add the YubiCo PPA
sudo apt-add-repository ppa:yubico/stable
sudo apt-get update

sudo apt-get install -y yubico-piv-tool              # Smartcard CLI
sudo apt-get install -y yubikey-piv-manager          # Smartcard GUI
sudo apt-get install -y yubikey-personalization-gui  # Personalization GUI
# sudo apt-get install -y yubikey-piv-manager          # Personalization CLI

# Install gpg2 smartcard daemon
sudo apt-get install scdaemon

# Not installed at the moment:
# isudo apt-get install yubioath-desktop             # For laptop logins

# For use with ssh -----------------------------------------------

# Install pre-requisites
sudo apt-get install -y gnupg2 gnupg-agent libpth20 pinentry-curses \
  libccid pcscd scdaemon libksba8

# This bit can't quite be automated -- you need to press 1
gpg2 --keyserver pgp.mit.edu --search-keys brendan@brendanrocks.com

