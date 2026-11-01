#! /bin/bash/

# Dump the source files here
pushd /usr/local/src

# Clone the repo from github, and enter the dir
sudo git clone https://github.com/douglascrockford/JSMin.git

pushd JSMin

# Compile the C code
sudo gcc -o jsmin jsmin.c

# Move the binary over here
sudo mv /usr/local/src/JSMin/jsmin /usr/local/bin/jsmin

# Outta here
popd
popd