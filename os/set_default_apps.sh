 #!/usr/bin/bash

ln -fs $HOME/projects/dotfiles/mimeapps.list \
   $HOME/.config/mimeapps.list

mkd $HOME/.local/share/applications/

ln -fs $HOME/projects/dotfiles/mimeapps.list \
   $HOME/.local/share/applications/mimeapps.list
