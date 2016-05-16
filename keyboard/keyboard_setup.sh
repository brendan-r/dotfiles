# Note: You should replace these with symlinks...

# Copy the Xmodmpa file over
cp ~/dotfiles/keyboard/.Xmodmap ~/.Xmodmap

# Copy the main xkp file to the right pace
cp ~/dotfiles/keyboard/us /usr/share/X11/xkb/symbols/us

# Copy the basic types file
cp ~/dotfiles/keyboard/basic /usr/share/X11/xkb/types/basic

# Remove the cached files
sudo rm -f /var/lib/xkb/*.xkm

# Run Xmodmap
xmodmap ~/.Xmodmap

