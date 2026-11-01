#!/bin/bash

# Create the personal directories used on this machine.
# configuration_args contains the requested directory paths.
# configuration_parent_is_safe checks HOME paths before creating them.
# configuration_result reports when no directory was created.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

# Explicit arguments make the script useful independently for other directories.
if [ "${#configuration_args[@]}" -gt 0 ]; then
    directories=("${configuration_args[@]}")
else
    directories=(archive Downloads/torrents projects)
fi

#  - - -  Validate all paths before creating any of them  - - -

for path in "${directories[@]}"; do
    case "$path" in
        ''|/*|*/|*//*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*\\*|*[[:cntrl:]]*)
            printf 'Expected a home-relative directory: %s\n' "$path" >&2
            exit 1
            ;;
    esac
    configuration_parent_is_safe "$HOME/$path"
done

#  - - -  Create only missing directories  - - -

changed=false
for path in "${directories[@]}"; do
    if [ ! -d "$HOME/$path" ]; then
        mkdir -p "$HOME/$path"
        changed=true
    fi
done

if ! "$changed"; then
    configuration_result unchanged
fi
