#!/bin/bash

# Use the same installer UI version on every machine, including a fresh installation.
set -eo pipefail

# Find the checkout containing this wrapper, including when it is a worktree.
root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

#  - - -  Select the bundled executable  - - -

case "$(uname -s)" in
    Darwin) platform=darwin ;;
    Linux)  platform=linux ;;
    *) echo 'No bundled installer UI for this operating system.' >&2; exit 1 ;;
esac

case "$(uname -m)" in
    arm64|aarch64) architecture=arm64 ;;
    x86_64|amd64)  architecture=amd64 ;;
    *) echo 'No bundled installer UI for this architecture.' >&2; exit 1 ;;
esac

binary="$root/os/vendor/installer-ui/installer-ui_${platform}_${architecture}"

if [ ! -x "$binary" ]; then
    printf 'Bundled installer UI is missing or not executable: %s\n' "$binary" >&2
    exit 1
fi

exec "$binary" "$@"
