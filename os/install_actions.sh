#!/bin/bash

# The sourcing installer supplies these shared execution variables.
# shellcheck disable=SC2154

# Sourced by install_menu.sh. These operations do not decide what to install;
# they execute the already-reviewed plan and check the resulting machine state.

#  - - -  Find Homebrew and inspect existing installations  - - -

find_brew() {

    local candidate

    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi

    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1

}

package_present() {

    local kind=$1 package=$2 installed

    case "$kind" in
        tap)
            [ -n "$brew_command" ] || return 1
            "$brew_command" tap | grep -Fxq "$package"
            ;;
        brew|cask)
            [ -n "$brew_command" ] || return 1

            if [ "$kind" = cask ]; then
                installed=$("$brew_command" list --cask --versions "$package" 2>/dev/null) || return 1
            else
                installed=$("$brew_command" list --formula --versions "$package" 2>/dev/null) || return 1
            fi

            [ -n "$installed" ]
            ;;
        apt)
            installed=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) || return 1
            [ "$installed" = 'install ok installed' ]
            ;;
    esac

}

#  - - -  Install only the requested packages  - - -

install_homebrew() {

    local installer expected actual installer_url

    installer="$run_directory/homebrew-install.sh"
    installer_url=$(cat "$root/os/homebrew-installer.url")
    expected=$(cat "$root/os/homebrew-installer.sha256")

    printf 'Downloading the official Homebrew installer.\n'
    curl -qfL --progress-bar --retry 2 "$installer_url" -o "$installer" || return 1

    actual=$(shasum -a 256 "$installer") || return 1
    actual=${actual%% *}
    [ "$actual" = "$expected" ] || {
        printf 'Homebrew installer checksum did not match.\n' >&2
        return 1
    }

    # Keep native prompts visible. --yes explicitly approves this prerequisite.
    if "$assume_yes"; then
        NONINTERACTIVE=1 /bin/bash "$installer" || return 1
    else
        /bin/bash "$installer" || return 1
    fi

    brew_command=$(find_brew) || return 1
    "$brew_command" --version

}

install_package() {

    local kind=$1 package=$2

    if [ "$kind" = tap ]; then

        # New Homebrew versions require explicit trust for third-party taps.
        # The plan names this source before confirmation; older versions lack it.
        if "$brew_command" help trust >/dev/null 2>&1; then
            "$brew_command" trust "$package" >> "$current_log" 2>&1 || return 1
        fi

        "$brew_command" tap "$package" >> "$current_log" 2>&1 || return 1

    elif [ "$kind" = apt ]; then

        # Refresh once per run, and only if a selected package is missing.
        if ! "$apt_updated"; then
            sudo -v || return 1
            run_logged 'Refreshing APT package metadata' sudo -n apt-get update || return 1
            apt_updated=true
        fi

        # Authenticate outside the spinner so a password prompt stays usable.
        sudo -v || return 1
        run_logged "Installing $package" \
            sudo -n env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y --no-upgrade "$package" || return 1

    elif [ "$kind" = brew ]; then

        run_logged "Installing $package" \
            env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
            "$brew_command" install --formula "$package" || return 1

    else

        # Casks can prompt for administrator access; leave them in the foreground.
        # Never silently adopt or overwrite an application installed another way.
        printf 'Installing %s (application installer output follows).\n' "$package"
        env HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
            "$brew_command" install --cask "$package" 2>&1 | tee -a "$current_log" || return 1

    fi

    package_present "$kind" "$package"

}

