#!/bin/bash
set -eo pipefail
: "${DOTFILES_TEST_GUEST:?Guest test marker required}"
test_home=$1
repo=$2
scratch=$(mktemp -d)
probe_path=''
trap '[ -z "$probe_path" ] || rm -f "$probe_path"; rm -rf "$scratch"' EXIT
# A unique command proves the new shell can actually use the repository's bin
# directory. Invoke it before re-sourcing anything, so setup cannot mask broken
# startup. The probe exists only in this disposable guest repository.
probe_path=$(mktemp "$repo/bin/dotfiles-startup-probe.XXXXXX")
printf '#!/bin/sh\nprintf "STARTUP_OK\\n"\n' > "$probe_path"
chmod +x "$probe_path"
probe_name=${probe_path##*/}
# Each child needs its own PTY: Bash 3.2 initializes job control through stderr,
# so redirecting an interactive shell directly to files produces a false warning.
term=$3
variant=$4
flags=()
case "$variant" in login) flags=(--login) ;; interactive) flags=(--noprofile -i) ;; login-interactive) flags=(--login -i) ;; esac
environment=("HOME=$test_home" 'PATH=/usr/bin:/bin:/usr/sbin:/sbin' 'LC_ALL=C' 'BASH_SILENCE_DEPRECATION_WARNING=1')
if [ "$term" != unset ]; then environment+=("TERM=$term"); fi
# Expand these variables in the child shell, not the test driver.
# shellcheck disable=SC2016
python3 "$(dirname "$0")/pty-run.py" env -i "${environment[@]}" /bin/bash "${flags[@]}" -c '
    "$1" || exit 10
    previous=$PATH
    . "$HOME/.bash_profile"
    [ "$PATH" = "$previous" ] || exit 11
    case ":$PATH:" in *::*) exit 12 ;; esac
' dotfiles-startup-check "$probe_name" >"$scratch/out" 2>"$scratch/err" || {
    printf 'Shell failure: %s TERM=%s\n' "$variant" "$term" >&2
    cat "$scratch/out" "$scratch/err" >&2
    exit 1
}
if [ "$(cat "$scratch/out")" != STARTUP_OK ] || [ -s "$scratch/err" ]; then
    printf 'Unexpected startup output: %s TERM=%s\n' "$variant" "$term" >&2
    cat "$scratch/out" "$scratch/err" >&2
    exit 1
fi
