#!/bin/bash

# Create a personal Bash settings file without replacing existing contents.
# configuration_args contains options not consumed by setup.
# configuration_result reports an unchanged file to the installer.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
[ "${#configuration_args[@]}" -eq 0 ] || exit 2

#  - - -  Validate the destination before changing anything  - - -

if { [ -e "$HOME/.bash.local" ] || [ -L "$HOME/.bash.local" ]; } \
    && [ ! -f "$HOME/.bash.local" ]; then
    printf '%s exists but is not a regular file.\n' "$HOME/.bash.local" >&2
    exit 1
fi

#  - - -  Create only when absent  - - -

if [ -f "$HOME/.bash.local" ]; then
    printf 'Keeping existing ~/.bash.local\n'
    configuration_result unchanged
    exit 0
fi

(set -o noclobber; : > "$HOME/.bash.local")
printf 'Created ~/.bash.local\n'
