# See https://help.ubuntu.com/community/SSH/OpenSSH/Configuring

# Install ssh server
sudo apt-get install openssh-server 

# Back-up the settings
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.factory-defaults
sudo chmod a-w /etc/ssh/sshd_config.factory-defaults

# Backup authorized keys, and copy yours in
cp ~/.ssh/authorized_keys ~/.ssh/authorized_keys_Backup
curl http://www.brendanrocks.com/id_rsa.pub >> ~/.ssh/authorized_keys

# Disable password auth
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config

# Log Level verbose
# You can see details at /var/log/auth.log
# You can see who's got in with grep sshd /var/log/auth.log | grep Accepted
sudo sed -i 's/LogLevel INFO/LogLevel VERBOSE/g' /etc/ssh/sshd_config

# Here you should probably set a port other than 22!

# Here you should move issue.net from the dotfiles repo, over to the server

# Rate limit connections
sudo ufw limit ssh

# install fail2ban: it should start running with sensible defaults automatically
sudo apt-get install fail2ban

# At this point, you need to allow port forwarding on the router...
