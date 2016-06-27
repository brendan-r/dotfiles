#!/bin/bash

# Note: This can also be used to update Rstudio desktop (until they get a PPA!)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt-get -y install libjpeg62 libgstreamer0.10-0 \
  libgstreamer-plugins-base0.10-0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Move to a clean/temp dir
mkdir /tmp/rstudio_desktop_installation
pushd /tmp/rstudio_desktop_installation

# Webscrape the dev's page for the URL of the latest version, and download it
curl https://www.rstudio.com/products/rstudio/download/ |
  grep -o 'https://download1.rstudio.org/rstudio.*amd64\.deb' |
  xargs wget --quiet

# Install
sudo dpkg -i rstudio-*-amd64.deb

# Use pandoc shipped by Rstudio for global use (ovewrite any existing files)
sudo ln -sf /usr/lib/rstudio/bin/pandoc/pandoc /usr/local/bin
sudo ln -sf /usr/lib/rstudio/bin/pandoc/pandoc-citeproc /usr/local/bin

# Outta here
popd
