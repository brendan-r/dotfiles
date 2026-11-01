#!/bin/bash

# The sourcing installer supplies root, platform, and the selected IDs.
# shellcheck disable=SC2154

# Sourced by the installer. Catalogue names serve as IDs and visible labels.
# Indexed arrays work with the Bash 3.2 shipped on macOS.
# shellcheck disable=SC2034

catalog_read() {

    if [ -n "${catalog_data:-}" ]; then
        printf '%s\n' "$catalog_data" | /bin/bash "$root/os/yq.sh" eval -r "$1" -
    else
        /bin/bash "$root/os/yq.sh" eval -r "$1" "$root/os/catalog.yaml"
    fi

}

valid_id() {

    # Commas delimit --only and dependency lists; controls break line-based
    # exchange with yq. Backslashes are escaped by yq's TSV output, while
    # wildcards would make a yq map lookup match more than one key.
    case "$1" in
        ''|-|*,*|*[[:cntrl:]]*|*\\*|*\**|*\?*|\ *|*\ |__homebrew-setup|__prerequisites) return 1 ;;
    esac

}

feature_index() {

    local index

    for ((index = 0; index < ${#feature_ids[@]}; index++)); do
        if [ "${feature_ids[$index]}" = "$1" ]; then
            printf '%s\n' "$index"
            return 0
        fi
    done

    return 1

}

contains() {

    local wanted=$1 item
    shift

    for item in "$@"; do
        if [ "$item" = "$wanted" ]; then
            return 0
        fi
    done

    return 1

}

# Keep IDs short enough for log filenames. Detect a duplicate before use, so
# even an unlikely hash collision cannot silently select the wrong dotfile.
dotfile_id() {

    local digest

    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(printf '%s' "$1" | sha256sum)
    else
        digest=$(printf '%s' "$1" | shasum -a 256)
    fi

    printf 'file-%s' "${digest%% *}"

}

#  - - -  Load the visible menu without executing any route  - - -

load_catalog() {

    local validation rows id label group recommended status dependencies machine_arch extra
    local manifest scope source target dependency_id dependency_rows dotfile_group
    local option_ids=()
    local dotfile_ids=()

    catalog_data=
    machine_arch=$(uname -m)
    case "$machine_arch" in
        aarch64) machine_arch=arm64 ;;
        x86_64) machine_arch=amd64 ;;
    esac

    validation=$(CATALOG_SEPARATOR=$'\037' catalog_read '

        (.schema_version == 1) and
        (.groups | tag == "!!map") and
        ([.groups[] | select((.options // {}) | tag != "!!map")] | length == 0) and
        ([.groups | keys | .[] | select(tag != "!!str")] | length == 0) and
        ([.groups[].options // {} | keys | .[] | select(tag != "!!str")] | length == 0) and
        ([.groups | keys | .[] | select(tag == "!!str") | select(test("[[:cntrl:]]"))] | length == 0) and
        ([.groups[].options // {} | keys | .[] | select(tag == "!!str") | select(test("[[:cntrl:]]"))] | length == 0) and
        ([.. | select(tag == "!!str") | select(contains(strenv(CATALOG_SEPARATOR)))] | length == 0) and
        ([.groups[] | select(.discover_dotfiles == true)] | length == 1)
    ')

    [ "$validation" = true ] || fail 'Expected one version-1 feature catalog.'

    # IDs are used across groups for dependencies and selection. Check them
    # before flattening, so duplicate names cannot silently overwrite options.
    rows=$(catalog_read '.groups[].options // {} | keys | .[]')
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        valid_id "$id" || fail "Invalid option ID: $id"
        contains "$id" "${option_ids[@]}" && fail "Duplicate option: $id"
        option_ids+=("$id")
    done <<< "$rows"

    # One explicit marker identifies where discovered files appear. The group
    # name itself remains editable, like any other catalogue name.
    dotfile_group=$(catalog_read '.groups | to_entries | .[] | select(.value.discover_dotfiles == true) | .key')

    # Flatten the editable groups once. Existing consumers use a single lookup
    # by option ID; the menu group and label come from their enclosing entries.
    # All later reads also share the same platform and architecture filtering.
    # shellcheck disable=SC2016
    catalog_data=$(PLATFORM="$platform" MACHINE_ARCH="$machine_arch" catalog_read '
        . as $catalog |
        .groups = ($catalog.groups | with_entries(.value = .key)) |
        .features = ([$catalog.groups | to_entries | .[] |
            .key as $group | (.value.options // {}) | to_entries | .[] |
            .value.group = $group | .value.label = .key |
            {(.key): .value}] | .[] as $item ireduce ({}; . * $item)) |
        del(.features[].platforms[strenv(PLATFORM)] |
            select(. != null) |
            select((.architectures // [strenv(MACHINE_ARCH)]) |
                   map(select(. == strenv(MACHINE_ARCH))) | length == 0)) |
        (.features[].platforms[] | select(.status == null)).status = "ready"
    ')

    # The filesystem owns the inventory. Each target becomes one preselected
    # menu item and one ordinary link action, using a stable path-derived ID.
    manifest=$(/bin/bash "$root/os/catalog_links.sh" "$root" "$platform") || return 1
    while IFS=$'\t' read -r scope source target; do
        [ -n "$target" ] || continue
        id=$(dotfile_id "$target")
        contains "$id" "${dotfile_ids[@]}" && fail "Duplicate dotfile ID: $target"
        [ "$(DOTFILE_ID="$id" catalog_read '.features[strenv(DOTFILE_ID)] == null')" = true ] \
            || fail "Dotfile ID conflicts with a feature: $id"
        dotfile_ids+=("$id")
        catalog_data=$(DOTFILE_ID="$id" DOTFILE_PATH="$target" DOTFILE_GROUP="$dotfile_group" PLATFORM="$platform" catalog_read '
            .features[strenv(DOTFILE_ID)] = {
                "label": strenv(DOTFILE_PATH), "group": strenv(DOTFILE_GROUP),
                "recommended": true, "individual": true,
                "platforms": {(strenv(PLATFORM)): {
                    "status": "ready", "steps": [{"links": [strenv(DOTFILE_PATH)]}]
                }}
            }
        ')
    done <<< "$manifest"

    # Turn named target prerequisites into the IDs just generated above. Keep
    # paths in metadata, so users never have to calculate or edit encoded IDs.
    # yq variables in this expression are not shell variables.
    # shellcheck disable=SC2016
    dependency_rows=$(PLATFORM="$platform" CATALOG_SEPARATOR=$'\037' catalog_read '
        .features | to_entries | .[] |
        select(.value.platforms[strenv(PLATFORM)] != null) |
        .key as $id | .value as $feature |
        [($feature.link_dependencies // [])[],
         ($feature.platforms[strenv(PLATFORM)].link_dependencies // [])[]] |
        .[] | [$id, .] | join(strenv(CATALOG_SEPARATOR))
    ')
    while IFS=$'\037' read -r id target extra; do
        [ -n "$id" ] || continue
        [ -n "$target" ] && [ -z "$extra" ] || fail "Invalid dotfile dependency for $id"
        dependency_id=$(dotfile_id "$target")
        contains "$dependency_id" "${dotfile_ids[@]}" || fail "Missing dotfile dependency for $id: $target"
        # shellcheck disable=SC2016
        catalog_data=$(FEATURE_ID="$id" DEPENDENCY_ID="$dependency_id" PLATFORM="$platform" catalog_read '
            .features[strenv(FEATURE_ID)] as $feature |
            .features[strenv(FEATURE_ID)].platforms[strenv(PLATFORM)].requires =
                (($feature.platforms[strenv(PLATFORM)].requires // $feature.requires // []) + [strenv(DEPENDENCY_ID)])
        ')
    done <<< "$dependency_rows"

    group_ids=()

    # A control-character separator keeps quotes in names literal. IDs are
    # validated to exclude controls, so no CSV-style quoting is necessary.
    rows=$(CATALOG_SEPARATOR=$'\037' catalog_read '
        .groups | to_entries | .[] | [.key, .value] | join(strenv(CATALOG_SEPARATOR))
    ')

    while IFS=$'\037' read -r id label extra; do
        valid_id "$id" || fail "Invalid group ID: $id"
        [ -n "$label" ] && [ -z "$extra" ] || fail "Invalid group: $id"
        group_ids+=("$id")
    done <<< "$rows"

    feature_ids=()
    feature_labels=()
    feature_recommended=()
    feature_status=()
    feature_requires=()

    # A dash represents an absent dependency list in the separated rows.
    rows=$(PLATFORM="$platform" CATALOG_SEPARATOR=$'\037' catalog_read '
        .features | to_entries | .[] |
        select(.value.platforms[strenv(PLATFORM)] != null) |
        [.key, .value.label, .value.group, (.value.recommended // false),
         .value.platforms[strenv(PLATFORM)].status,
         ((.value.platforms[strenv(PLATFORM)].requires // .value.requires // []) | join(",") | select(length > 0)) // "-"] |
        join(strenv(CATALOG_SEPARATOR))
    ')

    while IFS=$'\037' read -r id label group recommended status dependencies extra; do
        valid_id "$id" || fail "Invalid feature ID: $id"
        contains "$id" "${feature_ids[@]}" && fail "Duplicate feature: $id"
        contains "$group" "${group_ids[@]}" || fail "Unknown group for $id: $group"
        [ -n "$label" ] && [ -z "$extra" ] || fail "Invalid label for $id"

        case "$status" in
            ready|review|planned) ;;
            *) fail "Invalid status for $id: $status" ;;
        esac

        feature_ids+=("$id")
        feature_labels+=("$label")
        feature_recommended+=("$recommended")
        feature_status+=("$status")
        feature_requires+=("$dependencies")
    done <<< "$rows"

}

#  - - -  Resolve dependencies before building executable actions  - - -

include_feature() {

    local id=$1 index dependency
    local dependencies=()

    contains "$id" "${plan_features[@]}" && return 0
    contains "$id" "${visiting[@]}" && fail "Dependency cycle at $id"

    index=$(feature_index "$id") || fail "Unknown or unsupported feature: $id"
    [ "${feature_status[$index]}" = ready ] || fail "Feature is not ready: $id"

    visiting+=("$id")

    if [ "${feature_requires[$index]}" != - ]; then
        IFS=, read -r -a dependencies <<< "${feature_requires[$index]}"

        for dependency in "${dependencies[@]}"; do
            include_feature "$dependency"
        done
    fi

    unset 'visiting[${#visiting[@]}-1]'
    plan_features+=("$id")

}

build_plan() {

    local id rows shape kind value_type value extra key individual
    local seen=()

    plan_features=()
    visiting=()
    plan_owners=()
    plan_kinds=()
    plan_values=()
    needs_brew=false

    for id in "${selected[@]}"; do
        include_feature "$id"
    done

    for id in "${plan_features[@]}"; do

        # A discovered dotfile is a selectable item in its own right. It has
        # no child choices, unlike an older bundled link feature.
        individual=$(FEATURE_ID="$id" catalog_read '.features[strenv(FEATURE_ID)].individual // false')

        # Each step names exactly one operation; values remain data, never shell.
        shape=$(FEATURE_ID="$id" PLATFORM="$platform" catalog_read '
            .features[strenv(FEATURE_ID)].platforms[strenv(PLATFORM)].steps |
            select(tag == "!!seq" and length > 0) | .[] | length
        ')

        [ -n "$shape" ] || fail "No actions for $id"

        while IFS= read -r value; do
            [ "$value" = 1 ] || fail "Each step must name one operation: $id"
        done <<< "$shape"

        # $kind belongs to the yq expression, not to this shell.
        # shellcheck disable=SC2016
        rows=$(FEATURE_ID="$id" PLATFORM="$platform" CATALOG_SEPARATOR=$'\037' catalog_read '
            .features[strenv(FEATURE_ID)].platforms[strenv(PLATFORM)].steps[] |
            to_entries | .[] | .key as $kind |
            .value | [.] | flatten | .[] | [$kind, tag, .] | join(strenv(CATALOG_SEPARATOR))
        ')

        [ -n "$rows" ] || fail "Empty actions for $id"

        while IFS=$'\037' read -r kind value_type value extra; do
            [ "$value_type" = '!!str' ] && [ -n "$value" ] && [ -z "$extra" ] \
                || fail "Invalid action value for $id"

            case "$kind" in
                brew|cask|apt|tap)
                    case "$platform/$kind" in
                        macos/brew|macos/cask|macos/tap) needs_brew=true ;;
                        debian/apt) ;;
                        *) fail "Wrong package manager for $platform: $kind" ;;
                    esac

                    case "$value" in
                        -*|*[!a-zA-Z0-9@+._/-]*) fail "Invalid package name: $value" ;;
                    esac
                    ;;
                links)
                    # Interactive selection may narrow a feature's link bundle.
                    # Unattended --only retains the complete bundle.
                    if [ -n "${link_choices:-}" ] && [ "$individual" != true ]; then
                        if [ "$(printf '%s\n' "$link_choices" | FEATURE_ID="$id" TARGET="$value" \
                            /bin/bash "$root/os/yq.sh" -r '.[strenv(FEATURE_ID)] | map(select((. | @base64) == (strenv(TARGET) | @base64))) | length > 0')" != true ]; then
                            continue
                        fi
                    fi
                    ;;
                script)
                    # A script is a file in this checkout, never shell text.
                    case "$value" in
                        os/*.sh) ;;
                        *) fail "Expected an os/ shell script: $value" ;;
                    esac
                    case "/$value/" in
                        */../*|*/./*) fail "Script path cannot traverse directories: $value" ;;
                    esac
                    [ -f "$root/$value" ] || fail "Missing script: $value"
                    ;;
                *) fail "Unsupported operation for $id: $kind" ;;
            esac

            # Shared packages or links are executed once, in dependency order.
            key="$kind/$value"

            # Scripts may behave differently for each selected option. Only
            # packages and links are shared across different owners.
            if [ "$kind" = script ]; then
                key="$key/$id"
            fi

            if ! contains "$key" "${seen[@]}"; then
                seen+=("$key")
                plan_owners+=("$id")
                plan_kinds+=("$kind")
                plan_values+=("$value")
            fi
        done <<< "$rows"
    done

}
