#!/bin/bash
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"
setup_file() {
    require_guest
    export ACCOUNT_HOME="$HOME"
    export ACCOUNT_STATE="$BATS_FILE_TMPDIR/account-state"
    python3 "$DOTFILES_CANDIDATE/tests/helpers/home-state.py" save "$ACCOUNT_HOME" "$ACCOUNT_STATE" "$DOTFILES_CANDIDATE"
}
setup() {
    require_guest
    export HOME="$ACCOUNT_HOME"
    restore_home
    case_root="$BATS_TEST_TMPDIR/case"
    mkdir "$case_root"
    url=$DOTFILES_FIXTURE_URL
    revision=$DOTFILES_REVISION
    checkout="$HOME/projects/dotfiles"
    /usr/bin/curl -qfsS --max-time 30 "$url/dotfiles" -o "$case_root/bootstrap"
}
restore_home() {
    python3 "$DOTFILES_CANDIDATE/tests/helpers/home-state.py" restore "$ACCOUNT_HOME" "$ACCOUNT_STATE" "$DOTFILES_CANDIDATE"
}
teardown() { restore_home; }
account_install() {
    /bin/bash "$case_root/bootstrap" bootstrap --links-only --repo "$url/repo.git" --directory "$checkout" "$@"
}
conflict_target() {
    local scope source relative platform
    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac
    IFS=$'\t' read -r scope source relative < <(/bin/bash "$DOTFILES_CANDIDATE/os/catalog_links.sh" "$DOTFILES_CANDIDATE" "$platform")
    [ -n "$relative" ] || skip 'No dotfile links configured.'
    target="$HOME/$relative"
    mkdir -p "$(dirname "$target")"
}
function dotfiles__full_install__conflict_preserves_original_configuration { # @test
    conflict_target
    printf 'original configuration\n' > "$target"
    expect_failure account_install
    [ "$(cat "$target")" = 'original configuration' ]
}
function dotfiles__full_install__checkout_has_expected_revision_origin_branch_and_owner { # @test
    account_install --backup
    [ "$(git -C "$checkout" rev-parse HEAD)" = "$revision" ]
    [ "$(git -C "$checkout" remote get-url origin)" = "$url/repo.git" ]
    [ "$(git -C "$checkout" symbolic-ref --short HEAD)" = master ]
    [ -z "$(find "$checkout" ! -user "$(id -un)" -print)" ]
}
function dotfiles__full_install__rerun_does_not_create_additional_backups { # @test
    conflict_target
    printf 'original configuration\n' > "$target"
    account_install --backup
    backup_count=$(find "$HOME/.local/state/dotfiles/backups" -type d | wc -l)
    account_install --backup
    [ "$(find "$HOME/.local/state/dotfiles/backups" -type d | wc -l)" = "$backup_count" ]
}

function dotfiles__full_install__interactive_login_with_term_xterm_256color_runs_repo_command { # @test
    # The independent startup suite covers Bash even if this catalogue omits it.
    if [ ! -f "$DOTFILES_CANDIDATE/home/common/.bash_profile" ]; then
        skip 'This checkout does not include a Bash login profile.'
    fi
    account_install --backup
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$checkout" xterm-256color login-interactive
}
