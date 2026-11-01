#!/bin/bash

# Install the checked-in keyd layout for the Debian keyboard.
# root is this script's checkout, including when run from a worktree.
# backup is true only when --backup was requested.
# configuration_args contains options not consumed by setup.
# record_backup adds the original and saved paths to ~/TODO.org.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
[ "${#configuration_args[@]}" -eq 0 ] || exit 2

#  - - -  Preserve an existing keyd layout  - - -

command=$(command -v keyd.rvaiya || command -v keyd)
sudo -v
if sudo test -L /etc/keyd; then
    printf 'Existing /etc/keyd is a symlink; resolve it before installing.\n' >&2
    exit 1
fi
sudo mkdir -p /etc/keyd

if { sudo test -e /etc/keyd/default.conf || sudo test -L /etc/keyd/default.conf; } \
    && ! sudo cmp -s "$root/home/debian/.config/keyd/default.conf" /etc/keyd/default.conf; then
    if ! "$backup"; then
        printf 'Existing /etc/keyd/default.conf retained; use --backup.\n' >&2
        exit 1
    fi

    saved=$(sudo mktemp -d /etc/keyd/backup.XXXXXX)
    sudo cp -P /etc/keyd/default.conf "$saved/default.conf"
    printf 'Backup: %s/default.conf\n' "$saved"
    record_backup /etc/keyd/default.conf "$saved/default.conf"
fi

#  - - -  Install a root-owned copy and activate keyd  - - -

sudo rm -f /etc/keyd/default.conf
sudo install -o root -g root -m 644 "$root/home/debian/.config/keyd/default.conf" /etc/keyd/default.conf
sudo systemctl enable --now keyd.service
sudo "$command" reload
sudo systemctl is-active --quiet keyd.service
printf 'keyd configuration installed and service active.\n'
