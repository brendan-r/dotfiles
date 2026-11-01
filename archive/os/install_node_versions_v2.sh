#!/bin/bash

# Install a user-owned Node version manager and the current LTS release.
# Existing NVM checkouts are retained; this never resets local changes.
set -eo pipefail

repository=${1:?Expected NVM repository from YAML}
release=${2:?Expected NVM release from YAML}
channel=${3:?Expected Node channel from YAML}

# Keep metadata as arguments; none of it is interpreted as shell code or flags.
case "$release/$channel" in
    -*|*/-*) printf 'NVM release and Node channel cannot start with a dash.\n' >&2; exit 1 ;;
esac

export NVM_DIR="$HOME/.nvm"

#  - - -  Obtain a pinned NVM release  - - -

if [ ! -e "$NVM_DIR" ] && [ ! -L "$NVM_DIR" ]; then
    git clone --depth 1 --branch "$release" -- "$repository" "$NVM_DIR"
fi

if [ ! -f "$NVM_DIR/nvm.sh" ]; then
    printf 'Existing ~/.nvm is not an NVM installation; it was retained.\n' >&2
    exit 1
fi

# This is the user-selected version manager, not an installer fetched into eval.
# shellcheck disable=SC1091
source "$NVM_DIR/nvm.sh"

#  - - -  Preserve an existing default, or install LTS for a fresh setup  - - -

if ! nvm use default; then
    nvm install "$channel"
    nvm alias default "$channel"
    nvm use default
fi

node --version
npm --version

#  - - -  Make the version manager available to the dotfiles Bash startup  - - -

if [ -L "$HOME/.bash.local" ] \
    || { [ -e "$HOME/.bash.local" ] && [ ! -f "$HOME/.bash.local" ]; }; then
    printf 'Node installed. Existing ~/.bash.local is indirect; configure NVM startup manually.\n'
    exit 0
fi

if ! grep -Fq '# dotfiles: Node version manager' "$HOME/.bash.local" 2>/dev/null; then
    cat >> "$HOME/.bash.local" <<'STARTUP'

# dotfiles: Node version manager
export NVM_DIR="$HOME/.nvm"
[ ! -s "$NVM_DIR/nvm.sh" ] || . "$NVM_DIR/nvm.sh"
STARTUP
fi
