#!/bin/bash
# Invoked by tests/run only after cloning and verifying a disposable VM.
set -eo pipefail
[ -r /etc/dotfiles-test-image ] || { echo 'Run through tests/run in a disposable VM.' >&2; exit 2; }
[ "$(id -un)" = dotfiles ] || { echo 'Expected the disposable dotfiles account.' >&2; exit 2; }
export DOTFILES_TEST_GUEST=1 DOTFILES_FIXTURE_URL=$1 DOTFILES_REVISION=$2

#  - - -  Use a terminal definition available inside the disposable guest  - - -

# Kitty's terminal name crosses the SSH connection, but its terminfo does not.
# Keep its native definition when available; otherwise use the basic xterm mode
# for this test session only. Never change the user's host terminal settings.
if [ "${TERM:-}" = xterm-kitty ] && ! infocmp xterm-kitty >/dev/null 2>&1; then
    if infocmp xterm-256color >/dev/null 2>&1; then
        export TERM=xterm-256color
        printf 'Kitty terminfo is unavailable in this VM; using xterm-256color for this session.\n'
    fi
fi

#  - - -  Prepare the candidate checkout  - - -

mkdir -p "$HOME/projects"
GIT_TERMINAL_PROMPT=0 git clone "$DOTFILES_FIXTURE_URL/repo.git" "$HOME/projects/dotfiles"
cd "$HOME/projects/dotfiles"
[ "$(git rev-parse HEAD)" = "$DOTFILES_REVISION" ] || { echo 'Candidate revision mismatch.' >&2; exit 2; }
if [ "${3:-0}" = 1 ]; then
    printf '\nProvisioning enabled: this disposable account can use sudo.\n'
else
    printf '\nNo administrative access. Use --online --provision to test package installation.\n'
fi

cat <<'WELCOME'

Disposable dotfiles VM — nothing has been installed in this account yet.
You are in ~/projects/dotfiles, a copy of your local candidate snapshot.

Try the installer and answer any prompts yourself:
  ./dotfiles install --backup

Then start a shell with the installed configuration:
  exec /bin/bash -il

To try the download/bootstrap path from a fresh checkout:
  mv ~/projects/dotfiles ~/projects/dotfiles-before-bootstrap
  cd ~
  curl -qfsS "$DOTFILES_FIXTURE_URL/dotfiles" -o /tmp/dotfiles-bootstrap
  bash /tmp/dotfiles-bootstrap bootstrap --repo "$DOTFILES_FIXTURE_URL/repo.git" --ref "$DOTFILES_REVISION" --backup

This is the disposable dotfiles account. Host files are not shared.
Changes stay in this VM. Each new interactive run starts from the baseline.
Use `exit 0` when finished, or SSH's Enter then ~. escape to disconnect on macOS.

WELCOME
exec /bin/bash -il
