# Local lint and VM testing

## Boundary

Candidate installers, shell startup, and behavioral tests execute only inside disposable Tart VMs. Temporary homes separate individual cases inside a guest; they are not a sandbox. The guest scripts require a guest marker to reduce the risk of accidental host invocation. That marker is a guardrail, not an isolation mechanism: do not run those scripts manually on the host.

Syntax checks and ShellCheck run on the host using trusted, installed tools; they parse source files without executing or sourcing candidate code. The host harness, vendored Bats runtime and host checks, Python runtime, Bash, ShellCheck, Git, SSH, and Tart remain trusted. No host directory shares, SSH agent forwarding, personal credentials, or host environment secrets are exposed to guests. Audio, clipboard, and USB accessory integration are disabled.

Routine suites use Tart's **host-only networking** and a guest-loopback fixture endpoint. Both platforms use Tart's guest agent over the local virtualization control channel. Debian runs commands directly through the agent; macOS uses it to carry SSH to the guest's own loopback address. This gives macOS commands a normal remote-login session without granting the agent access to protected user files. The host does not connect to guest IP addresses, so this transport does not require Local Network permission. Guests cannot use ordinary internet routing through Tart, but host-only networking is **not isolation from host network services or other VMs**. The HTTP server runs entirely inside the guest and exposes only a disposable candidate snapshot. A successful test does not establish that a package or image is trustworthy. VM escapes and compromised host tools remain outside this test harness's protection.

Baseline preparation uses online networking to obtain prerequisites. Prepared baselines are never used as test targets. Failed test guests are stopped, retained for inspection, and never promoted into baselines.

## Host prerequisites

Local lint needs Python 3, Bash, and a trusted ShellCheck installation on PATH. Install ShellCheck with `brew install shellcheck` on macOS or `sudo apt install shellcheck` on Debian, or select an existing executable with `SHELLCHECK=/absolute/path/to/shellcheck ./tests/run lint`. Lint does not install anything automatically, require VM baselines, or invoke Tart. It ignores personal ShellCheck rc files so the repository's checks do not depend on local exclusions.

Behavioral VM tests additionally require:

- Apple Silicon macOS, Python 3, working system Git/Command Line Tools, and SSH.
- Tart with `exec`, `--disk`, `--net-host`, `--no-clipboard`, and `--no-usb-accessories` support (tested with 2.41.1).
- macOS's built-in `hdiutil` for the read-only agent setup disk.
- Space for the approximately 24 GB compressed vanilla macOS image plus expanded images and changed guest disks. Test guests run sequentially, with 2 CPUs/4 GiB RAM. Preparing macOS does not require a Debian VM.

The attempted `brew install cirruslabs/cli/tart` may fail with older tap formulae on newer Homebrew versions. The alternative used here is the official Tart 2.41.1 release archive, installed under:

```
~/Library/Caches/dotfiles-tests/tools/tart-2.41.1/tart.app/Contents/MacOS/tart
```

Obtain the archive and published checksum from the [official release](https://github.com/openai/tart/releases/tag/2.41.1), verify SHA-256 before extraction, and preserve the `.app` layout. The harness also accepts `TART=/absolute/path/to/tart.app/Contents/MacOS/tart` or a `tart` on PATH. It does not install host software automatically.

`DOTFILES_TEST_STATE` overrides the default `~/Library/Caches/dotfiles-tests`. This directory holds baseline metadata and optionally downloaded Tart binaries. It does not need to contain a private key. Each command needing macOS access generates a fresh test-only SSH key in a private temporary directory and removes it when the command finishes. Only the public key is sent to the guest, through the existing agent. Guest SSH host keys are also recorded only in that temporary directory; neither personal SSH configuration nor an SSH authentication agent is used.

Every macOS test clone is authorized afresh, so a prepared baseline can be used on another Mac without copying a private key. On a new Mac, install the host prerequisites and run preparation, or import your existing prepared Tart baseline and copy its matching `macos.json` metadata. This harness currently runs VMs on Apple Silicon macOS; local lint also works on Debian.

## Prepare baselines once

```sh
./tests/run prepare-vms debian
./tests/run prepare-vms macos
```

`prepare-vms` without a platform prepares Debian and then macOS.

The upstream image references in `images.json` are pinned by OCI digest. Debian must identify itself as Debian Trixie ARM64; macOS must be macOS 26 ARM64.

- Debian: ensure Git, curl, CA certificates, and SSH are installed. The image’s guest agent and Python 3 support fixture transport; Python is not an installer prerequisite.
- macOS: use vanilla Tahoe, add Tart's RPC agent, and install Command Line Tools using the guest's `softwareupdate`. The harness selects only an explicitly named Command Line Tools product; it does not install full Xcode, Homebrew, Safari updates, or an OS upgrade. If Apple offers no CLT product, install CLT in the guest manually and rerun preparation.

Vanilla macOS has no Tart agent. Run initial preparation in an interactive host terminal. It opens the VM window and attaches a small read-only disk containing `setup-macos-agent.sh`. If the agent is absent, preparation prints this command and waits up to 15 minutes. In **the VM's Terminal**, type:

```sh
/bin/bash /Volumes/DotfilesSetup/setup.sh
```

This is a one-time manual prerequisite for a newly created vanilla baseline. The script downloads the official guest-agent archive inside the VM, verifies its pinned SHA-256, and installs a persistent RPC service as the guest's `admin` user. It refuses to run outside a macOS VM. The service does not enable clipboard sharing or automatic disk resizing. No Homebrew, Node, Ruby, or CI tools are added. The host resumes preparation when the agent becomes available, then removes the temporary setup disk after stopping the VM. An existing baseline with the agent already installed skips the manual step. Routine tests require no interaction.

The setup disk contains only the installer script, with no keys or host files.

Preparation creates a dedicated `dotfiles` account with no administrative rights. Debian starts test commands as that account through `sudo`; macOS logs in as that account using the temporary test key. Only the key's public half is installed in the guest. Routine suites never grant administrative access to candidate code. The explicit
package suite and interactive `--provision` mode grant it only inside fresh clones. It records guest OS/tool versions and the pinned image in state metadata, then stops the baseline. It never silently refreshes a validated baseline. To rebuild, explicitly delete the relevant `dotfiles-baseline-*` VM and its corresponding state JSON. Never delete unrelated VMs.

No host privacy, firewall, VPN, or routing settings are changed. If the guest agent or guest SSH fails, the harness reports the failure rather than executing candidate code on the host.

## Run

```sh
./tests/run host-syntax    # Optional: system Bash parses scripts on the host
./tests/run lint           # Local ShellCheck and syntax; no VM needed
./tests/run unit           # Behavioral cases, disposable macOS guest
./tests/run quick          # Local lint plus macOS behavioral cases (still needs a VM)
./tests/run vm debian      # Cases plus full installation in Debian account HOME
./tests/run vm macos       # Cases plus full installation in macOS account HOME
./tests/run vm all         # Both full suites, sequentially
```

Host syntax checks only parse files. No host behavioral mode exists. `quick` reuses downloaded baselines, not an already-modified guest. Lint covers the maintained entrypoint, linker, installed Bash files, and guest test scripts; historical application installers are outside the initial gate.

The harness builds a temporary Git repository from tracked working-tree files (including edits) and new files in `tests/`, `os/`, `shell/`, `ui/`, `config/`, `mac-stuff/`, `keyboard/`, `.githooks/` and `home/`. Deleted tracked files stay deleted; ignored files and unrelated untracked directories are omitted. It does not stage or commit anything in the real repository. Fixtures containing symlinks are rejected to prevent the HTTP server from following links into host files. One snapshot is frozen per command and shared by both platforms; later working-tree edits cannot change an in-progress run. The fixture commit is synthetic and recorded in each result.

The same download/execute procedure documented in [BOOTSTRAP.md](../BOOTSTRAP.md) fetches the candidate bootstrap from the fixture server. Its repository URL points to a cloneable HTTP fixture. Tests assert the installed commit and origin. No push is necessary, and tests do not accidentally fetch unchanged GitHub `master`.

Cases cover platform links, reruns, spaces in paths, conflict preflight, backup contents, symlinked parents, missing sources/Git, unsupported platforms, failed clones and refs, dirty checkouts, and stock-Bash startup. Interactive shells run under their own guest PTYs so Apple's Bash 3.2 can initialize job control before its output is captured. Optional applications and generated locales are not required. Full suites use the account's real guest home with OS skeleton files, then verify checkout ownership, a usable branch, reruns, and shell startup. Each behavioral case gets a fresh HOME and mutable source copy. Independent integration cases restore installer-owned paths in the real guest account HOME from a saved snapshot; SSH credentials and macOS Library contents are not reset.

## Try the dotfiles interactively

Run this in a real terminal on the host after preparing the corresponding baseline:

```sh
./tests/run interactive macos
./tests/run interactive debian
./tests/run interactive macos --gui       # Also open the VM window
./tests/run interactive debian --online  # Allow internet access for downloads
./tests/run interactive macos --keep      # Preserve the stopped clone after exit
```

The command freezes your current working-tree snapshot, clones a fresh VM, and opens a real guest terminal as the `dotfiles` account (unprivileged unless `--provision` is given). It clones the candidate into `~/projects/dotfiles` inside the guest and starts there **without running the installer**. Try `./dotfiles install --backup`, answer prompts, inspect the results, and use `exec /bin/bash -il` to load the installed shell configuration. Input, terminal menus, Ctrl-C, and terminal resizing pass through the terminal transport. The maintained installer opens its Bubble Tea menu in this terminal.

The welcome message includes commands for testing the download/bootstrap path against the same local snapshot. `DOTFILES_FIXTURE_URL` and `DOTFILES_REVISION` are available in the guest shell. The fixture server runs inside the guest on loopback while the session is open. No commit or push is required. Host edits made after launch do not change the running candidate, and guest edits never sync back to the host.

Use `exit 0` to finish successfully. The runner stops and deletes the clone after a successful session unless `--keep` was specified. A nonzero shell exit, disconnect, setup failure, or interruption retains the stopped clone and reports its name. On macOS, OpenSSH's Enter then `~.` escape disconnects a stuck session. Ctrl-C during a guest command interrupts that command; Ctrl-C during setup interrupts the runner and cleans up. Interactive sessions have no test-suite time limit. Setup and cleanup still have timeouts.

`--keep` preserves the disk for manual inspection; it does not add a resume command. The summary prints the VM name for Tart inspection or `tart delete NAME` when finished. Temporary access keys and the fixture server are cleaned up even when retaining the disk; starting another `interactive` command always creates a new clone. Infrastructure logs and `source.json` are saved in `.test-results/`; terminal contents and typed input are not recorded in `guest.log`. An interactive `PASS` means the session and cleanup finished successfully, not that automated assertions ran.

Networking remains host-only by default, with the same host-network caveat described above. `--online` explicitly enables the VM's ordinary internet routing. `--gui` adds the VM console window; the interactive command still runs in your host terminal, and the console may be logged into a different account. Neither option shares host directories, clipboard, audio, or personal credentials. Graphical mode retains Tart’s virtual USB keyboard and pointer; `--no-usb-accessories` is only used headlessly because it removes Linux console input devices. The account remains non-administrative unless `--provision` is explicitly added with `--online`. These flags apply only to `interactive`, which requires exactly one platform and terminal stdin/stdout; piping or redirecting the command is rejected before creating a VM.

## One framework and live output

Bats-core runs every test: local static checks, guest behavior, full installation, and guest-only Python harness probes with fake transports. The Python entrypoint manages VMs, subprocesses, and progress; it is not another test framework. All nine terminal/startup combinations appear individually for isolated guest homes. The full account installation retains one interactive-login startup check with `TERM=xterm-256color`. The full VM suites include installer and harness cases; the local static checks are separate. Tests use Bash-compatible function syntax with `# @test` so syntax checks can parse them without executing them.

Test names follow `area__component__expected_behavior`: double underscores separate the three levels, and single underscores separate words within a level. Use lowercase names that describe the observable outcome, for example `dotfiles__install__conflicts_preserve_originals_before_linking` or `runner__processes__timeout_stops_child`. Put case variations in the final level, such as `dotfiles__shell__login_with_term_unset_runs_repo_command`. Keep the execution platform out of the name: the runner adds `[host]`, `[macos]`, or `[debian]` separately.

See [Test coverage and gaps](#test-coverage-and-gaps) for the scope of each group and the repository functionality outside the current suite.

Keep cases from each group adjacent, with dotfiles checks before runner checks. Pretty output shows one heading for each consecutive group and readable case names beneath it; TAP retains complete names for identifying individual results. The `unit` suite omits `dotfiles / full_install`; full VM suites include it.

```text
[macos] dotfiles / install
  ✓ conflicts preserve originals before linking (12 ms)

[macos] runner / processes
  ✓ timeout stops child (530 ms)
```

```sh
./tests/run vm all --format pretty  # Named tests and colored checkmarks
./tests/run vm all --format tap     # Plain per-suite TAP and stage comments
./tests/run quick                   # Automatic terminal detection
NO_COLOR=1 ./tests/run lint --format pretty  # Checkmarks without ANSI colors
```

`--format auto` is the default. A capable terminal gets green ✓ passes, red ✗ failures, yellow skips, timings, and totals. Each running test occupies one row, which is replaced by its result on completion. Long running labels are shortened to fit the terminal; the completed result retains the full name. Redirected output, `TERM=dumb`, and `NO_COLOR` select plain TAP automatically. Explicit `pretty` works in captured output too, printing one completed line per test without cursor controls. `NO_COLOR` still disables colors. The overall command contains separate TAP suites and progress comments, not a single merged TAP document.

VM operations print their start and completion immediately. Guest test results stream to the terminal and `guest.log` while the tests run; nothing waits for the whole suite to finish. Normal command output is captured, with diagnostics shown on failure. The final summary reports every requested suite, including failures.

Bats continues after independent test failures. The harness also continues to the next platform after a suite or setup failure, and `quick` still runs guest tests if lint fails. An infrastructure failure aborts the affected suite. Any failed check, setup, or cleanup makes the command exit nonzero. Ctrl-C/SIGTERM stops scheduling new work and cleans up the current guest.

## Vendored dependencies

The installer uses pinned yq binaries bundled under [os/vendor/yq](../os/vendor/yq/README.md) to read [os/catalog.yaml](../os/catalog.yaml); dotfile paths are discovered directly from the HOME-shaped `home/` tree. These binaries travel with the candidate into each VM. Host lint parses shell wrappers but does not execute the candidate parser.


`vendor/bats-core` contains the unchanged `bin`, `lib`, and `libexec` runtime and `LICENSE.md` from Bats-core **v1.14.0**. `UPSTREAM.json` records the source commit and SHA-256 of the upstream release archive. The runtime is about 188 KiB. The same files run on the host and travel in the candidate archive into each guest. No Bats installation, baseline rebuild, or test-time download is needed. The project formatter lives outside the vendor directory in `format-pretty` and uses the pinned Bats formatter callbacks. No assertion plugins are required.

To update Bats, download the chosen tagged upstream source archive, review its release notes and source provenance, and record its commit and archive SHA-256. Replace only the runtime directories and license with byte-for-byte upstream copies, updating `UPSTREAM.json`. Keep formatter changes outside the vendor tree. Then run lint and both full VM suites, including the formatter and subprocess regression cases. Do not update Bats automatically during tests.

## Results and cleanup

Results appear under `.test-results/dotfiles-test-<platform>-<id>/`:

- `source.json`: frozen candidate commit, baseline identity/versions, suite mode, and Bats provenance.
- `guest.log`: completed guest test results and failure diagnostics, without ANSI escapes or overwritten running rows. An interrupted last line is preserved.
- `tart.log`: VM startup diagnostics.
- `server.log`: guest fixture server diagnostics.

Local checks write `host.log` under a corresponding `dotfiles-test-host-*` directory. Partial logs survive failures, timeouts, and interruptions.

The harness bounds startup, provisioning, and execution, including silent subprocesses, except the deliberately unbounded interactive terminal session. It stops guests on exit and deletes successful test clones only after verifying they stopped. Failed guests are retained for inspection. If stopping fails, output explicitly says stopping is unconfirmed; it never claims the VM stopped successfully. Original failures and cleanup failures are both reported. Delete retained guests individually with `tart delete NAME` when finished. Logs remain until you choose to remove them.

To check a change on both platforms, run local `lint`, `vm macos`, and `vm debian` against the same source snapshot. `vm all` freezes one snapshot for both full suites. Each includes the behavioral and harness cases also run by `unit`, so running `quick` as well is optional. Testing the published GitHub one-liner is a separate post-publication check. There is no GitHub Actions workflow.

## Test coverage and gaps

Routine VM cases exercise dotfile discovery and linking, selection and dependency
handling, backups and migration, shell startup, catalogue parsing, reminders,
installer status, interruption, and the test harness. They use synthetic
catalogues and package commands where practical. The opt-in package suite installs
real available packages, reruns the installer and checks package-manager receipts;
it does not establish that every application runs correctly.

The macOS preference tests reject a headless session before changing settings.
In a graphical session they also check the active image, preference values and
preservation of unrelated settings across reruns. If macOS blocks the Reduce
Motion write, they check that the failure explains the manual step instead. They
do not test shortcuts or animation after logout. The default-app script has link, backup and rerun tests;
the suitability of its application associations has not been checked.

The optional i3 check starts an X11 session and exercises basic window and
notification behavior. VMs cannot establish physical keyboard, display, audio,
battery, dock or suspend behavior on the target ThinkPads. The Debian VM runs
on ARM64, not the intended AMD64 hardware. Yabai/skhd permissions, GUI Emacs,
application logins and real VPN connections also need hands-on validation.

Tests do not cover every shell alias, personal utility or Git setting, nor the
separate personal-data backup workflow. They cover selected backup failures and
interruptions, not every recovery scenario, full disk or concurrent install.
The published bootstrap URL and a completely untouched machine are not exercised
by the local fixture. See [platform support](../docs/architecture-review.md)
for the AMD64 checks and their limits.

## Package installation tests

```sh
./tests/run packages all              # Explicit online, privileged guest tests
./tests/run packages macos            # Includes fresh Homebrew installation
./tests/run packages debian
./tests/run interactive macos --online --provision --gui
./tests/run interactive debian --online --provision
```

`packages` automatically enables networking and guest-only sudo in a disposable
clone. It selects available routes for the guest platform and architecture from YAML,
checks package-manager receipts, and repeats installation. LaTeX is excluded
by default because the full distribution is large; select it with `--only 'LaTeX (full TeX Live)'`.
Configuration scripts run as selected by that catalogue; this suite does not
maintain application-specific executable checks or fixed keyboard expectations.
Emacs configuration can report Installed; startup check failed even when its checkout succeeds;
inspect retained installer logs for package-bootstrap errors. It does not run in routine suites or
change baseline permissions. Failed clones are retained with the usual logs.
Internet availability and upstream packages affect this smoke test.

Interactive `--provision` requires `--online`; its banner identifies the privileged
clone. Inside, run `./dotfiles install --backup` and choose the features yourself.
The candidate still runs as the ordinary test user, with sudo available when needed.
Homebrew can request its normal confirmation. No host administrator rights or host
software installation are involved.

Routine suites add focused checks using fake package-manager commands,
real selected links, and actual UI selection, cancellation, and execution. They assert effects and
outcomes rather than exact menu formatting, colors, or spinner frames. Dashboard
checks cover hidden prompt input, resizing, seamless direct installation, the Org
completion preview (wrapping, scrolling and preserving the file), and cancellation
that stops worker children. All candidate
behavior, including fakes, remains inside VMs. The all-links tests use `--links-only` explicitly.

The standalone UI model tests are compiled on the host and executed only in the
guests. AMD64 releases are cross-compiled; native execution is covered on ARM64.
Installer logs are retained in each result directory as `installer-logs.tar`.
Use `--keep` with `packages` to retain the stopped guest for investigation.

Post-install reminders live beside their features in the catalogue; platform-specific
reminders live under the corresponding platform. Shared always-on reminders remain
under `post_install`, and numbered heading keys set output order. Empty sections are omitted. The writer matches
checkbox text within its heading, ignoring checked/unchecked state; changing
text or headings adds new entries without deleting the old ones. Existing notes
and older TODO/DONE headings are left untouched.

### Focused desktop package checks

```sh
./tests/run packages macos --only 'Yabai window manager'
./tests/run packages debian --only 'i3 desktop,Custom keyboard layout'
```

The selection uses catalogue option names and includes dependencies. Omitting `--only`
runs all available routes except LaTeX. A selected i3 script also runs a small Xvfb
session check: real config parsing, an X11 window, workspace movement and a
notification. Xvfb/xterm are test dependencies, not added to the user's catalogue.
ThinkPad hardware is outside VM coverage; Debian VM execution is ARM64, while
AMD64 package availability can be checked independently against Debian's index.

### Focused LaTeX package checks

```sh
./tests/run packages all --only 'LaTeX (full TeX Live)'
```

LaTeX is excluded from default package runs; opt in with `--only 'LaTeX (full TeX Live)'`.
This online test installs the full distributions in disposable VMs, reruns the
installer, then typesets a PDF and renders a DVI math preview. Allow several GB
of downloads and disk space per guest. The standard macOS baseline is too small
for full MacTeX; use a larger system volume before running its test. macOS opens
a new terminal for MacTeX's PATH entry; the in-process smoke test adds that path because it predates install.

### Production architecture versus test architecture

Debian's intended production machines are Intel/AMD64 ThinkPads. The local Tart
baseline is ARM64; its identity checks describe that test image only. UI test
binaries are built for AMD64 and ARM64 and dispatched using the guest CPU.
Synthetic architecture tests cover both catalogue availability and executable
selection without copying real package inventories into assertions.

The [architecture review](../docs/architecture-review.md) records AMD64 dependency
resolution and execution of the actual AMD64 UI/parser binaries under QEMU user
emulation. These checks supplement ARM VM tests; they do not replace native Intel
or physical ThinkPad validation. Keep hardware-specific production behaviour even
when a VM cannot exercise it.

### Rejecting stale UI builds

The pre-commit hook compares staged Go sources/module files and vendored binaries
with `os/vendor/installer-ui/BUILD.json` only when `go` is on PATH. Without Go,
it exits successfully before invoking Python: any source/config edits can be
committed on ordinary dotfiles machines. It never rebuilds or stages files.
On development machines, an unchanged build needs only hashing. A commit with
no UI files at all is allowed, so independent archive commits remain possible.

Enable the checked-in hook for a checkout with:

```sh
git config core.hooksPath .githooks
```

For a worktree-only setting, use `git config --worktree core.hooksPath .githooks`
after enabling Git's `extensions.worktreeConfig` setting. The ui-layer worktree
can enable this separately. Hooks can be bypassed; all VM test commands independently check
the frozen candidate before starting a VM. `prepare-vms` only prepares baselines.

On a mismatch, rebuild explicitly and stage the matching source and artifacts:

```sh
python3 ui/build.py /absolute/path/to/go os/vendor/installer-ui
```

If you have unstaged Go edits, decide which changes belong in the commit before
rebuilding: a build of the working tree may not match a partially staged source.
Manual checks are `python3 tests/check-ui-build.py` (working tree) and the same
command with `--staged` (index). The latter honors `GIT_INDEX_FILE` too.
