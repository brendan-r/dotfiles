#!/bin/bash

# Exercise TODO collection independently with synthetic catalogue values.
# Bats supplies the status and output variables after run.
# shellcheck disable=SC2154

# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {

    require_guest
    case_root="$BATS_TEST_TMPDIR/todo-case"
    mkdir -p "$case_root/home"
    export HOME="$case_root/home"
    root=$DOTFILES_CANDIDATE
    platform=debian
    catalog_data=

    # shellcheck source=os/menu_catalog.sh
    source "$root/os/menu_catalog.sh"
    # shellcheck source=os/post_install.sh
    source "$root/os/post_install.sh"
    # shellcheck source=os/lib/backup_history.sh
    source "$root/os/lib/backup_history.sh"

    # Override only the document location, leaving real yq parsing in place.
    # Called by the sourced post-install function.
    # shellcheck disable=SC2329
    catalog_read() {
        /bin/bash "$root/os/yq.sh" -r "$1" "$case_root/catalog.yaml"
    }

    cat > "$case_root/catalog.yaml" <<'YAML'
post_install:
  "10. Shared heading":
    always: [An always-present task]
features:
  tile:
    todo:
      "2. First heading": [A short-ID task]
    platforms:
      debian: {}
  tile-wide:
    todo:
      "2. First heading": [A common task]
    platforms:
      debian:
        todo:
          "1. Second heading": [A Debian task]
      macos:
        todo:
          "1. Second heading": [A macOS task]
  unfinished:
    todo:
      "2. First heading": [A failed task]
    platforms:
      debian: {}
YAML

}

function todos__backups__preserve_personal_content_and_remain_at_end { # @test

    cat > "$HOME/TODO.org" <<'ORG'
#+title: Personal notes
* Personal
- [X] Already done
Keep this note.
ORG
    record_backup "$HOME/example file" "$HOME/saved file"
    record_backup "$HOME/example file" "$HOME/saved file"
    plan_features=(tile-wide)
    results=('Installed and verified')
    write_post_install
    record_backup "$HOME/other" "$HOME/another backup"

    grep -Fxq -- '- [X] Already done' "$HOME/TODO.org"
    grep -Fxq 'Keep this note.' "$HOME/TODO.org"
    [ "$(grep -Fc -- "- $HOME/example file -> $HOME/saved file" "$HOME/TODO.org")" = 1 ]
    grep -Fxq -- "- $HOME/other -> $HOME/another backup" "$HOME/TODO.org"
    [ "$(grep '^\* ' "$HOME/TODO.org" | tail -1)" = '* Backups' ]

}

teardown() {
    rm -rf "$case_root"
}

function todos__selection__successful_features_and_platform_tasks_follow_heading_order { # @test

    plan_features=(tile-wide unfinished)
    results=('Installed and verified' Failed)
    write_post_install

    grep -Fxq -- '- [ ] A common task' "$HOME/TODO.org"
    grep -Fxq -- '- [ ] A Debian task' "$HOME/TODO.org"
    grep -Fxq -- '- [ ] An always-present task' "$HOME/TODO.org"
    ! grep -Fq 'A macOS task' "$HOME/TODO.org"
    ! grep -Fq 'A failed task' "$HOME/TODO.org"
    ! grep -Fq 'A short-ID task' "$HOME/TODO.org"
    [ "$(grep '^\* ' "$HOME/TODO.org" | tr '\n' '|')" = \
      '* Second heading|* First heading|* Shared heading|' ]

    # The same feature uses its other platform's tasks, and no Debian-only task.
    rm "$HOME/TODO.org"
    platform=macos
    results=('Already present' Failed)
    write_post_install
    grep -Fxq -- '- [ ] A macOS task' "$HOME/TODO.org"
    ! grep -Fq 'A Debian task' "$HOME/TODO.org"

}

function todos__rerun__preserves_checked_boxes_personal_text_and_old_tasks { # @test

    cat > "$HOME/TODO.org" <<'ORG'
#+title: Personal notes
* First heading
- [X] A common task
Personal notes stay here.
- [ ] An older task
ORG
    plan_features=(tile-wide)
    results=('Installed and verified')
    write_post_install
    cp "$HOME/TODO.org" "$case_root/first"
    write_post_install
    cmp "$HOME/TODO.org" "$case_root/first"
    grep -Fxq -- '- [X] A common task' "$HOME/TODO.org"
    grep -Fxq 'Personal notes stay here.' "$HOME/TODO.org"
    grep -Fxq -- '- [ ] An older task' "$HOME/TODO.org"
    [ "$(grep -Fc 'A common task' "$HOME/TODO.org")" = 1 ]

}
