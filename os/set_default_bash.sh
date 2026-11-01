#!/bin/bash

# Set GNU Bash as the account's login shell.
# configuration_args contains options not consumed by setup.
# configuration_result reports an already configured shell.
# shellcheck source=os/lib/setup.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/setup.sh" || exit 1
setup "$@"
[ "${#configuration_args[@]}" -eq 0 ] || exit 2

#  - - -  Find the installed Bash and the account's current shell  - - -

if [ "$(uname -s)" = Darwin ]; then
    brew_command=$(command -v brew || true)
    if [ -z "$brew_command" ]; then
        for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
            if [ -x "$candidate" ]; then
                brew_command=$candidate
                break
            fi
        done
    fi
    if [ -z "$brew_command" ]; then
        printf 'Homebrew is required to locate Bash.\n' >&2
        exit 1
    fi
    prefix=$("$brew_command" --prefix)
    target="$prefix/bin/bash"
    current=$(dscl . -read "/Users/$(id -un)" UserShell | sed 's/^UserShell: //')
else
    target=/bin/bash
    current=$(getent passwd "$(id -un)" | cut -d: -f7)
fi

"$target" --version >/dev/null
if [ "$current" = "$target" ] && grep -Fxq "$target" /etc/shells; then
    configuration_result unchanged
    printf 'Default shell already set to %s.\n' "$target"
    exit 0
fi

#  - - -  Register the executable and change the account shell  - - -

sudo -v
if ! grep -Fxq "$target" /etc/shells; then
    printf '\n%s\n' "$target" | sudo tee -a /etc/shells >/dev/null
fi

if [ "$current" != "$target" ]; then
    sudo chsh -s "$target" "$(id -un)"
fi

if [ "$(uname -s)" = Darwin ]; then
    current=$(dscl . -read "/Users/$(id -un)" UserShell | sed 's/^UserShell: //')
else
    current=$(getent passwd "$(id -un)" | cut -d: -f7)
fi
[ "$current" = "$target" ] && grep -Fxq "$target" /etc/shells
printf 'Default shell: %s. Open a new login session to use it.\n' "$target"
