# Install Rstudio server

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Set-up the rstudio user
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Cook up a very long password
declare -r rs_password="$(openssl rand -base64 50)"
declare -r rs_user="brstudio"

# Write here to copy into a key manager
rm ~/rstudio_password
echo $rs_password  >> ~/rstudio_password

# Create the user
sudo useradd -mN $rs_user

# With the password
echo $rs_user:$rs_password | sudo chpasswd

# Create the rstudio user group, and add them to it
sudo groupadd rstudio
sudo usermod -G rstudio $rs_user

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sudo apt-get install -y gdebi-core
sudo apt-get install -y libapparmor1 # Required only for Ubuntu, not Debian

# download .deb files

# Get the latest version number, for 64 bit systems.
curl http://www.rstudio.com/products/rstudio/download-server/ | \
    grep -o 'https://download2.rstudio.org/rstudio-server.*amd64\.deb' >> \
    rs_deb_url

# Download the deb file
paste rs_deb_url |  xargs wget -q

# Run it. You really need to find a way for this to be accepted automatically (it prompts you to hit 'y')
sudo gdebi rstudio-*-amd64.deb

sudo touch /etc/rstudio/rserver.conf
echo "auth-required-user-group=rstudio"  | sudo tee -a /etc/rstudio/rserver.conf

# make sure everything is working
sudo rstudio-server verify-installation
