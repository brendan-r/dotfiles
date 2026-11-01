#!/bin/bash

cd "$(dirname "${BASH_SOURCE}")" && source "../utils.sh"

# ----------------------------------------------------------------------
# | Privacy                                                            |
# ----------------------------------------------------------------------

set_privacy_settings() {

    # Turn off "Remote Search" so that search
    # terms in Dash don't get sent over the internet
    gsettings set com.canonical.Unity.Lenses remote-content-search 'none' && \

    # Disable Dash's "More suggestions" section
    gsettings set com.canonical.Unity.ApplicationsLens display-available-apps false

}

# ----------------------------------------------------------------------
# | UI/UX                                                              |
# ----------------------------------------------------------------------

gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'


set_ui_and_ux_settings() {

    # Hide the bluetooth and volume icons from the menu bar
    gsettings set com.canonical.indicator.bluetooth visible false && \
    gsettings set com.canonical.indicator.sound visible false && \

    # Hide the battery icon from the menu bar when the battery is not in use
    gsettings set com.canonical.indicator.power icon-policy "charge" && \
    gsettings set com.canonical.indicator.power show-time false && \

    # Use custom date format in the menu bar
    # (for other date interpreted sequences: date --help)
    gsettings set com.canonical.indicator.datetime custom-time-format "%l:%M %p" && \
    gsettings set com.canonical.indicator.datetime time-format "custom" && \

    # Set desktop background image location and options
    gsettings set org.gnome.desktop.background picture-options "stretched" && \
    #gsettings set org.gnome.desktop.background picture-uri "file:///home/..." && \

    # Set keyboard languages
    gsettings set org.gnome.libgnomekbd.keyboard layouts "[ 'us', 'ro' ]" && \

    # Set Launcher favorites
    gsettings set com.canonical.Unity.Launcher favorites "[
        'org.gnome.Nautilus.desktop',
        'chromium-browser.desktop',
        'rstudio.desktop',
        'sublime-text.desktop',
        'spotify.desktop',
        'firefox.desktop',
        'anki.desktop',
    ]"

}


make_firefox_default_browser(){
    sudo update-alternatives --install  /usr/bin/x-www-browser x-www-browser \
         /usr/bin/firefox 250
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

main() {
    execute "set_privacy_settings" "Privacy"
    execute "set_ui_and_ux_settings" "UI & UX"
    execute "make_firefox_default_browser" "Make Firefox Default Browser"
}

main
