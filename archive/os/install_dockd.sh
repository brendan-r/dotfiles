#!/bin/bash

sudo apt-get install libusb-1.0-0-dev


sudo apt-get install libxrandr-dev build-essential libsystemd-dev libudev-dev -y

mkdir /tmp/install-libthinkpad-dockd
pushd /tmp/install-libthinkpad-dockd

wget https://github.com/libthinkpad/libthinkpad/archive/2.6.tar.gz

ll

tar xvfz 2.6.tar.gz

pushd libthinkpad-2.6
cmake . -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install

popdir


wget https://github.com/libthinkpad/dockd/archive/1.21.tar.gz
tar xvfz 1.21.tar.gz
pushd dock-1.21
cmake . -DCMAKE_INSTALL_PREFIX=/usr
make
sudo make install

popd

popd
