#!/bin/bash

# Add a backup to the user's TODO file. This helper does not create the backup;
# callers invoke it only after the original has been safely preserved.

#  - - -  Record the original and saved paths  - - -

record_backup() {

    local original=$1 saved=$2 todo temporary input

    todo="$HOME/TODO.org"

    # Never replace a symlink or another non-file object at the TODO path.
    if [ -L "$todo" ] || { [ -e "$todo" ] && [ ! -f "$todo" ]; }; then
        printf 'Cannot record backup in %s: expected a regular file.\n' "$todo" >&2
        printf 'Backup retained: %s -> %s\n' "$original" "$saved" >&2
        return 1
    fi

    temporary=$(mktemp "$HOME/.dotfiles-backup-history.XXXXXX") || {
        printf 'Cannot create backup history. Backup retained: %s -> %s\n' "$original" "$saved" >&2
        return 1
    }

    input=$todo
    [ -f "$input" ] || input=/dev/null

    # Match the exact line inside the Backups section. Keep user notes and
    # existing entries untouched, and create a section at the end if needed.
    if ! BACKUP_ORIGINAL="$original" BACKUP_SAVED="$saved" awk '
        { lines[NR] = $0 }
        END {
            entry = "- " ENVIRON["BACKUP_ORIGINAL"] " -> " ENVIRON["BACKUP_SAVED"]
            for (i = 1; i <= NR; i++) {
                if (lines[i] ~ /^\* /) {
                    if (inside && !boundary) boundary = i
                    inside = (lines[i] == "* Backups")
                    if (inside && !section) section = i
                }
                if (inside && lines[i] == entry) found = 1
            }
            if (!boundary) boundary = NR + 1
            for (i = 1; i <= NR; i++) {
                if (section && !found && i == boundary) print entry
                print lines[i]
            }
            if (!found) {
                if (!section) {
                    if (NR) print ""
                    else print "#+title: Post-install tasks\n"
                    print "* Backups"
                }
                if (!section || boundary == NR + 1) print entry
            }
        }
    ' "$input" > "$temporary"; then
        rm -f "$temporary"
        printf 'Cannot record backup in %s. Backup retained: %s -> %s\n' "$todo" "$original" "$saved" >&2
        return 1
    fi

    if [ -f "$todo" ] && cmp -s "$todo" "$temporary"; then
        rm -f "$temporary"
    elif ! mv "$temporary" "$todo"; then
        rm -f "$temporary"
        printf 'Cannot update %s. Backup retained: %s -> %s\n' "$todo" "$original" "$saved" >&2
        return 1
    fi

}
