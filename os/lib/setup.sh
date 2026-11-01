#!/bin/bash

# Common setup for installer scripts. Scripts may source this helper and run
# `setup "$@"` directly; no menu, runner, or fixed checkout path is required.
# The sourcing scripts use the checkout paths supplied here.
# shellcheck disable=SC2034

#  - - -  Find this checkout and load shared script utilities  - - -

setup() {

    # Stop on an error, including an error in a pipeline.
    set -eo pipefail

    local helper_directory

    # These paths refer to this helper's checkout, including a worktree.
    helper_directory=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
    script_directory=$(cd "$helper_directory/.." && pwd)
    root=$(cd "$script_directory/.." && pwd)

    # Load option parsing, status reporting, and the backup history helper.
    # shellcheck source=os/lib/configuration.sh
    source "$helper_directory/configuration.sh"
    # shellcheck source=os/lib/backup_history.sh
    source "$helper_directory/backup_history.sh"

    # Set backup and collect all other script-specific arguments.
    configuration_options "$@"

}
