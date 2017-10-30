#!/usr/bin/bash

ln -fs $(cd .. && pwd)/mimeapps.list \
   $HOME/.config/mimeapps.list

ln -fs $(cd .. && pwd)/mimeapps.list \
   $HOME/.local/share/applications/mimeapps.list
