#!/bin/bash
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

function dotfiles__install__platform_links_resolve_in_paths_with_spaces { # @test
    install
    verify_links
}

function dotfiles__install__rerun_keeps_valid_links_without_backups { # @test
    install
    install
    verify_links
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
}

function dotfiles__install__correct_relative_links_are_preserved { # @test
    install
    relative=''
    parent=$HOME
    while [ "$parent" != / ]; do relative="../$relative"; parent=$(dirname "$parent"); done
    relative="$relative${repo#/}/shell/bashrc"
    rm "$HOME/.bashrc"
    ln -s "$relative" "$HOME/.bashrc"
    install
    [ "$(readlink "$HOME/.bashrc")" = "$relative" ]
    [ ! -e "$HOME/.local/state/dotfiles/backups" ]
}

function dotfiles__install__conflicts_preserve_originals_before_linking { # @test
    make_conflicts
    expect_failure install
    [ "$(cat "$HOME/.bashrc")" = 'keep me' ]
    [ "$(readlink "$HOME/.vimrc")" = "$case_root/does-not-exist" ]
    [ "$(cat "$HOME/.gvimrc/original")" = 'directory contents' ]
    [ ! -e "$HOME/.gitignore" ]
}

function dotfiles__install__backups_preserve_files_directories_and_dangling_links { # @test
    make_conflicts
    install --backup
    verify_links
    saved=$(find "$HOME/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d)
    [ "$(cat "$saved/.bashrc")" = 'keep me' ]
    [ "$(readlink "$saved/.vimrc")" = "$case_root/does-not-exist" ]
    [ "$(cat "$saved/.gvimrc/original")" = 'directory contents' ]
    install --backup
    [ "$(find "$HOME/.local/state/dotfiles/backups" -mindepth 1 -maxdepth 1 -type d)" = "$saved" ]
}

function dotfiles__install__symlinked_parents_do_not_redirect_writes_outside_home { # @test
    mkdir "$case_root/outside"
    ln -s "$case_root/outside" "$HOME/.config"
    expect_failure install
    [ -z "$(ls -A "$case_root/outside")" ]
    [ ! -e "$HOME/.bashrc" ]
    install --backup
    verify_links
    [ -z "$(ls -A "$case_root/outside")" ]
}

function dotfiles__install__missing_source_fails_before_linking { # @test
    rm "$repo/vim/vimrc"
    expect_failure install
    [ ! -e "$HOME/.bashrc" ]
}

function dotfiles__install__unsupported_platform_is_rejected { # @test
    mkdir "$case_root/shims"
    printf '#!/bin/bash\nprintf "UnsupportedOS\\n"\n' > "$case_root/shims/uname"
    chmod +x "$case_root/shims/uname"
    expect_failure env PATH="$case_root/shims:/usr/bin:/bin" /bin/bash "$repo/dotfiles" install
}

function dotfiles__checkout__missing_git_reports_required_prerequisite { # @test
    mkdir "$case_root/shims"
    ln -s /usr/bin/uname "$case_root/shims/uname"
    expect_failure env PATH="$case_root/shims" /bin/bash "$repo/dotfiles" bootstrap
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
    git -C "$checkout" remote set-url origin git@github.com:brendan-R/dotfiles.git
    /bin/bash "$repo/dotfiles" bootstrap --directory "$checkout"
}

function dotfiles__checkout__mismatched_origin_is_rejected { # @test
    bootstrap
    expect_failure /bin/bash "$repo/dotfiles" bootstrap --repo "$url/another.git" --directory "$checkout"
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
    expect_failure /bin/bash "$repo/dotfiles" bootstrap --repo "$url/missing.git" --directory "$checkout"
    [ ! -e "$checkout" ]
    [ -z "$(find "$HOME" -maxdepth 1 -name '.dotfiles-clone.*' -print)" ]
}

function dotfiles__checkout__unrelated_directory_contents_are_preserved { # @test
    mkdir "$checkout"
    printf 'original\n' > "$checkout/file"
    expect_failure bootstrap
    [ "$(cat "$checkout/file")" = original ]
}
