# Note: You should replace these with symlinks...

# Copy the Xmodmap file over
cp ~/projects/dotfiles/keyboard/.Xmodmap ~/.Xmodmap

# Copy the main xkb file to the right pace
sudo cp ~/projects/dotfiles/keyboard/us /usr/share/X11/xkb/symbols/us

# Copy the basic types file
sudo cp ~/projects/dotfiles/keyboard/basic /usr/share/X11/xkb/types/basic

# Remove the cached files
sudo rm -f /var/lib/xkb/*.xkm

# Run Xmodmap
xmodmap ~/.Xmodmap
