#!/bin/bash

# Install java stuff lol
sudo apt-get install -y openjdk-8-jre tomcat8

# Do this thing, not sure what it means
sudo update-alternatives --config java

# If the Tomcat thing started running, stop it running
sudo systemctl stop tomcat8.service

# Temp dirs to keep things tidy
mkdir /tmp/airsonic-install
pushd /tmp/airsonic-install

# Make a place for the airsonic war file to live
sudo rm -rf /var/airsonic/
sudo mkdir  /var/airsonic/
sudo chown -R tomcat8:tomcat8 /var/airsonic/

# Remove any pre-existing files
sudo rm /var/lib/tomcat8/webapps/airsonic.war
sudo rm -R /var/lib/tomcat8/webapps/airsonic/
sudo rm -R /var/lib/tomcat8/work/*

# Download the WAR file
wget https://github.com/airsonic/airsonic/releases/download/v10.1.1/airsonic.war

# Move it over here
sudo mv airsonic.war /var/lib/tomcat8/webapps/airsonic.war

# Hopefully it should run now
sudo systemctl start tomcat8.service

# There's some additional stuff with transcoders you should do here...

# If everything worked, after a couple of minutes, there should be stuff
# happening at  http://localhost:8080/airsonic
popd
