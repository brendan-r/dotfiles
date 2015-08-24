## R

# At the time of writing, this is required for git2r, which is required for
# devtools, which is required for quite a lot of your workflow
sudo apt-get install libssl-dev


sudo add-apt-repository -y "deb http://cran.rstudio.com/bin/linux/ubuntu `lsb_release -cs`/"
# The Ubuntu archives on CRAN are signed with the key of “Michael Rutter
# marutter@gmail.com”
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9

sudo apt-get update



# Do the actuall install
sudo apt-get -y install r-base r-base-dev

# Create a symlink of texi2dvi for R CMD check, as per
# http://stackoverflow.com/questions/10819959/diagnosing-r-package-build-warning-latex-errors-when-creating-pdf-version
sudo ln -s /usr/bin/texi2dvi /usr/local/bin/texi2dvi

# These are needed for Cairo graphics to work
sudo apt-get install -y r-cran-cairodevice libcairo2-dev libxt-dev

# Install your favourite packages
sudo Rscript install_r_packages.R
