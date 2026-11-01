#!/usr/bin/bash

# Happily this is very easy these days
sudo apt install emacs-gtk emacs-el

# Symlink alternate CLI --------------------------------------------------------

sudo ln -fs $(cd .. && pwd)/bin/emacs-gui-client \
   /usr/bin/emacs-gui-client
