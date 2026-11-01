#!/bin/bash

# Register macOS launch agents without starting permission-gated applications.
# configuration_args contains the executable and launch-agent label pairs.
# configuration_parent_is_safe checks each destination under HOME.
# configuration_result reports when services were already registered.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/setup.sh" || exit 1
setup "$@"
set -- "${configuration_args[@]}"
[ "$#" -gt 0 ] && [ "$(( $# % 2 ))" -eq 0 ] || {
    printf 'Expected executable and launch-agent label pairs.\n' >&2
    exit 2
}

#  - - -  Validate all destinations before installing any services  - - -

for ((index = 0; index < ${#configuration_args[@]}; index += 2)); do
    executable=${configuration_args[$index]}
    label=${configuration_args[$((index + 1))]}
    case "$executable" in ''|-*|*[!a-zA-Z0-9._/-]*) exit 1 ;; esac
    case "$label" in ''|.*|*[!a-zA-Z0-9.-]*) exit 1 ;; esac
    destination="$HOME/Library/LaunchAgents/$label.plist"
    configuration_parent_is_safe "$destination"
    [ ! -L "$destination" ] || exit 1
done

#  - - -  Register missing agents and check their executable paths  - - -

changed=false
while [ "$#" -gt 0 ]; do
    executable=$1
    label=$2
    shift 2
    destination="$HOME/Library/LaunchAgents/$label.plist"
    if [ ! -e "$destination" ]; then
        mkdir -p "$(dirname "$destination")"
        "$executable" --install-service
        changed=true
    fi

    /usr/bin/plutil -lint "$destination"
    actual=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$destination")
    [ "$actual" = "$label" ]
    actual=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$destination")
    [ -x "$actual" ] || { printf 'Service executable is missing: %s\n' "$actual" >&2; exit 1; }
    printf 'Registered %s. Permission approval and startup are listed in ~/TODO.org.\n' "$label"
done

if ! "$changed"; then
    configuration_result unchanged
fi
