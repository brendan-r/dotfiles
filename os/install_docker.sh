# Install Docker
# You're currently using 14.04 or 15.04, so there are no dependencies
# However, there might be on other versions. See:
# https://docs.docker.com/installation/ubuntulinux/

# You should already have curl installed
# sudo apt-get update
# sudo apt-get install curl

# Download the latest Docker package
curl -sSL https://get.docker.com/ | sh

# Create the docker group and add yourself
usermod -aG docker $USER

# You're opting *not* to take the performance hit involved in
# enabling memory & swap accounting. Details if you want to do it
# are here: https://docs.docker.com/installation/ubuntulinux/

# Configuring a DNS server
# Apparently you need to do this if you're using docker on any kind
# of desktop version of Ubutu
# Here you're setting it to use OpenDNS
sed -i 's/.*DOCKER_OPTS=.*/DOCKER_OPTS="--dns 208.67.222.222 --dns 208.67.220.220"/g' /etc/default/docker
