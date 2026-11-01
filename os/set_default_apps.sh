#!/bin/bash

# Link the reviewed MIME associations from whichever checkout owns this script.
# Existing personal files are backed up, never silently discarded.
set -euo pipefail

#  - - -  Find this checkout  - - -

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_file="$root/mimeapps.list"
[ -f "$source_file" ] || { printf 'Missing %s\n' "$source_file" >&2; exit 1; }

#  - - -  Install links, preserving conflicting files and directories  - - -

for directory in "${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_DATA_HOME:-$HOME/.local/share}/applications"; do
    mkdir -p "$directory"
    target="$directory/mimeapps.list"

    if [ -L "$target" ] && [ "$(readlink "$target")" = "$source_file" ]; then
        printf 'Already linked: %s\n' "$target"
        continue
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        # mktemp reserves a unique backup name, including on repeated runs.
        backup=$(mktemp -d "$directory/mimeapps.backup.XXXXXX")
        mv -- "$target" "$backup/mimeapps.list"
        printf 'Backup: %s\n' "$backup/mimeapps.list"
    fi

    ln -s "$source_file" "$target"
    printf 'Linked: %s\n' "$target"
done
