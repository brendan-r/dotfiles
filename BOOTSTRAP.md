# Dotfiles

Personal configuration for macOS and Debian. The maintained installer handles
configuration links and Bash startup. Application installers and OS preference
scripts under `os/` are historical, separate utilities; bootstrap does not run them.

## Install

Prerequisites: a normal user account, Bash, working Git, and curl for the one-liner.
On macOS, install Apple's **Command Line Tools**, not full Xcode:
`xcode-select --install`. On Debian, install `git curl ca-certificates` with APT.
The installer reports missing Git and stops; it does not install prerequisites.

From an existing checkout:

```bash
./dotfiles install
```

To download a normal Git clone and install its configuration:

```bash
( script=$(mktemp) && trap 'rm -f "$script"' EXIT && curl -qfsSL https://raw.githubusercontent.com/brendan-r/dotfiles/master/dotfiles -o "$script" && /bin/bash "$script" bootstrap )
```

Run without `sudo`. The default destination is `~/projects/dotfiles`, with an HTTPS
origin and the `master` branch checked out. `--directory`, `--repo`, and `--ref`
are bootstrap options. A commit/tag ref can leave a detached HEAD.

**Publication note:** the GitHub one-liner uses published `master`. Changes on a
development branch are exercised with local VM fixtures until they are merged.
Do not assume the remote script already contains these changes.

## Conflicts and updates

The installer preflights all links and reports conflicts before linking anything.
Correct links are left alone. It never replaces configuration by default:

```bash
./dotfiles install --backup
```

`--backup` preserves conflicting files, directories, and symlinks under
`~/.local/state/dotfiles/backups/<unique-run>/`, with their original relative
paths. It prints the backup location. Backups are not automatically deleted.
If moving a backup fails, installation stops; any staged originals remain in the
printed `~/.dotfiles-backup.*` directory. Resolve that failure before retrying.
To restore, remove only the installed link at the conflicting path, then move the
saved original back. Review backup contents before deleting a backup directory.

Bootstrap reuses an existing checkout of the same repository without fetching,
resetting, cleaning, or modifying local edits. Update it yourself with Git, then
rerun `./dotfiles install`. Existing SSH origins for this GitHub repository are
also recognized; bootstrap does not set up push authentication.

Common links include Bash, Git, Vim configuration, and Kitty. macOS additionally
gets Yabai, skhd, and the macOS Bash fragment. Debian gets the Linux desktop
configuration and Rofi data. No plugins or packages are installed, no default
shell is changed, and macOS UI settings are not applied.

Machine-specific interactive Bash settings belong in `~/.bash.local`, which the
installer never creates or replaces. Optional applications need not be installed
for shell startup to succeed.

## Tests

See [the local testing guide](tests/README.md) for prerequisites, image preparation,
commands, security boundaries, and retained failure diagnostics.

All behavioral tests run inside disposable VMs. Temporary homes are used **inside
the guests only**. Run `./tests/run lint` for local Bash syntax checks and
ShellCheck; this needs an installed ShellCheck but no VM. Static checks do not
execute or source the candidate configuration.
