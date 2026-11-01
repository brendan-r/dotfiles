# Standalone Debian installers

Application procedures live in `os/install_*.sh` and can be run directly with
Bash as your normal user. Each script detects the CPU automatically and uses
sudo for system changes. The catalogue selects the supported routes; the same
scripts run from the installation menu.

- Firefox uses Mozilla's signed APT repository and leaves Firefox ESR installed.
- Spotify and Signal use their vendors' APT repositories on AMD64.
- Anki selects the current upstream archive for AMD64 or ARM64 and checks its
  published GitHub digest. This checks integrity, not an independent signature.
- RStudio selects the current Debian-compatible AMD64 package from Posit's stable
  release metadata and checks the published SHA-256. The checksum and package
  come from the same source, rather than an independent signature.
- Proton VPN uses Proton's signed APT repository on AMD64. Repository setup and
  AMD64 dependency resolution have been checked, but the VPN package and its
  GUI, credentials and connection have not been tested under i3. Proton
  officially supports GNOME.

The download helper in `os/lib/download.sh` reports HTTP and rate-limit errors,
retries bounded failures and checks checksums. Each script owns its package
names and temporary files.

The standalone `os/set_default_apps.sh` can link `mimeapps.list`, but is not a
menu option: review that file's application associations before using it. It
backs up conflicting files; the link and rerun behavior have focused tests.

See [the testing guide](../tests/README.md) for package tests and their limits.
