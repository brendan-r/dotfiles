#!/bin/bash

# Link Firefox preferences into the default profiles of installed editions.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

[ "${#configuration_args[@]}" -eq 0 ] || { echo 'Unknown Firefox configuration arguments.' >&2; exit 2; }

#  - - -  Locate Firefox's profile registry for this platform  - - -

case "$(uname -s)" in
    Darwin)
        platform=macos
        profile_roots=("$HOME/Library/Application Support/Firefox")
        firefox=/Applications/Firefox.app/Contents/MacOS/firefox
        ;;
    Linux)
        platform=debian
        profile_roots=("$HOME/.mozilla/firefox" "${XDG_CONFIG_HOME:-$HOME/.config}/mozilla/firefox")
        firefox=$(command -v firefox || true)
        ;;
    *) echo 'Firefox configuration supports macOS and Debian only.' >&2; exit 1 ;;
esac

registries=()
for profile_root in "${profile_roots[@]}"; do
    registry="$profile_root/profiles.ini"
    if [ -f "$registry" ]; then
        registries+=("$registry")
    elif [ -e "$registry" ] || [ -L "$registry" ]; then
        echo 'Firefox profile registry is not a regular file; no profile was initialized.' >&2
        exit 1
    fi
done

if [ "${#registries[@]}" -eq 0 ]; then
    # A normal headless startup lets Firefox choose and register its own profile.
    # Screenshot of a local blank page exits on its own without visiting a site.
    for profile_root in "${profile_roots[@]}"; do
        configuration_parent_is_safe "$profile_root/profiles.ini"
    done
    [ -x "$firefox" ] || { echo 'Firefox is not installed; cannot initialize its profile.' >&2; exit 1; }
    scratch=$(mktemp -d)
    firefox_pid=''
    cleanup() {
        if [ -n "$firefox_pid" ]; then
            kill "$firefox_pid" 2>/dev/null || true
            wait "$firefox_pid" 2>/dev/null || true
        fi
        rm -rf "$scratch"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    printf 'Initializing the Firefox profile headlessly.\n'
    "$firefox" --no-remote --headless --screenshot "$scratch/blank.png" about:blank &
    firefox_pid=$!
    elapsed=0
    while kill -0 "$firefox_pid" 2>/dev/null && [ "$elapsed" -lt 90 ]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done
    if kill -0 "$firefox_pid" 2>/dev/null; then
        echo 'Firefox profile initialization timed out.' >&2
        exit 1
    fi
    if ! wait "$firefox_pid"; then
        firefox_pid=''
        echo 'Firefox could not initialize its profile headlessly.' >&2
        exit 1
    fi
    firefox_pid=''
    for profile_root in "${profile_roots[@]}"; do
        [ ! -f "$profile_root/profiles.ini" ] || registries+=("$profile_root/profiles.ini")
    done
    [ -s "$scratch/blank.png" ] && [ "${#registries[@]}" -gt 0 ] || {
        echo 'Firefox did not initialize its profile; no configuration was linked.' >&2
        exit 1
    }
fi

#  - - -  Resolve each installed edition's default without guessing  - - -

options=()
"$backup" && options+=(--backup)
for registry in "${registries[@]}"; do
    profile_root=${registry%/profiles.ini}
    profiles=$(awk '
    function save() {
        if (section ~ /^Install/ && default_path != "") installs[default_path] = 1
        if (section ~ /^Profile/ && is_default == "1" && path != "") {
            profiles[path] = relative
        }
        default_path = path = is_default = relative = ""
    }
    /^\[/ { save(); section = $0; sub(/^\[/, "", section); sub(/\].*$/, "", section); next }
    { sub(/\r$/, "") }
    /^Default=/ {
        value = substr($0, 9)
        if (section ~ /^Install/) default_path = value
        else is_default = value
    }
    /^Path=/ { path = substr($0, 6) }
    /^IsRelative=/ { relative = substr($0, 12) }
    END {
        save()
        for (p in installs) { print p; count++ }
        if (count) exit
        for (p in profiles) { selected = p; count++; rel = profiles[p] }
        if (count != 1) exit 2
        if (rel != "1" && selected !~ /^\//) exit 2
        print selected
    }
' "$registry") || {
        echo 'Firefox has no unambiguous default profile; select a default in Firefox and retry.' >&2
        exit 1
    }

    while IFS= read -r profile; do
        [ -n "$profile" ] || { echo 'Firefox has no default profile.' >&2; exit 1; }
        case "$profile" in
            /*) destination="$profile/user.js" ;;
            *) destination="$profile_root/$profile/user.js" ;;
        esac

        # Refuse traversal and profiles outside HOME, including symlinked parents.
        case "$destination" in
            "$HOME"/*) target=${destination#"$HOME/"} ;;
            *) echo 'A Firefox default profile is outside HOME; no file was changed.' >&2; exit 1 ;;
        esac
        [ -d "${destination%/user.js}" ] || {
            echo "Firefox profile directory does not exist: ${destination%/user.js}" >&2
            exit 1
        }
        options+=(--mapping os/firefox/user.js "$target")
    done <<< "$profiles"
done

#  - - -  Reuse the regular linker's conflict checks and backup handling  - - -

if /bin/bash "$root/os/create_symbolic_links.sh" "$root" "$platform" --status \
    "${options[@]}"; then
    configuration_result unchanged
    exit 0
fi

/bin/bash "$root/os/create_symbolic_links.sh" "$root" "$platform" "${options[@]}"
printf 'Restart Firefox to apply the linked preferences.\n'
