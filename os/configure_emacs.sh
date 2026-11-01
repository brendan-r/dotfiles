#!/bin/bash

# Install and bootstrap the published Emacs configuration without resetting it.
# root is the checkout containing the bootstrap helper.
# configuration_args contains options not consumed by setup.
# configuration_result reports existing state and bootstrap failures.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

# The defaults live here; arguments make the script useful for other checkouts.
repository=https://github.com/brendan-r/dotemacs.git
if [ "$(uname -s)" = Darwin ]; then
    emacs_command=/Applications/Emacs.app/Contents/MacOS/Emacs
else
    emacs_command=emacs
fi
# The installer sets this for an explicit retry; direct runs may use --retry.
retry=${DOTFILES_RETRY_EMACS_BOOTSTRAP:-false}
set -- "${configuration_args[@]}"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repository)
            [ "$#" -ge 2 ] || exit 2
            repository=$2
            shift
            ;;
        --executable)
            [ "$#" -ge 2 ] || exit 2
            emacs_command=$2
            shift
            ;;
        --retry|--retry-emacs-bootstrap)
            retry=true
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
    shift
done
[ -n "$repository" ] && [ -n "$emacs_command" ] || exit 2

#  - - -  Report a distinct failed bootstrap to the installer, if present  - - -

bootstrap_failure() {

    local detail=$1 quoted_option retry_action

    # Quote the installer's option name so retry commands work with spaces.
    # Direct runs can retry the same script without knowing a menu name.
    if [ -n "${DOTFILES_OPTION_ID:-}" ]; then
        printf -v quoted_option '%q' "$DOTFILES_OPTION_ID"
        retry_action="Retry: ./dotfiles install --only $quoted_option --retry-emacs-bootstrap"
    else
        retry_action='Retry this script with --retry.'
    fi

    configuration_result substep-failed 'Initialise Emacs packages' "$detail" \
        "$retry_action"

}

#  - - -  Clone or reuse the configuration, then initialise packages  - - -

configure_emacs() {

    local destination="$HOME/.emacs.d" staging origin alternate state

    # Accept an existing SSH checkout of the configured public GitHub repository.
    alternate=$repository
    case "$repository" in
        https://github.com/*) alternate="git@github.com:${repository#https://github.com/}" ;;
    esac

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        origin=$(git -C "$destination" remote get-url origin 2>/dev/null) || {
            printf 'Existing Emacs configuration retained: %s\n' "$destination" >&2
            return 1
        }

        if [ "${origin%.git}" != "${repository%.git}" ] && [ "${origin%.git}" != "${alternate%.git}" ]; then
            printf 'Unrelated Emacs configuration retained.\n' >&2
            return 1
        fi

        # Store installer state in local Git metadata, never in tracked config.
        # A missing marker means unknown, including checkouts made by older installers.
        state=$(git -C "$destination" config --local --get dotfiles.bootstrap-status) || state=unknown

        if ! "$retry"; then
            case "$state" in
                succeeded)
                    printf 'Existing Emacs checkout retained; the previous bootstrap succeeded.\n'
                    configuration_result unchanged
                    ;;
                failed)
                    printf 'The previous Emacs bootstrap failed; its checkout and local changes are retained.\n'
                    bootstrap_failure "The previous Emacs bootstrap failed."
                    ;;
                *)
                    printf 'Emacs bootstrap is unfinished or unverified; its checkout and local changes are retained.\n'
                    bootstrap_failure "Emacs bootstrap is unfinished or unverified."
                    ;;
            esac

            if [ "$state" != succeeded ]; then
                printf 'Rerun this script with --retry, or use --retry-emacs-bootstrap with the installer.\n'
            fi
            [ "$state" = succeeded ] && return 0
            return 1
        fi

        printf 'Retrying Emacs bootstrap in the existing checkout; local changes are retained.\n'
    else
        staging=$(mktemp -d "$HOME/.dotemacs-install.XXXXXX") || return 1

        # Fetch public submodules without SSH credentials or global Git changes.
        if ! git -c url.https://github.com/.insteadOf=git@github.com: \
            clone --recurse-submodules -- "$repository" "$staging/config"; then
            rm -rf "$staging"
            return 1
        fi

        # Mark before publishing the checkout: interruption must not look like success.
        git -C "$staging/config" config --local dotfiles.bootstrap-status pending || return 1
        mv "$staging/config" "$destination" || return 1
        rmdir "$staging"
        printf 'Installed published Emacs configuration: %s\n' "$destination"
    fi

    git -C "$destination" config --local dotfiles.bootstrap-status pending || return 1

    # Explicit retry may download/build packages, but never resets or pulls the checkout.
    if "$emacs_command" --batch --debug-init \
        --load "$root/os/emacs_bootstrap.el" \
        --load "$destination/early-init.el" --load "$destination/init.el" \
        --eval '(dotfiles-verify-bootstrap)'; then
        git -C "$destination" config --local dotfiles.bootstrap-status succeeded || return 1
    else
        git -C "$destination" config --local dotfiles.bootstrap-status failed || return 1
        printf 'Emacs files were installed, but startup failed. Retry this script with --retry.\n'
        bootstrap_failure "Emacs files are installed, but package startup failed."
        return 1
    fi

}


configure_emacs
