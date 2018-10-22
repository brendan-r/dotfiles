#!/bin/bash

# Install dependencies
sudo apt install autoconf automake libtool texinfo libgmime-2.6-dev libxapian-dev -y

# Download the source to a new tempdir, and unpack it
mkdir /tmp/mu-install/
pushd /tmp/mu-install/

wget https://github.com/djcb/mu/archive/v1.0.tar.gz
tar xvfz v1.0.tar.gz

cd mu-1.0

# Install mu
./autogen.sh && ./configure && make
sudo make install

# Get back to where you were
popd