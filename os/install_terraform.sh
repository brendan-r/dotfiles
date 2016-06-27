#! /bin/bash/

# Install terraform
mkdir /tmp/terraform_installation
pushd /tmp/terraform_installation

# Remove any existing .zip files
find . -name "terraform_*linux_amd64*zip*" -delete

# Webscrape the dev's page for the URL of the latest version, and download it
curl --silent https://www.terraform.io/downloads.html |
  grep -o 'https://releases.hashicorp.com/terraform/.*_linux_amd64.zip' |
  xargs wget --quiet
  
# Install it -- by unzipping binaries
mkdir -p $HOME/opt/terraform
unzip terraform_*linux_amd64*zip -d $HOME/opt/terraform

# Copy the binary to $PATH. This may be specific to the way my dotfiles are
# set-up. The below looks for some mention of 'opt/terrafrom', and if it's not
# found, looks for the line 'export PATH' and inserts it above that.
if ! grep -Fxq 'opt/terraform' $HOME/.bash_profile; then
    line=$(cat $HOME/.bash_profile | grep -n 'export PATH' | grep -o '^[0-9]*')
    sed -i ${line}'i\# Add Terraform\nPATH=$PATH:$HOME/opt/terraform\n' \
      $HOME/.bash_profile
fi

# Outta here
popd
