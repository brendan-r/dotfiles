# Dotfiles

Personal configuration for macOS and Debian. The interactive installer lets you select
individual dotfiles and available package installations. Only implemented routes
appear in the menu.

## Install

Prerequisites: a normal user account, Bash, working Git, and curl for the one-liner.
On macOS, install Apple's **Command Line Tools**, not full Xcode:
`xcode-select --install`. On Debian, install `git curl ca-certificates` with APT.
The installer reports missing Git and stops; it does not install prerequisites.

On a new machine, download the bootstrap script, create a normal Git clone, and
open the menu:

```bash
( script=$(curl -qfsSL https://raw.githubusercontent.com/brendan-r/dotfiles/master/dotfiles) && /bin/bash -c "$script" -- bootstrap )
```

The script is held in memory and runs only if the download succeeds. An interrupted
download runs nothing. Terminal input stays available for the interactive installer,
and the variable is discarded when the command finishes.

Run without `sudo`. The default destination is `~/projects/dotfiles`, with an HTTPS
origin and the `master` branch checked out. `--directory`, `--repo`, and `--ref`
are bootstrap options. A commit/tag ref can leave a detached HEAD.

The GitHub one-liner uses the published `master` branch; it does not include
unpublished changes in another checkout.

From an existing checkout, open the same menu:

```bash
./dotfiles install
```

## Conflicts and updates

If an operation fails, earlier completed changes are retained.
Correct links are left alone. It never replaces configuration by default:

```bash
./dotfiles install --backup
```

For symbolic links, `--backup` preserves conflicting files, directories, and symlinks under
`~/.local/state/dotfiles/backups/<unique-run>/`, with their original relative
paths. It prints the backup location. Backups are not automatically deleted.
Each saved path and its original location are also recorded under `* Backups`
in `~/TODO.org`, including when using `--links-only` or a later step fails.
If moving a backup fails, installation stops; any staged originals remain in the
printed `~/.dotfiles-backup.*` directory. Resolve that failure before retrying.
To restore, remove only the installed link at the conflicting path, then move the
saved original back. Review backup contents before deleting a backup directory.

Bootstrap reuses an existing checkout of the same repository without fetching,
resetting, cleaning, or modifying local edits. Update it yourself with Git, then
rerun `./dotfiles install`. Existing SSH origins for this GitHub repository are
also recognized; bootstrap does not set up push authentication.

## Menu and unattended use

The first screen has the “brendan’s dotfiles” header and a grouped checkbox list. Use arrows or j/k to move, Space or
x to toggle, c to clear selections, Enter to start installation, and Escape to cancel.
Every applicable dotfile or configuration directory appears as an individual,
preselected choice. A details pane describes the focused option on wide terminals;
there is no separate review screen. Required dotfiles are automatically selected
with their dependent features. On macOS, the keyboard option installs skhd and
selects its configuration.

The UI is built from the independent Go module in `ui/`; compiled binaries are
vendored, so installing dotfiles does not require Go. Package and configuration
routes remain in the handwritten YAML and shell scripts. Review the Git
configuration before using it: it contains personal identity and signing defaults.

Packages use Brew on macOS and APT on Debian. Missing Homebrew is shown as an
explicit prerequisite and installed using a pinned, checksum-verified official
installer. Command Line Tools remain a prerequisite. Brew runs as the normal user;
APT, shell registration, and the account change request sudo when needed.
Homebrew analytics are disabled for every installer command and persistently switched off once installation starts when Homebrew is used. The prerequisite row and output state this explicitly.
The installer does not request a system-wide upgrade. Simple catalogue package
steps skip installed packages; standalone scripts may install or upgrade their
own packages and dependencies.

Installation is sequential. Selection, preparation and installation stay in one continuous UI. A persistent
dashboard displays the selected feature statuses on the left, with live output
and native prompts on the right.
Active items animate; successful operations have green ticks. Narrow terminals
hide the sidebar but retain the active feature and completion count. Keyboard
input goes to the running command; Ctrl+C stops the installation and its children.
The completion screen retains those statuses and previews ~/TODO.org with Org
highlighting and wrapped lines. Use arrows, Page Up/Down or the mouse wheel to
scroll; Tab switches panes (or switches views in a narrow terminal). Press Enter
or click the pink “Happy Hacking!” button to return to the shell. A failure stops
later features and gets an explicit failure summary instead of success wording.
The result summary prints per-feature status and a temporary directory containing
logs; completed changes are retained on failure or interruption. Open a new login
session after changing the default shell.

For explicit unattended operation:

```sh
./dotfiles install --only 'Pandoc,VLC,Use GNU Bash as the default shell' --yes
./dotfiles install --only '.bash.local' --yes --backup
./dotfiles install --links-only --backup
```

`--yes` approves only the names given with `--only`, their dependencies, and any
required Homebrew installation. It does not supply administrator credentials.
Names are case-sensitive; quote selections containing spaces in your shell.
Without a terminal, use one of these explicit modes. Bootstrap accepts the same
installation options.

`--links-only` links all common and current-platform entries without a menu or
packages. The sources are discovered directly from `home/common`, `home/macos`,
and `home/debian`: their paths mirror destinations under HOME. `.config`, `.local`,
and `.local/share` are containers; a configuration directory below them, such as
`.config/i3`, is linked as one unit. New entries appear automatically. Conflicting
common/platform destinations and unsafe paths fail before anything is changed.

Existing links to this checkout's previous source paths are migrated to the new
layout without a backup. Unrelated files and symlinks remain conflicts, handled
by `--backup` as described above.

The [catalogue](os/catalog.yaml) groups menu options under their sections.
Group and option keys are their displayed names and dependency identifiers;
`link_dependencies` identify the discovered paths an option requires.
Names cannot contain commas, control characters, backslashes, `*`, or `?`.
Unsupported architectures are hidden. Available operations are `tap`, `brew`,
`cask`, `apt`, and `script`. Scripts also run directly; scripts that replace files
accept `--backup`.
The bundled, pinned yq parser reads the YAML without requiring an additional
host dependency or download. The installer checks catalogue structure and link
dependencies before executing the plan. TODO entries are processed at the end.

On Debian, Firefox is installed from Mozilla's signed APT repository. An
existing Firefox ESR installation is retained and may use a different profile.

The macOS desktop-preferences option also sets the background from the PNG in
the checkout. Keep that checkout in place so macOS can continue to find it.
It shows the Finder path bar and filename extensions, turns off automatic
spelling correction, and hides desktop and Stage Manager widgets. Widgets in
Notification Center are unaffected.
If macOS blocks the Reduce Motion preference, enable it in System Settings under
Accessibility → Display, then rerun the option. The other preferences and
background are applied before this check. Terminal access may require Full Disk
Access under Privacy & Security.

Vim configuration and Powerline installers are retained in [archive/](archive/README.md)
for reference. Installation does not create or remove Vim configuration or fonts.

Machine-specific interactive Bash settings belong in `~/.bash.local`. Its optional
menu item creates an empty file only if missing and preserves existing contents. Optional applications need not be installed
for shell startup to succeed.

## Tests

See [the local testing guide](tests/README.md) for prerequisites, image preparation,
commands, security boundaries, and retained failure diagnostics.

All behavioral tests run inside disposable VMs. Temporary homes are used **inside
the guests only**. Run `./tests/run lint` for local Bash syntax checks and
ShellCheck; this needs an installed ShellCheck but no VM. Static checks do not
execute or source the candidate configuration.

## Post-install reminders

After installation, the installer adds missing tasks to `~/TODO.org` for
successfully completed features. General tasks live in the catalogue's
`post_install` section; conditional tasks live beside features, optionally under a
platform. Numbered heading keys set their order; numbers are omitted from TODO.org.
Existing tasks are matched by their
heading and text, preserving checked boxes and personal notes. Editing a task's
text creates a new entry on a later run. Cancellation creates no TODO file.

Keyboard scripts preserve the checked-in mappings. Debian installs a root-owned keyd configuration. macOS links the Karabiner configuration directory and skhd configuration; existing conflicts require `--backup`, and macOS permission grants remain manual. An existing Karabiner directory is backed up as a whole, including any other profiles or assets; they are not merged into the linked configuration. After changing the directory link, log out and back in so Karabiner watches the new location. Changes made in Karabiner's settings can modify the checkout.

Emacs configuration is cloned from the published repository with its public submodule fetched over HTTPS. Existing checkouts and local changes are retained. A startup failure is reported as a failed operation without modifying dotemacs source.

See [platform support](docs/ui-status.md) for available routes and testing limits.

Successful package, configuration and symlink operations receive green ticks. Manual permissions and login steps remain in TODO.org; they do not make an installation look unsuccessful. Failed startup checks and skipped configuration are reported explicitly.

## Retrying Emacs startup

A failed or interrupted Emacs bootstrap remains unsuccessful on later installs.
Existing checkouts without a recorded result are also unverified. To retry
startup explicitly with the current catalogue:

```sh
./dotfiles install --only 'Emacs configuration' --yes --retry-emacs-bootstrap
```

This uses the existing checkout, including local edits; it does not pull, reset,
or replace it. Startup can download and build Emacs packages. The installer records
pending/failed/succeeded in the checkout's local Git configuration. A successful
retry records success; ordinary reruns do not execute startup again.
