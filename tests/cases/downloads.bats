#!/bin/bash

# Exercise behavior with synthetic HTTP responses, not live servers or copied
# application URLs/checksums. All candidate execution remains inside the VM.
# shellcheck disable=SC2154
# shellcheck source=tests/helpers/guest.bash
source "$BATS_TEST_DIRNAME/../helpers/guest.bash"

setup() {

    guest_setup
    # shellcheck source=os/lib/download.sh
    source "$repo/os/lib/download.sh"
    export response_code=200 response_body='sample download' transfer_exit=0

}

# The curl stand-in writes the same three outputs as curl: body, headers, status.
curl() {

    local body headers
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output) body=$2; shift ;;
            --dump-header) headers=$2; shift ;;
        esac
        shift
    done
    printf '%s' "$response_body" > "$body"
    printf 'HTTP/2 %s\r\nRetry-After: 120\r\n' "$response_code" > "$headers"
    printf '%s' "$response_code"
    return "$transfer_exit"

}

function downloads__success__publishes_complete_file_and_checks_digest { # @test

    download_file https://example.invalid/release "$case_root/result"
    [ "$(cat "$case_root/result")" = "$response_body" ]
    [ ! -e "$case_root/result.part" ]
    if command -v sha256sum >/dev/null 2>&1; then
        digest=$(sha256sum "$case_root/result")
    else
        digest=$(shasum -a 256 "$case_root/result")
    fi
    verify_sha256 "$case_root/result" "${digest%% *}"

    printf 'corruption' >> "$case_root/result"
    run verify_sha256 "$case_root/result" "${digest%% *}"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Checksum mismatch'* ]]

}

function downloads__failure__preserves_previous_file_and_explains_rate_limit { # @test

    printf 'previous' > "$case_root/result"
    for response_code in 403 429 404; do
        run download_file https://example.invalid/release "$case_root/result"
        [ "$status" -ne 0 ]
        [[ "$output" = *"HTTP $response_code"* ]]
        if [ "$response_code" != 404 ]; then
            [[ "$output" = *'Retry-After: 120'* ]]
        fi
        [ "$(cat "$case_root/result")" = previous ]
        [ ! -e "$case_root/result.part" ]
        [ ! -e "$case_root/result.headers" ]
    done

    response_code=200
    transfer_exit=18
    run download_file https://example.invalid/release "$case_root/result"
    [ "$status" -ne 0 ]
    [[ "$output" = *'interrupted'* ]]
    [ "$(cat "$case_root/result")" = previous ]

}

function downloads__server_failure__retries_are_bounded { # @test

    response_code=503
    # Called by download_file through the shell command lookup.
    # shellcheck disable=SC2329
    sleep() { printf 'retry delay\n' >> "$case_root/retries"; }
    run download_file https://example.invalid/release "$case_root/result"
    [ "$status" -ne 0 ]
    [ "$(wc -l < "$case_root/retries" | tr -d ' ')" = 2 ]
    [ ! -e "$case_root/result" ]
    [ ! -e "$case_root/result.part" ]

}

function installers__unsupported_cpu__fails_before_privilege_or_network { # @test

    mkdir "$case_root/commands"
    printf '#!/bin/sh\necho imaginary-cpu\n' > "$case_root/commands/dpkg"
    # Expand HOME when the stub runs, not when writing it.
    # shellcheck disable=SC2016
    printf '#!/bin/sh\necho unexpected >> "$HOME/side-effects"\nexit 99\n' > "$case_root/commands/sudo"
    cp "$case_root/commands/sudo" "$case_root/commands/curl"
    chmod +x "$case_root/commands/"*
    export PATH="$case_root/commands:$PATH"

    for script in "$repo"/os/install_{anki,spotify,signal_desktop,rstudio_desktop,proton_vpn}.sh; do
        run /bin/bash "$script"
        [ "$status" -ne 0 ]
        [[ "$output" = *'imaginary-cpu'* ]]
    done
    [ ! -e "$HOME/side-effects" ]

}

function default_apps__rerun__keeps_backup_and_existing_links { # @test

    printf '[Default Applications]\n' > "$repo/mimeapps.list"
    export XDG_CONFIG_HOME="$HOME/settings" XDG_DATA_HOME="$HOME/data"
    mkdir -p "$XDG_CONFIG_HOME"
    printf 'personal settings' > "$XDG_CONFIG_HOME/mimeapps.list"

    /bin/bash "$repo/os/set_default_apps.sh"
    /bin/bash "$repo/os/set_default_apps.sh"
    [ "$(readlink "$XDG_CONFIG_HOME/mimeapps.list")" = "$repo/mimeapps.list" ]
    [ "$(readlink "$XDG_DATA_HOME/applications/mimeapps.list")" = "$repo/mimeapps.list" ]
    backups=("$XDG_CONFIG_HOME"/mimeapps.backup.*/mimeapps.list)
    [ "${#backups[@]}" = 1 ]
    [ "$(cat "${backups[0]}")" = 'personal settings' ]

}

function installers__rstudio__current_release_is_checked_before_installation { # @test

    command -v jq >/dev/null || skip 'Needs jq to parse RStudio metadata'
    [ "$(uname -s)" = Linux ] || skip 'Debian package installer'
    mkdir -p "$case_root/commands"
    export FIXTURE_RELEASE="$case_root/releases.json"
    export FIXTURE_BUILD="$case_root/build.json"
    export FIXTURE_PACKAGE="$case_root/package.deb"

    printf 'sample package' > "$FIXTURE_PACKAGE"
    digest=$(sha256sum "$FIXTURE_PACKAGE")
    digest=${digest%% *}

    cat > "$case_root/commands/curl" <<'SCRIPT'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) destination=$2; shift ;;
        --dump-header) headers=$2; shift ;;
    esac
    url=$1
    shift
done
case "$url" in
    */api/v1/release/index.json) cp "$FIXTURE_RELEASE" "$destination" ;;
    */api/v1/build/*/index.json) cp "$FIXTURE_BUILD" "$destination" ;;
    */electron/jammy/amd64/*.deb) cp "$FIXTURE_PACKAGE" "$destination" ;;
    *) exit 1 ;;
esac
printf 'HTTP/2 200\r\n' > "$headers"
printf 200
SCRIPT
    cat > "$case_root/commands/sudo" <<'SCRIPT'
#!/bin/bash
# Record only an actual local-package install, not prerequisite installation.
for argument in "$@"; do
    case "$argument" in */rstudio.deb) printf 'installed\n' >> "$HOME/installed" ;; esac
done
SCRIPT
    printf '#!/bin/sh\necho amd64\n' > "$case_root/commands/dpkg"
    chmod +x "$case_root/commands/"*
    export PATH="$case_root/commands:$PATH"

    # The release and package versions are deliberately unrelated to real releases.
    printf '%s\n' '{"released":[{"published":[{"builds_url":"https://dailies.rstudio.com/api/v1/build/example.42/index.json"}]}]}' > "$FIXTURE_RELEASE"
    jq -n --arg digest "$digest" '{products: {electron: {platforms: {"jammy-amd64": {
        channel: "Release", link: "https://dl.dailies.rstudio.com/electron/jammy/amd64/rstudio-example.42-amd64.deb", sha256: $digest
    }}}}}' > "$FIXTURE_BUILD"

    /bin/bash "$repo/os/install_rstudio_desktop.sh"
    [ "$(cat "$HOME/installed")" = installed ]

    # A broken digest or untrusted metadata must fail before installing a package.
    printf 'corrupt' >> "$FIXTURE_PACKAGE"
    run /bin/bash "$repo/os/install_rstudio_desktop.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Checksum mismatch'* ]]
    [ "$(cat "$HOME/installed")" = installed ]

    printf '%s\n' '{"released":[{"published":[{"builds_url":"https://example.invalid/index.json"}]}]}' > "$FIXTURE_RELEASE"
    run /bin/bash "$repo/os/install_rstudio_desktop.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Unexpected RStudio build metadata URL'* ]]
    [ "$(cat "$HOME/installed")" = installed ]

}

function installers__anki__release_selection_and_verification_precede_installation { # @test

    # Run this additionally in the online Anki provisioning VM, where its actual
    # parser/extractor dependencies exist. Routine baselines need not install them.
    command -v jq >/dev/null || skip 'Needs the Anki provisioning dependencies'
    command -v zstd >/dev/null || skip 'Needs the Anki provisioning dependencies'
    [ "$(uname -s)" = Linux ] || skip 'Debian archive installer'
    mkdir -p "$case_root/commands" "$case_root/archive/sample"
    export FIXTURE_RELEASE="$case_root/release.json" FIXTURE_ARCHIVE="$case_root/archive.tar.zst"

    cat > "$case_root/archive/sample/install.sh" <<'SCRIPT'
#!/bin/sh
printf 'installed\n' >> "$HOME/installed"
SCRIPT
    chmod +x "$case_root/archive/sample/install.sh"
    tar --zstd -cf "$FIXTURE_ARCHIVE" -C "$case_root/archive" sample
    digest=$(sha256sum "$FIXTURE_ARCHIVE")
    digest=${digest%% *}

    cat > "$case_root/commands/curl" <<'SCRIPT'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) destination=$2; shift ;;
        --dump-header) headers=$2; shift ;;
    esac
    url=$1
    shift
done
case "$url" in
    https://api.github.com/*) cp "$FIXTURE_RELEASE" "$destination" ;;
    *) cp "$FIXTURE_ARCHIVE" "$destination" ;;
esac
printf 'HTTP/2 200\r\n' > "$headers"
printf 200
SCRIPT
    cat > "$case_root/commands/sudo" <<'SCRIPT'
#!/bin/bash
# Package installation is inert; run only the synthetic archive's installer.
case "$1" in ./install.sh) exec "$@" ;; *) exit 0 ;; esac
SCRIPT
    printf '#!/bin/sh\necho amd64\n' > "$case_root/commands/dpkg"
    printf '#!/bin/sh\nexit 1\n' > "$case_root/commands/dpkg-query"
    chmod +x "$case_root/commands/"*
    export PATH="$case_root/commands:$PATH"

    asset=$(jq -n --arg digest "sha256:$digest" \
        '{name: "anki-example-linux-x86_64.tar.zst", browser_download_url: "https://example.invalid/archive", digest: $digest}')

    # Bad JSON, no matching asset, ambiguous assets and absent digest must all
    # stop before extraction/installation, with no fallback to an arbitrary file.
    for document in 'not json' '{"assets":[]}' \
        "{\"assets\":[$asset,$asset]}" \
        "$(printf '%s' "$asset" | jq '{assets: [del(.digest)]}')"; do
        printf '%s' "$document" > "$FIXTURE_RELEASE"
        run /bin/bash "$repo/os/install_anki.sh"
        [ "$status" -ne 0 ]
        [ ! -e "$HOME/installed" ]
    done

    printf '{"assets":[%s]}' "$asset" > "$FIXTURE_RELEASE"
    /bin/bash "$repo/os/install_anki.sh"
    [ "$(cat "$HOME/installed")" = installed ]

    printf 'corrupt' >> "$FIXTURE_ARCHIVE"
    run /bin/bash "$repo/os/install_anki.sh"
    [ "$status" -ne 0 ]
    [[ "$output" = *'Checksum mismatch'* ]]
    [ "$(cat "$HOME/installed")" = installed ]

}
