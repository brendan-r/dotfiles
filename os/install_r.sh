#!/bin/bash

## Install R
# Add the repo
sudo add-apt-repository -y \
  "deb https://cran.rstudio.com/bin/linux/ubuntu `lsb_release -cs`/"

# The Ubuntu archives on CRAN are signed with the key of “Michael Rutter
# marutter@gmail.com”
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9

# At the time of writing, this is required for git2r, which is required for
# devtools, which is required for quite a lot of your workflow
sudo apt-get -y build-dep libcurl4-gnutls-dev
sudo apt-get -y install libcurl4-gnutls-dev libssl-dev libxml2-dev \
  mesa-common-dev libcairo2-dev libxt-dev

sudo apt-get update

# R install
sudo apt-get -y install r-base r-base-dev

# Create a symlink of texi2dvi for R CMD check [^1]
ln -s /usr/bin/texi2dvi /usr/local/bin/texi2dvi

# Get some binary packages (pre-built deps)
sudo apt-get install -y r-cran-cairodevice r-cran-kernsmooth r-cran-matrix \
  r-cran-mgcv r-cran-nlme r-cran-nnet r-cran-rodbc

# Install your favourite packages
# R < install_r_packages.R --no-save

# [^1]: http://stackoverflow.com/questions/10819959/diagnosing-r-package-build-warning-latex-errors-when-creating-pdf-version
