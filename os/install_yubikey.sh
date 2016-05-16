
# Add the YubiCo PPA
sudo apt-add-repository ppa:yubico/stable
sudo apt-get update

sudo apt-get install -y yubico-piv-tool              # Smartcard CLI
sudo apt-get install -y yubikey-piv-manager          # Smartcard GUI
sudo apt-get install -y yubikey-personalization-gui  # Personalization GUI
# sudo apt-get install -y yubikey-piv-manager          # Personalization CLI

# Not installed at the moment:
# isudo apt-get install yubioath-desktop             # For laptop logins
