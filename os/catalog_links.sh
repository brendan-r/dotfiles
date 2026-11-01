#!/bin/bash

# Discover HOME-relative dotfiles before changing anything in the user's HOME.
# Output is scope, checkout-relative source, HOME-relative target, tab-separated.
set -eo pipefail

root=${1:?Checkout root required}
platform=${2:?Platform required (macos, debian, or all)}

fail() {

    printf 'Invalid dotfiles inventory: %s\n' "$*" >&2
    exit 1

}

valid_path() {

    # Paths are data, not shell expressions. Reject ambiguous or unsafe names.
    case "$1" in
        ''|/*|*/|*//*|.|..|./*|../*|*/./*|*/../*|*/.|*/..|*\\*|*[[:cntrl:]]*)
            return 1
            ;;
    esac

}

case "$platform" in
    macos|debian|all) ;;
    *) fail "unknown platform: $platform" ;;
esac

#  - - -  Collect one complete inventory before printing anything  - - -

shopt -s dotglob nullglob
scopes=()
targets=()
rows=()

visit() {

    local scope=$1 relative=$2 directory entry target previous index
    local entries=()

    directory="$root/home/$scope${relative:+/$relative}"
    [ -d "$directory" ] && [ ! -L "$directory" ] || fail "not a directory: $directory"
    entries=("$directory"/*)

    for entry in "${entries[@]}"; do
        target="${relative:+$relative/}${entry##*/}"
        valid_path "$target" || fail "unsafe path: $target"
        [ ! -L "$entry" ] || fail "source is a symbolic link: $entry"

        # These directories mirror HOME's hierarchy; children are link units.
        case "$target" in
            .config|.local|.local/share)
                [ -d "$entry" ] || fail "expected directory: $entry"
                visit "$scope" "$target"
                continue
                ;;
        esac

        [ -f "$entry" ] || [ -d "$entry" ] || fail "unsupported source: $entry"

        # Platform-specific sources may share a destination with the other OS,
        # but neither may overlap common or another entry on the same platform.
        for ((index = 0; index < ${#targets[@]}; index++)); do
            previous=${targets[$index]}
            if [ "$scope" != common ] && [ "${scopes[$index]}" != common ] \
                && [ "$scope" != "${scopes[$index]}" ]; then
                continue
            fi
            case "$target/" in "$previous/"*) fail "overlapping destinations: $previous and $target" ;; esac
            case "$previous/" in "$target/"*) fail "overlapping destinations: $target and $previous" ;; esac
        done

        targets+=("$target")
        scopes+=("$scope")
        if [ "$platform" = all ] || [ "$scope" = common ] || [ "$scope" = "$platform" ]; then
            rows+=("$scope"$'\t'"home/$scope/$target"$'\t'"$target")
        fi
    done

}

# A missing scope is empty; adding its first file requires no metadata edit.
for scope in common macos debian; do
    directory="$root/home/$scope"
    if [ -e "$directory" ] || [ -L "$directory" ]; then
        visit "$scope" ''
    fi
done

[ "${#rows[@]}" -gt 0 ] || fail 'no dotfiles found for this platform'
printf '%s\n' "${rows[@]}"
