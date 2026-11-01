#!/bin/bash
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {
    guest_setup
    # Use an invented HOME tree, independent of the user's configuration.
    rm -rf "${repo:?}/home"
    mkdir -p "$repo/home/common/.config" "$repo/home/macos" "$repo/home/debian"
    for name in one two three four five; do
        printf '%s\n' "$name" > "$repo/home/common/.sample-$name"
    done
    printf 'six\n' > "$repo/home/common/.config/sample"
    printf 'mac\n' > "$repo/home/macos/.platform-mac"
    printf 'linux\n' > "$repo/home/debian/.platform-linux"

}

function dotfiles__install__platform_links_resolve_in_paths_with_spaces { # @test
    install
    verify_links
}

function dotfiles__install__rerun_keeps_valid_links_without_backups { # @test
    install
    install
    verify_links
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
    [ ! -e "$HOME/TODO.org" ]
}

function dotfiles__install__correct_relative_links_are_preserved { # @test
    install
    relative=''
    parent=$HOME
    while [ "$parent" != / ]; do relative="../$relative"; parent=$(dirname "$parent"); done
    relative="$relative${repo#/}/home/common/.sample-one"
    rm "$HOME/.sample-one"
    ln -s "$relative" "$HOME/.sample-one"
    install
    [ "$(readlink "$HOME/.sample-one")" = "$relative" ]
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
}

function dotfiles__install__conflicts_preserve_originals_before_linking { # @test
    make_conflicts
    expect_failure install
    [ "$(cat "$HOME/.sample-one")" = 'keep me' ]
    [ "$(readlink "$HOME/.sample-two")" = "$case_root/does-not-exist" ]
    [ "$(cat "$HOME/.sample-three/original")" = 'directory contents' ]
    [ ! -e "$HOME/.sample-four" ]
}

function dotfiles__install__backups_preserve_files_directories_and_dangling_links { # @test
    make_conflicts
    install --backup
    verify_links
    saved=$(find "$HOME/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d)
    [ "$(cat "$saved/.sample-one")" = 'keep me' ]
    [ "$(readlink "$saved/.sample-two")" = "$case_root/does-not-exist" ]
    [ "$(cat "$saved/.sample-three/original")" = 'directory contents' ]
    grep -Fxq '* Backups' "$HOME/TODO.org"
    grep -Fxq -- "- $HOME/.sample-one -> $saved/.sample-one" "$HOME/TODO.org"
    grep -Fxq -- "- $HOME/.sample-two -> $saved/.sample-two" "$HOME/TODO.org"
    grep -Fxq -- "- $HOME/.sample-three -> $saved/.sample-three" "$HOME/TODO.org"
    cp "$HOME/TODO.org" "$case_root/backup-history"
    install --backup
    [ "$(find "$HOME/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d)" = "$saved" ]
    cmp "$HOME/TODO.org" "$case_root/backup-history"
}

function dotfiles__install__backup_history_retains_earlier_runs { # @test
    printf 'first original\n' > "$HOME/.sample-one"
    install --backup
    first=$(find "$HOME/.local/state/dotfiles/backups" -name .sample-one)

    rm "$HOME/.sample-two"
    printf 'second original\n' > "$HOME/.sample-two"
    install --backup
    second=$(find "$HOME/.local/state/dotfiles/backups" -name .sample-two)

    grep -Fxq -- "- $HOME/.sample-one -> $first" "$HOME/TODO.org"
    grep -Fxq -- "- $HOME/.sample-two -> $second" "$HOME/TODO.org"
    [ "$(grep -Fc '* Backups' "$HOME/TODO.org")" = 1 ]
}

function dotfiles__install__unwritable_history_preserves_backup { # @test
    printf 'original\n' > "$HOME/.sample-one"
    ln -s "$case_root/outside-todo" "$HOME/TODO.org"
    expect_failure install --backup
    saved=$(find "$HOME/.local/state/dotfiles/backups" -name .sample-one)
    [ "$(cat "$saved")" = original ]
    [ -L "$HOME/TODO.org" ]
    [ ! -e "$case_root/outside-todo" ]
}

function dotfiles__install__failed_backup_move_records_staged_originals { # @test
    printf 'original\n' > "$HOME/.sample-one"
    mkdir "$case_root/shims"
    cat > "$case_root/shims/mv" <<'SHIM'
#!/bin/bash
for destination do :; done
case "$destination" in
    */.local/state/dotfiles/backups/*) exit 1 ;;
esac
exec /bin/mv "$@"
SHIM
    chmod +x "$case_root/shims/mv"
    expect_failure env PATH="$case_root/shims:/usr/bin:/bin" \
        /bin/bash "$repo/dotfiles" install --links-only --backup

    staged=$(find "$HOME" -path '*/.dotfiles-backup.*/.sample-one')
    [ "$(cat "$staged")" = original ]
    grep -Fxq -- "- $HOME/.sample-one -> $staged" "$HOME/TODO.org"
}

function dotfiles__install__symlinked_parents_do_not_redirect_writes_outside_home { # @test
    mkdir "$case_root/outside"
    ln -s "$case_root/outside" "$HOME/.config"
    expect_failure install
    [ -z "$(ls -A "$case_root/outside")" ]
    [ ! -e "$HOME/.sample-one" ]
    install --backup
    verify_links
    [ -z "$(ls -A "$case_root/outside")" ]
}

function dotfiles__install__unsafe_source_fails_before_linking { # @test
    rm "$repo/home/common/.sample-two"
    ln -s "$case_root/outside" "$repo/home/common/.sample-two"
    expect_failure install
    [ ! -e "$HOME/.sample-one" ]
}

function dotfiles__install__unsupported_platform_is_rejected { # @test
    mkdir "$case_root/shims"
    printf '#!/bin/bash\nprintf "UnsupportedOS\\n"\n' > "$case_root/shims/uname"
    chmod +x "$case_root/shims/uname"
    expect_failure env PATH="$case_root/shims:/usr/bin:/bin" /bin/bash "$repo/dotfiles" install --links-only
}

function dotfiles__install__directory_changes_update_links_without_catalog_edits { # @test
    # Newly added names, including spaces, require no metadata change.
    printf 'custom\n' > "$repo/home/common/a path with spaces"
    rm "$repo/home/common/.sample-two"
    install
    [ "$(readlink "$HOME/a path with spaces")" = "$repo/home/common/a path with spaces" ]
    [ ! -e "$HOME/.sample-two" ]
    verify_links
}

function dotfiles__install__invalid_inventory_preserves_existing_files_before_backup { # @test
    printf 'original\n' > "$HOME/.sample-one"

    # A platform file cannot overlap a common destination.
    printf 'duplicate\n' > "$repo/home/debian/.sample-one"
    expect_failure install --backup
    [ "$(cat "$HOME/.sample-one")" = original ]
    [ ! -e "$HOME/.sample-five" ]
    rm "$repo/home/debian/.sample-one"

    # Symbolic sources and structural container symlinks are rejected.
    ln -s "$case_root/outside" "$repo/home/common/unsafe"
    expect_failure install --backup
    [ "$(cat "$HOME/.sample-one")" = original ]
    rm "$repo/home/common/unsafe"
    rm -rf "$repo/home/common/.config"
    ln -s "$case_root/outside" "$repo/home/common/.config"
    expect_failure install --backup
    [ "$(cat "$HOME/.sample-one")" = original ]
}

function dotfiles__install__legacy_managed_links_migrate_without_backup { # @test
    # Existing links to the old checkout layout may now be dangling.
    rm "$repo/home/common/.sample-one"
    printf 'config\n' > "$repo/home/common/.bashrc"
    ln -s "$repo/shell/bashrc" "$HOME/.bashrc"
    install
    [ "$(readlink "$HOME/.bashrc")" = "$repo/home/common/.bashrc" ]
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
}

function dotfiles__install__unrelated_old_links_remain_conflicts { # @test
    printf 'config\n' > "$repo/home/common/.bashrc"
    ln -s "$case_root/shell/bashrc" "$HOME/.bashrc"
    expect_failure install
    [ "$(readlink "$HOME/.bashrc")" = "$case_root/shell/bashrc" ]
}

function dotfiles__checkout__missing_git_reports_required_prerequisite { # @test
    mkdir "$case_root/shims"
    ln -s /usr/bin/uname "$case_root/shims/uname"
    expect_failure env PATH="$case_root/shims" /bin/bash "$repo/dotfiles" bootstrap --links-only
    /usr/bin/grep -q 'Git is required' "$case_root/failure.log"
}

function dotfiles__checkout__clone_uses_requested_revision_and_origin { # @test
    bootstrap
    [ "$(git -C "$checkout" rev-parse HEAD)" = "$revision" ]
    [ "$(git -C "$checkout" remote get-url origin)" = "$url/repo.git" ]
}

function dotfiles__checkout__rerun_preserves_local_edits_and_untracked_file { # @test
    bootstrap
    printf 'local changes\n' >> "$checkout/README.md"
    printf 'untracked\n' > "$checkout/local-only"
    bootstrap
    /usr/bin/grep -q 'local changes' "$checkout/README.md"
    [ -f "$checkout/local-only" ]
}

function dotfiles__checkout__existing_checkout_accepts_historical_ssh_origin { # @test
    bootstrap
    git -C "$checkout" remote set-url origin git@github.com:Example/Arbitrary.git
    /bin/bash "$repo/dotfiles" bootstrap --links-only --repo https://github.com/example/arbitrary.git --directory "$checkout"
}

function dotfiles__checkout__mismatched_origin_is_rejected { # @test
    bootstrap
    expect_failure /bin/bash "$repo/dotfiles" bootstrap --links-only --repo "$url/another.git" --directory "$checkout"
}

function dotfiles__checkout__invalid_ref_preserves_existing_head { # @test
    bootstrap
    expect_failure bootstrap --ref no-such-ref
    [ "$(git -C "$checkout" rev-parse HEAD)" = "$revision" ]
}

function dotfiles__checkout__invalid_refs_leave_no_partial_clone { # @test
    for ref in no-such-ref README.md; do
        expect_failure bootstrap --ref "$ref"
        [ ! -e "$checkout" ]
        [ -z "$(find "$HOME" -maxdepth 1 -name '.dotfiles-clone.*' -print)" ]
    done
}

function dotfiles__checkout__failed_clone_leaves_no_partial_checkout { # @test
    expect_failure /bin/bash "$repo/dotfiles" bootstrap --links-only --repo "$url/missing.git" --directory "$checkout"
    [ ! -e "$checkout" ]
    [ -z "$(find "$HOME" -maxdepth 1 -name '.dotfiles-clone.*' -print)" ]
}

function dotfiles__checkout__unrelated_directory_contents_are_preserved { # @test
    mkdir "$checkout"
    printf 'original\n' > "$checkout/file"
    expect_failure bootstrap
    [ "$(cat "$checkout/file")" = original ]
}

function dotfiles__install__configuration_directories_are_single_link_units { # @test
    mkdir -p "$repo/home/common/.config/example/nested"
    printf 'setting\n' > "$repo/home/common/.config/example/nested/settings"

    install

    [ -L "$HOME/.config/example" ]
    [ "$(readlink "$HOME/.config/example")" = "$repo/home/common/.config/example" ]
    [ "$(cat "$HOME/.config/example/nested/settings")" = setting ]
}

function dotfiles__install__different_platform_sources_may_share_a_destination { # @test
    printf 'mac\n' > "$repo/home/macos/.shared"
    printf 'linux\n' > "$repo/home/debian/.shared"

    install

    case "$(uname -s)" in Darwin) expected=macos ;; *) expected=debian ;; esac
    [ "$(readlink "$HOME/.shared")" = "$repo/home/$expected/.shared" ]
    verify_links
}

function dotfiles__install__invalid_filename_fails_before_creating_links { # @test
    printf 'unsafe\n' > "$repo/home/common/$(printf 'line\nbreak')"
    expect_failure install --backup
    [ ! -e "$HOME/.sample-one" ]
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
}
