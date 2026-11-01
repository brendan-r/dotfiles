#!/bin/bash

# Make the checkout's personal commands available at ~/bin when it is free.
# root is the checkout containing the personal scripts.
# configuration_args contains options not consumed by setup.
# configuration_result reports unchanged or skipped work.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
[ "${#configuration_args[@]}" -eq 0 ] || exit 2

#  - - -  Keep existing user files  - - -

if [ -L "$HOME/bin" ] && [ "$(readlink "$HOME/bin")" = "$root/bin" ]; then
    configuration_result unchanged
    exit 0
fi

if [ -e "$HOME/bin" ] || [ -L "$HOME/bin" ]; then
    printf 'Existing ~/bin retained. Add the checkout bin directory to PATH instead.\n'
    configuration_result skipped
    exit 0
fi

ln -s "$root/bin" "$HOME/bin"
printf 'Linked ~/bin to %s/bin\n' "$root"
