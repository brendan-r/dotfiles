# ThinkPad graphics observations

These notes preserve observations from physical hardware associated with the
pre-revamp `thinkpad-cruft` branch (commit `2599626`). They are troubleshooting
evidence, not graphics settings to apply to every ThinkPad. The snapshot below
was supplied by the owner; it was not collected in a VM or reproduced by the
repository's tests.

## T480: reported graphics baseline

| Component                         | Reported value                                           |
|-----------------------------------|----------------------------------------------------------|
| Laptop                            | Lenovo ThinkPad T480                                     |
| CPU                               | Intel Core i7-8650U                                      |
| GPU                               | Intel UHD Graphics 620, PCI vendor/device ID `8086:5917` |
| System                            | Debian GNU/Linux 13 (Trixie), AMD64                      |
| Kernel                            | `6.12.94+deb13-amd64`                                    |
| Kernel graphics driver in use     | `i915`                                                   |
| Xorg server package               | `2:21.1.16-1.3+deb13u4`                                  |
| Intel Xorg driver package         | `2:2.99.917+git20210115-1`, installed                    |
| Mesa DRI, GLX and Vulkan packages | `25.0.7-2+deb13u1`, installed                            |
| Picom package                     | `12.5-1`, installed                                      |

`glxinfo -B` reported direct rendering enabled, acceleration enabled, and renderer
`Mesa Intel(R) UHD Graphics 620 (KBL GT2)`. It reported OpenGL 4.6 and Mesa
`25.0.7-2+deb13u1`. This establishes hardware-accelerated OpenGL rendering for the
queried session; it does not establish the performance effect of any one tweak.

The reported Picom configuration contained:

```conf
backend = "glx";
vsync = true;
glx-no-rebind-pixmap = true;
glx-no-stencil = true;
use-damage = true;
```

The two `glx-no-*` settings are the additions in `thinkpad-cruft`. The other three
settings are already present in the current repository. This snapshot establishes
that the options are configured, not that the running Picom process loaded or
honored them. No Picom runtime diagnostics or before/after measurements were
supplied.

## Reported result: partial improvement

The owner reports that the graphics changes made videos watchable. Screen tearing
when scrolling in the browser remains a problem, and the overall result is still
unsatisfactory. Text rendering looks great.

Preserve this as a useful improvement over the previous state, not a resolved
graphics configuration. The report does not isolate which change improved video
playback or identify the cause of the remaining tearing. Further changes should
retain watchable video and good text rendering while addressing browser scrolling.

## Intel Xorg override: not established

The old branch's TODO proposed forcing `Driver "intel"`, DRI2 and TearFree through
`/etc/X11/xorg.conf.d/20-intel.conf`. The owner's query of that file returned no
matching Driver, DRI, TearFree or AccelMethod settings. Because the query suppressed
errors, this could mean the file was missing, unreadable, or lacked matching lines.
Other Xorg configuration locations were not inspected.

The installed Intel Xorg package does not prove that Xorg uses that driver.
Likewise, the active `i915` kernel driver and Mesa renderer do not distinguish
Xorg's `intel` driver from `modesetting`. Do not describe this snapshot as evidence
that forcing the Intel driver, DRI2 or TearFree was necessary or successful.
The installed Vulkan package also does not establish that it fixed desktop
rendering.

## Integration decision and remaining evidence

Preserve the Picom settings as a T480 troubleshooting candidate with a reported
video-playback improvement and unresolved browser-scroll tearing. Do not enable
them globally or install the old Intel Xorg override based on this snapshot alone.
Keep the physical-machine observation even if a VM behaves differently.

Before promoting a tweak to a supported hardware-specific setting, record:

- The browser, video player or site, and playback conditions used to reproduce
  the video improvement and remaining scroll tearing.
- Which changes improved it, whether they were tried individually or together,
  and whether the current snapshot matches the configuration that helped.
- Internal/external display use, docking, resolution and refresh rate.
- The active Xorg driver and whether Picom accepts and uses the options.
- A comparison on this T480 with and without each tweak, followed by checks for
  rendering artifacts, suspend/resume and external-display behavior.

This document intentionally includes only model identifiers, software versions,
selected settings and rendering observations. It omits serial numbers, hostnames,
usernames, network addresses, monitor EDIDs and raw diagnostic logs.
