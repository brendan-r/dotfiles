#!/bin/bash

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Prerequisites
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sudo apt-get -y install libjpeg62

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Get the latest version number, for 64 bit systems.
curl http://www.rstudio.com/products/rstudio/download/ |
  grep -o 'http://download1.rstudio.org/rstudio.*amd64\.deb' > rs_deb_url

# Download the deb file
paste rs_deb_url |  xargs wget -q -P ~/Downloads

rm rs_deb_url

sudo dpkg -i ~/Downloads/rstudio-*-amd64.deb

# use pandoc shipped by Rstudio for global use
sudo ln -s /usr/lib/rstudio/bin/pandoc/pandoc /usr/local/bin
sudo ln -s /usr/lib/rstudio/bin/pandoc/pandoc-citeproc /usr/local/bin

