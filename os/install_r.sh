## R

# At the time of writing, this is required for git2r, which is required for
# devtools, which is required for quite a lot of your workflow
apt-get -y build-dep libcurl4-gnutls-dev
apt-get -y install libcurl4-gnutls-dev libssl-dev libxml2-dev mesa-common-dev \
  libcairo2-dev libxt-dev

 add-apt-repository -y "deb http://cran.rstudio.com/bin/linux/ubuntu `lsb_release -cs`/"
# The Ubuntu archives on CRAN are signed with the key of “Michael Rutter
# marutter@gmail.com”
 apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9

 apt-get update


# Do the actuall install
 apt-get -y install r-base r-base-dev

# Create a symlink of texi2dvi for R CMD check, as per
# http://stackoverflow.com/questions/10819959/diagnosing-r-package-build-warning-latex-errors-when-creating-pdf-version
 ln -s /usr/bin/texi2dvi /usr/local/bin/texi2dvi

# These are needed for Cairo graphics to work
 apt-get install -y r-cran-cairodevice r-cran-kernsmooth r-cran-matrix \
   r-cran-mgcv r-cran-nlme r-cran-nnet r-cran-rodbc

# Install your favourite packages
 Rscript install_r_packages.R
