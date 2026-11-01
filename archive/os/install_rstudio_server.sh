# Install Rstudio server

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Set-up the rstudio user
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# If the user is already registered on the system, don't overwrite the existing
# one!

# This is really confusing and broken -- fix!

declare rs_usr=$(grep -q brstudio /etc/passwd)
declare rs_grp=$(grep -q rstudio  /etc/group)

if [ -z "$rs_usr" ] && [ -z "$rs_grp" ]
then
    # Cook up a good long password
    declare -r rs_password="$(openssl rand -base64 30)"
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

    echo "User brstudio in the group rstudio created."
    echo "Copy ~/rstudio_password to a password manager, and delete it!"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Download and install the .deb file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sudo apt-get install -y gdebi-core libapparmor1

# Get the latest version number, for 64 bit systems.
curl https://www.rstudio.com/products/rstudio/download-server/ |
    grep -o 'https://download2.rstudio.org/rstudio-server.*amd64\.deb' |
    xargs wget --quiet

# Install
sudo gdebi --non-interactive rstudio-*-amd64.deb

sudo touch /etc/rstudio/rserver.conf
echo "auth-required-user-group=rstudio" | sudo tee -a /etc/rstudio/rserver.conf

# make sure everything is working
sudo rstudio-server verify-installation
