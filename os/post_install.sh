#!/bin/bash

# The sourcing installer supplies plan_features, platform, and results.
# shellcheck disable=SC2154

#  - - -  Add missing checkboxes without changing existing user entries  - - -

append_reminders() {

    local rows=$1 heading task temporary

    while IFS=$'\t' read -r heading task; do
        [ -n "$heading" ] && [ -n "$task" ] || continue
        temporary=$(mktemp "$HOME/.dotfiles-todo.XXXXXX") || return 1

        # Environment variables preserve literal backslashes in task text.
        # Match within the named heading, ignoring only the checkbox state.
        if ! TODO_HEADING="$heading" TODO_TASK="$task" awk '
            { lines[NR] = $0 }
            END {
                wanted = "* " ENVIRON["TODO_HEADING"]
                task = ENVIRON["TODO_TASK"]
                for (i = 1; i <= NR; i++) {
                    if (lines[i] ~ /^\* /) {
                        if (inside && !boundary) boundary = i
                        inside = (lines[i] == wanted)
                        if (inside && !section) section = i
                        if (lines[i] == "* Backups" && !backups) backups = i
                    }
                    text = lines[i]
                    if (inside && sub(/^[[:space:]]*[-+] \[[ xX-]\] /, "", text) && text == task) {
                        found = 1
                    }
                }
                if (!boundary) boundary = NR + 1
                for (i = 1; i <= NR; i++) {
                    if (section && !found && i == boundary) print "- [ ] " task "\n"
                    # Keep a newly created backup section at the end, even if
                    # other reminders are added after backups were recorded.
                    if (!section && !found && i == backups) {
                        print "\n" wanted
                        print "- [ ] " task "\n"
                        added = 1
                    }
                    print lines[i]
                }
                if (!found) {
                    if (!section && !added) print "\n" wanted
                    if ((!section && !added) || (section && boundary == NR + 1)) print "- [ ] " task
                }
            }
        ' "$HOME/TODO.org" > "$temporary"; then
            rm -f "$temporary"
            return 1
        fi

        # Leave an unchanged file alone; otherwise replace it atomically.
        if cmp -s "$HOME/TODO.org" "$temporary"; then
            rm -f "$temporary"
        else
            mv "$temporary" "$HOME/TODO.org" || return 1
        fi
    done <<< "$rows"

}

#  - - -  Collect applicable tasks in the heading order supplied by YAML  - - -

write_post_install() {

    local rows index completed=''

    # Refuse indirect destinations rather than modifying a file through a link.
    if [ -L "$HOME/TODO.org" ] \
        || { [ -e "$HOME/TODO.org" ] && [ ! -f "$HOME/TODO.org" ]; }; then
        printf 'Cannot update ~/TODO.org: expected a regular file.\n' >&2
        return 1
    fi

    for ((index = 0; index < ${#plan_features[@]}; index++)); do
        case "${results[$index]}" in
            'Installed and verified'|'Already present')
                completed="${completed:+$completed,}${plan_features[$index]}"
                ;;
        esac
    done

    # Each heading starts with a number for sorting. Strip that prefix before
    # matching the user's existing headings and checked boxes in TODO.org.
    # Task order within a heading follows catalogue order (stable sort).
    # shellcheck disable=SC2016
    rows=$(COMPLETED="$completed" PLATFORM="$platform" CATALOG_SEPARATOR=$'\037' catalog_read '
        . as $catalog |
        [($catalog.post_install // {} | to_entries | .[] |
          {"key": .key, "value": (.value.always // [])}),
         ($catalog.features | to_entries | .[] |
          select((.key | @base64) as $id | strenv(COMPLETED) | split(",") | map(select((. | @base64) == $id)) | length > 0) |
          [(.value.todo // {}), (.value.platforms[strenv(PLATFORM)].todo // {})] |
          .[] | to_entries | .[])] |
        .[] | .key as $heading | .value[] | [$heading, .] | join(strenv(CATALOG_SEPARATOR))
    ' | awk -F $'\037' '
        # yq may emit one blank line when there are no applicable tasks.
        $0 == "" { next }
        NF != 2 {
            print "Invalid TODO heading or task: unexpected control character" > "/dev/stderr"
            exit 1
        }
        $1 !~ /^[0-9]+[.] / {
            print "Invalid numbered TODO heading: " $1 > "/dev/stderr"
            exit 1
        }
        {
            order = $1
            sub(/[.].*$/, "", order)
            heading = $1
            sub(/^[0-9]+[.] /, "", heading)
            if (heading == "") {
                print "Empty TODO heading" > "/dev/stderr"
                exit 1
            }
            printf "%s\t%s\t%s\n", order, heading, $2
        }
    ' | LC_ALL=C sort -s -t "$(printf '\t')" -k1,1n | cut -f2-) || return 1

    if [ ! -e "$HOME/TODO.org" ]; then
        (set -o noclobber; printf '#+title: Post-install tasks\n' > "$HOME/TODO.org") \
            || return 1
    fi

    append_reminders "$rows" || return 1
    printf 'Remaining user steps: %s/TODO.org\n' "$HOME"

}
