#!/bin/bash

# Shared transport only. URLs, release selection and installation stay in callers.
# Callers own their temporary directory and remove it with an EXIT trap.

#  - - -  Download without mistaking an HTTP error page for a package  - - -

download_file() {

    local url=$1 destination=$2 code
    local attempt headers partial

    headers="${destination}.headers"
    partial="${destination}.part"

    for attempt in 1 2 3; do
        printf 'Downloading %s\n' "$url" >&2

        # Ignore personal curl settings; require HTTPS even after a redirect.
        # Slow/stalled connections time out, but large healthy downloads may run.
        if ! code=$(curl -q --location --proto '=https' --proto-redir '=https' \
            --user-agent 'dotfiles-installer' --connect-timeout 20 \
            --speed-limit 1024 --speed-time 60 --max-time 1800 \
            --progress-bar --show-error --dump-header "$headers" \
            --output "$partial" --write-out '%{http_code}' "$url"); then
            printf 'Download interrupted or connection failed: %s\n' "$url" >&2
            rm -f "$partial" "$headers"
            return 1
        fi

        case "$code" in
            200)
                mv -f "$partial" "$destination" || return 1
                rm -f "$headers"
                return 0
                ;;
            403|429)
                # A 403 is not necessarily a rate limit. Show the server's
                # guidance without guessing, retrying indefinitely or hiding it.
                printf 'Server refused the download (HTTP %s): %s\n' "$code" "$url" >&2
                tr -d '\r' < "$headers" \
                    | grep -iE '^(retry-after|x-ratelimit-(remaining|reset)):' >&2 || true
                printf 'Retry later; GitHub reset timestamps are UTC epoch seconds.\n' >&2
                ;;
            500|502|503|504)
                if [ "$attempt" -lt 3 ]; then
                    printf 'Server error HTTP %s; retrying shortly (%s/3).\n' "$code" "$attempt" >&2
                    sleep "$((attempt * 2))"
                    continue
                fi
                printf 'Server still failing (HTTP %s): %s\n' "$code" "$url" >&2
                ;;
            *) printf 'Download failed (HTTP %s): %s\n' "$code" "$url" >&2 ;;
        esac

        rm -f "$partial" "$headers"
        return 1
    done

}

#  - - -  Check integrity before extracting or installing  - - -

verify_sha256() {

    local file=$1 expected=$2 actual

    if [ "${#expected}" -ne 64 ] || [[ "$expected" = *[!0-9a-f]* ]]; then
        printf 'Missing or invalid SHA-256 checksum for %s\n' "$file" >&2
        return 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file") || return 1
    else
        actual=$(shasum -a 256 "$file") || return 1
    fi
    actual=${actual%% *}

    if [ "$actual" != "$expected" ]; then
        printf 'Checksum mismatch for %s; refusing to install.\n' "$file" >&2
        return 1
    fi

}
