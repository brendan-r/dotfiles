#!/bin/bash

# Internal entrypoint; use ./dotfiles install.
set -eo pipefail

root=${1:?Checkout root required}
os=${2:?Platform required}
shift 2

# shellcheck source=os/lib/backup_history.sh
source "$root/os/lib/backup_history.sh"

backup=''
status_only=false
selective=false
requested=()

# Selection is explicit: an empty selection must never mean "link everything".
while [ "$#" -gt 0 ]; do
    case "$1" in
        --backup)
            backup=--backup
            shift
            ;;
        --status)
            status_only=true
            shift
            ;;
        --selected)
            selective=true
            shift
            requested=("$@")
            break
            ;;
        *)
            printf 'Unknown linker option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

#  - - -  Validate HOME and prepare link inspection helpers  - - -

: "${HOME:?}"

if [ ! -d "$HOME" ] || [ -L "$HOME" ]; then
    echo 'HOME must be an existing non-symlink directory.' >&2
    exit 1
fi

HOME=$(cd -P "$HOME" && pwd)
sources=()
targets=()
conflicts=()

add_conflict() {

    local item

    for item in "${conflicts[@]}"; do
        [ "$1" != "$item" ] || return 0
    done

    conflicts+=("$1")

}

same_link() {

    local path=$1 expected=$2 link directory depth=0

    [ -L "$path" ] || return 1

    # Resolve relative and chained links without relying on GNU readlink -f.
    while [ -L "$path" ]; do
        depth=$((depth + 1))
        [ "$depth" -le 40 ] || return 1
        link=$(readlink "$path") || return 1

        case "$link" in
            /*) path=$link ;;
            *) path="$(dirname "$path")/$link" ;;
        esac
    done

    [ -e "$path" ] || return 1
    if [ -d "$path" ]; then
        path=$(cd -P "$path" && pwd) || return 1
    else
        directory=$(cd -P "$(dirname "$path")" && pwd) || return 1
        path="$directory/$(basename "$path")"
    fi

    [ "$path" = "$expected" ]

}

#  - - -  Recognize links created by the previous checkout layout  - - -

legacy_link() {

    local path=$1 target=$2 old_source=''

    [ -L "$path" ] || return 1

    # The previous linker always wrote absolute checkout paths. Only replace
    # exact historical destinations; any other link remains a normal conflict.
    case "$target" in
        .bash_aliases|.bash_exports|.bash_functions|.bash_logout|.bash_options|.bash_profile|.bash_prompt|.bashrc|.curlrc|.inputrc|.screenrc|.bash_mac_stuff)
            old_source="shell/${target#.}"
            ;;
        .gitattributes|.gitconfig|.gitignore) old_source="git/${target#.}" ;;
        .config/autorandr|.config/dunst|.config/i3|.config/keyd|.config/kitty|.config/picom|.config/polybar|.config/rofi)
            old_source="config/${target#.config/}"
            ;;
        .local/share/rofi) old_source=local-share/rofi ;;
        .xinitrc) old_source=config/i3/xinitrc ;;
        .yabairc) old_source=mac-stuff/yabairc ;;
        .skhdrc) old_source=mac-stuff/skhdrc ;;
        *) return 1 ;;
    esac

    [ "$(readlink "$path")" = "$root/$old_source" ]

}

#  - - -  Resolve the catalog before inspecting or changing destinations  - - -

# Command substitution preserves parser failures; process substitution would not.
manifest=$(/bin/bash "$root/os/catalog_links.sh" "$root" "$os")

errors=0
all_present=true
found=()

while IFS=$'\t' read -r _scope source target; do

    if "$selective"; then
        wanted=false

        for requested_target in "${requested[@]}"; do
            if [ "$target" = "$requested_target" ]; then
                wanted=true
                found+=("$target")
                break
            fi
        done

        "$wanted" || continue
    fi

    if [ ! -e "$root/$source" ]; then
        printf 'Missing source: %s\n' "$root/$source" >&2
        errors=1
    fi
    sources+=("$root/$source")
    targets+=("$HOME/$target")

    # Walk parents from HOME down. Never follow a symlinked configuration directory.
    remainder=$target
    parent=$HOME
    blocked=false

    while [[ "$remainder" == */* ]]; do
        parent="$parent/${remainder%%/*}"
        remainder=${remainder#*/}
        if [ -L "$parent" ] || { [ -e "$parent" ] && [ ! -d "$parent" ]; }; then
            add_conflict "$parent"
            blocked=true
            break
        fi
    done

    "$blocked" && continue
    path="$HOME/$target"
    if same_link "$path" "$root/$source"; then
        continue
    fi

    all_present=false

    # Migrate our exact old absolute symlink without backing it up as a user file.
    if legacy_link "$path" "$target"; then
        continue
    fi

    if [ -e "$path" ] || [ -L "$path" ]; then
        add_conflict "$path"
    fi
done <<< "$manifest"

for requested_target in "${requested[@]}"; do
    matched=false

    for target in "${found[@]}"; do
        if [ "$target" = "$requested_target" ]; then
            matched=true
            break
        fi
    done

    if ! "$matched"; then
        printf 'Unknown selected link: %s\n' "$requested_target" >&2
        errors=1
    fi
done

[ "$errors" -eq 0 ] || exit 1

if "$status_only"; then
    [ "${#conflicts[@]}" -eq 0 ] && "$all_present"
    exit "$?"
fi

#  - - -  Preserve conflicts before replacing any selected links  - - -

if [ "${#conflicts[@]}" -gt 0 ]; then
    printf 'Conflicting paths:\n' >&2
    printf '  %s\n' "${conflicts[@]}" >&2

    if [ "$backup" != --backup ]; then
        echo 'Resolve conflicts or rerun with --backup.' >&2
        exit 1
    fi

    # Stage in HOME first: even .local itself may be a conflict. Never delete backups.
    saved=$(mktemp -d "$HOME/.dotfiles-backup.XXXXXX")
    printf 'Preserving originals in %s\n' "$saved"

    # If any later move fails or the process is interrupted, record whichever
    # originals were already staged, even if the final directory was not made.
    moved_backups=()
    final=''

    flush_backup_history() {

        local relative location failed=false
        location=$saved
        if [ -n "$final" ] && [ -d "$final" ] && [ ! -d "$saved" ]; then
            location=$final
        fi

        for relative in "${moved_backups[@]}"; do
            if [ -e "$location/$relative" ] || [ -L "$location/$relative" ]; then
                record_backup "$HOME/$relative" "$location/$relative" || failed=true
            fi
        done
        moved_backups=()
        ! "$failed"

    }

    finish_interrupted_backup() {

        local status=$1
        trap - EXIT
        flush_backup_history || status=1
        exit "$status"

    }

    trap 'finish_interrupted_backup "$?"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    for path in "${conflicts[@]}"; do
        relative=${path#"$HOME/"}
        mkdir -p "$saved/$(dirname "$relative")"
        moved_backups+=("$relative")
        mv "$path" "$saved/$relative"
    done

    parent=$HOME

    for part in .local state dotfiles backups; do
        parent="$parent/$part"
        if [ -L "$parent" ] || { [ -e "$parent" ] && [ ! -d "$parent" ]; }; then
            printf 'Unsafe backup destination: %s. Originals retained at %s\n' "$parent" "$saved" >&2
            exit 1
        fi
        mkdir -p "$parent"
    done

    final="$parent/$(date -u +%Y%m%dT%H%M%SZ)-${saved##*.}"
    mv "$saved" "$final"
    printf 'Backup: %s\n' "$final"
    flush_backup_history
    trap - EXIT INT TERM
fi

#  - - -  Create only missing or changed links  - - -

for ((i = 0; i < ${#sources[@]}; i++)); do
    target=${targets[$i]}
    source=${sources[$i]}

    if same_link "$target" "$source"; then
        continue
    fi

    mkdir -p "$(dirname "$target")"

    # Never remove an unrelated symlink that appeared after validation.
    if legacy_link "$target" "${target#"$HOME/"}"; then
        rm "$target"
    fi

    ln -s "$source" "$target"
done

printf 'Configuration installed for %s from %s\n' "$os" "$root"
