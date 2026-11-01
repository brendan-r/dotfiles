# Debian platform support

The Debian configuration targets Intel/AMD64 ThinkPads: X1 Carbon 6th generation,
T480 and X200T. The installer detects CPU architecture when selecting packages
and binaries; ARM64 availability in a VM does not define support for these laptops.

The local VM suites run Debian Trixie on ARM64. AMD64 package dependencies have
also been resolved against Debian's package index, and the AMD64 UI and YAML
parser have been exercised under QEMU user emulation. These checks do not replace
installation on an Intel machine.

Before relying on the desktop on a ThinkPad, test keyboard mappings, brightness,
audio, suspend and resume, battery reporting, external displays and docking. On
the X200T, also test screen rotation and stylus alignment. Existing autorandr
profiles describe particular displays and may need adjustment for your setup.

See [the testing guide](../tests/README.md) for VM commands and coverage limits.
