#!/bin/bash
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {
    guest_setup
    # Bash startup files are discovered from the HOME-shaped tree.

}

function dotfiles__shell__login_with_term_xterm_256color_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" xterm-256color login
}

function dotfiles__shell__interactive_with_term_xterm_256color_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" xterm-256color interactive
}

function dotfiles__shell__login_interactive_with_term_xterm_256color_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" xterm-256color login-interactive
}

function dotfiles__shell__login_with_term_dumb_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" dumb login
}

function dotfiles__shell__interactive_with_term_dumb_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" dumb interactive
}

function dotfiles__shell__login_interactive_with_term_dumb_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" dumb login-interactive
}

function dotfiles__shell__login_with_term_unset_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" unset login
}

function dotfiles__shell__interactive_with_term_unset_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" unset interactive
}

function dotfiles__shell__login_interactive_with_term_unset_runs_repo_command { # @test
    install
    /bin/bash "$DOTFILES_CANDIDATE/tests/shell-check.sh" "$HOME" "$repo" unset login-interactive
}
