#!/bin/bash

# Synthetic HOME trees test discovery, selection and execution without package
# managers or the real application's catalogue. Bats provides run/status/output.
# shellcheck disable=SC2154
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {

    guest_setup
    rm -rf "${repo:?}/home"
    mkdir -p "$repo/home/common/.config/sample-directory"
    printf 'required\n' > "$repo/home/common/.required"
    printf 'optional\n' > "$repo/home/common/.optional"
    printf 'unselected\n' > "$repo/home/common/.unselected"
    printf 'config\n' > "$repo/home/common/.config/sample-directory/config"

    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac

    cat > "$repo/os/catalog.yaml" <<'YAML'
schema_version: 1
post_install: {}
groups:
  dotfiles:
    discover_dotfiles: true
    options: {}
  examples:
    options:
      helper:
        link_dependencies: [.required]
        platforms:
          macos: {steps: [{script: os/test-helper.sh}]}
          debian: {steps: [{script: os/test-helper.sh}]}
      action:
        requires: [helper]
        platforms:
          macos:
            link_dependencies: [.config/sample-directory]
            steps: [{script: os/test-action.sh}]
          debian:
            link_dependencies: [.config/sample-directory]
            steps: [{script: os/test-action.sh}]
      cpu-dependent:
        platforms:
          macos: {architectures: [amd64], steps: [{script: os/test-action.sh}]}
          debian: {architectures: [amd64], steps: [{script: os/test-action.sh}]}
YAML

    # These scripts are intentionally synthetic: they verify real execution
    # order without mirroring the names or package inventory in the catalogue.
    cat > "$repo/os/test-helper.sh" <<'SCRIPT'
#!/bin/bash
set -e
[ -L "$HOME/.required" ]
printf 'helper\n' >> "$HOME/order"
SCRIPT
    cat > "$repo/os/test-action.sh" <<'SCRIPT'
#!/bin/bash
set -e
[ -L "$HOME/.required" ]
[ -L "$HOME/.config/sample-directory" ]
grep -qx helper "$HOME/order"
printf 'action\n' >> "$HOME/order"
SCRIPT

}

function menu_inventory__only__installs_required_paths_before_dependent_scripts { # @test

    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false action true
    [ -L "$HOME/.required" ]
    [ -L "$HOME/.config/sample-directory" ]
    [ ! -e "$HOME/.optional" ]
    [ ! -e "$HOME/.unselected" ]
    [ "$(tr '\n' ' ' < "$HOME/order")" = 'helper action ' ]

}

function menu_inventory__interactive__empty_choices_still_links_selected_individual_paths { # @test

    export DOTFILES_UI_DIRECTORY="$case_root/ui"
    mkdir "$DOTFILES_UI_DIRECTORY"
    digest=$(printf '%s' '.optional' | { sha256sum 2>/dev/null || shasum -a 256; })
    optional_id="file-${digest%% *}"
    printf '{"selected":["action","%s"],"choices":{}}\n' "$optional_id" \
        > "$DOTFILES_UI_DIRECTORY/state.json.selection"

    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false '' false worker
    [ -L "$HOME/.optional" ]
    [ -L "$HOME/.required" ]
    [ -L "$HOME/.config/sample-directory" ]
    [ ! -e "$HOME/.unselected" ]
    [ "$(tr '\n' ' ' < "$HOME/order")" = 'helper action ' ]

    # The UI receives a complete result for the selected operation.
    [ -f "$DOTFILES_UI_DIRECTORY/state.json" ]
}

function menu_inventory__missing_dependency__fails_before_any_changes { # @test

    rm "$repo/home/common/.required"
    run /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false action true
    [ "$status" -ne 0 ]
    [[ "$output" = *'Missing dotfile dependency'* ]]
    [ ! -e "$HOME/order" ]
    [ ! -e "$HOME/.config" ]
    [ ! -e "$HOME/TODO.org" ]

}

function menu_inventory__groups__dependencies_cross_groups_and_duplicate_ids_fail { # @test

    # Moving an option to another group must not change its dependency IDs.
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.other = {"options": {"action": .groups.examples.options.action}} |
        del(.groups.examples.options.action)
    ' "$repo/os/catalog.yaml"
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false action true
    [ "$(tr '\n' ' ' < "$HOME/order")" = 'helper action ' ]

    # An ID in two groups must be rejected before either option can run.
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.other.options.helper = .groups.examples.options.helper
    ' "$repo/os/catalog.yaml"
    run /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false helper true
    [ "$status" -ne 0 ]
    [[ "$output" = *'Duplicate option: helper'* ]]
    [ "$(tr '\n' ' ' < "$HOME/order")" = 'helper action ' ]

}

function menu_inventory__names__are_data_across_selection_progress_and_todos { # @test

    # The option contains spaces, path separators and shell/JSON punctuation.
    # Its name is data, not a shell command or a path to create.
    # shellcheck disable=SC2016
    export SAMPLE_OPTION='Service / Tom'"'"'s "Tools" $HOME'
    /bin/bash "$repo/os/yq.sh" -i '
        .groups["Example Group"] = .groups.examples |
        del(.groups.examples) |
        .groups["Example Group"].options[strenv(SAMPLE_OPTION)] = .groups["Example Group"].options.action |
        del(.groups["Example Group"].options.action) |
        .groups["Example Group"].options[strenv(SAMPLE_OPTION)].todo = {"1. Example tasks": ["Check the selected item"]}
    ' "$repo/os/catalog.yaml"

    export DOTFILES_UI_DIRECTORY="$case_root/ui"
    mkdir "$DOTFILES_UI_DIRECTORY"
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false "$SAMPLE_OPTION" true

    [ "$(tr '\n' ' ' < "$HOME/order")" = 'helper action ' ]
    grep -Fxq -- '- [ ] Check the selected item' "$HOME/TODO.org"
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.states[strenv(SAMPLE_OPTION)]' "$DOTFILES_UI_DIRECTORY/state.json")" = 'Installed and verified' ]
    log=$(/bin/bash "$repo/os/yq.sh" -r '.steps[] | select(.feature == strenv(SAMPLE_OPTION)) | .log' "$DOTFILES_UI_DIRECTORY/state.json" | head -n 1)
    [ -f "$log" ]
    [[ "$log" != *"$SAMPLE_OPTION"* ]]

}

function menu_inventory__cpu_filter__hides_unsupported_feature_from_catalogue { # @test

    root=$repo
    fail() { printf '%s\n' "$*" >&2; return 1; }
    # shellcheck source=os/menu_catalog.sh
    source "$root/os/menu_catalog.sh"

    # Override uname only in the loader shell, not in yq's child process.
    # shellcheck disable=SC2329
    uname() { if [ "$1" = -m ]; then printf '%s\n' "$TEST_ARCH"; else command uname "$@"; fi; }

    TEST_ARCH=aarch64
    load_catalog
    ! feature_index cpu-dependent >/dev/null

    TEST_ARCH=x86_64
    load_catalog
    feature_index cpu-dependent >/dev/null

}

