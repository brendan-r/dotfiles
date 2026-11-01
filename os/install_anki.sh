#!/bin/bash

# Install the current upstream Anki release on Debian.
# https://docs.ankiweb.net/manual/platform/linux/installing
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

#  - - -  Select the archive for this machine, without prompting  - - -

architecture=$(dpkg --print-architecture)
case "$architecture" in
    amd64) archive_arch=x86_64 ;;
    arm64) archive_arch=aarch64 ;;
    *) printf 'Anki has no supported archive for %s.\n' "$architecture" >&2; exit 1 ;;
esac

# shellcheck source=os/lib/download.sh
source "$script_directory/lib/download.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Install extraction tools and the upstream desktop dependencies  - - -

sudo apt-get update --error-on=any
sudo apt-get install -y ca-certificates curl jq zstd xdg-utils \
    libxcb-xinerama0 libxcb-cursor0 libnss3 libxcb-icccm4 libxcb-keysyms1

# An existing distro installation would conflict with the upstream installer.
# Do not silently remove it or the user's data.
if dpkg-query -W -f='${Status}' anki 2>/dev/null | grep -qx 'install ok installed'; then
    printf 'Remove the APT Anki package before installing the upstream release. Your decks should be backed up first.\n' >&2
    exit 1
fi

#  - - -  Resolve one release asset, then verify it before extraction  - - -

download_file https://api.github.com/repos/ankitects/anki/releases/latest "$work/release.json"

# Reject missing/ambiguous assets explicitly. Never pass an HTTP error to jq
# or combine multiple download URLs into a single shell argument.
asset=$(jq -cer --arg suffix "-linux-$archive_arch.tar.zst" '
    [.assets[] | select(.name | startswith("anki-") and endswith($suffix))] |
    if length == 1 then .[0] else error("Expected exactly one matching Anki archive") end
' "$work/release.json")
url=$(printf '%s\n' "$asset" | jq -er '.browser_download_url')
digest=$(printf '%s\n' "$asset" | jq -er '.digest | select(startswith("sha256:"))')

# GitHub's digest checks transfer integrity; it is not an independent signature.
download_file "$url" "$work/anki.tar.zst"
verify_sha256 "$work/anki.tar.zst" "${digest#sha256:}"

#  - - -  Extract as the user; elevate only the upstream installation step  - - -

mkdir "$work/unpacked"
tar --zstd -xf "$work/anki.tar.zst" -C "$work/unpacked"
shopt -s nullglob
installers=("$work"/unpacked/*/install.sh)
if [ "${#installers[@]}" -ne 1 ]; then
    printf 'Unexpected Anki archive layout: expected one install.sh.\n' >&2
    exit 1
fi

cd -- "$(dirname -- "${installers[0]}")"
sudo ./install.sh
printf 'Anki installed. Open it to complete its first-run setup.\n'
