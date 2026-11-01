#!/bin/bash

# Install Signal Desktop on Debian, independently of the dotfiles menu.
# Upstream instructions: https://signal.org/download/linux/
# configuration_args contains options not consumed by setup.
# script_directory is the os/ directory containing the download helper.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

if [ "${#configuration_args[@]}" -gt 0 ]; then
    printf 'Unknown option: %s\n' "${configuration_args[0]}" >&2
    exit 2
fi

# Treat an unset variable as an error during installation.
set -u

#  - - -  Check the machine before changing anything  - - -

architecture=$(dpkg --print-architecture)
case "$architecture" in
    amd64) ;;
    *) printf 'Signal Desktop has no supported download in this script for %s.\n' "$architecture" >&2; exit 1 ;;
esac

# shellcheck source=os/lib/download.sh
source "$script_directory/lib/download.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Obtain Signal's signing key and repository definition  - - -

# Existing tools let us repair an old repository key before refreshing APT.
if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    sudo apt-get update --error-on=any
    sudo apt-get install -y ca-certificates curl gnupg
fi

download_file https://updates.signal.org/desktop/apt/keys.asc "$work/key.asc"
gpg --batch --yes --dearmor --output "$work/key.gpg" "$work/key.asc"
download_file https://updates.signal.org/static/desktop/apt/signal-desktop.sources "$work/signal-desktop.sources"

# The vendor still names its suite xenial; this is also its Debian route.
sudo install -m 644 "$work/key.gpg" /usr/share/keyrings/signal-desktop-keyring.gpg
sudo install -m 644 "$work/signal-desktop.sources" /etc/apt/sources.list.d/signal-desktop.sources

# Retain the old script's source file as a backup outside APT's active suffixes.
if [ -f /etc/apt/sources.list.d/signal-xenial.list ]; then
    sudo mv --backup=numbered /etc/apt/sources.list.d/signal-xenial.list \
        /etc/apt/sources.list.d/signal-xenial.list.disabled
fi

#  - - -  Install from the signed repository  - - -

sudo apt-get update --error-on=any
sudo apt-get install -y signal-desktop
printf 'Signal installed. Open it and link your phone.\n'
