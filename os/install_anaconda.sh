# Install Anaconda

# Get the latest version for 64 bit systems
curl https://www.continuum.io/downloads | \
    grep -o \
    'https://[[:alnum:]|-]*.ssl.cf1.rackcdn.com/Anaconda3-.*-Linux-x86_64.sh' \
    >> anaconda_script_url

# Download the bash file
cat paste rs_deb_url |  xargs wget -q

# Execute it
# You should pass the -b argument somewhere
# Note: This script will error out if the anaconda directory already exists.
# It's probably a good idea to detect that before running
cat anaconda_script_url | grep -o "Anaconda3-.*-Linux-x86_64.sh" | \
    sed 's/$/ -b /' | xargs bash
