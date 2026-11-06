#!/bin/bash

# Internal entrypoint. The public command parses options and detects the OS.
set -eo pipefail

root=${1:?Checkout root required}
platform=${2:?Platform required}
backup=${3:?Backup preference required}
only=${4:-}
assume_yes=${5:-false}

# Opt out before any Homebrew command, including installation and inspection.
# After confirmation, brew analytics off also persists the preference.
export HOMEBREW_NO_ANALYTICS=1

fail() {

    printf 'dotfiles: %s\n' "$*" >&2
    exit 1

}

report_status() {

    local state=$1 label=$2 marker color

    case "$state" in
        success) marker='✓'; color=32 ;;
        failure) marker='✗'; color=31 ;;
        *) marker='·'; color=0 ;;
    esac

    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        printf '\033[%sm%s\033[0m %s\n' "$color" "$marker" "$label"
    else
        printf '%s %s\n' "$marker" "$label"
    fi

}

ui() {

    /bin/bash "$root/os/ui.sh" "$@"

}

# shellcheck source=os/menu_catalog.sh
source "$root/os/menu_catalog.sh"

# shellcheck source=os/install_actions.sh
source "$root/os/install_actions.sh"

# shellcheck source=os/post_install.sh
source "$root/os/post_install.sh"

#  - - -  Present the catalogue through the standalone JSON interface  - - -

catalogue_request() {

    local request

    # yq handles JSON escaping; labels and notes are never shell expressions.
    # Names are data: yq escapes them for the UI's JSON interface.
    # Compare whole IDs: yq contains() also matches substrings within strings.
    # shellcheck disable=SC2016
    request=$(UI_BRAND="brendan's dotfiles" LINK_CHOICES="${link_choices:-null}" PLATFORM="$platform" SELECTION="$(IFS=,; printf '%s' "${selected[*]}")" \
        catalog_read '
        {"version": 1, "title": "Select what will be installed and configured",
         "brand": strenv(UI_BRAND),
         "completion": {"file": (strenv(HOME) + "/TODO.org"), "title": "~/TODO.org",
             "success_title": "Setup success!", "button": "Happy Hacking!",
             "success_text": "The script has done all it can. There are likely some additional things to do in the OS to get everything working. Your TODO list is in ~/TODO.org. And previewed on the right."},
         "groups": (.groups | to_entries | map({"id": .key, "label": .value})),
         "items": (.features | to_entries | map(select(.value.platforms[strenv(PLATFORM)] != null)) |
           map({"id": .key, "label": .value.label, "group": .value.group,
                "parent": (.value.parent // ""), "requires": (.value.platforms[strenv(PLATFORM)].requires // .value.requires // []),
                "choices": (env(LINK_CHOICES)[.key] // null),
                "options": ([.value as $feature | .value.platforms[strenv(PLATFORM)].steps[]? |
                    select(($feature.individual // false) == false) | .links[]?] | map({"id": ., "label": .})),
                "status": .value.platforms[strenv(PLATFORM)].status,
                "operations": ([.value.platforms[strenv(PLATFORM)].steps[]? |
                    ((.links // [])[] | "Symlink ~/" + .),
                    ((.brew // [])[] | "Install with Homebrew: " + .),
                    ((.cask // [])[] | "Install application with Homebrew: " + .),
                    ((.apt // [])[] | "Install with APT: " + .),
                    (select(.tap != null) | "Trust Homebrew tap: " + .tap),
                    (select(.script != null) | "Run " + .script)]),
                "note": (.value.platforms[strenv(PLATFORM)].note // .value.note // ""),
                "selected": ((.key | @base64) as $id | strenv(SELECTION) | split(",") | map(select((. | @base64) == $id)) | length > 0)}))} | @json
    ')

    printf '%s\n' "$request"

}

read_selection() {

    local response id

    response=$(cat "$DOTFILES_UI_DIRECTORY/state.json.selection")
    link_choices=$(printf '%s\n' "$response" | /bin/bash "$root/os/yq.sh" -o=json '.choices')
    selected=()

    while IFS= read -r id; do
        [ -n "$id" ] && selected+=("$id")
    done < <(printf '%s\n' "$response" | /bin/bash "$root/os/yq.sh" -r '.selected[]')

}

#  - - -  Review the installation plan  - - -

linker() {

    local options=()

    if "$backup"; then
        options+=(--backup)
    fi

    /bin/bash "$root/os/create_symbolic_links.sh" "$root" "$platform" "${options[@]}" "$@"

}

show_plan() {

    local id index action

    printf '\nInstallation plan (%s)\n' "$platform"

    if "$needs_brew" && [ -z "$brew_command" ]; then
        printf '  Prerequisite: install Homebrew using its official installer.\n'
    fi

    if "$needs_brew"; then
        printf '  Disable Homebrew analytics (also saved for future brew commands).\n'
    fi

    for id in "${plan_features[@]}"; do
        index=$(feature_index "$id")
        printf '\n  %s\n' "${feature_labels[$index]}"

        for ((action = 0; action < ${#plan_owners[@]}; action++)); do
            [ "${plan_owners[$action]}" = "$id" ] || continue
            case "${plan_kinds[$action]}" in
                links) printf '    Link ~/%s to this checkout\n' "${plan_values[$action]}" ;;
                tap) printf '    Add and trust Homebrew tap %s\n' "${plan_values[$action]}" ;;
                brew) printf '    Install %s with Homebrew\n' "${plan_values[$action]}" ;;
                cask) printf '    Install %s with Homebrew Cask\n' "${plan_values[$action]}" ;;
                apt) printf '    Install %s with APT\n' "${plan_values[$action]}" ;;
                script) printf '    Run %s\n' "${plan_values[$action]}" ;;
            esac
        done
    done

    if "$backup"; then
        printf '\nConflicting dotfiles will be backed up before replacement.\n'
    fi

    printf '\nOnly these selections and their dependencies will be installed.\n'
    printf 'Post-install reminders will be added to ~/TODO.org; existing notes and checked boxes are retained.\n'

}

#  - - -  Execute one feature at a time, keeping native prompts usable  - - -

# The UI reads this separate status file; command output is only terminal output.
# IDs were validated by load_catalog; status values are fixed strings below.
# Record each attempted step separately from the feature's overall result.
# yq escapes labels and paths; catalogue text is never interpolated into JSON.
record_operation() {

    local state=$1 detail=${2:-} action=${3:-}

    OP_INDEX="$operation_index" OP_FEATURE="$active_feature" \
        OP_LABEL="$operation_label" OP_STATE="$state" OP_DETAIL="$detail" \
        OP_LOG="${current_log:-}" OP_ACTION="$action" \
        /bin/bash "$root/os/yq.sh" -i -o=json '
            .[env(OP_INDEX)] = {
                "feature": strenv(OP_FEATURE), "label": strenv(OP_LABEL),
                "state": strenv(OP_STATE), "detail": strenv(OP_DETAIL),
                "log": strenv(OP_LOG), "action": strenv(OP_ACTION)
            }
        ' "$run_directory/operations.json" || return 1

    operation_state=$state
    publish_progress

}

start_operation() {

    operation_index=$((operation_index + 1))
    operation_label=$1
    record_operation Working

}

publish_progress() {

    local row ids states
    local progress_ids=() progress_states=()

    if "$needs_brew"; then
        progress_ids+=(__homebrew-setup)
        progress_states+=("${homebrew_result:-Not run}")
    fi

    for ((row = 0; row < ${#plan_features[@]}; row++)); do
        progress_ids+=("${plan_features[$row]}")
        progress_states+=("${results[$row]}")
    done

    # Names may contain quotes, slashes or shell characters. Pass them as
    # data and let yq produce JSON; catalogue validation excludes newlines.
    ids=$(printf '%s\n' "${progress_ids[@]}")
    states=$(printf '%s\n' "${progress_states[@]}")
    # shellcheck disable=SC2016
    RESULT_IDS="$ids" RESULT_STATES="$states" RESULT_ACTIVE="${active_feature:-}" \
        RESULT_STEPS="$run_directory/operations.json" RESULT_ERROR="${result_error:-}" \
        RESULT_LOGS="$run_directory" /bin/bash "$root/os/yq.sh" -n -o=json '
            (strenv(RESULT_STATES) | split("\n")) as $states |
            {"active": strenv(RESULT_ACTIVE),
             "states": ((strenv(RESULT_IDS) | split("\n") | to_entries | .[]) as $entry
                 ireduce ({}; .[$entry.value] = $states[$entry.key])),
             "steps": load(strenv(RESULT_STEPS)),
             "error": strenv(RESULT_ERROR), "logs": strenv(RESULT_LOGS)}
        ' > "$run_directory/result.next" || return 1

    mv "$run_directory/result.next" "$run_directory/result.json"
    [ -n "${DOTFILES_UI_DIRECTORY:-}" ] || return 0
    cp "$run_directory/result.json" "$DOTFILES_UI_DIRECTORY/state.next"

    # Rename makes every observed snapshot complete, even during fast operations.
    mv "$DOTFILES_UI_DIRECTORY/state.next" "$DOTFILES_UI_DIRECTORY/state.json"

}

prepare_dashboard() {

    local request
    selected=("${plan_features[@]}")
    request=$(catalogue_request)

    # Keep catalogue ordering in the sidebar; execution still follows dependencies.
    request=$(printf '%s\n' "$request" | /bin/bash "$root/os/yq.sh" -o=json '
        .items |= map(select(.selected)) |
        .items[].requires = [] |
        .items[].parent = ""
    ')

    if "$needs_brew"; then
        request=$(printf '%s\n' "$request" | /bin/bash "$root/os/yq.sh" -o=json '
            .groups = [{"id": "__prerequisites", "label": "Getting ready"}] + .groups |
            .items = [{"id": "__homebrew-setup", "label": "Homebrew · analytics off",
                       "group": "__prerequisites", "status": "ready"}] + .items
        ')
    fi

    printf '%s\n' "$request" > "$DOTFILES_UI_DIRECTORY/state.json.request.next"
    mv "$DOTFILES_UI_DIRECTORY/state.json.request.next" "$DOTFILES_UI_DIRECTORY/state.json.request"

}

start_session() {

    local directory code=0

    directory=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-ui.XXXXXX")
    catalogue_request > "$directory/request.json"

    # One UI owns the terminal from selection through completion. The executor
    # reads the saved selection and runs the plan inside the terminal pane.
    DOTFILES_UI_DIRECTORY="$directory" \
        ui session "$directory/state.json" -- \
        /bin/bash "$root/os/install_menu.sh" "$root" "$platform" "$backup" \
        "" false worker < "$directory/request.json" || code=$?

    # The dashboard uses the alternate screen. Leave a useful summary afterwards.
    if [ -f "$directory/summary" ]; then
        cat "$directory/summary"
    fi

    rm -rf "$directory"
    return "$code"

}

run_logged() {

    local title=$1 code=0
    shift

    printf '%s\n' "$title" >> "$current_log"

    if [ -n "${DOTFILES_UI_DIRECTORY:-}" ]; then
        printf '%s\n' "$title"

        # The dashboard supplies a real foreground PTY, including password echo
        # control. Stream output to both its live pane and the persistent log.
        "$@" 2>&1 | tee -a "$current_log"
        return
    fi

    # Give the action its own process group. The interrupt handler can then stop
    # the package manager and its children, not merely the spinner watching it.
    set -m
    (
        # Authentication already happened in the foreground. A background sudo
        # must not read the terminal or stop while restoring terminal settings.
        trap '' TTIN TTOU
        "$@" </dev/null >> "$current_log" 2>&1
    ) &
    active_pid=$!
    set +m

    printf '  %s\n' "$title"

    wait "$active_pid" || code=$?
    active_pid=''
    return "$code"

}

perform_feature() {

    local id=$1 index kind value result_file script_code substep_label substep_detail substep_action
    local script_options=()

    if "$backup"; then
        script_options+=(--backup)
    fi

    feature_changed=false
    feature_not_run=false
    completion_note=

    for ((index = 0; index < ${#plan_owners[@]}; index++)); do
        [ "${plan_owners[$index]}" = "$id" ] || continue
        kind=${plan_kinds[$index]}
        value=${plan_values[$index]}

        case "$kind" in
            links) operation_label="Sync ~/$value" ;;
            script) operation_label="Run $value" ;;
            *) operation_label="Install $value ($kind)" ;;
        esac
        start_operation "$operation_label" || return 1

        case "$kind" in
            links)
                # Apply links here, in YAML order, before a later script uses them.
                if ! linker --status --selected "$value" >/dev/null 2>&1; then
                    feature_changed=true
                    linker --selected "$value" >> "$current_log" 2>&1 || return 1
                    sed -n '/^Backup: /p' "$current_log"
                fi

                linker --status --selected "$value" >> "$current_log" 2>&1 || return 1
                report_status success "Synced ~/$value"
                ;;
            brew|cask|apt|tap)
                # Revisit tap trust even when the tap was added by an earlier run.
                if [ "$kind" != tap ] && package_present "$kind" "$value" >> "$current_log" 2>&1; then
                    report_status success "Already present: $value"
                else
                    feature_changed=true
                    install_package "$kind" "$value" || return 1
                    report_status success "Installed: $value"
                fi
                ;;
            script)
                result_file="$run_directory/action-$index.result"
                rm -f "$result_file"

                # Scripts may prompt (including sudo). Keep them foregrounded
                # so their input and output work in the dashboard and terminal.
                printf 'Running %s\n' "$value"
                script_code=0
                DOTFILES_BACKUP="$backup" DOTFILES_RESULT="$result_file" \
                    DOTFILES_OPTION_ID="$id" DOTFILES_RUN_DIRECTORY="$run_directory" \
                    /bin/bash "$root/$value" "${script_options[@]}" \
                    2>&1 | tee -a "$current_log" || script_code=$?

                # Result files are optional. An ordinary zero-exit script is a
                # completed change, and can be run without any installer state.
                completion_note=
                if [ -f "$result_file" ]; then
                    IFS= read -r completion_note < "$result_file" || true
                fi

                # A named substep can explain a failing exit while preserving
                # an earlier success. All other nonzero exits fail outright.
                if [ "$script_code" -ne 0 ] && [ "$completion_note" != substep-failed ]; then
                    return "$script_code"
                fi

                case "$completion_note" in
                    ''|changed)
                        feature_changed=true
                        report_status success "Completed: $value"
                        ;;
                    unchanged)
                        report_status success 'Already configured'
                        ;;
                    skipped)
                        feature_not_run=true
                        report_status pending "Skipped: $value"
                        record_operation 'Not run' 'The script skipped this operation; see its output.' \
                            'Review the script output and retry if needed.'
                        continue
                        ;;
                    substep-failed)
                        # A script may report completed work followed by a
                        # failed named substep, with a concrete retry action.
                        substep_label=$(sed -n '2p' "$result_file")
                        substep_detail=$(sed -n '3p' "$result_file")
                        substep_action=$(sed -n '4p' "$result_file")
                        [ -n "$substep_label" ] && [ -n "$substep_detail" ] && [ -n "$substep_action" ] \
                            || { printf 'Invalid script result: %s\n' "$value" >&2; return 1; }
                        report_status success "Completed: $value"
                        record_operation Succeeded 'Earlier work completed.' || return 1
                        start_operation "$substep_label" || return 1
                        record_operation Failed "$substep_detail" "$substep_action" || return 1
                        report_status failure "$substep_detail $substep_action"
                        return 1
                        ;;
                    *)
                        printf 'Unknown script result for %s: %s\n' "$value" "$completion_note" >&2
                        return 1
                        ;;
                esac
                ;;
        esac
        record_operation Succeeded || return 1
    done

}

render_results() {

    local index feature state

    printf '\nResults\n'

    for ((index = 0; index < ${#plan_features[@]}; index++)); do
        feature=$(feature_index "${plan_features[$index]}")
        case "${results[$index]}" in
            'Installed and verified'|'Already present') state=success ;;
            Failed|Interrupted) state=failure ;;
            *) state=pending ;;
        esac

        report_status "$state" "${feature_labels[$feature]} — ${results[$index]}"
    done

    /bin/bash "$root/os/yq.sh" -r '
        .[] | select(.state != "Succeeded") |
        .label + " — " + .state + "\n" + .detail + "\n" + .action + "\nLog: " + .log
    ' "$run_directory/operations.json"
    printf 'Logs and saved results: %s\n' "$run_directory"

    write_post_install || {
        result_error='Installation results are above, but TODO.org could not be written. Check its path and permissions, then rerun the installer.'
        printf '%s\n' "$result_error" >&2
        publish_progress
        return 1
    }

}

print_results() {

    publish_progress

    local code=0
    render_results | tee "$run_directory/summary.txt" || code=$?
    if [ -n "${DOTFILES_UI_DIRECTORY:-}" ]; then
        cp "$run_directory/summary.txt" "$DOTFILES_UI_DIRECTORY/summary"
    fi
    return "$code"

}

interrupted() {

    if [ -n "${active_pid:-}" ]; then
        kill -TERM -- "-$active_pid" 2>/dev/null || true
        kill -CONT -- "-$active_pid" 2>/dev/null || true
        wait "$active_pid" 2>/dev/null || true
        active_pid=''
    fi

    local row
    for ((row = 0; row < ${#results[@]}; row++)); do
        [ "${results[$row]}" != Working ] || results[row]=Interrupted
    done

    if [ "${operation_state:-}" = Working ]; then
        record_operation Interrupted 'Installer interrupted.' 'Rerun the installer and select this item.' || true
    fi

    printf '\nInterrupted. Completed changes are retained.\n' >&2
    print_results || true
    exit 130

}

execute_plan() {

    local id index feature brew_prefix failure_detail

    # Keep logs outside HOME so a selected .local link cannot redirect them.
    run_directory=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install.XXXXXX")
    results=()
    operation_index=-1
    operation_state=
    result_error=
    printf '[]\n' > "$run_directory/operations.json"
    apt_updated=false

    for id in "${plan_features[@]}"; do
        results+=('Not run')
    done

    trap interrupted INT TERM

    if "$needs_brew"; then
        active_feature=__homebrew-setup
        homebrew_result=Working
    fi
    publish_progress

    if "$needs_brew" && [ -z "$brew_command" ]; then
        current_log="$run_directory/homebrew.log"

        if ! install_homebrew 2>&1 | tee "$current_log"; then
            homebrew_result=Failed
            printf 'Homebrew installation failed.\n' >&2
            print_results
            return 1
        fi

        # A pipeline runs its function in a subshell; discover the new executable here.
        brew_command=$(find_brew) || return 1
    fi

    if "$needs_brew"; then
        # Newly installed tools must be visible to later configuration scripts.
        # Read the prefix as data instead of evaluating Homebrew's shell output.
        brew_prefix=$("$brew_command" --prefix) || return 1
        export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"

        if ! "$brew_command" analytics off >> "$run_directory/homebrew.log" 2>&1; then
            homebrew_result=Failed
            report_status failure 'Could not disable Homebrew analytics'
            print_results
            return 1
        fi

        homebrew_result='Installed and verified'
        publish_progress
        report_status success 'Homebrew analytics disabled (saved for future brew commands)'
    fi

    for ((index = 0; index < ${#plan_features[@]}; index++)); do
        id=${plan_features[$index]}
        feature=$(feature_index "$id")
        # Use a numeric filename; the human-readable option name is not a path.
        current_log="$run_directory/feature-$index.log"
        : > "$current_log"
        printf '\n%s\n' "${feature_labels[$feature]}"
        results[index]='Working'
        active_feature=$id
        publish_progress

        if perform_feature "$id"; then
            if "$feature_not_run"; then
                results[index]='Not run'
            elif "$feature_changed"; then
                results[index]='Installed and verified'
            else
                results[index]='Already present'
            fi

        else
            results[index]='Failed'
            if [ "$operation_state" = Working ]; then
                # Keep the actual error in the completion screen and saved summary.
                # Bound noisy command output; the full log remains linked below it.
                failure_detail=$(tail -n 15 "$current_log")
                if [ -n "$failure_detail" ]; then
                    failure_detail=$(printf 'Recent command output:\n%s' "$failure_detail")
                else
                    failure_detail='The command failed without writing any output to its log.'
                fi

                record_operation Failed "$failure_detail" \
                    'Resolve the reported error, then rerun the installer and select this item.'
            fi
            printf '✗ Failed. Recent output:\n' >&2
            tail -n 15 "$current_log" >&2
            print_results
            return 1
        fi
        publish_progress
    done

    active_feature=
    trap - INT TERM
    print_results

}

#  - - -  Main flow  - - -

[ -d "$HOME" ] && [ ! -L "$HOME" ] || fail 'HOME must be an existing non-symlink directory.'

load_catalog
selected=()
brew_command=$(find_brew) || brew_command=''

if [ -n "$only" ]; then
    IFS=, read -r -a selected <<< "$only"
else
    for ((index = 0; index < ${#feature_ids[@]}; index++)); do
        if [ "${feature_status[$index]}" = ready ] \
            && [ "${feature_recommended[$index]}" = true ]; then
            selected+=("${feature_ids[$index]}")
        fi
    done
fi

if [ "${6:-}" = worker ]; then
    read_selection
elif ! "$assume_yes"; then
    start_session
    exit $?
fi

if [ "${#selected[@]}" -eq 0 ]; then
    printf 'Nothing selected. No installation changes made.\n'
    exit 0
fi

build_plan

if [ "${6:-}" = worker ]; then
    prepare_dashboard
else
    show_plan
fi

execute_plan
