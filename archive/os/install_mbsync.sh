#!/bin/bash

sudo apt-get install libssl-dev

mkdir /tmp/isync/
pushd /tmp/isync/

wget https://downloads.sourceforge.net/project/isync/isync/1.3.0/isync-1.3.0.tar.gz
tar -xzf isync-1.3.0.tar.gz
cd isync-1.3.0

./configure
make
sudo make install

popd
