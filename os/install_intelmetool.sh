# Install intelmetool from coreboot

# Helps you understand how much of a security risk your CPU is

# Dependencies
sudo apt install git build-essential libpci-dev pkg-config

# Clone the repo, make install
git clone --depth=1 https://review.coreboot.org/coreboot
cd coreboot/util/intelmetool
make
sudo make install

# Get some output to understand your system
sudo intelmetool -b
