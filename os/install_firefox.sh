#!/bin/bash

# Install Mozilla's current Firefox release on Debian, without removing ESR.
# https://support.mozilla.org/en-US/kb/install-firefox-linux

# configuration_args contains options not consumed by setup.
# configuration_result reports an unchanged installation to the menu.
# setup accepts --backup, though this script never overwrites APT settings.
# shellcheck disable=SC2154
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"

if [ "${#configuration_args[@]}" -ne 0 ]; then
    printf 'Unknown Firefox installer arguments: %s\n' "${configuration_args[*]}" >&2
    exit 2
fi

#  - - -  Check that Mozilla publishes packages for this machine  - - -

architecture=$(dpkg --print-architecture)

case "$architecture" in
    amd64|arm64) ;;
    *)
        printf 'Mozilla Firefox has no supported Debian package for %s.\n' "$architecture" >&2
        exit 1
        ;;
esac

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

#  - - -  Download and verify Mozilla's repository signing key  - - -

sudo -v

if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
    sudo apt-get update --error-on=any
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove ca-certificates curl gnupg
fi

# Fail on HTTP errors; a server error page must never become an APT key.
if ! curl -q --fail --location --show-error --retry 2 --connect-timeout 20 \
    --proto '=https' --proto-redir '=https' \
    --output "$work/mozilla.asc" \
    https://packages.mozilla.org/apt/repo-signing-key.gpg; then
    printf 'Could not download the Mozilla APT signing key. Try again later.\n' >&2
    exit 1
fi

# Verify the primary key from Mozilla's instructions. Reject extra primary
# keys, even when one of them has the expected fingerprint.
mkdir -m 700 "$work/gnupg"

if ! gpg --no-options --homedir "$work/gnupg" --batch --with-colons \
    --import-options show-only --dry-run --import "$work/mozilla.asc" > "$work/key-info"; then
    printf 'Could not inspect the Mozilla APT signing key.\n' >&2
    exit 1
fi

if ! awk -F: '
    $1 == "pub" { keys++; waiting = 1; next }
    $1 == "fpr" && waiting {
        if ($10 != "35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3") invalid = 1
        waiting = 0
    }
    END { if (keys != 1 || waiting || invalid) exit 1 }
' "$work/key-info"; then
    printf 'The Mozilla APT signing key fingerprint did not match; no repository was added.\n' >&2
    exit 1
fi

#  - - -  Prepare the Debian Trixie repository and scoped preference  - - -

key=/etc/apt/keyrings/packages.mozilla.org.asc
source_file=/etc/apt/sources.list.d/mozilla.sources
preference=/etc/apt/preferences.d/dotfiles-mozilla-firefox

cat > "$work/mozilla.sources" <<'SOURCE'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
SOURCE

# Prefer Mozilla only for Firefox, not for unrelated packages such as ESR.
cat > "$work/preference" <<'PREFERENCE'
Package: firefox
Pin: origin packages.mozilla.org
Pin-Priority: 1000
PREFERENCE

# Existing directories and files may be shared with another setup. Never follow
# a symlink or change an existing directory's permissions.
for directory in /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d; do
    if sudo test -L "$directory" \
        || { sudo test -e "$directory" && ! sudo test -d "$directory"; }; then
        printf 'Unsafe APT configuration directory: %s. Resolve it before continuing.\n' "$directory" >&2
        exit 1
    fi
done

# Keep existing files untouched unless they exactly match this configuration.
for pair in "mozilla.asc:$key" "mozilla.sources:$source_file" "preference:$preference"; do
    staged=${pair%%:*}
    destination=${pair#*:}

    if sudo test -L "$destination"; then
        printf 'Existing APT configuration is a symlink: %s. Resolve it before continuing.\n' "$destination" >&2
        exit 1
    fi

    if sudo test -e "$destination" && ! sudo cmp -s "$work/$staged" "$destination"; then
        printf 'Existing APT configuration differs: %s. It was retained; review it before continuing.\n' "$destination" >&2
        exit 1
    fi
done

changed=false

for directory in /etc/apt/keyrings /etc/apt/sources.list.d /etc/apt/preferences.d; do
    if ! sudo test -d "$directory"; then
        sudo install -d -m 755 "$directory"
        changed=true
    fi
done

for pair in "mozilla.asc:$key" "mozilla.sources:$source_file" "preference:$preference"; do
    staged=${pair%%:*}
    destination=${pair#*:}

    if ! sudo test -e "$destination"; then
        sudo install -m 644 "$work/$staged" "$destination"
        changed=true
    fi
done

#  - - -  Install Firefox only when APT selects Mozilla's signed repository  - - -

sudo apt-get update --error-on=any

LC_ALL=C apt-cache policy firefox > "$work/firefox-policy"
candidate=$(awk '$1 == "Candidate:" { print $2; exit }' "$work/firefox-policy")

if [ -z "$candidate" ] || [ "$candidate" = '(none)' ]; then
    printf 'APT has no Firefox candidate after adding the Mozilla repository.\n' >&2
    exit 1
fi

# Match the candidate's own version stanza, not merely any Mozilla entry.
if ! awk -v candidate="$candidate" '
    $1 == "***" { version = $2; next }
    NF == 2 && $2 ~ /^[0-9]+$/ { version = $1; next }
    version == candidate && index($0, "https://packages.mozilla.org/apt ") { found = 1 }
    END { if (!found) exit 1 }
' "$work/firefox-policy"; then
    printf 'APT did not select Firefox %s from the Mozilla repository.\n' "$candidate" >&2
    exit 1
fi

installed=$(dpkg-query -W -f='${Status} ${Version}' firefox 2>/dev/null || true)

if [ "$installed" != "install ok installed $candidate" ]; then
    # Download only from the verified Mozilla source. APT preferences select a
    # version, but do not choose between repositories with the same version.
    if ! (
        cd "$work"
        apt-get -o "Dir::Etc::sourcelist=$source_file" \
            -o Dir::Etc::sourceparts=- download "firefox=$candidate"
    ); then
        printf 'Could not download Firefox %s from the Mozilla repository.\n' "$candidate" >&2
        exit 1
    fi

    # APT verifies the download against the signed repository metadata. Require
    # one complete archive, then allow normal sources to supply dependencies.
    set -- "$work"/firefox_*.deb
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        printf 'Expected one Firefox package from the Mozilla repository.\n' >&2
        exit 1
    fi

    # --no-remove ensures that an existing Firefox ESR is never removed.
    sudo env DEBIAN_FRONTEND=noninteractive \
        apt-get install -y --no-remove "$1"
    changed=true
else
    # dpkg records the version, not the repository from which it was fetched.
    printf 'Firefox %s is already installed; its original source was not verified.\n' "$candidate"
fi

installed=$(dpkg-query -W -f='${Status} ${Version}' firefox 2>/dev/null || true)

if [ "$installed" != "install ok installed $candidate" ]; then
    printf 'Firefox installation could not be verified.\n' >&2
    exit 1
fi

if ! "$changed"; then
    configuration_result unchanged
fi

printf 'Firefox %s is installed and the Mozilla repository is configured; existing Firefox ESR was retained.\n' "$candidate"
