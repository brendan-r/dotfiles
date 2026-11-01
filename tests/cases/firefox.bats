#!/bin/bash

# Test the Firefox installer with disposable files and synthetic APT output.
# No host or guest package configuration is changed by these tests.
# shellcheck disable=SC2154
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {

    guest_setup

    export FAKE_APT_ROOT="$case_root/apt-root"
    export FAKE_APT_VERSION='123.4~example1'
    export FAKE_APT_ARCH=amd64
    export FAKE_FINGERPRINT=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
    mkdir -p "$FAKE_APT_ROOT" "$case_root/commands"

    # These stubs provide data independently of the real machine's APT state.
    cat > "$case_root/commands/dpkg" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$FAKE_APT_ARCH"
SCRIPT
    cat > "$case_root/commands/dpkg-query" <<'SCRIPT'
#!/bin/bash
[ -f "$FAKE_APT_ROOT/installed" ] || exit 1
printf 'install ok installed %s' "$(cat "$FAKE_APT_ROOT/installed")"
SCRIPT
    cat > "$case_root/commands/curl" <<'SCRIPT'
#!/bin/bash
if [ "${FAKE_CURL_FAIL:-false}" = true ]; then exit 22; fi
while [ "$#" -gt 0 ]; do
    case "$1" in --output) destination=$2; shift ;; esac
    shift
done
printf 'fixture key\n' > "$destination"
SCRIPT
    cat > "$case_root/commands/gpg" <<'SCRIPT'
#!/bin/bash
printf 'pub:::::::::\nfpr:::::::::%s:\n' "$FAKE_FINGERPRINT"
if [ "${FAKE_EXTRA_KEY:-false}" = true ]; then
    printf 'pub:::::::::\nfpr:::::::::SECONDKEY:\n'
fi
SCRIPT
    cat > "$case_root/commands/apt-cache" <<'SCRIPT'
#!/bin/bash
printf 'firefox:\n  Installed: (none)\n  Candidate: %s\n  Version table:\n' "$FAKE_APT_VERSION"
if [ "${FAKE_WRONG_ORIGIN:-false}" = true ]; then
    printf '     %s 1000\n        1000 https://example.invalid/apt stable/main amd64 Packages\n' "$FAKE_APT_VERSION"
    printf '     old-version 500\n        500 https://packages.mozilla.org/apt mozilla/main amd64 Packages\n'
else
    printf '     %s 1000\n        1000 https://packages.mozilla.org/apt mozilla/main amd64 Packages\n' "$FAKE_APT_VERSION"
fi
SCRIPT
    cat > "$case_root/commands/apt-get" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_APT_ROOT/apt-calls"
case "$*" in
    *' download firefox='*)
        case " $* " in *' Dir::Etc::sourceparts=- '*) ;; *) exit 1 ;; esac
        case " $* " in *' Dir::Etc::sourcelist=/etc/apt/sources.list.d/mozilla.sources '*) ;; *) exit 1 ;; esac
        [ "${FAKE_DOWNLOAD_FAIL:-false}" != true ] || exit 1
        printf 'verified archive\n' > "firefox_${FAKE_APT_VERSION}_${FAKE_APT_ARCH}.deb"
        ;;
    install*firefox_*.deb*)
        case " $* " in *' --no-remove '*) ;; *) exit 1 ;; esac
        printf '%s' "$FAKE_APT_VERSION" > "$FAKE_APT_ROOT/installed"
        ;;
esac
SCRIPT
    cat > "$case_root/commands/sudo" <<'SCRIPT'
#!/bin/bash
set -e
[ "$1" != -v ] || exit 0
command=$1
shift
case "$command" in
    env) exec env "$@" ;;
    apt-get) exec apt-get "$@" ;;
    test|cmp|install) ;;
    *) printf 'Unexpected privileged command: %s\n' "$command" >&2; exit 1 ;;
esac
args=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        /etc/apt/*) args+=("$FAKE_APT_ROOT$1") ;;
        *) args+=("$1") ;;
    esac
    shift
done
exec "$command" "${args[@]}"
SCRIPT
    chmod +x "$case_root/commands/"*
    export PATH="$case_root/commands:$PATH"

}

function firefox__repository__installs_from_mozilla_and_reruns_without_reinstall { # @test

    printf 'existing ESR\n' > "$FAKE_APT_ROOT/esr"
    /bin/bash "$repo/os/install_firefox.sh"

    [ "$(cat "$FAKE_APT_ROOT/installed")" = "$FAKE_APT_VERSION" ]
    [ "$(cat "$FAKE_APT_ROOT/esr")" = 'existing ESR' ]
    grep -Fxq 'Package: firefox' "$FAKE_APT_ROOT/etc/apt/preferences.d/dotfiles-mozilla-firefox"
    grep -Fxq 'URIs: https://packages.mozilla.org/apt' "$FAKE_APT_ROOT/etc/apt/sources.list.d/mozilla.sources"
    grep -Fq -- '--no-remove ' "$FAKE_APT_ROOT/apt-calls"
    grep -Fq -- 'Dir::Etc::sourceparts=- download firefox=' "$FAKE_APT_ROOT/apt-calls"

    export DOTFILES_RESULT="$case_root/result"
    /bin/bash "$repo/os/install_firefox.sh"
    [ "$(cat "$DOTFILES_RESULT")" = unchanged ]
    [ "$(grep -c 'download firefox=' "$FAKE_APT_ROOT/apt-calls")" = 1 ]

    # ARM and Intel are selected from dpkg; neither needs user input.
    export FAKE_APT_ARCH=arm64
    /bin/bash "$repo/os/install_firefox.sh"
    [ "$(cat "$DOTFILES_RESULT")" = unchanged ]

}

function firefox__repository__rejects_bad_keys_and_network_errors { # @test

    export FAKE_APT_ARCH=imaginary
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'imaginary'* ]]
    [ ! -e "$FAKE_APT_ROOT/etc/apt" ]

    export FAKE_APT_ARCH=amd64
    export FAKE_FINGERPRINT=WRONG
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'fingerprint did not match'* ]]
    [ ! -e "$FAKE_APT_ROOT/etc/apt" ]

    export FAKE_FINGERPRINT=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3 FAKE_EXTRA_KEY=true
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [ ! -e "$FAKE_APT_ROOT/etc/apt" ]

    unset FAKE_EXTRA_KEY
    export FAKE_CURL_FAIL=true
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Could not download'* ]]
    [ ! -e "$FAKE_APT_ROOT/etc/apt" ]

}

function firefox__repository__does_not_claim_source_of_existing_package { # @test

    # A matching dpkg version does not identify where that package came from.
    printf '%s' "$FAKE_APT_VERSION" > "$FAKE_APT_ROOT/installed"
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -eq 0 ]
    [[ "$output" = *'original source was not verified'* ]]
    ! grep -Fq 'download firefox=' "$FAKE_APT_ROOT/apt-calls"

}

function firefox__repository__preserves_conflicts_and_rejects_wrong_origin { # @test

    mkdir -p "$FAKE_APT_ROOT/etc/apt/sources.list.d"
    printf 'personal source\n' > "$FAKE_APT_ROOT/etc/apt/sources.list.d/mozilla.sources"

    run /bin/bash "$repo/os/install_firefox.sh" --backup
    [ "$status" -ne 0 ]
    [[ "$output" = *'Existing APT configuration differs'* ]]
    [ "$(cat "$FAKE_APT_ROOT/etc/apt/sources.list.d/mozilla.sources")" = 'personal source' ]
    [ ! -e "$FAKE_APT_ROOT/etc/apt/keyrings/packages.mozilla.org.asc" ]

    rm "$FAKE_APT_ROOT/etc/apt/sources.list.d/mozilla.sources"
    export FAKE_WRONG_ORIGIN=true
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'did not select Firefox'* ]]
    [ ! -e "$FAKE_APT_ROOT/installed" ]

    unset FAKE_WRONG_ORIGIN
    export FAKE_DOWNLOAD_FAIL=true
    run /bin/bash "$repo/os/install_firefox.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Could not download Firefox'* ]]
    [ ! -e "$FAKE_APT_ROOT/installed" ]

}
