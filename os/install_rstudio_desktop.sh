#!/bin/bash

# Install the open-source RStudio Desktop build for Debian 13.
# Upstream instructions: https://docs.posit.co/ide/user/download.html
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
    *) printf 'RStudio Desktop has no supported download in this script for %s.\n' "$architecture" >&2; exit 1 ;;
esac

# shellcheck source=os/lib/download.sh
source "$script_directory/lib/download.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Find the current stable build for Debian 13  - - -

sudo apt-get update --error-on=any
sudo apt-get install -y ca-certificates curl jq r-base

# Posit documents this stable-release index and the build metadata it points to:
# https://dailies.rstudio.com/json-api/
download_file https://dailies.rstudio.com/api/v1/release/index.json "$work/releases.json"
build_url=$(jq -er '.released[0].published[0].builds_url | strings' "$work/releases.json") || {
    printf 'Could not find the current stable RStudio build in Posit metadata.\n' >&2
    exit 1
}

# Refuse unexpected hosts or paths rather than following arbitrary metadata.
if [[ ! "$build_url" =~ ^https://dailies\.rstudio\.com/api/v1/build/[a-zA-Z0-9.+_-]+/index\.json$ ]]; then
    printf 'Unexpected RStudio build metadata URL: %s\n' "$build_url" >&2
    exit 1
fi

download_file "$build_url" "$work/build.json"

# Select the open-source Desktop package, not a daily or commercial Pro build.
package_url=$(jq -er '.products.electron.platforms["jammy-amd64"] | select(.channel == "Release") | .link | strings' "$work/build.json") || {
    printf 'Could not find a stable RStudio Desktop package for Debian AMD64.\n' >&2
    exit 1
}
checksum=$(jq -er '.products.electron.platforms["jammy-amd64"].sha256 | strings' "$work/build.json") || {
    printf 'Posit did not provide a checksum for RStudio Desktop.\n' >&2
    exit 1
}

if [[ ! "$package_url" =~ ^https://dl\.dailies\.rstudio\.com/electron/jammy/amd64/rstudio-[a-zA-Z0-9.+_-]+-amd64\.deb$ ]]; then
    printf 'Unexpected RStudio package URL: %s\n' "$package_url" >&2
    exit 1
fi

# The digest comes from Posit over HTTPS; it is not an independent signature.
download_file "$package_url" "$work/rstudio.deb"
verify_sha256 "$work/rstudio.deb" "$checksum"

#  - - -  Let APT resolve the local package's dependencies  - - -

sudo apt-get install -y "$work/rstudio.deb"
printf 'RStudio Desktop installed. Open it to test your R session.\n'
