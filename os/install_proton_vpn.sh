#!/bin/bash

# Install Proton VPN on Debian; this script also runs independently of the menu.
# Upstream instructions: https://protonvpn.com/support/linux-vpn-debian-ubuntu
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
    *) printf 'Proton VPN has no supported download in this script for %s.\n' "$architecture" >&2; exit 1 ;;
esac

# shellcheck source=os/lib/download.sh
source "$script_directory/lib/download.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Obtain the vendor's repository signing key  - - -

# Existing tools let us refresh a repository key before updating APT metadata.
if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    sudo apt-get update --error-on=any
    sudo apt-get install -y ca-certificates curl gnupg
fi

# Bootstrap trust over HTTPS. APT verifies repository signatures and package
# checksums from here onwards; there is no versioned .deb to scrape or pin.
download_file https://repo.protonvpn.com/debian/public_key.asc "$work/key.asc"
gpg --batch --yes --dearmor --output "$work/key.gpg" "$work/key.asc"

# Use the same paths and source definition as Proton's repository package.
# Installing that package through APT below gives it ownership of future updates.
sudo install -d -m 755 /usr/share/keyrings
sudo install -m 644 "$work/key.gpg" /usr/share/keyrings/protonvpn-stable-archive-keyring.gpg

#  - - -  Register the stable repository, without duplicate entries on reruns  - - -

cat > "$work/protonvpn-stable.sources" <<'SOURCES'
Types: deb
URIs: https://repo.protonvpn.com/debian
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/protonvpn-stable-archive-keyring.gpg
SOURCES

sudo install -m 644 "$work/protonvpn-stable.sources" /etc/apt/sources.list.d/protonvpn-stable.sources

#  - - -  Let APT select and verify the current packages  - - -

# The signed repository and AMD64 dependency resolution have been tested.
# The VPN application, i3 keyring integration and an actual connection have not.
sudo apt-get update --error-on=any
sudo apt-get install -y protonvpn-stable-release proton-vpn-gnome-desktop gnome-keyring

# Desktop/session services belong to the desktop setup, not this VPN installer.
printf 'Proton VPN installed. Sign in and test a connection in your desktop session.\n'
printf 'Upstream officially supports GNOME; i3 integration requires a working keyring.\n'
