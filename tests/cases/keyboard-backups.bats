#!/bin/bash

# Exercise standalone keyboard backups without changing host or guest services.
# shellcheck disable=SC2154
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

function keyboard_backups__karabiner__links_directory_and_preserves_existing_files { # @test

    mkdir -p "$HOME/.config/karabiner"
    cat > "$HOME/.config/karabiner/karabiner.json" <<'JSON'
{"profiles":[{"name":"Personal","selected":true}],"global":{"show_in_menu_bar":true}}
JSON
    mkdir -p "$HOME/.config/karabiner/assets"
    printf 'personal asset\n' > "$HOME/.config/karabiner/assets/rule.json"
    cp "$HOME/.config/karabiner/karabiner.json" "$case_root/original.json"

    # Conflicts are preserved unless backup is explicitly requested.
    run /bin/bash "$repo/os/create_symbolic_links.sh" "$repo" macos --selected .config/karabiner
    [ "$status" -ne 0 ]
    cmp "$case_root/original.json" "$HOME/.config/karabiner/karabiner.json"
    [ ! -e "$HOME/TODO.org" ]

    # Linking the whole directory preserves file watching and backs up assets.
    /bin/bash "$repo/os/create_symbolic_links.sh" "$repo" macos --backup --selected .config/karabiner
    saved=$(find "$HOME/.local/state/dotfiles/backups" -type d -name karabiner)
    [ -n "$saved" ]
    cmp "$case_root/original.json" "$saved/karabiner.json"
    [ "$(cat "$saved/assets/rule.json")" = 'personal asset' ]
    grep -Fxq -- "- $HOME/.config/karabiner -> $saved" "$HOME/TODO.org"
    [ -L "$HOME/.config/karabiner" ]
    [ "$(readlink "$HOME/.config/karabiner")" = "$repo/home/macos/.config/karabiner" ]
    [ ! -L "$HOME/.config/karabiner/karabiner.json" ]
    cmp "$DOTFILES_CANDIDATE/home/macos/.config/karabiner/karabiner.json" \
        "$HOME/.config/karabiner/karabiner.json"

    # Simulate an application replacing its file; the directory link survives.
    printf 'replacement\n' > "$HOME/.config/karabiner/new.json"
    mv "$HOME/.config/karabiner/new.json" "$HOME/.config/karabiner/karabiner.json"
    [ -L "$HOME/.config/karabiner" ]
    [ "$(cat "$repo/home/macos/.config/karabiner/karabiner.json")" = replacement ]

}

function keyboard_backups__karabiner__is_a_required_macos_dotfile { # @test

    root=$repo
    platform=macos
    fail() { printf '%s\n' "$*" >&2; return 1; }

    # shellcheck source=os/menu_catalog.sh
    source "$repo/os/menu_catalog.sh"
    load_catalog
    index=$(feature_index 'Custom keyboard layout')
    target=$(dotfile_id .config/karabiner)

    # The dependency is matched as a complete ID, alongside other prerequisites.
    case ",${feature_requires[$index]}," in
        *,"$target",*) ;;
        *) return 1 ;;
    esac

}

function keyboard_backups__keyd__preserves_and_records_existing_layout { # @test

    [ "$(uname -s)" = Linux ] || skip 'Debian keyd configuration'

    # Substitute only the exact commands used by the installer. /etc/keyd paths
    # are translated to a temporary directory; no service or system file changes.
    mkdir -p "$case_root/shims" "$case_root/etc/keyd"
    export FAKE_KEYD_ROOT="$case_root/etc/keyd"
    export FAKE_KEYD_BINARY="$case_root/shims/keyd.rvaiya"
    printf 'personal keyd settings\n' > "$FAKE_KEYD_ROOT/default.conf"

    cat > "$FAKE_KEYD_BINARY" <<'SHIM'
#!/bin/bash
exit 0
SHIM
    cat > "$case_root/shims/sudo" <<'SHIM'
#!/bin/bash
set -e
[ "$1" != -v ] || exit 0
command=$1
shift
case "$command" in
    systemctl|"$FAKE_KEYD_BINARY") exit 0 ;;
    test|mkdir|cmp|mktemp|cp|rm|install) ;;
    *) printf 'Unexpected sudo command: %s\n' "$command" >&2; exit 1 ;;
esac
args=()
while [ "$#" -gt 0 ]; do
    case "$command:$1" in
        install:-o|install:-g) shift 2; continue ;;
    esac
    case "$1" in
        /etc/keyd|/etc/keyd/*) args+=("$FAKE_KEYD_ROOT${1#/etc/keyd}") ;;
        *) args+=("$1") ;;
    esac
    shift
done
if [ "$command" = mktemp ]; then
    result=$(mktemp "${args[@]}")
    printf '/etc/keyd%s\n' "${result#"$FAKE_KEYD_ROOT"}"
else
    "$command" "${args[@]}"
fi
SHIM
    chmod +x "$FAKE_KEYD_BINARY" "$case_root/shims/sudo"
    export PATH="$case_root/shims:/usr/bin:/bin"

    run /bin/bash "$repo/os/configure_keyboard_debian.sh"
    [ "$status" -ne 0 ]
    [ "$(cat "$FAKE_KEYD_ROOT/default.conf")" = 'personal keyd settings' ]
    [ ! -e "$HOME/TODO.org" ]

    /bin/bash "$repo/os/configure_keyboard_debian.sh" --backup
    saved=$(find "$FAKE_KEYD_ROOT" -path '*/backup.*/default.conf')
    [ "$(cat "$saved")" = 'personal keyd settings' ]
    expected="/etc/keyd${saved#"$FAKE_KEYD_ROOT"}"
    grep -Fxq -- "- /etc/keyd/default.conf -> $expected" "$HOME/TODO.org"
    cmp "$repo/home/debian/.config/keyd/default.conf" "$FAKE_KEYD_ROOT/default.conf"

}
