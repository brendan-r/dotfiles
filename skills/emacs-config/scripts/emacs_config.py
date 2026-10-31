#!/usr/bin/env python3
"""Private Emacs configuration experiments on macOS and Debian (Python 3.8+).

Examples (run from the skill directory; substitute the printed SESSION path):
  python3 scripts/emacs_config.py prepare --source ~/.emacs.d
  python3 scripts/emacs_config.py test SESSION --baseline
  # Edit SESSION/candidate/init.el; write SESSION/tests/change-tests.el.
  python3 scripts/emacs_config.py test SESSION --ert SESSION/tests/change-tests.el
  python3 scripts/emacs_config.py test SESSION --minimal --load SESSION/activation.el
  python3 scripts/emacs_config.py diff SESSION --check-source
  # Only after the user chooses the corresponding action:
  python3 scripts/emacs_config.py gui SESSION --approved
  python3 scripts/emacs_config.py live-load SESSION --approved \
      --socket /explicit/existing/socket --expect-pid 1234 --file SESSION/activation.el
  python3 scripts/emacs_config.py clean SESSION

No command applies edits to the original config. Diff + separate user approval
is the handoff for a narrowly scoped permanent edit by the agent.
"""

import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid

HERE = Path(__file__).resolve().parent
BOOTSTRAP = HERE / "bootstrap.el"
FORMAT = 1
# Disposable state is not source. Package trees ARE copied, but not proposed as
# permanent source edits. Rebuild virtualenvs rather than copying host symlinks.
OMIT = {".git", "__pycache__", "auto-save-list", "eln-cache", "org-persist",
        "server", "history", "recentf", "tramp", "elfeed", "rpc-venv",
        "package-quickstart.el", "package-quickstart.elc"}
PACKAGE_DIRS = {"elpa", "straight", "elpaca"}
CONNECTION_ENV = {"EMACS_SOCKET_NAME", "EMACS_SERVER_FILE", "ALTERNATE_EDITOR",
                  "INSIDE_EMACS", "EMACSLOADPATH", "EMACSPATH", "EMACSDATA",
                  "EMACSDOC", "EMACS_USER_DIRECTORY"}


def fail(message):
    raise ValueError(message)


def inside(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def executable(value, default):
    found = shutil.which(value or default)
    if not found:
        fail("Executable not found: %s; supply an explicit path" % (value or default))
    return str(Path(found).absolute())


def bundle_environment(emacs):
    """Read GUI launch defaults from the selected macOS application bundle.

    Directly executing an app's binary bypasses Launch Services and its
    LSEnvironment, including native compiler paths supplied by some builds.
    Never guess a Homebrew version or contact a running Emacs to recover them.
    """
    if sys.platform != "darwin":
        return None
    for parent in Path(emacs).resolve().parents:
        if parent.suffix != ".app":
            continue
        plist = parent / "Contents/Info.plist"
        if not plist.is_file():
            return None
        with plist.open("rb") as stream:
            defaults = plistlib.load(stream).get("LSEnvironment", {})
        if not isinstance(defaults, dict) or any(
                not isinstance(k, str) or not isinstance(v, str) or
                not k or "=" in k or "\0" in k or "\0" in v
                for k, v in defaults.items()):
            fail("Invalid LSEnvironment in %s; use --no-bundle-env for CLI testing" % plist)
        return {"plist": str(plist), "defaults": defaults}
    return None


def discover(home, xdg=None):
    """List plausible sources; do not guess when multiple configurations exist."""
    candidates = []
    for path in (home / ".emacs", home / ".emacs.el", home / ".emacs.elc",
                 home / ".emacs.d", Path(xdg) / "emacs" if xdg else
                 home / ".config/emacs"):
        if path.exists() and (path.is_file() or (path / "init.el").exists()
                              or (path / "init.elc").exists()):
            if path.resolve() not in [p.resolve() for p in candidates]:
                candidates.append(path)
    return candidates


def source_layout(source):
    source = source.expanduser().absolute()
    if source.is_dir():
        if not (source / "init.el").is_file():
            fail("Source must contain init.el; compiled-only configs need their Lisp source")
        return source.resolve(), None
    if source.name == "init.el" and source.is_file():
        return source.parent.resolve(), None
    if source.name in (".emacs", ".emacs.el") and source.is_file():
        # Legacy init files can still use ~/.emacs.d for packages and support files.
        return (source.parent / ".emacs.d").resolve(), source.resolve()
    fail("Choose a config directory, init.el, .emacs, or .emacs.el source file")


def omitted(name):
    return name in OMIT or name.startswith(".#") or name.endswith("~") or (
        name.startswith("#") and name.endswith("#"))


def copy_tree(source, dest, exclude=(), root=None, ancestors=()):
    """Independent bytes; reject escaping/cyclic symlinks, skip special files.

    External links require a deliberate --exclude RELPATH and a private copy or
    fixture supplied by the agent. They are never silently retained or traversed.
    """
    root = root or source.resolve()
    resolved = source.resolve()
    if not inside(resolved, root):
        fail("External symlink: %s -> %s; exclude it and supply a private fixture" %
             (source, resolved))
    if resolved in ancestors:
        fail("Cyclic symlink: %s" % source)
    dest.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.iterdir()):
        relative = entry.relative_to(root).as_posix()
        if omitted(entry.name) or any(relative == e or relative.startswith(e + "/")
                                      for e in exclude):
            continue
        target = dest / entry.name
        if entry.is_symlink() and (not entry.exists() or not inside(entry, root)):
            fail("External or broken symlink: %s; use --exclude %s" % (entry, relative))
        if entry.is_dir():
            copy_tree(entry, target, exclude, root, ancestors + (resolved,))
        elif entry.is_file():
            shutil.copy2(str(entry), str(target))
        # Sockets, FIFOs and devices are runtime artifacts, never copied.


def source_files(root):
    result = {}
    for path in root.rglob("*"):
        rel = path.relative_to(root)
        if any(p in PACKAGE_DIRS or omitted(p) for p in rel.parts):
            continue
        if path.is_symlink():
            fail("Unexpected symlink in staged source: %s" % path)
        if path.is_file() and path.suffix not in (".elc", ".eln"):
            result[rel.as_posix()] = digest(path)
    return result


def get_session(value):
    root = Path(value).expanduser().resolve()
    metadata = root / "session.json"
    if not metadata.is_file() or root.is_symlink() or root.stat().st_uid != os.getuid():
        fail("Not an owned emacs-config session: %s" % root)
    data = json.loads(metadata.read_text())
    if data.get("format") != FORMAT or data.get("root") != str(root):
        fail("Session identity does not match this directory")
    return root, data


def prepare(args):
    choices = discover(Path.home(), os.environ.get("XDG_CONFIG_HOME"))
    if args.source:
        source = Path(args.source)
    elif len(choices) == 1:
        source = choices[0]
    else:
        fail("Specify --source; discovered: " + (", ".join(map(str, choices)) or "none"))
    config, legacy = source_layout(source)
    emacs = executable(args.emacs, "emacs")
    bundle = None if args.no_bundle_env else bundle_environment(emacs)
    version = subprocess.check_output([emacs, "--version"], text=True).splitlines()[0]
    match = re.search(r"Emacs (\d+)", version)
    if not match or int(match.group(1)) < 27:
        fail("Emacs 27 or newer required; found " + version)
    root = Path(tempfile.mkdtemp(prefix="emacs-config-", dir=args.temp_root)).resolve()
    try:
        if inside(root, config):
            fail("Temporary workspace must be outside the source configuration")
        baseline = root / "baseline"
        baseline.mkdir()
        if config.exists():
            copy_tree(config, baseline, args.exclude)
        if legacy:
            shutil.copy2(str(legacy), str(baseline / "init.el"))
        copy_tree(baseline, root / "candidate")
        for directory in ("tests", "logs", "runs", "fixtures/home"):
            (root / directory).mkdir(parents=True, exist_ok=True)
        for directory in args.fixture_dir:
            relative = Path(directory)
            if relative.is_absolute() or ".." in relative.parts or ".emacs.d" in relative.parts:
                fail("Fixture directory must be relative to private HOME, outside .emacs.d")
            (root / "fixtures/home" / relative).mkdir(parents=True, exist_ok=True)
        hashes = source_files(baseline)
        # Detect source edits during snapshot creation instead of calling it a baseline.
        for rel, sha in hashes.items():
            original = legacy if legacy and rel == "init.el" else config / rel
            if not original.is_file() or digest(original) != sha:
                fail("Source changed during snapshot: %s; prepare again" % original)
        data = {"format": FORMAT, "id": uuid.uuid4().hex, "root": str(root),
                "source": str(config), "legacy_init": str(legacy) if legacy else None,
                "emacs": emacs, "version": version, "hashes": hashes,
                "excluded": args.exclude, "bundle_environment": bundle,
                "runs": [], "live_loads": []}
        save_json(root / "session.json", data)
        print(json.dumps({"session": str(root), "candidate": str(root / "candidate"),
                          "version": version, "bundle_environment": bundle}, indent=2))
        return 0
    except BaseException:
        shutil.rmtree(str(root))
        raise


def child_environment(run, socket_dir, bundle=None):
    # Explicit caller settings win over bundle defaults.  Apply isolation last,
    # so neither source can redirect HOME, caches, or server connections.
    env = dict((bundle or {}).get("defaults", {}))
    env.update(os.environ)
    env = {k: v for k, v in env.items() if k not in CONNECTION_ENV}
    paths = {"HOME": run / "home", "XDG_CONFIG_HOME": run / "home/.config",
             "XDG_CACHE_HOME": run / "cache", "XDG_DATA_HOME": run / "data",
             "XDG_STATE_HOME": run / "state", "XDG_RUNTIME_DIR": run / "runtime",
             "TMPDIR": run / "tmp", "TMP": run / "tmp", "TEMP": run / "tmp"}
    for key, path in paths.items():
        path.mkdir(parents=True, exist_ok=True)
        env[key] = str(path)
    # Accidental subprocess emacsclient calls can reach only this test server.
    env.update(EC_RUN=str(run), EC_SOCKET_DIR=str(socket_dir),
               EMACS_SOCKET_NAME=str(socket_dir / "test"),
               ALTERNATE_EDITOR=executable(None, "false"),
               EDITOR=executable(None, "false"), VISUAL=executable(None, "false"))
    return env


def make_run(root, data, baseline=False):
    run = root / "runs" / (time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    run.mkdir()
    config = run / "home/.emacs.d"
    copy_tree(root / ("baseline" if baseline else "candidate"), config)
    # Stale compiled user Lisp must not mask edited source. Package bytecode stays.
    for path in config.rglob("*.elc"):
        if not any(part in PACKAGE_DIRS for part in path.relative_to(config).parts):
            path.unlink()
    fixtures = root / "fixtures/home"
    if any((fixtures / name).exists() for name in (".emacs.d", ".emacs", ".emacs.el", ".emacs.elc", ".config/emacs")):
        fail("Fixtures must not replace Emacs startup files")
    copy_tree(fixtures, run / "home")
    # Normalize startup to .emacs.d while supporting explicit XDG path references
    # in copied configs. This alias stays wholly inside the run's private home.
    (run / "home/.config").mkdir(exist_ok=True)
    (run / "home/.config/emacs").symlink_to("../.emacs.d", target_is_directory=True)
    for directory in ("work", "state/backups", "state/autosave"):
        (run / directory).mkdir(parents=True, exist_ok=True)
    socket_dir = run / "socket"
    if len(os.fsencode(socket_dir / "test")) >= 100:
        # AF_UNIX limits are especially short on macOS. Both target OSes have
        # /tmp; use a short, independently owned directory only when necessary.
        socket_dir = Path(tempfile.mkdtemp(prefix="ec-", dir="/tmp")).resolve()
    else:
        socket_dir.mkdir()
    (socket_dir / ".emacs-config-owner").write_text(data["id"])
    env = child_environment(run, socket_dir, data.get("bundle_environment"))
    record = {"path": str(run), "socket_dir": str(socket_dir), "pid": None}
    data["runs"].append(record)
    save_json(root / "session.json", data)
    return run, env, record


def kill_group(proc):
    # Every child is launched with start_new_session=True. Never pkill/killall,
    # never send signals to a PID supplied by a user or recovered from a file.
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    proc.wait()


def private_file(value, root):
    path = Path(value).expanduser().resolve()
    if not inside(path, root) or not path.is_file():
        fail("Use a regular file inside the session: %s" % value)
    return path


def test(args):
    root, data = get_session(args.session)
    loads = [private_file(p, root) for p in args.load]
    tests = [private_file(p, root) for p in args.ert]
    run, env, record = make_run(root, data, args.baseline)
    env["EC_MINIMAL"] = "1" if args.minimal else "0"
    command = [data["emacs"], "-Q", "--batch", "--load", str(BOOTSTRAP),
               "--funcall", "emacs-config-batch"]
    for path in loads + tests:
        command += ["--load", str(path)]
    if tests:
        command += ["--eval", "(require 'ert)", "--funcall", "ert-run-tests-batch-and-exit"]
    log = run / "output.log"
    started = time.monotonic()
    with log.open("w") as output:
        proc = subprocess.Popen(command, env=env, cwd=str(run / "work"),
                                stdin=subprocess.DEVNULL, stdout=output,
                                stderr=subprocess.STDOUT, start_new_session=True)
        record["pid"] = proc.pid
        save_json(root / "session.json", data)
        timed_out = False
        try:
            code = proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out, code = True, 124
        finally:
            kill_group(proc)
            record["pid"] = None
            save_json(root / "session.json", data)
    result = {"run": str(run), "log": str(log), "exit_code": code,
              "timeout": timed_out, "baseline": args.baseline, "minimal": args.minimal,
              "seconds": round(time.monotonic() - started, 2)}
    save_json(run / "result.json", result)
    print(json.dumps(result, indent=2))
    return code if code >= 0 else 1


def diff(args):
    root, data = get_session(args.session)
    before, after = data["hashes"], source_files(root / "candidate")
    conflicts = []
    for rel in sorted(set(before) | set(after)):
        if before.get(rel) == after.get(rel):
            continue
        if args.check_source:
            original = (Path(data["legacy_init"]) if data["legacy_init"] and rel == "init.el"
                        else Path(data["source"]) / rel)
            actual = digest(original) if original.is_file() else None
            if actual != before.get(rel):
                conflicts.append(str(original))
        old, new = root / "baseline" / rel, root / "candidate" / rel
        try:
            old_text = old.read_text().splitlines(keepends=True) if old.is_file() else []
            new_text = new.read_text().splitlines(keepends=True) if new.is_file() else []
            sys.stdout.writelines(difflib.unified_diff(old_text, new_text,
                                                      fromfile="baseline/" + rel,
                                                      tofile="candidate/" + rel))
        except UnicodeDecodeError:
            print("Binary file changed: " + rel)
    if conflicts:
        print("Concurrent original edits; do not overwrite:\n" + "\n".join(conflicts), file=sys.stderr)
        return 2
    return 0


def lisp_string(value):
    # JSON string escapes used here are also valid Elisp for filesystem paths.
    # Do not interpolate into shell code; all process calls use argument lists.
    return json.dumps(str(value), ensure_ascii=False)


def write_gui_early(run):
    early = run / "home/.emacs.d/early-init.el"
    original = early.read_text() if early.exists() else ""
    # Keep a first-line lexical-binding cookie at the top. The copied init.el is
    # untouched and startup uses HOME discovery, so Emacs 27 needs no new flags.
    first, _, rest = original.partition("\n")
    prefix = "(load %s nil nil t)\n(emacs-config-isolate)\n" % lisp_string(BOOTSTRAP)
    # Only a comment may precede isolation. A config can begin with executable
    # code (including a platform-specific conditional); never insert inside it.
    early.write_text((first + "\n" + prefix + rest) if first.lstrip().startswith(";")
                     else prefix + original + "\n")


def gui(args):
    if not args.approved:
        fail("gui requires --approved after the user chooses a new GUI process")
    root, data = get_session(args.session)
    if sys.platform != "darwin" and not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        fail("No DISPLAY or WAYLAND_DISPLAY; headless results remain available")
    run, env, record = make_run(root, data)
    probe = subprocess.run([data["emacs"], "-Q", "--batch", "--eval",
                            '(princ system-configuration-features)'], env=env,
                           cwd=str(run / "work"), capture_output=True, text=True, timeout=20)
    if probe.returncode or not re.search(r"\b(NS|X11|PGTK)\b", probe.stdout):
        fail("Selected Emacs lacks a supported GUI build; select a graphical executable")
    write_gui_early(run)
    with (run / "output.log").open("w") as log:
        proc = subprocess.Popen([data["emacs"], "--no-site-file", "--no-site-lisp",
                                 "--no-x-resources", "--debug-init"],
                                env=env, cwd=str(run / "work"), stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    record["pid"] = proc.pid
    record["gui"] = True
    save_json(root / "session.json", data)
    print(json.dumps({"pid": proc.pid, "run": str(run),
                      "note": "New process launched; inspect the GUI and log before claiming success."}, indent=2))
    return 0


def live_load(args):
    if not args.approved:
        fail("live-load requires --approved after approval of this activation file")
    root, data = get_session(args.session)
    path = private_file(args.file, root)
    if path.name in ("init.el", "early-init.el", "bootstrap.el"):
        fail("Use a narrowly scoped activation file, not a startup file")
    socket = Path(args.socket).expanduser()
    if not socket.is_absolute() or not stat.S_ISSOCK(socket.stat().st_mode):
        fail("Supply the absolute path of the selected existing Unix server socket")
    client = executable(args.emacsclient, "emacsclient")
    env = {k: v for k, v in os.environ.items() if k not in CONNECTION_ENV}
    # PID verification and activation occur in ONE evaluation on ONE connection.
    # A false alternate editor prevents an absent server from launching anything.
    form = '(if (= (emacs-pid) %d) (load %s nil nil t) (error "Wrong Emacs PID"))' % (
        args.expect_pid, lisp_string(path))
    data["live_loads"].append({"file": str(path), "sha256": digest(path),
                               "socket": str(socket), "pid": args.expect_pid,
                               "outcome": "attempted; retain files even if the client times out"})
    save_json(root / "session.json", data)
    try:
        result = subprocess.run([client, "--socket-name", str(socket),
                                 "--alternate-editor=" + executable(None, "false"),
                                 "--eval", form], env=env, capture_output=True,
                                text=True, timeout=args.timeout)
    except subprocess.TimeoutExpired:
        fail("Client timed out; activation may have run. Inspect the selected session before retrying")
    print(result.stdout, end="")
    print(result.stderr, end="", file=sys.stderr)
    data["live_loads"][-1]["outcome"] = "exit %d" % result.returncode
    save_json(root / "session.json", data)
    return result.returncode


def clean(args):
    root, data = get_session(args.session)
    if data["live_loads"] and not args.release_live_files:
        fail("Live-loaded files are retained; use --release-live-files only when no longer needed")
    for record in data["runs"]:
        if record.get("pid"):
            try:
                os.kill(record["pid"], 0)
            except ProcessLookupError:
                pass
            else:
                # Conservative even if a PID was reused: never kill from stale metadata.
                fail("Recorded process %s still exists; close the test Emacs before cleanup" % record["pid"])
    for record in data["runs"]:
        socket_dir = Path(record["socket_dir"])
        marker = socket_dir / ".emacs-config-owner"
        if socket_dir.exists() and not inside(socket_dir, root):
            if socket_dir.is_symlink() or not marker.is_file() or marker.read_text() != data["id"]:
                fail("Socket directory ownership mismatch: %s" % socket_dir)
            shutil.rmtree(str(socket_dir))
    shutil.rmtree(str(root))
    print("Removed session " + str(root))
    return 0


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = result.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare", help="copy current config and packages into a private session")
    p.add_argument("--source", help="config directory or legacy .emacs/.emacs.el file")
    p.add_argument("--emacs", help="executable path (default: emacs on PATH)")
    p.add_argument("--no-bundle-env", action="store_true",
                   help="omit macOS app LSEnvironment defaults to test a CLI launch")
    p.add_argument("--temp-root", help="parent for temporary sessions (default: OS temp directory)")
    p.add_argument("--exclude", action="append", default=[], metavar="RELPATH",
                   help="explicit source exclusions, e.g. an external symlink")
    p.add_argument("--fixture-dir", action="append", default=[], metavar="RELPATH",
                   help="empty directory relative to private HOME; repeat as needed")
    p.set_defaults(func=prepare)
    for name, function, help_text in (("test", test, "fresh batch smoke/ERT run"),
                                      ("diff", diff, "source diff; never applies it"),
                                      ("gui", gui, "approved new graphical process"),
                                      ("live-load", live_load, "approved activation in an explicit existing server"),
                                      ("clean", clean, "remove only an inactive owned session")):
        p = sub.add_parser(name, help=help_text)
        p.add_argument("session")
        p.set_defaults(func=function)
        if name == "test":
            p.add_argument("--baseline", action="store_true")
            p.add_argument("--minimal", action="store_true", help="skip user startup; explicitly --load dependencies")
            p.add_argument("--load", action="append", default=[], metavar="FILE")
            p.add_argument("--ert", action="append", default=[], metavar="FILE")
            p.add_argument("--timeout", type=float, default=120)
        elif name == "diff":
            p.add_argument("--check-source", action="store_true", help="fail if proposed targets changed since prepare")
        elif name in ("gui", "live-load"):
            p.add_argument("--approved", action="store_true", help="attest that the user approved this action")
            if name == "live-load":
                p.add_argument("--socket", required=True, help="absolute Unix socket; no default-server guessing")
                p.add_argument("--expect-pid", type=int, required=True)
                p.add_argument("--file", required=True, help="reviewed activation file inside SESSION")
                p.add_argument("--emacsclient")
                p.add_argument("--timeout", type=float, default=30)
        elif name == "clean":
            p.add_argument("--release-live-files", action="store_true")
    return result


def main():
    # Private directories/files, including package-manager subprocess outputs.
    os.umask(0o077)
    args = parser().parse_args()
    try:
        return args.func(args)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print("error: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
