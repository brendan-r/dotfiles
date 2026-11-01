#! /bin/bash/

# Install packer
mkdir /tmp/packer_installation
pushd /tmp/packer_installation

# Remove any existing .zip files
find . -name "packer_*linux_amd64*zip*" -delete

# Webscrape the dev's page for the URL of the latest version, and download it
curl --silent https://www.packer.io/downloads.html |
  grep -o 'https://releases.hashicorp.com/packer/.*_linux_amd64.zip' |
  xargs wget --quiet

# Install it -- by unzipping binaries
mkdir -p $HOME/opt/packer
unzip packer_*linux_amd64*zip -d $HOME/opt/packer

# Copy the binary to $PATH. This may be specific to the way my dotfiles are
# set-up. The below looks for some mention of 'opt/packer', and if it's not
# found, looks for the line 'export PATH' and inserts it above that.
if ! grep -Fxq 'opt/packer' $HOME/.bash_profile; then
    line=$(cat $HOME/.bash_profile | grep -n 'export PATH' | grep -o '^[0-9]*')
    sed -i ${line}'i\# Add Packer\nPATH=$PATH:$HOME/opt/packer\n' \
      $HOME/.bash_profile
fi

# Outta here
popd
