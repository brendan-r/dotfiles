# Installer support and limits

The menu shows the dotfiles and catalogue options available for the current
platform and architecture. See [the catalogue](../os/catalog.yaml) for the
current list. Dotfiles are discovered individually from `home/`; selected
features also select any configuration paths they require.

Homebrew and APT run package operations sequentially. Some options use standalone
scripts for their installation procedure. If an operation fails, the installer
shows the failed step and log path; completed changes remain in place. Reminders
for completed features are added to `~/TODO.org`.

Debian Firefox comes from Mozilla's signed APT repository; an existing Firefox
ESR is left installed. Proton VPN is optional on macOS and Debian AMD64. Its
Debian repository setup and AMD64 dependency resolution have been checked, but
the VPN package, GUI, credentials and connection have not been tested under i3.
Intel macOS Emacs, Node, and personal R/Stan
package setup are not offered by the installer.

The Debian desktop targets Intel ThinkPads. Local macOS and Debian VM tests run on
ARM64; native Intel and physical ThinkPad testing remain necessary. The i3 smoke
test exercises a small X11 session, not real keyboard, display, audio, suspend,
or docking hardware. See [the testing guide](../tests/README.md) for commands and
coverage.

macOS Accessibility/Input Monitoring permissions, testing keyboard behaviour,
application logins and any remaining desktop setup are manual steps. The Emacs
batch bootstrap checks package startup but does not establish that GUI Emacs or
client frames work. The bootstrap uses a timer inside Emacs, so an Emacs process
that cannot process timers may require interruption.
