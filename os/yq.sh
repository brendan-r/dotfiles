#!/bin/bash

# Use the pinned parser bundled with the checkout, never a machine-local yq.
set -eo pipefail

# Find the checkout containing this wrapper, including when it is a worktree.
root=$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

#  - - -  Select the upstream binary for this host  - - -

case "$(uname -s)" in
    Darwin) platform=darwin ;;
    Linux)  platform=linux ;;
    *) echo 'No bundled YAML parser for this operating system.' >&2; exit 1 ;;
esac

case "$(uname -m)" in
    arm64|aarch64) architecture=arm64 ;;
    x86_64|amd64)  architecture=amd64 ;;
    *) echo 'No bundled YAML parser for this architecture.' >&2; exit 1 ;;
esac

binary="$root/os/vendor/yq/yq_${platform}_${architecture}"

if [ ! -x "$binary" ]; then
    printf 'Bundled YAML parser is missing or not executable: %s\n' "$binary" >&2
    exit 1
fi

# Replace this wrapper so parser errors propagate unchanged to the caller.
exec "$binary" --no-colors "$@"
