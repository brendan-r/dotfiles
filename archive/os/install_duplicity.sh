#!/bin/bash

# Add the repo (to get non-ancient versions) and install
sudo add-apt-repository ppa:duplicity-team/ppa
sudo apt-get update
sudo apt-get install -y duplicity

# Make a dir for the logs
mkdir /var/log/duplicity/

# Install the b2 Python lib -- has to be Python 2 to work with duplicity
sudo -H pip2 install -U b2

# You now need the environment variables $B2_ACCOUNT_ID, $B2_APP_KEY,
# $B2_MACHINE_BUCKET, and $DIR_TO_BACKUP to be set and exported, by tradition in
# your ~/.bash.local, and run `b2 authorize-account`.
#
# Send yourself a notification to this effect
notify-send --urgency=critical "Backups: More to do" "
You now need the environment variables B2_ACCOUNT_ID, B2_APP_KEY
B2_MACHINE_BUCKET, and DIR_TO_BACKUP to be set and exported, by tradition in
your ~/.bash.local, and run b2 authorize-account.

If you don't do this, backups won't work."
