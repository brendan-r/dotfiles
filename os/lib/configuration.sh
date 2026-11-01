#!/bin/bash

# Helpers shared by the standalone configuration scripts.
# Variables are consumed by the sourcing scripts.
# shellcheck disable=SC2034

#  - - -  Common installer options  - - -

configuration_options() {

    backup=false
    configuration_args=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --backup) backup=true ;;
            *) configuration_args+=("$1") ;;
        esac
        shift
    done

}

configuration_result() {

    if [ -n "${DOTFILES_RESULT:-}" ]; then
        printf '%s\n' "$@" > "$DOTFILES_RESULT"
    fi

}

#  - - -  Protect personal files from indirect destinations  - - -

configuration_parent_is_safe() {

    local destination=$1 parent
    parent=$(dirname "$destination")

    while [ "$parent" != "$HOME" ]; do
        case "$parent" in
            "$HOME"/*) ;;
            *) printf 'Configuration destination is outside HOME: %s\n' "$destination" >&2; return 1 ;;
        esac

        if [ -L "$parent" ] || { [ -e "$parent" ] && [ ! -d "$parent" ]; }; then
            printf 'Configuration parent is indirect or not a directory: %s\n' "$parent" >&2
            return 1
        fi

        parent=$(dirname "$parent")
    done

}

place_configuration() {

    local source_file=$1 destination=$2 saved

    configuration_parent_is_safe "$destination" || return 1

    if [ -f "$destination" ] && cmp -s "$source_file" "$destination"; then
        configuration_result unchanged
        return 0
    fi

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        if ! "$backup"; then
            printf 'Configuration exists: %s. Use --backup to preserve and replace it.\n' "$destination" >&2
            return 1
        fi

        saved=$(mktemp -d "${destination}.backup.XXXXXX") || return 1
        mv "$destination" "$saved/original" || return 1
        printf 'Backup: %s\n' "$saved/original"
        record_backup "$destination" "$saved/original" || return 1
    fi

    mkdir -p "$(dirname "$destination")" || return 1
    cp "$source_file" "$destination" || return 1

}
