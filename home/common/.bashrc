#!/bin/bash
case $- in
    *i*)
        if [ -r "$HOME/.bash_profile" ]; then
            # shellcheck source=home/common/.bash_profile
            . "$HOME/.bash_profile"
        fi ;;
esac
