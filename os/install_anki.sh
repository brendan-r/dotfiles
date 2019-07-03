#!/bin/bash

install_dir=/tmp/anki-install

mkdir $install_dir
pushd $install_dir

wget https://apps.ankiweb.net/downloads/current/anki-2.1.14-linux-amd64.tar.bz2

tar xjf anki-2.1.14-linux-amd64.tar.bz2

cd anki-2.1.14-linux-amd64

sudo make install

popd
