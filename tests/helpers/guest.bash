#!/bin/bash
# Variables and parameterized helpers are consumed by the sourcing Bats cases.
# shellcheck disable=SC2034,SC2120,SC2119
# Shared by guest-only Bats cases. Never source candidate code on the host.
require_guest() {
    bats_require_minimum_version 1.14.0
    [ -r /etc/dotfiles-test-image ] && [ "${DOTFILES_TEST_GUEST:-}" = 1 ] || {
        echo 'Run through tests/run in a disposable VM.' >&2
        return 1
    }
}
setup() {
    require_guest
    case_root="$BATS_TEST_TMPDIR/case"
    mkdir -p "$case_root"
    case_root=$(cd -P "$case_root" && pwd)
    repo="$case_root/repo with spaces"
    mkdir "$repo"
    # Each case may mutate its own source; exclude the test runtime to keep copies small.
    cp -R "$DOTFILES_CANDIDATE/dotfiles" "$DOTFILES_CANDIDATE/os" \
        "$DOTFILES_CANDIDATE/shell" "$DOTFILES_CANDIDATE/vim" \
        "$DOTFILES_CANDIDATE/config" "$DOTFILES_CANDIDATE/git" \
        "$DOTFILES_CANDIDATE/keyboard" "$DOTFILES_CANDIDATE/local-share" \
        "$DOTFILES_CANDIDATE/bin" "$DOTFILES_CANDIDATE/mac-stuff" "$repo/"
    export HOME="$case_root/home with spaces"
    mkdir "$HOME"
    url=$DOTFILES_FIXTURE_URL
    revision=$DOTFILES_REVISION
    checkout="$HOME/checkout with spaces"
    cd /
}
install() { /bin/bash "$repo/dotfiles" install "$@"; }
bootstrap() { /bin/bash "$repo/dotfiles" bootstrap --repo "$url/repo.git" --directory "$checkout" "$@"; }
expect_failure() {
    run ! "$@"
    # Bats run supplies output.
    # shellcheck disable=SC2154
    printf '%s\n' "$output" > "$case_root/failure.log"
}
verify_links() {
    local scope source target _extra platform actual active shared
    local active_targets=() inactive_targets=()
    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac
    while read -r scope source target _extra; do
        case "$scope" in ''|'#'*) continue ;; esac
        if [ "$scope" != common ] && [ "$scope" != "$platform" ]; then
            inactive_targets+=("$target")
            continue
        fi
        active_targets+=("$target")
        [ -L "$HOME/$target" ] && [ -e "$HOME/$target" ]
        actual=$(readlink "$HOME/$target")
        if [ "$actual" != "$repo/$source" ]; then
            printf 'Wrong link %s: expected %s, got %s\n' "$target" "$repo/$source" "$actual"
            return 1
        fi
    done < "$repo/os/links.tsv"
    # A destination may be listed for both platforms with different sources.
    # Only destinations absent from the active manifest must remain absent.
    for target in "${inactive_targets[@]}"; do
        shared=0
        for active in "${active_targets[@]}"; do
            if [ "$active" = "$target" ]; then shared=1; break; fi
        done
        if [ "$shared" = 1 ]; then continue; fi
        if [ -e "$HOME/$target" ] || [ -L "$HOME/$target" ]; then
            printf 'Inactive platform target was created: %s\n' "$target"
            return 1
        fi
    done
}
make_conflicts() {
    install
    rm "$HOME/.bashrc" "$HOME/.vimrc" "$HOME/.gvimrc" "$HOME/.gitignore"
    printf 'keep me\n' > "$HOME/.bashrc"
    ln -s "$case_root/does-not-exist" "$HOME/.vimrc"
    mkdir "$HOME/.gvimrc"
    printf 'directory contents\n' > "$HOME/.gvimrc/original"
}
