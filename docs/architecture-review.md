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

The i3 session uses XFCE Power Manager and XFCE Screensaver for locking; do not
run xss-lock alongside them. Configure and test manual and idle locking, and
confirm that the screen is locked before suspend or lid close on each machine.
Fingerprint enrollment and authentication are optional and depend on the sensor
and the packaged libfprint version. Verify password fallback before relying on it.

The old Nibbler installer ran a mutable remote script. If Nibbler is wanted
again, add it as an optional application using a reviewed, versioned release and
verified downloads instead. The shared download helper already reports download
and rate-limit failures. Keyboard repeat remains a preference to tune on hardware.

See [the testing guide](../tests/README.md) for VM commands and coverage limits.
See [ThinkPad graphics observations](thinkpad-graphics.md) for the physical T480
baseline and the limits of the historical graphics tweaks.
