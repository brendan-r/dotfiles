#!/bin/bash

# Install a small util called 'light' to set screen brightness; replaces
# xbacklight, which doesn't seem to work on the X1C
# https://github.com/haikarainen/light/


mkdir /tmp/light-install
pushd /tmp/light-install

wget https://github.com/haikarainen/light/releases/download/v1.2/light-1.2.tar.gz

tar xf light-1.2.tar.gz
cd light-1.2/
./configure && make
sudo make install

popd
