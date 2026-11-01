
sudo apt install dunst

# Tell autostart to ignore existing notification system
mkdir -p ~/.config/autostart
cp /etc/xdg/autostart/xfce4-notifyd.desktop ~/.config/autostart/
echo "Hidden=true" >> ~/.config/autostart/xfce4-notifyd.desktop

# Stop the dbus service
systemctl --user mask xfce4-notifyd

# Kill existing instances
killall xfce4-notifyd

# In the future notifications should look sane
