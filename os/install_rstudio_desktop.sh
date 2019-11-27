#!/bin/bash

# Note: This can also be used to update Rstudio desktop (until they get a PPA!)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt-get -y install libclang-dev gdebi-core pandoc

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Move to a clean/temp dir
mkdir /tmp/rstudio_desktop_installation
pushd /tmp/rstudio_desktop_installation

# Webscrape the dev's page for the URL of the latest version, and download it
curl https://www.rstudio.com/products/rstudio/download/ |
    grep -Po 'https://download1.rstudio.org/desktop/bionic/amd64/rstudio-1\.[0-9]+\.[0-9]+-amd64\.deb' |
    xargs wget --quiet

# Install
sudo gdebi -y rstudio-*-amd64.deb

# Outta here
popd
