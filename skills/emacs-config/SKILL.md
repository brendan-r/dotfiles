---
name: emacs-config
description: Edit and test Emacs configuration, Elisp, and packages in isolated processes on macOS or Debian, then optionally preview a GUI or live-load approved functionality.
---

# Emacs configuration

Use [the commented helper](scripts/emacs_config.py) and [bootstrap](scripts/bootstrap.el).
Requires Python 3.8+ and Emacs 27+. Run `python3 scripts/emacs_config.py --help`
from this skill directory; each subcommand has its own `--help`.

## Edit and test

1. Run `prepare`. It prints JSON with the session and editable `candidate` paths.
   Specify `--source` if discovery reports ambiguity; include uncommitted edits.
   Use `--fixture-dir Nextcloud/org/career` or files under `fixtures/home/` for
   required personal-data fixtures. Never symlink fixtures to live personal data.
   On macOS, `prepare` records the selected app bundle's `LSEnvironment` defaults
   for child processes (including compiler library paths). Caller variables take
   precedence; nonempty `LIBRARY_PATH` entries precede the bundle's entries so
   both compiler search paths remain available. Private HOME and socket settings always win.
   Use `--no-bundle-env` to test a CLI launch without those GUI defaults.
   Prepare a new session after changing the app build or its launch defaults.

2. Run `test SESSION --baseline` before editing. If startup fails, report the
   error and investigate the failing code. Make test-only adjustments in the
   private copy and record them alongside the test results. Do not audit the
   entire configuration or installed packages as a prerequisite to testing.
   Before attributing a failure to the config, check for test-environment
   differences: launch variables, fresh native caches, and library lookup order.
   The helper preserves normal `~/.emacs.d/` spelling because expanding it can
   change how configuration code builds `load-path`. Do not suppress compiler
   errors or remove package paths merely to make the test pass.

3. Edit only `SESSION/candidate/`; put ERT tests under `SESSION/tests/`.
   Run `test SESSION --ert TEST_FILE` after changes. Use `--minimal --load FILE`
   for focused tests without the full init.
   Each run has its own copied config, home, packages, caches, and server socket.

4. Inspect the logs, not just the exit code: packages can catch their own errors.
   Report baseline failures separately. Never hide them with blanket stubs.
   Package downloads, when requested by the copied configuration, stay in the
   run's package directory. Reuse deliberately installed packages by copying
   their directories from that run's
   `home/.emacs.d/elpa/` into `candidate/elpa/`, then test again.

5. Run `diff SESSION` and report the proposed change and test evidence. Batch
   checks do not prove GUI startup or interactive behavior. Test on both OSes
   when available; label a platform unverified when only mocked or untested.

A private home is not a security sandbox: Lisp can still access explicitly named
real files or services.

## After tests pass

Report the results. For testing-only requests, stop after reporting unless the
user requested GUI testing or activation. Do not offer to activate test-only
adjustments.

When implementing a requested configuration change, ask the user which action
they want (honor an explicit choice already made):

- Test it out in a GUI Emacs session in a new process.
- Live-load eligible new functionality into the current Emacs process.
- Do nothing for now.

For GUI testing, use `gui SESSION --approved`; never use a client of the user's
existing Emacs. For live-loading, prepare and review `SESSION/activation.el`
containing only the requested change, then use `live-load --help`. Select the
existing socket explicitly and verify its PID. Explain any restart-only change
instead of trying to reproduce early startup in a running session. Do not reload
the whole init file. Retain activation dependencies while they are in use.

Neither action authorizes permanent edits. Ask separately to apply the reviewed
source diff. Immediately before applying it, run `diff SESSION --check-source`;
resolve concurrent edits rather than overwriting them. Apply only approved source
changes, never copied package trees, fixtures, caches, or generated launchers.

Keep staged results until cleanup is requested; temporary storage may be cleared
by the OS. `clean SESSION` refuses active test processes and retained live-load
files. Use `--release-live-files` only after those files are no longer needed.
Never stop, restart, query, or mutate the user's Emacs during ordinary testing.

## Validate the helpers

Run `python3 -m unittest discover -s scripts -p 'test_*.py' -v`. Integration tests
use disposable Emacs processes and sockets; they never select the default server.
