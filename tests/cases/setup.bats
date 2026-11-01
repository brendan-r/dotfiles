#!/bin/bash

# Test the setup helper through scripts in a disposable checkout with spaces.
# shellcheck disable=SC2154
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

function setup__standalone__resolves_checkout_and_arguments { # @test

    cat > "$repo/os/fixture-setup.sh" <<'SCRIPT'
#!/bin/bash
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
printf '%s\n' "$root" "$script_directory" "$backup" "${configuration_args[@]}"
SCRIPT

    # A different current directory must not change which checkout is used.
    cd /
    run /bin/bash "$repo/os/fixture-setup.sh" --backup 'value with spaces'
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' "$repo" "$repo/os" true 'value with spaces')" ]

}

function setup__standalone__existing_file_reports_unchanged { # @test

    export DOTFILES_RESULT="$case_root/result"
    printf 'personal settings\n' > "$HOME/.bash.local"

    /bin/bash "$repo/os/create_bash_local.sh" --backup
    [ "$(cat "$HOME/.bash.local")" = 'personal settings' ]
    [ "$(cat "$DOTFILES_RESULT")" = unchanged ]

    # Standalone runs also work without any runner-provided environment.
    unset DOTFILES_RESULT
    /bin/bash "$repo/os/create_bash_local.sh"
    [ "$(cat "$HOME/.bash.local")" = 'personal settings' ]

}
