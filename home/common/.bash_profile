#!/bin/bash
# A login shell needs exports too; .bashrc uses this same guarded entrypoint.
if [ "${_DOTFILES_BASH_LOADED:-}" = 1 ]; then return 0; fi
_DOTFILES_BASH_LOADED=1

dotfiles_load_bash() {
    local file source_path directory path_entry clean_path='' remaining
    case "$(uname -s)" in
        Darwin) DOTFILES_OS=macos ;;
        Linux) DOTFILES_OS=linux ;;
        *) DOTFILES_OS=unknown ;;
    esac
    # Follow the installed .bash_profile link without GNU readlink -f.
    source_path=${BASH_SOURCE[0]}
    while [ -L "$source_path" ]; do
        directory=$(cd -P "$(dirname "$source_path")" && pwd) || return 1
        source_path=$(readlink "$source_path") || return 1
        case "$source_path" in /*) ;; *) source_path="$directory/$source_path" ;; esac
    done
    DOTFILES_ROOT=$(cd -P "$(dirname "$source_path")/../.." && pwd) || return 1
    remaining="${PATH:-/usr/bin:/bin}:$DOTFILES_ROOT/bin:$HOME/.local/bin:$HOME/bin"
    if [ "$DOTFILES_OS" = macos ]; then
        remaining="$remaining:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
    fi
    while [ -n "$remaining" ]; do
        path_entry=${remaining%%:*}
        case "$remaining" in *:*) remaining=${remaining#*:} ;; *) remaining='' ;; esac
        [ -n "$path_entry" ] || continue
        case ":$clean_path:" in *":$path_entry:"*) ;; *) clean_path="${clean_path:+$clean_path:}$path_entry" ;; esac
    done
    export PATH=$clean_path
    # shellcheck source=home/common/.bash_exports
    . "$HOME/.bash_exports"
    case $- in *i*) ;; *) return 0 ;; esac
    for file in bash_aliases bash_functions bash_options bash_prompt; do
        if [ -r "$HOME/.$file" ]; then
            # shellcheck disable=SC1090
            . "$HOME/.$file"
        fi
    done
    if [ "$DOTFILES_OS" = macos ] && [ -r "$HOME/.bash_mac_stuff" ]; then
        # shellcheck source=home/macos/.bash_mac_stuff
        . "$HOME/.bash_mac_stuff"
    fi
    if [ -r /etc/bash_completion ] && ! shopt -oq posix; then
        # shellcheck disable=SC1091
        . /etc/bash_completion
    fi
    if [ -r "$HOME/.bash.local" ]; then
        # shellcheck disable=SC1091
        . "$HOME/.bash.local"
    fi
    return 0
}
dotfiles_load_bash
unset -f dotfiles_load_bash
