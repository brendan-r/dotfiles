#!/bin/bash

# Note: This can also be used to update Rstudio desktop (until they get a PPA!)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt-get -y install libjpeg62

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Remove any existing .deb files
rm ~/rstudio-*-amd64.de

# Get the latest version number, for 64 bit systems.
curl https://www.rstudio.com/products/rstudio/download/ |
  grep -o 'https://download1.rstudio.org/rstudio.*amd64\.deb' > rs_deb_url

# Download the deb file
paste rs_deb_url |  xargs wget --quiet -P ~

rm rs_deb_url

sudo dpkg -i ~/rstudio-*-amd64.deb

# Use pandoc shipped by Rstudio for global use (ovewrite any existing files)
sudo ln -sf /usr/lib/rstudio/bin/pandoc/pandoc /usr/local/bin
sudo ln -sf /usr/lib/rstudio/bin/pandoc/pandoc-citeproc /usr/local/bin

# Remove the .deb file
rm ~/rstudio-*-amd64.deb
