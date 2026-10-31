#!/bin/bash
# Internal entrypoint; use ./dotfiles install.
set -eo pipefail
root=${1:?Checkout root required}
os=${2:?Platform required}
backup=${3:-}
: "${HOME:?}"
if [ ! -d "$HOME" ] || [ -L "$HOME" ]; then echo 'HOME must be an existing non-symlink directory.' >&2; exit 1; fi
HOME=$(cd -P "$HOME" && pwd)
sources=() targets=() conflicts=()
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
    while [ -L "$path" ]; do
        depth=$((depth + 1))
        [ "$depth" -le 40 ] || return 1
        link=$(readlink "$path") || return 1
        case "$link" in /*) path=$link ;; *) path="$(dirname "$path")/$link" ;; esac
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
errors=0
while read -r scope source target extra; do
    case "$scope" in ''|'#'*) continue ;; esac
    [ "$scope" = common ] || [ "$scope" = "$os" ] || continue
    case "$source:$target" in *..*|/*|*:/.*|*://*) echo 'Invalid manifest path.' >&2; exit 1 ;; esac
    [ -z "$extra" ] || { echo 'Malformed link manifest.' >&2; exit 1; }
    if [ ! -e "$root/$source" ]; then
        printf 'Missing source: %s\n' "$root/$source" >&2
        errors=1
    fi
    sources+=("$root/$source") targets+=("$HOME/$target")
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
    if [ -e "$path" ] || [ -L "$path" ]; then add_conflict "$path"; fi
done < "$root/os/links.tsv"
[ "$errors" -eq 0 ] || exit 1
if [ "${#conflicts[@]}" -gt 0 ]; then
    printf 'Conflicting paths:\n' >&2
    printf '  %s\n' "${conflicts[@]}" >&2
    [ "$backup" = --backup ] || { echo 'Resolve conflicts or rerun with --backup.' >&2; exit 1; }
    # Stage in HOME first: even .local itself may be a conflict. Never delete backups.
    saved=$(mktemp -d "$HOME/.dotfiles-backup.XXXXXX")
    printf 'Preserving originals in %s\n' "$saved"
    for path in "${conflicts[@]}"; do
        relative=${path#"$HOME/"}
        mkdir -p "$saved/$(dirname "$relative")"
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
fi
for ((i=0; i<${#sources[@]}; i++)); do
    target=${targets[$i]}
    source=${sources[$i]}
    if same_link "$target" "$source"; then continue; fi
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
done
printf 'Configuration installed for %s from %s\n' "$os" "$root"
