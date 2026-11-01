#!/bin/bash

# Install Spotify on Debian, independently of the dotfiles menu.
# Upstream instructions: https://www.spotify.com/us/download/linux/
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
    *) printf 'Spotify has no supported download in this script for %s.\n' "$architecture" >&2; exit 1 ;;
esac

# shellcheck source=os/lib/download.sh
source "$script_directory/lib/download.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Obtain the repository signing key  - - -

# Existing tools let us repair an old repository key before refreshing APT.
if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    sudo apt-get update --error-on=any
    sudo apt-get install -y ca-certificates curl gnupg
fi

download_file https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc "$work/key.asc"
gpg --batch --yes --dearmor --output "$work/key.gpg" "$work/key.asc"

# Scope this key to Spotify; do not add it to APT's global trust store.
sudo install -d -m 755 /etc/apt/keyrings
sudo install -m 644 "$work/key.gpg" /etc/apt/keyrings/spotify.gpg

#  - - -  Configure the repository and install  - - -

# Replace our own file on reruns rather than appending duplicate entries.
printf '%s\n' 'deb [arch=amd64 signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free' \
    > "$work/spotify.list"
sudo install -m 644 "$work/spotify.list" /etc/apt/sources.list.d/spotify.list

sudo apt-get update --error-on=any
sudo apt-get install -y spotify-client
printf 'Spotify installed. Open it and sign in.\n'
