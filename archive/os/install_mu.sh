#!/bin/bash

# Install mu ------------------------------------------------------------------

# Install dependencies
sudo apt install autoconf automake libtool texinfo libgmime-2.6-dev \
     libxapian-dev gmime-3.0 -y

# Download the source to a new tempdir, and unpack it
mkdir /tmp/mu-install/
pushd /tmp/mu-install/

wget https://github.com/djcb/mu/archive/1.2.tar.gz
tar xvfz 1.2.tar.gz

cd mu-1.2

# Install mu
./autogen.sh && ./configure && make
sudo make install

# Get back to where you were
popd

# Install tools to get at gnome-keyring securely -------------------------------

# You can then store passwords in gnome-keyring with something like
# secret-tool store --label='<label>' username <foo> id <baz>
# And retrieve it with something like
# secret-tool store username <foo> id <baz>

sudo apt install libsecret-tools
