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

Older harness versions stored `id_ed25519`, `id_ed25519.pub`, and `known_hosts` in the state directory. Those files are no longer read or needed by this harness. They are not automatically deleted; you can remove those dedicated legacy files after checking that nothing else uses them.

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

This replaces the Debian relay rather than moving that dependency elsewhere. The setup disk contains only the installer script, with no keys or host files.

Preparation creates a dedicated `dotfiles` account with no administrative rights. Debian starts test commands as that account through `sudo`; macOS logs in as that account using the temporary test key. Only the key's public half is installed in the guest. The administrative provisioning identity is not used to execute candidate code. It records guest OS/tool versions and the pinned image in state metadata, then stops the baseline. It never silently refreshes a validated baseline. To rebuild, explicitly delete the relevant `dotfiles-baseline-*` VM and its corresponding state JSON. Never delete unrelated VMs.

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

The former tooling VM is no longer used or prepared. If you have an old `dotfiles-baseline-tooling`, you can remove that VM and its `tooling.json` state file manually; lint does not delete existing VM data.

The harness builds a temporary Git repository from tracked working-tree files (including edits) and new files in `tests/`, `os/`, and `shell/`. Deleted tracked files stay deleted; ignored files and unrelated untracked directories are omitted. It does not stage or commit anything in the real repository. Fixtures containing symlinks are rejected to prevent the HTTP server from following links into host files. One snapshot is frozen per command and shared by both platforms; later working-tree edits cannot change an in-progress run. The fixture commit is synthetic and recorded in each result.

The same download/execute procedure documented in [BOOTSTRAP.md](../BOOTSTRAP.md) fetches the candidate bootstrap from the fixture server. Its repository URL points to a cloneable HTTP fixture. Tests assert the installed commit and origin. No push is necessary, and tests do not accidentally fetch unchanged GitHub `master`.

Cases cover platform links, reruns, spaces in paths, conflict preflight, backup contents, symlinked parents, missing sources/Git, unsupported platforms, failed clones and refs, dirty checkouts, and stock-Bash startup. Interactive shells run under their own guest PTYs so Apple's Bash 3.2 can initialize job control before its output is captured. Optional applications and generated locales are not required. Full suites use the account's real guest home with OS skeleton files, then verify checkout ownership, a usable branch, reruns, and shell startup. Each behavioral case gets a fresh HOME and mutable source copy. Independent integration cases restore installer-owned paths in the real guest account HOME from a saved snapshot; SSH credentials and macOS Library contents are not reset.

## One framework and live output

Bats-core runs every test: local static checks, guest behavior, full installation, and guest-only Python harness probes with fake transports. The Python entrypoint manages VMs, subprocesses, and progress; it is not another test framework. All nine terminal/startup combinations appear individually for isolated guest homes. The full account installation retains one interactive-login startup check with `TERM=xterm-256color`. Each full VM suite has 38 named cases: 30 dotfiles cases and eight runner cases. The two local static checks are separate. Tests use Bash-compatible function syntax with `# @test` so syntax checks can parse them without executing them.

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

## Vendored dependency

`vendor/bats-core` contains the unchanged `bin`, `lib`, and `libexec` runtime and `LICENSE.md` from Bats-core **v1.14.0**. `UPSTREAM.json` records the source commit and SHA-256 of the upstream release archive. The runtime is about 188 KiB. The same files run on the host and travel in the candidate archive into each guest. No Bats installation, baseline rebuild, or test-time download is needed. The project formatter lives outside the vendor directory in `format-pretty` and uses the pinned Bats formatter callbacks. No assertion plugins are required.

To update Bats, download the chosen tagged upstream source archive, review its release notes and source provenance, and record its commit and archive SHA-256. Replace only the runtime directories and license with byte-for-byte upstream copies, updating `UPSTREAM.json`. Keep formatter changes outside the vendor tree. Then run lint and both full VM suites, including the formatter and subprocess regression cases. Do not update Bats automatically during tests.

## Results and cleanup

Results appear under `.test-results/dotfiles-test-<platform>-<id>/`:

- `source.json`: frozen candidate commit, baseline identity/versions, suite mode, and Bats provenance.
- `guest.log`: completed guest test results and failure diagnostics, without ANSI escapes or overwritten running rows. An interrupted last line is preserved.
- `tart.log`: VM startup diagnostics.
- `server.log`: guest fixture server diagnostics.

Local checks write `host.log` under a corresponding `dotfiles-test-host-*` directory. Partial logs survive failures, timeouts, and interruptions.

The harness bounds startup, provisioning, and execution, including silent subprocesses. It stops guests on exit and deletes successful test clones only after verifying they stopped. Failed guests are retained for inspection. If stopping fails, output explicitly says stopping is unconfirmed; it never claims the VM stopped successfully. Original failures and cleanup failures are both reported. Delete retained guests individually with `tart delete NAME` when finished. Logs remain until you choose to remove them.

Completion requires local `lint`, `vm macos`, and `vm debian` to pass on the same source snapshot. `vm all` freezes one snapshot for both full suites. Each includes the behavioral and harness cases also run by `unit`, so running `quick` as well is optional. Testing the published GitHub one-liner is a separate post-publication check. No GitHub Actions workflow is included in this milestone.

## Test coverage and gaps

The current milestone is downloading a checkout, installing configuration links, and starting Bash successfully on prepared macOS and Debian guests. Each full VM suite contains 30 dotfiles cases and eight runner cases; the two host static checks are separate. A passing suite establishes this limited bootstrap behavior, not that the repository can provision a complete working machine or that every linked configuration works in its application.

### Types of tests

The `unit` command runs focused behavioral tests in a real VM, including real filesystem operations, Git commands, and shell processes. Its name does not mean all these tests are isolated functions with mocked dependencies. Temporary homes separate the cases inside the VM. Full VM suites add the four `dotfiles / full_install` cases in the guest account's actual home. Runner tests deliberately use subprocess fixtures and mocked VM operations to exercise failure paths without needing to break a real VM.

- **`static / shell` — 2 cases; static analysis on the host.** Runs Bash's parser and ShellCheck without sourcing or executing the candidate configuration. The selected files are the `dotfiles` entrypoint, `os/create_symbolic_links.sh`, the maintained Bash startup fragments listed in `SHELL_FILES` in [run](run), and non-vendored shell/Bats test scripts. This catches syntax, quoting, and other shell mistakes. It is not repository-wide lint: historical installers, `bin` utilities, Python/R code, and application configuration formats are outside these checks. Cases: [host.bats](host.bats).

- **`dotfiles / install` — 8 cases; filesystem behavior in temporary guest homes.** Runs the actual installer against disposable copies of the repository. Checks that the selected platform's manifest entries become working symlinks, paths containing spaces work, repeated installs avoid unnecessary backups, and already-correct relative links survive. Conflict and backup cases exercise ordinary files, directories, dangling symlinks, symlinked parent directories, and a missing source. An unsupported OS name must be rejected. Assertions inspect resulting links and preserved contents; they do not validate the settings inside linked files. Cases: the install group in [cases/behavior.bats](cases/behavior.bats).

- **`dotfiles / checkout` — 9 cases; Git/bootstrap integration with a local HTTP fixture.** Invokes the real bootstrap and Git against a disposable repository served inside the guest. Checks the cloned revision and origin, an actionable missing-Git error, reuse of an existing checkout, retention of a local edit and an untracked file, acceptance of the historical SSH-form origin, rejection of a different origin, invalid-reference handling, cleanup after clone failures, and preservation of an unrelated destination directory. These are real clone and filesystem operations. They do not contact GitHub, authenticate over SSH, or exercise every supported ref/checkout arrangement. Cases: the checkout group in [cases/behavior.bats](cases/behavior.bats).

- **`dotfiles / shell` — 9 cases; Bash startup behavior in temporary guest homes.** Installs the links, then starts the guest's system Bash in each combination of login, interactive, or interactive-login mode and `TERM=xterm-256color`, `TERM=dumb`, or no TERM. Each shell must execute a temporary command placed in the checkout's `bin` directory by basename, produce no unexpected startup output/errors, and keep PATH stable when the profile is sourced again, with no empty PATH entries. Interactive shells use a pseudo-terminal. This proves that the startup path loads enough configuration to expose repository commands; it does not test every alias, function, export, or displayed prompt. Cases: [cases/startup.bats](cases/startup.bats), using [shell-check.sh](shell-check.sh).

- **`dotfiles / full_install` — 4 cases; end-to-end testing of the bootstrap milestone.** Downloads the candidate bootstrap script from the local fixture and runs it in the non-administrator guest account's actual home, restoring relevant home state between cases. Checks preservation of a conflicting profile, the installed checkout's revision/origin/branch/ownership, no additional backups on rerun, and one interactive-login shell startup with `TERM=xterm-256color`. “Full” refers to this download → checkout → link → shell flow, not application installation or complete OS provisioning. Cases: [cases/integration.bats](cases/integration.bats).

- **`runner / processes` — 4 cases; subprocess regression tests inside the guest.** Launches controlled Python child processes through the runner to check streaming before process exit, termination of a silent timed-out child, interruption cleanup with partial logs preserved, and retention of a failed process's exit status and output. The failed-process case uses a local child that exits with status 255; it does not simulate an actual broken SSH or guest-agent connection. Cases: the processes group in [cases/harness.bats](cases/harness.bats), implemented in [helpers/harness-probe.py](helpers/harness-probe.py).

- **`runner / suites` — 1 case; suite scheduling/error-handling test.** Supplies controlled failing, successful, and interrupted jobs to the runner. Checks that ordinary test/setup failures allow subsequent suites to run while preserving an overall failure result, and that interruption stops scheduling further suites. This tests the project's orchestration logic, not Bats' own ability to continue after a failed test. Case: the suites group in [cases/harness.bats](cases/harness.bats).

- **`runner / output` — 1 case; formatter and log-processing regression tests.** Feeds synthetic pass/fail/skip events and diagnostics through the actual formatter and log writer. Checks result totals, grouped headings and platform changes, readable case labels, color/no-color modes, live-row handling, narrow-terminal truncation, and plain saved logs, including fragmented text and interrupted output. This checks whether test results are faithfully presented; it does not test dotfiles behavior. Case: the output group in [cases/harness.bats](cases/harness.bats).

- **`runner / vms` — 2 cases; VM lifecycle logic with mocked commands.** Injects fake Tart commands, inventory responses, and subprocesses into the real orchestration functions. Checks that cleanup failures remain visible alongside the original failure, that an unconfirmed stop is reported, and that successful guests are deleted while failed guests are retained across success, assertion, setup, transport, and stop-failure scenarios. The lifecycle simulation exercises the Debian execution path. Ordinary full-suite runs also boot and clean up real VMs, but these injected failure cases do not prove real Tart/SSH/agent behavior under every failure condition. Cases: the vms group in [cases/harness.bats](cases/harness.bats).

### Repository functionality not currently tested

The following are major coverage gaps. Some concern historical utilities that the maintained bootstrap intentionally does not invoke; others concern application behavior after configuration has been linked. Their presence in the repository, successful linking, or a green bootstrap suite does not establish that they work on current macOS or Debian.

- **Package installation and upgrades.** The suite does not run [os/install_applications.sh](../os/install_applications.sh), the Ubuntu/APT installer under [os/ubuntu](../os/ubuntu), the Homebrew installer under [os/os_x](../os/os_x), or the individual `os/install_*.sh` utilities. It does not establish package availability, valid repositories/taps, dependency resolution, current installer flags, repeatability, upgrades, or successful application launches. Language and development-tool setup such as Node/npm, R/RStudio, Python/Anaconda, Julia, LaTeX, Docker, Terraform, and Packer is untested. Installing prerequisites during baseline preparation is not a test of these repository installers.

- **macOS UI preferences and default-shell setup.** [os/os_x/set_preferences.sh](../os/os_x/set_preferences.sh), the Terminal profile, and [os/os_x/change_default_bash_version.sh](../os/os_x/change_default_bash_version.sh) are not exercised. There are no checks that Dock, Finder, keyboard, browser, or other GUI settings take effect, persist after logout/reboot, or match settings currently configured manually. Tests explicitly launch system Bash; they do not change the account's default shell or test a Homebrew Bash installation.

- **Linux desktop preferences and default applications.** [os/set_preferences.sh](../os/set_preferences.sh), [os/set_default_apps.sh](../os/set_default_apps.sh), and [mimeapps.list](../mimeapps.list) are not exercised. The suite does not start a desktop session or verify browser/file associations, themes, fonts, notifications, session startup, or compatibility of the older Ubuntu-specific preference commands with Debian Trixie.

- **Window managers, hotkeys, terminals, and desktop applications.** Relevant manifest entries for Yabai/skhd, i3, Kitty, Rofi, Polybar, Dunst, Picom/Compton, and autorandr are checked as links. The applications are not launched to parse those configurations, run bindings, arrange windows, render bars/menus, or verify accessibility permissions and supporting services. Rofi helper scripts are not invoked. A correctly linked configuration can still be invalid or unusable in its application.

- **Physical keyboard, display, and laptop integration.** [keyboard/keyboard_setup.sh](../keyboard/keyboard_setup.sh), [os/keyboard_startup.sh](../os/keyboard_startup.sh), keyd system configuration/reloading, monitor profiles, docking, brightness, and related utilities are not tested against actual devices. In particular, linking `~/.config/keyd` does not verify installation of `/etc/keyd/default.conf` or a working keyd service. The VMs do not establish that this setup works with the machine's keyboard, monitors, dock, or power-management behavior.

- **Editor and everyday application behavior.** Vim/gVim configuration files are linked, but Vim is not started and its settings, plugins, mappings, and plugin installation are not tested. Emacs installation and the desktop/client launchers are not exercised. There is no dedicated functional coverage of Git aliases, identity/signing, ignore/attribute behavior, curl settings, Readline key bindings, or Screen configuration. Git's use in bootstrap tests covers those specific checkout operations, not the rest of the Git configuration.

- **Shell features beyond startup.** Most aliases and functions in [shell/bash_aliases](../shell/bash_aliases) and [shell/bash_functions](../shell/bash_functions) are parsed or sourced but not invoked. Prompt rendering and Git-status display, completion, history/readline behavior, individual exports, macOS application aliases, logout behavior, and user-specific `~/.bash.local` customization have no dedicated behavioral tests. Optional applications being absent during startup does not prove the corresponding helpers work once those applications are installed.

- **Personal command-line utilities and external integrations.** The actual tools in [bin](../bin), including repository checking, Emacs launching, calendar synchronization, compression/content inspection, and photo processing, are not executed. The shell test uses a disposable probe command to check PATH loading. It does not exercise those utilities' logic, bundled binaries, dependencies, network services, or authenticated accounts.

- **Backup and restore of personal data.** [bin/backup](../bin/backup) and [os/install_duplicity.sh](../os/install_duplicity.sh) have no functional tests for encryption, signing, cloud uploads, retention, notifications, or restoring data. The `dotfiles / install` backup cases only check preservation of conflicting configuration during link installation; they do not validate this separate personal-data backup workflow.

- **System services, networking, and security-device setup.** SSH server/firewall configuration, VPN and DNS settings, YubiKey/GPG integration, mail synchronization, and server applications such as Airsonic are not provisioned or validated through the repository's scripts. No tests establish their service startup, permissions, authentication, persistence after reboot, or behavior on a real network. Test-runner SSH access to a disposable guest is separate from testing [os/server_ssh_setup.sh](../os/server_ssh_setup.sh).

- **Published bootstrap and first-time provisioning.** Routine suites use the local HTTP fixture and prepared accounts with prerequisite tools already installed. They do not validate the live GitHub/raw download URLs, public HTTPS/DNS behavior, private-repository credentials, or the complete path from an untouched OS image through prerequisite installation to a ready personal machine. Baseline preparation is a separate setup operation, not repeated by each full suite. Compromise of a downloaded package or image is not something a passing functional suite rules out.

- **Installer recovery, upgrades, and less common Git arrangements.** Existing cases cover selected conflicts and failures, not interrupted installs, full disks, permission failures during backup moves, concurrent installs, or restoring an old configuration from backups. There is no complete valid branch/tag/commit-ref matrix or coverage of every worktree/submodule arrangement. Removing obsolete links, migrating between manifest versions, uninstalling, and historical update/directory-setup utilities such as [os/update_content.sh](../os/update_content.sh) and [os/create_directories.sh](../os/create_directories.sh) are outside the current tests.

- **Other platforms, releases, and CI environments.** The automated VM coverage is the pinned macOS 26 ARM64 and Debian Trixie ARM64 baselines. There is no corresponding matrix for Intel Macs, x86 Debian, older/newer OS releases, Ubuntu, alternative default shells, or different personal machine states. GitHub Actions execution is not configured or tested. A successful local run also does not exhaustively test guest preparation, real transport failures, host crashes, or VM recovery.
