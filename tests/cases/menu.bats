#!/bin/bash

# Bats supplies status and output after run.
# shellcheck disable=SC2154

# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {

    guest_setup
    cp "$DOTFILES_CANDIDATE/tests/fixtures/menu.yaml" "$repo/os/catalog.yaml"
    mkdir "$repo/fixture"
    printf 'first\n' > "$repo/fixture/first"
    printf 'second\n' > "$repo/fixture/second"
    printf 'later\n' > "$repo/fixture/later"
    rm -rf "${repo:?}/home"
    mkdir -p "$repo/home/common" "$repo/home/macos" "$repo/home/debian"
    cp "$repo/fixture/first" "$repo/home/common/.sample-first"
    cp "$repo/fixture/second" "$repo/home/common/.sample-second"
    cp "$repo/fixture/later" "$repo/home/common/.sample-later"
    printf '#!/bin/bash\nexit 0\n' > "$repo/os/fixture-noop.sh"
    cat > "$repo/os/fixture-directories.sh" <<'SCRIPT'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/create_personal_directories.sh" \
    "$@" 'sample-area' 'folder with spaces/nested'
SCRIPT

}

feature_install() {

    /bin/bash "$repo/dotfiles" install --yes "$@"

}

fake_packages() {

    export DOTFILES_FAKE_PACKAGES="$case_root/packages"
    mkdir -p "$DOTFILES_FAKE_PACKAGES/bin"

    for name in brew apt-get dpkg-query sudo; do
        cp "$DOTFILES_CANDIDATE/tests/helpers/package-stub.py" "$DOTFILES_FAKE_PACKAGES/bin/$name"
        chmod +x "$DOTFILES_FAKE_PACKAGES/bin/$name"
    done

    export PATH="$DOTFILES_FAKE_PACKAGES/bin:$PATH"

}

function menu__selection__dependency_links_and_local_overrides_are_preserved { # @test

    feature_install --only local-settings
    [ -L "$HOME/.sample-second" ]
    [ -f "$HOME/.bash.local" ]
    [ ! -e "$HOME/.gitconfig" ]
    [ ! -e "$HOME/.sample-later" ]

    printf 'personal override\n' > "$HOME/.bash.local"
    feature_install --only local-settings
    [ "$(cat "$HOME/.bash.local")" = 'personal override' ]

}

function menu__actions__conflicts_preserve_originals_and_keep_completed_packages { # @test

    fake_packages
    printf 'original\n' > "$HOME/.sample-second"
    export DOTFILES_UI_DIRECTORY="$case_root/dashboard"
    mkdir "$DOTFILES_UI_DIRECTORY"

    expect_failure feature_install --only tools,files
    [ -f "$DOTFILES_FAKE_PACKAGES/sample-tool" ]
    [ "$(cat "$HOME/.sample-second")" = original ]

    # The completion screen and retained summary must explain the conflict.
    detail=$(/bin/bash "$repo/os/yq.sh" -r '.steps[-1].detail' "$DOTFILES_UI_DIRECTORY/state.json")
    [[ "$detail" == *'Conflicting paths:'* ]]
    [[ "$detail" == *"$HOME/.sample-second"* ]]
    [[ "$detail" == *'Resolve conflicts or rerun with --backup.'* ]]
    grep -Fq "$HOME/.sample-second" "$DOTFILES_UI_DIRECTORY/summary"
    grep -Fq 'Resolve conflicts or rerun with --backup.' "$DOTFILES_UI_DIRECTORY/summary"

    feature_install --only files --backup
    saved=$(find "$HOME/.local/state/dotfiles/backups" -name .sample-second)
    [ "$(cat "$saved")" = original ]
    [ -L "$HOME/.sample-second" ]

}

function menu__catalog__unavailable_unknown_and_cyclic_selections_fail_without_changes { # @test

    for id in pending unreviewed unknown-feature; do
        expect_failure feature_install --only "$id"
    done

    /bin/bash "$repo/os/yq.sh" -i '.groups.examples.options.files.requires = ["local-settings"]' "$repo/os/catalog.yaml"
    expect_failure feature_install --only local-settings
    [ -z "$(ls -A "$HOME")" ]

}

function menu__catalog__unsupported_steps_and_wrong_platform_managers_are_rejected { # @test

    case "$(uname -s)" in
        Darwin) export MENU_TEST_PLATFORM=macos MENU_TEST_MANAGER=apt ;;
        *) export MENU_TEST_PLATFORM=debian MENU_TEST_MANAGER=brew ;;
    esac

    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.tools.platforms[strenv(MENU_TEST_PLATFORM)].steps = [{"script": "os/install_applications.sh"}]
    ' "$repo/os/catalog.yaml"
    expect_failure feature_install --only tools

    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.tools.platforms[strenv(MENU_TEST_PLATFORM)].steps = [{(strenv(MENU_TEST_MANAGER)): ["tools"]}]
    ' "$repo/os/catalog.yaml"
    expect_failure feature_install --only tools
    [ -z "$(ls -A "$HOME")" ]

}

function menu__packages__successful_installation_is_verified_and_reruns_skip_it { # @test

    fake_packages
    feature_install --only tools,tools
    [ -f "$DOTFILES_FAKE_PACKAGES/sample-tool" ]
    if [ "$(uname -s)" = Darwin ]; then
        [ -f "$DOTFILES_FAKE_PACKAGES/analytics-disabled" ]
    fi

    run feature_install --only tools
    [ "$status" -eq 0 ]
    [[ "$output" == *'Already present'* ]]
    [ "$(wc -l < "$DOTFILES_FAKE_PACKAGES/calls" | tr -d ' ')" = 1 ]

}

function menu__packages__failure_stops_following_features_and_reports_not_run { # @test

    fake_packages
    export DOTFILES_FAKE_FAILURE=1

    run feature_install --only tools,later
    [ "$status" -ne 0 ]
    [[ "$output" == *'Failed'* ]]
    [[ "$output" == *'Not run'* ]]
    [ ! -e "$HOME/.sample-later" ]

    # Cancelling an active install must also stop its children and later features.
    unset DOTFILES_FAKE_FAILURE
    python3 "$DOTFILES_CANDIDATE/tests/helpers/interrupt-menu.py" "$repo"
    [ ! -e "$HOME/.sample-later" ]

}

function menu__bootstrap__explicit_selection_uses_the_downloaded_catalog { # @test

    # Bootstrap from a test-owned repository, including its synthetic catalogue.
    git -C "$repo" init -b master
    git -C "$repo" add .
    git -C "$repo" -c user.name=Test -c user.email=test@example.invalid \
        -c commit.gpgsign=false commit -qm Fixture

    /bin/bash "$repo/dotfiles" bootstrap --repo "$repo" \
        --directory "$checkout" --only later --yes

    [ "$(readlink "$HOME/.sample-later")" = "$checkout/home/common/.sample-later" ]
    [ ! -e "$HOME/.sample-second" ]

    # An unattended invocation must not silently accept recommendations.
    expect_failure /bin/bash "$repo/dotfiles" install </dev/null

}

function menu__terminal__real_ui_selection_cancellation_and_installation_work { # @test

    fake_packages
    python3 "$DOTFILES_CANDIDATE/tests/helpers/menu-terminal.py" "$repo"

    # Apple's Python creates Library/Caches in HOME; that is not an install.
    # Assert the effects we own instead of requiring an entirely empty directory.
    [ ! -e "$DOTFILES_FAKE_PACKAGES/calls" ]
    [ ! -e "$DOTFILES_FAKE_PACKAGES/analytics-disabled" ]
    [ ! -e "$HOME/.bash.local" ]
    [ ! -e "$HOME/.local/state/dotfiles" ]
    [ -z "$(find "$HOME" -type l -print)" ]

    # Exercise live output, a hidden native prompt, and resizing the dashboard.
    export DOTFILES_FAKE_TERMINAL=1 DOTFILES_FAKE_PROMPT=1
    python3 "$DOTFILES_CANDIDATE/tests/helpers/menu-terminal.py" "$repo" install
    [ -f "$DOTFILES_FAKE_PACKAGES/sample-tool" ]

}

function menu__reminders__preserve_notes_completed_tasks_and_avoid_duplicates { # @test

    printf '#+title: My tasks\n* Example tasks\n- [X] A completed task\nPersonal notes\n\n* My own heading\n- [ ] Another task\n' > "$HOME/TODO.org"
    feature_install --only local-settings
    cp "$HOME/TODO.org" "$case_root/first-todo.org"
    feature_install --only local-settings
    cmp "$HOME/TODO.org" "$case_root/first-todo.org"

    [ "$(grep -Fc -- '- [X] A completed task' "$HOME/TODO.org")" = 1 ]
    [ "$(grep -Fc -- '- [ ] Another task' "$HOME/TODO.org")" = 2 ]
    grep -Fxq -- '- [X] A completed task' "$HOME/TODO.org"
    grep -Fxq 'Personal notes' "$HOME/TODO.org"
    ! grep -q 'A task for an unselected feature' "$HOME/TODO.org"
    ! grep -q '^:DOTFILES_TASK_ID:' "$HOME/TODO.org"

    # Rewording creates a new checkbox, retaining the old checked entry.
    /bin/bash "$repo/os/yq.sh" -i \
        '.post_install["1. Example tasks"].always[0] = "Reworded task"' "$repo/os/catalog.yaml"
    feature_install --only local-settings
    grep -Fxq -- '- [X] A completed task' "$HOME/TODO.org"
    grep -Fxq -- '- [ ] Reworded task' "$HOME/TODO.org"

}

function menu__ui__standalone_model_contracts_pass { # @test

    case "$(uname -s)" in
        Darwin) binary=darwin ;;
        Linux) binary=linux ;;
        *) skip 'Unsupported UI test platform' ;;
    esac
    case "$(uname -m)" in
        arm64|aarch64) binary=${binary}_arm64 ;;
        x86_64|amd64) binary=${binary}_amd64 ;;
        *) skip 'Unsupported UI test architecture' ;;
    esac

    "$DOTFILES_CANDIDATE/ui/test-bin/$binary.test"

}

function menu__terminal__individual_dotfiles_can_be_selected { # @test

    fake_packages
    python3 "$DOTFILES_CANDIDATE/tests/helpers/menu-terminal.py" "$repo" partial
    [ -L "$HOME/.sample-first" ]
    [ ! -e "$HOME/.sample-second" ]
    [ ! -e "$DOTFILES_FAKE_PACKAGES/calls" ]

}

function menu__configuration__directories_and_personal_bin_are_idempotent { # @test

    feature_install --only folders,scripts
    [ -d "$HOME/sample-area" ]
    [ -d "$HOME/folder with spaces/nested" ]
    [ "$(readlink "$HOME/bin")" = "$repo/bin" ]
    feature_install --only folders,scripts
    [ "$(grep -Fc -- '- [ ] Check the scripts path' "$HOME/TODO.org")" = 1 ]

}

function menu__scripts__run_independently { # @test

    unset DOTFILES_RESULT DOTFILES_BACKUP DOTFILES_RUN_DIRECTORY DOTFILES_OPTION_ID

    /bin/bash "$repo/os/create_bash_local.sh"
    /bin/bash "$repo/os/create_personal_directories.sh" 'example tree/child'
    /bin/bash "$repo/os/link_personal_bin.sh"
    [ -f "$HOME/.bash.local" ]
    [ -d "$HOME/example tree/child" ]
    [ "$(readlink "$HOME/bin")" = "$repo/bin" ]

}

function menu__configuration__parents_and_existing_files_are_preserved { # @test

    # Exercise file placement without requiring privileges or application installs.
    # shellcheck source=os/lib/configuration.sh
    source "$repo/os/lib/configuration.sh"
    # shellcheck source=os/lib/backup_history.sh
    source "$repo/os/lib/backup_history.sh"
    backup=false
    source_file="$repo/fixture/first"
    destination="$HOME/.config/example/settings"
    mkdir "$case_root/outside"
    ln -s "$case_root/outside" "$HOME/.config"
    expect_failure place_configuration "$source_file" "$destination"
    [ -z "$(ls -A "$case_root/outside")" ]

    rm "$HOME/.config"
    mkdir -p "$HOME/.config/example"
    printf 'original configuration\n' > "$destination"
    expect_failure place_configuration "$source_file" "$destination"
    backup=true
    place_configuration "$source_file" "$destination"
    cmp "$source_file" "$destination"
    saved=$(find "$HOME/.config/example" -name original)
    [ "$(cat "$saved")" = 'original configuration' ]

}

function menu__results__successful_operations_and_skipped_configuration_are_distinct { # @test

    run feature_install --only folders
    [ "$status" -eq 0 ]
    [[ "$output" == *'Completed:'* ]]
    [[ "$output" != *'Needs attention'* ]]
    [[ "$output" == *'Remaining user steps:'* ]]

    mkdir "$HOME/bin"
    printf 'keep me\n' > "$HOME/bin/original"
    # A later adapter must not inherit the skipped adapter's outcome.
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.scripts.platforms[].steps += [{"script": "os/create_bash_local.sh"}]
    ' "$repo/os/catalog.yaml"
    export DOTFILES_UI_DIRECTORY="$case_root/dashboard"
    mkdir "$DOTFILES_UI_DIRECTORY"
    run feature_install --only scripts
    [ "$status" -eq 0 ]
    [[ "$output" == *'Skipped: os/link_personal_bin.sh'* ]]
    [[ "$output" == *'Not run'* ]]
    [ "$(cat "$HOME/bin/original")" = 'keep me' ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.steps[-2].state' "$DOTFILES_UI_DIRECTORY/state.json")" = 'Not run' ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.steps[-1].state' "$DOTFILES_UI_DIRECTORY/state.json")" = Succeeded ]

}

function menu__terminal__dashboard_interrupt_stops_worker_children { # @test

    fake_packages
    export DOTFILES_FAKE_WAIT=1 DOTFILES_FAKE_STUBBORN=1

    python3 "$DOTFILES_CANDIDATE/tests/helpers/menu-terminal.py" "$repo" interrupt
    [ ! -e "$DOTFILES_FAKE_PACKAGES/sample-tool" ]

}

make_emacs_fixture() {

    source_repo="$case_root/arbitrary emacs source"
    mkdir "$source_repo"
    printf 'example config\n' > "$source_repo/init.el"
    git -C "$source_repo" init -b master
    git -C "$source_repo" add .
    git -C "$source_repo" -c user.name=Test -c user.email=test@example.invalid \
        -c commit.gpgsign=false commit -qm Fixture

    # A stand-in isolates cloning and preservation from Emacs package downloads.
    export SAMPLE_REPOSITORY="$source_repo" SAMPLE_EXECUTABLE="$case_root/fake-emacs"
    # Expand HOME when the stand-in runs, not while writing its source.
    # shellcheck disable=SC2016
    printf '#!/bin/bash\nprintf "called\\n" >> "$HOME/emacs-called"\n[ ! -e "$HOME/fail-bootstrap" ]\n' > "$SAMPLE_EXECUTABLE"
    chmod +x "$SAMPLE_EXECUTABLE"
    cat > "$repo/os/fixture-emacs.sh" <<'SCRIPT'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/configure_emacs.sh" \
    "$@" --repository "$SAMPLE_REPOSITORY" --executable "$SAMPLE_EXECUTABLE"
SCRIPT
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.editor = {
            "platforms": {
                "macos": {"status": "ready", "steps": [{"script": "os/fixture-emacs.sh"}]},
                "debian": {"status": "ready", "steps": [{"script": "os/fixture-emacs.sh"}]}
            }
        }
    ' "$repo/os/catalog.yaml"

}

function menu__configuration__emacs_uses_the_selected_features_repository_and_executable { # @test

    make_emacs_fixture
    feature_install --only editor
    [ "$(git -C "$HOME/.emacs.d" remote get-url origin)" = "$source_repo" ]
    printf 'local edit\n' >> "$HOME/.emacs.d/init.el"
    feature_install --only editor
    grep -Fxq 'local edit' "$HOME/.emacs.d/init.el"
    [ "$(wc -l < "$HOME/emacs-called" | tr -d ' ')" = 1 ]

}

function menu__scripts__emacs_runs_directly_with_explicit_arguments { # @test

    make_emacs_fixture
    unset DOTFILES_RESULT DOTFILES_OPTION_ID DOTFILES_RUN_DIRECTORY
    /bin/bash "$repo/os/configure_emacs.sh" \
        --repository "$SAMPLE_REPOSITORY" --executable "$SAMPLE_EXECUTABLE"
    [ "$(git -C "$HOME/.emacs.d" remote get-url origin)" = "$source_repo" ]
    [ "$(wc -l < "$HOME/emacs-called" | tr -d ' ')" = 1 ]

}

function menu__catalog__architecture_availability_matches_ui_and_executor { # @test

    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.folders.recommended = true |
        .groups.examples.options.folders.platforms[].architectures = ["imaginary-test-cpu"]
    ' "$repo/os/catalog.yaml"

    # Capture the actual UI request, without starting an installer worker.
    cat > "$repo/os/ui.sh" <<'CAPTURE'
#!/bin/bash
cat > "$HOME/menu-request.json"
CAPTURE
    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false '' false

    cat "$HOME/menu-request.json"
    [ "$(/bin/bash "$repo/os/yq.sh" -r '[.items[] | select(.id == "folders")] | length' "$HOME/menu-request.json")" = 0 ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.items[] | select(.id == "files") | .status' "$HOME/menu-request.json")" = ready ]
    expect_failure feature_install --only folders
    [ ! -e "$HOME/sample-area" ]

}

function menu__catalog__configuration_owners_are_distinct_but_shared_packages_install_once { # @test

    fake_packages
    case "$(uname -s)" in
        Darwin) export SAMPLE_PLATFORM=macos SAMPLE_MANAGER=brew ;;
        *) export SAMPLE_PLATFORM=debian SAMPLE_MANAGER=apt ;;
    esac
    cat > "$repo/os/fixture-other-directories.sh" <<'SCRIPT'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/create_personal_directories.sh" "$@" 'another area/child'
SCRIPT
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.folders.platforms[strenv(SAMPLE_PLATFORM)].steps += [{(strenv(SAMPLE_MANAGER)): ["sample-tool"]}] |
        .groups.examples.options["other-folders"] = .groups.examples.options.folders |
        .groups.examples.options["other-folders"].platforms[].steps[0].script = "os/fixture-other-directories.sh"
    ' "$repo/os/catalog.yaml"

    feature_install --only folders,other-folders,folders
    [ -d "$HOME/sample-area" ]
    [ -d "$HOME/another area/child" ]
    [ "$(wc -l < "$DOTFILES_FAKE_PACKAGES/calls" | tr -d ' ')" = 1 ]

}

function menu__configuration__failed_and_unverified_emacs_bootstrap_requires_explicit_retry { # @test

    make_emacs_fixture
    export DOTFILES_UI_DIRECTORY="$case_root/dashboard"
    mkdir "$DOTFILES_UI_DIRECTORY"
    touch "$HOME/fail-bootstrap"
    run feature_install --only editor
    [ "$status" -ne 0 ]
    [[ "$output" == *'Initialise Emacs packages — Failed'* ]]
    [[ "$output" == *'--only editor --retry-emacs-bootstrap'* ]]
    [ "$(git -C "$HOME/.emacs.d" config --local --get dotfiles.bootstrap-status)" = failed ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.states.editor' "$DOTFILES_UI_DIRECTORY/state.json")" = Failed ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.steps[-2].state' "$DOTFILES_UI_DIRECTORY/state.json")" = Succeeded ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.steps[-1].state' "$DOTFILES_UI_DIRECTORY/state.json")" = Failed ]
    original_head=$(git -C "$HOME/.emacs.d" rev-parse HEAD)
    printf 'local edits\n' >> "$HOME/.emacs.d/init.el"

    # Rerunning must neither hide failure nor unexpectedly execute configuration.
    run feature_install --only editor
    [ "$status" -ne 0 ]
    [[ "$output" == *'Initialise Emacs packages — Failed'* ]]
    [[ "$output" == *'--only editor --retry-emacs-bootstrap'* ]]
    [ "$(wc -l < "$HOME/emacs-called" | tr -d ' ')" = 1 ]

    rm "$HOME/fail-bootstrap"
    feature_install --only editor --retry-emacs-bootstrap
    [ "$(git -C "$HOME/.emacs.d" config --local --get dotfiles.bootstrap-status)" = succeeded ]
    [ "$(git -C "$HOME/.emacs.d" rev-parse HEAD)" = "$original_head" ]
    grep -Fxq 'local edits' "$HOME/.emacs.d/init.el"
    feature_install --only editor
    [ "$(wc -l < "$HOME/emacs-called" | tr -d ' ')" = 2 ]

    # Interrupted attempts and pre-marker checkouts must also remain unverified.
    for state in pending unknown; do
        if [ "$state" = unknown ]; then
            git -C "$HOME/.emacs.d" config --local --unset dotfiles.bootstrap-status
        else
            git -C "$HOME/.emacs.d" config --local dotfiles.bootstrap-status "$state"
        fi
        run feature_install --only editor
        [ "$status" -ne 0 ]
        [[ "$output" == *'Initialise Emacs packages — Failed'* ]]
    done
    [ "$(wc -l < "$HOME/emacs-called" | tr -d ' ')" = 2 ]

}

function menu__scripts__retry_command_quotes_option_names { # @test

    make_emacs_fixture
    export SAMPLE_EDITOR="Editor's config / examples"
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options[strenv(SAMPLE_EDITOR)] = .groups.examples.options.editor |
        del(.groups.examples.options.editor)
    ' "$repo/os/catalog.yaml"
    touch "$HOME/fail-bootstrap"

    run feature_install --only "$SAMPLE_EDITOR"
    [ "$status" -ne 0 ]

    # Bash's reusable quoting must reproduce the exact name as one argument.
    printf -v quoted_editor '%q' "$SAMPLE_EDITOR"
    [[ "$output" == *"--only $quoted_editor --retry-emacs-bootstrap"* ]]

}

# Desktop preferences include a wallpaper, so a logged-in screen is needed.
macos_has_screen() {

    /usr/bin/osascript >/dev/null 2>&1 <<'APPLESCRIPT'
use framework "AppKit"
set screens to current application's NSScreen's screens()
if (screens's |count|() as integer) is 0 then error "No screen"
APPLESCRIPT

}

function menu__preferences__reruns_preserve_unrelated_keys_and_shortcuts { # @test

    [ "$(uname -s)" = Darwin ] || skip 'macOS preferences'
    macos_has_screen || skip 'Requires a graphical macOS session'
    cp "$DOTFILES_CANDIDATE/os/catalog.yaml" "$repo/os/catalog.yaml"
    rm -rf "${repo:?}/home"
    cp -R "$DOTFILES_CANDIDATE/home" "$repo/home"

    # Exercise real macOS preferences only inside the disposable test VM.
    defaults write com.apple.dock dotfiles-test-unrelated -string retained
    defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add \
        999 '<dict><key>enabled</key><false/></dict>'

    # Protected motion settings can require a manual change in System Settings.
    for attempt in 1 2; do
        run feature_install --only 'macOS desktop preferences and background'
        if [ "$status" -ne 0 ]; then
            [[ "$output" = *'Could not enable Reduce Motion'* ]] || {
                printf 'Unexpected preference failure on attempt %s\n' "$attempt" >&2
                return 1
            }
        fi
    done

    [ "$(defaults read com.apple.dock dotfiles-test-unrelated)" = retained ]
    defaults export com.apple.symbolichotkeys "$case_root/shortcuts.plist"
    [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:999:enabled' "$case_root/shortcuts.plist")" = false ]

    # A failed settings script must leave existing preferences unchanged.
    defaults write com.apple.dock tilesize -float 37
    cat > "$repo/os/fixture-invalid-preferences.sh" <<'SCRIPT'
#!/bin/bash
exit 1
SCRIPT
    /bin/bash "$repo/os/yq.sh" -i '.groups["UX changes"].options["macOS desktop preferences and background"].platforms.macos.steps[0].script = "os/fixture-invalid-preferences.sh"' "$repo/os/catalog.yaml"
    expect_failure feature_install --only 'macOS desktop preferences and background'
    [ "$(defaults read com.apple.dock tilesize)" = 37 ]

}

function menu__preferences__native_settings_apply_in_disposable_macos { # @test

    [ "$(uname -s)" = Darwin ] || skip 'macOS preferences'
    cp "$DOTFILES_CANDIDATE/os/catalog.yaml" "$repo/os/catalog.yaml"
    rm -rf "${repo:?}/home"
    cp -R "$DOTFILES_CANDIDATE/home" "$repo/home"

    # Without a screen, the combined action must fail before changing settings.
    if ! macos_has_screen; then
        defaults write com.apple.dock tilesize -float 37
        expect_failure feature_install --only 'macOS desktop preferences and background'
        [ "$(defaults read com.apple.dock tilesize)" = 37 ]
        return
    fi

    # Other settings are applied even when macOS protects Reduce Motion.
    run feature_install --only 'macOS desktop preferences and background'
    export MOTION_APPLIED=true
    if [ "$status" -ne 0 ]; then
        [[ "$output" = *'Could not enable Reduce Motion'* ]]
        MOTION_APPLIED=false
    fi

    # Independently read back the intended settings, including shortcut types.
    python3 - <<'VERIFY'
import os, plistlib, subprocess

def preferences(domain):
    return plistlib.loads(subprocess.check_output(['defaults', 'export', domain, '-']))

dock = preferences('com.apple.dock')
assert dock['autohide'] is True
assert dock['mineffect'] == 'scale'
assert dock['mru-spaces'] is False
assert dock['tilesize'] == 51
assert preferences('com.apple.finder')['ShowPathbar'] is True
global_preferences = preferences('NSGlobalDomain')
assert global_preferences['AppleShowAllExtensions'] is True
assert global_preferences['NSAutomaticSpellingCorrectionEnabled'] is False
widgets = preferences('com.apple.WindowManager')
assert widgets['StandardHideWidgets'] is True
assert widgets['StageManagerHideWidgets'] is True
if os.environ['MOTION_APPLIED'] == 'true':
    motion = subprocess.check_output(['osascript', '-e',
        'use framework "AppKit"\nreturn current application\'s NSWorkspace\'s sharedWorkspace()\'s accessibilityDisplayShouldReduceMotion() as boolean'], text=True)
    assert motion.strip() == 'true'
shortcuts = preferences('com.apple.symbolichotkeys')['AppleSymbolicHotKeys']
for desktop, key_code in enumerate([18, 19, 20, 21, 23, 22, 26, 28, 25, 29], start=1):
    shortcut = shortcuts[str(117 + desktop)]
    assert shortcut['enabled'] is True, desktop
    assert shortcut['value']['type'] == 'standard', desktop
    assert shortcut['value']['parameters'] == [65535, key_code, 262144], desktop
VERIFY

    # macOS reads the checked-in image directly; no copy is created in HOME.
    background="$repo/os/os_x/grey.png"
    [ ! -e "$HOME/Library/Application Support/dotfiles/background.png" ]

    # Query the native API independently after applying the wallpaper.
    /usr/bin/osascript > "$case_root/active-background" <<'APPLESCRIPT'
use framework "AppKit"
set workspace to current application's NSWorkspace's sharedWorkspace()
set screen to current application's NSScreen's mainScreen()
return (workspace's desktopImageURLForScreen:screen)'s |path|() as text
APPLESCRIPT
    [ "$(cat "$case_root/active-background")" = "$background" ]

}

function menu__actions__links_and_configuration_follow_yaml_order { # @test

    cat > "$repo/os/fixture-order.sh" <<'CHECK'
#!/bin/bash
[ -L "$HOME/.sample-first" ] && [ ! -e "$HOME/.sample-second" ]
CHECK
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.files.link_dependencies = [".sample-first"] |
        .groups.examples.options.files.platforms[].steps = [{"script": "os/fixture-order.sh"}]
    ' "$repo/os/catalog.yaml"
    # shellcheck source=os/menu_catalog.sh
    source "$repo/os/menu_catalog.sh"
    feature_install --only "files,$(dotfile_id .sample-second)"
    [ -L "$HOME/.sample-second" ]

}

function menu__services__register_metadata_agents_and_preserve_existing_files { # @test

    [ "$(uname -s)" = Darwin ] || skip 'launchd services'
    export SAMPLE_AGENT_LABEL=org.example.synthetic-agent
    mkdir "$case_root/tools"
    cat > "$case_root/tools/example-agent" <<'AGENT'
#!/bin/bash
set -e
[ "$1" = --install-service ]
printf 'installed\n' >> "$HOME/agent-calls"
file="$HOME/Library/LaunchAgents/$SAMPLE_AGENT_LABEL.plist"
/usr/bin/plutil -create xml1 "$file"
/usr/libexec/PlistBuddy -c "Add :Label string $SAMPLE_AGENT_LABEL" "$file"
/usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$file"
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $0" "$file"
AGENT
    chmod +x "$case_root/tools/example-agent"
    export PATH="$case_root/tools:$PATH"
    cat > "$repo/os/fixture-agent.sh" <<'SCRIPT'
#!/bin/bash
exec /bin/bash "$(dirname "$0")/lib/launch_agents.sh" \
    "$@" example-agent "$SAMPLE_AGENT_LABEL"
SCRIPT
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.agent = {
          "platforms": {"macos": {"status": "ready", "steps": [{"script": "os/fixture-agent.sh"}]}}
        }
    ' "$repo/os/catalog.yaml"

    feature_install --only agent
    feature_install --only agent
    [ "$(wc -l < "$HOME/agent-calls" | tr -d ' ')" = 1 ]
    file="$HOME/Library/LaunchAgents/$SAMPLE_AGENT_LABEL.plist"
    /usr/libexec/PlistBuddy -c 'Set :Label unrelated' "$file"
    expect_failure feature_install --only agent
    [ "$(/usr/libexec/PlistBuddy -c 'Print :Label' "$file")" = unrelated ]

}

function menu__desktop__thinkpad_helpers_discover_devices_without_fixed_paths { # @test

    mkdir "$case_root/devices"
    export DEVICE_CALLS="$case_root/device-calls"
    cat > "$case_root/devices/xinput" <<'INPUT'
#!/bin/bash
if [ "$1" = list ]; then
    printf '%s\n' 'Example Trackpad With Spaces' 'Example Keyboard'
else
    [ "$#" = 2 ] || exit 1
    printf '%s\n' "$*" >> "$DEVICE_CALLS"
fi
INPUT
    cat > "$case_root/devices/xrandr" <<'DISPLAY'
#!/bin/bash
if [ "$1" = --query ]; then
    printf '%s\n' 'LVDS-42 connected primary 1280x800+0+0 (normal left inverted right x axis y axis)'
else
    printf '%s\n' "$*" >> "$DEVICE_CALLS"
fi
DISPLAY
    cat > "$case_root/devices/xsetwacom" <<'TABLET'
#!/bin/bash
if [ "$1" = list ]; then
    printf '%s\n' 'Wacom ISDv4 Example Pen stylus id: 42 type: STYLUS' 'External Drawing Tablet id: 99 type: STYLUS'
else
    printf '%s\n' "$*" >> "$DEVICE_CALLS"
fi
TABLET
    cat > "$case_root/devices/wpctl" <<'AUDIO'
#!/bin/bash
printf '%s\n' "$*" >> "$DEVICE_CALLS"
AUDIO
    printf '#!/bin/bash\nexit 0\n' > "$case_root/devices/notify-send"
    chmod +x "$case_root/devices/"*
    export PATH="$case_root/devices:$PATH"

    /bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/i3/touchpad.sh" off
    /bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/i3/rotate-tablet.sh"
    grep -Fxq 'disable Example Trackpad With Spaces' "$DEVICE_CALLS"
    grep -Fxq -- '--output LVDS-42 --rotate left' "$DEVICE_CALLS"
    grep -Fxq 'set 42 Rotate ccw' "$DEVICE_CALLS"
    grep -Fxq 'set 42 MapToOutput LVDS-42' "$DEVICE_CALLS"
    ! grep -q 'set 99 ' "$DEVICE_CALLS"
    /bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/i3/audio.sh" mic-mute
    /bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/i3/audio.sh" up
    grep -Fxq 'set-mute @DEFAULT_AUDIO_SOURCE@ toggle' "$DEVICE_CALLS"
    grep -Fxq 'set-volume --limit 1.0 @DEFAULT_AUDIO_SINK@ 5%+' "$DEVICE_CALLS"
    grep -Fxq 'set-mute @DEFAULT_AUDIO_SINK@ 0' "$DEVICE_CALLS"

}

function menu__desktop__battery_display_handles_multiple_and_absent_devices { # @test

    export DOTFILES_POWER_SUPPLY_DIR="$case_root/power"
    mkdir -p "$DOTFILES_POWER_SUPPLY_DIR/cell-a" "$DOTFILES_POWER_SUPPLY_DIR/cell-b"
    for device in "$DOTFILES_POWER_SUPPLY_DIR/"*; do
        printf 'Battery\n' > "$device/type"
        printf '1\n' > "$device/present"
    done
    printf '41\n' > "$DOTFILES_POWER_SUPPLY_DIR/cell-a/capacity"
    printf 'Charging\n' > "$DOTFILES_POWER_SUPPLY_DIR/cell-a/status"
    printf '73\n' > "$DOTFILES_POWER_SUPPLY_DIR/cell-b/capacity"
    [ "$(/bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/polybar/battery.sh")" = 'cell-a 41%+  cell-b 73%' ]
    printf '0\n' > "$DOTFILES_POWER_SUPPLY_DIR/cell-b/present"
    [ "$(/bin/bash "$DOTFILES_CANDIDATE/home/debian/.config/polybar/battery.sh")" = 'cell-a 41%+' ]

}

function menu__selection__overlapping_ids_and_link_names_match_exactly { # @test

    # Short IDs and paths must not match a selected longer value.
    cp "$repo/fixture/second" "$repo/home/common/.sample-first-extra"
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options = {"tile": .groups.examples.options.later, "tile-wide": .groups.examples.options.files} |
        .groups.examples.options.tile-wide.link_dependencies = [".sample-first-extra"] |
        .post_install = {} |
        .groups.examples.options.tile.todo = {"1. Checks": ["Short feature reminder"]} |
        .groups.examples.options.tile-wide.todo = {"1. Checks": ["Selected feature reminder"]}
    ' "$repo/os/catalog.yaml"

    cat > "$repo/os/ui.sh" <<'CAPTURE'
#!/bin/bash
cat > "$HOME/menu-request.json"
CAPTURE
    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false '' false
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.items[] | select(.id == "tile") | .selected' "$HOME/menu-request.json")" = false ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.items[] | select(.id == "tile-wide") | .selected' "$HOME/menu-request.json")" = true ]

    export DOTFILES_UI_DIRECTORY="$case_root/dashboard"
    mkdir "$DOTFILES_UI_DIRECTORY"
    printf '%s\n' '{"selected":["tile-wide"],"choices":{}}' \
        > "$DOTFILES_UI_DIRECTORY/state.json.selection"
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false '' false worker

    [ "$(/bin/bash "$repo/os/yq.sh" -r '.items | length' "$DOTFILES_UI_DIRECTORY/state.json.request")" = 2 ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '[.items[] | select(.id == "tile-wide")] | length' "$DOTFILES_UI_DIRECTORY/state.json.request")" = 1 ]
    [ -L "$HOME/.sample-first-extra" ]
    [ ! -e "$HOME/.sample-first" ]
    [ ! -e "$HOME/.sample-later" ]
    grep -Fq 'Selected feature reminder' "$HOME/TODO.org"
    ! grep -Fq 'Short feature reminder' "$HOME/TODO.org"

}

function menu__results__reminder_failure_preserves_successful_operation_results { # @test

    export DOTFILES_UI_DIRECTORY="$case_root/dashboard"
    mkdir "$DOTFILES_UI_DIRECTORY" "$HOME/TODO.org"

    run feature_install --only folders
    [ "$status" -ne 0 ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.states.folders' "$DOTFILES_UI_DIRECTORY/state.json")" = 'Installed and verified' ]
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.steps[-1].state' "$DOTFILES_UI_DIRECTORY/state.json")" = Succeeded ]
    [[ "$(/bin/bash "$repo/os/yq.sh" -r '.error' "$DOTFILES_UI_DIRECTORY/state.json")" == *'TODO.org could not be written'* ]]
    logs=$(/bin/bash "$repo/os/yq.sh" -r '.logs' "$DOTFILES_UI_DIRECTORY/state.json")
    [ -f "$logs/summary.txt" ]
    [ -f "$logs/result.json" ]

}

function menu__catalog__architecture_restrictions_keep_intel_routes_available { # @test

    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.files.platforms.debian.architectures = ["amd64"] |
        .groups.examples.options.folders.platforms.debian.architectures = ["arm64"]
    ' "$repo/os/catalog.yaml"
    root=$repo
    platform=debian
    fail() { printf '%s\n' "$*" >&2; return 1; }
    # shellcheck source=os/menu_catalog.sh
    source "$repo/os/menu_catalog.sh"

    # Override only the catalogue's CPU query in this process. The parser itself
    # still runs natively; this tests decisions, not execution of an Intel binary.
    uname() { printf '%s\n' "$test_cpu"; }
    for test_cpu in x86_64 amd64 aarch64 arm64; do
        load_catalog
        case "$test_cpu" in
            x86_64|amd64) native=files; foreign=folders ;;
            *) native=folders; foreign=files ;;
        esac
        [ "${feature_status[$(feature_index "$native")]}" = ready ]
        ! feature_index "$foreign" >/dev/null
    done

}

function menu__binaries__dispatch_uses_os_and_cpu_without_arm_fallback { # @test

    mkdir "$case_root/commands"
    cat > "$case_root/commands/uname" <<'UNAME'
#!/bin/bash
case "$1" in -s) printf '%s\n' "$TEST_OS" ;; -m) printf '%s\n' "$TEST_CPU" ;; esac
UNAME
    chmod +x "$case_root/commands/uname"
    export PATH="$case_root/commands:$PATH"
    for file in "$repo/os/vendor/yq/"yq_* "$repo/os/vendor/installer-ui/"installer-ui_*; do
        # Preserve $0 for the stub's own invocation.
        # shellcheck disable=SC2016
        printf '#!/bin/bash\nbasename "$0"\n' > "$file"
        chmod +x "$file"
    done
    for TEST_OS in Linux Darwin; do
        export TEST_OS
        case "$TEST_OS" in Linux) expected_os=linux ;; *) expected_os=darwin ;; esac
        for TEST_CPU in x86_64 aarch64; do
            export TEST_CPU
            case "$TEST_CPU" in x86_64) expected_cpu=amd64 ;; *) expected_cpu=arm64 ;; esac
            [ "$(/bin/bash "$repo/os/ui.sh")" = "installer-ui_${expected_os}_${expected_cpu}" ]
            [ "$(/bin/bash "$repo/os/yq.sh")" = "yq_${expected_os}_${expected_cpu}" ]
        done
        export TEST_CPU=unsupported-example
        expect_failure /bin/bash "$repo/os/ui.sh"
        expect_failure /bin/bash "$repo/os/yq.sh"
        expect_failure /bin/bash "$repo/bin/get-compression-heatmap"
    done

}

function menu__script__runs_checkout_file_and_reports_its_failure { # @test

    cat > "$repo/os/fixture-operation.sh" <<'SCRIPT'
#!/bin/bash
printf 'Script output reached the log\n'
printf 'ran\n' >> "$HOME/script-runs"
exit "${FIXTURE_EXIT:-0}"
SCRIPT
    cat > "$repo/os/catalog.yaml" <<'YAML'
schema_version: 1
groups:
  dotfiles:
    discover_dotfiles: true
    options: {}
  fixture:
    options:
      invented-operation:
        platforms:
          macos: {status: ready, steps: [{script: os/fixture-operation.sh}]}
          debian: {status: ready, steps: [{script: os/fixture-operation.sh}]}
YAML
    run feature_install --only invented-operation
    [ "$status" -eq 0 ]
    [ -f "$HOME/script-runs" ]

    export FIXTURE_EXIT=7
    run feature_install --only invented-operation
    [ "$status" -ne 0 ]
    [[ "$output" = *'Failed'* ]]

    sed 's@os/fixture-operation.sh@os/../outside.sh@g' "$repo/os/catalog.yaml" > "$case_root/invalid.yaml"
    mv "$case_root/invalid.yaml" "$repo/os/catalog.yaml"
    run feature_install --only invented-operation
    [ "$status" -ne 0 ]
    [[ "$output" = *'traverse'* ]]
    [ "$(wc -l < "$HOME/script-runs" | tr -d ' ')" = 2 ]

}

function menu__catalog__steps_are_available_without_explicit_status { # @test

    # Fixture-only values show availability is a schema default, not an inventory.
    /bin/bash "$repo/os/yq.sh" -i 'del(.groups.examples.options.tools.platforms[].status)' "$repo/os/catalog.yaml"
    fake_packages
    feature_install --only tools

}

function menu__dotfiles__discovery_defaults_and_merged_dependencies { # @test

    printf 'platform only\n' > "$repo/home/debian/.platform-only"
    cp "$repo/fixture/first" "$repo/home/common/.unrelated"
    /bin/bash "$repo/os/yq.sh" -i '
        .groups.examples.options.files.link_dependencies = [".sample-first"] |
        .groups.examples.options.files.platforms[].link_dependencies = [".sample-second"]
    ' "$repo/os/catalog.yaml"

    cat > "$repo/os/ui.sh" <<'CAPTURE'
#!/bin/bash
cat > "$HOME/menu-request.json"
CAPTURE
    case "$(uname -s)" in Darwin) platform=macos ;; *) platform=debian ;; esac
    /bin/bash "$repo/os/install_menu.sh" "$repo" "$platform" false '' false
    # A synthetic path appears immediately with no catalogue entry and is preselected.
    [ "$(/bin/bash "$repo/os/yq.sh" -r '.items[] | select(.label == ".unrelated") | .selected' "$HOME/menu-request.json")" = true ]
    if [ "$platform" = debian ]; then
        [ "$(/bin/bash "$repo/os/yq.sh" -r '[.items[] | select(.label == ".platform-only")] | length' "$HOME/menu-request.json")" = 1 ]
    else
        [ "$(/bin/bash "$repo/os/yq.sh" -r '[.items[] | select(.label == ".platform-only")] | length' "$HOME/menu-request.json")" = 0 ]
    fi

    feature_install --only files
    [ -L "$HOME/.sample-first" ] && [ -L "$HOME/.sample-second" ]
    [ ! -e "$HOME/.unrelated" ] && [ ! -e "$HOME/.sample-later" ]

    /bin/bash "$repo/os/yq.sh" -i '.groups.examples.options.files.link_dependencies = [".missing-target"]' "$repo/os/catalog.yaml"
    run feature_install --only files
    [ "$status" -ne 0 ]
    [[ "$output" = *'Missing dotfile dependency'* ]]

}
