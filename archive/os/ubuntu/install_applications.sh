#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")" && source "../utils.sh"

declare -a COMMON_APT_PACKAGES=(
    "curl"
    "git"
    "imagemagick"
    "vim-gnome"
    "virtualbox"
    "build-essential"

    # GnuPG archive keys of the Debian archive
    "debian-archive-keyring"

    # Software which is not included by default
    # in Ubuntu due to legal or copyright reasons
    "ubuntu-restricted-extras"
)

declare -a DESKTOP_APT_PACKAGES=(
    "atom"
    "chromium-browser"
    "flashplugin-installer"
    "gimp"
    "vlc"
    "xclip"
)

declare -a SERVER_APT_PACKAGES=(
    "openssh-server"
    "fail2ban"
)

# Combine array, dependent on what wants installing - - - - - - - - - -

declare -a APT_PACKAGES=${COMMON_APT_PACKAGES[@]}

if $INSTALL_DESKTOP_APPS; then
    APT_PACKAGES=( ${APT_PACKAGES[@]} ${DESKTOP_APT_PACKAGES[@]} )
fi

if $INSTALL_SERVER_APPS; then
    APT_PACKAGES=( ${APT_PACKAGES[@]} ${SERVER_APT_PACKAGES[@]} )
fi


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

main() {

    local i=""

    add_software_sources
    update_and_upgrade

    printf "\n"

    for i in ${!APT_PACKAGES[*]}; do
        install_package "${APT_PACKAGES[$i]}"
    done

    printf "\n"

    update_and_upgrade
    remove_unneeded_packages

}

main
