"""Behavioral tests. All servers belong to this suite; never use a default socket.

Run on each available target OS:
  python3 -m unittest discover -s scripts -p 'test_*.py' -v
Set EMACS_TEST_EXECUTABLE to exercise a different Emacs version/build.
"""
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import emacs_config as ec

EMACS = os.environ.get("EMACS_TEST_EXECUTABLE") or shutil.which("emacs")


class PureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="emacs helper tests ")
        self.root = Path(self.temp.name).resolve()

    def tearDown(self):
        self.temp.cleanup()

    def test_xdg_and_legacy_discovery_ambiguity(self):
        home = self.root / "home"
        home.mkdir()
        xdg = self.root / "xdg"
        (xdg / "emacs").mkdir(parents=True)
        (xdg / "emacs/init.el").write_text(";; config\n")
        self.assertEqual(ec.discover(home, str(xdg)), [xdg / "emacs"])
        (home / ".emacs").write_text(";; legacy\n")
        self.assertEqual(len(ec.discover(home, str(xdg))), 2)

    def test_copy_materializes_internal_links_and_rejects_escape(self):
        source = self.root / "source"
        source.mkdir()
        (source / "a.el").write_text("original")
        (source / "b.el").symlink_to("a.el")
        ec.copy_tree(source, self.root / "copy")
        self.assertFalse((self.root / "copy/b.el").is_symlink())
        (self.root / "copy/a.el").write_text("changed")
        self.assertEqual((source / "a.el").read_text(), "original")
        (source / "escape").symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "External"):
            ec.copy_tree(source, self.root / "rejected")
        ec.copy_tree(source, self.root / "excluded", ["escape"])
        self.assertFalse((self.root / "excluded/escape").exists())

    def test_copy_rejects_link_cycles(self):
        source = self.root / "source"
        source.mkdir()
        (source / "loop").symlink_to(source)
        with self.assertRaisesRegex(ValueError, "Cyclic"):
            ec.copy_tree(source, self.root / "copy")

    def test_child_environment_does_not_mutate_parent(self):
        with mock.patch.dict(os.environ, {"EMACS_SOCKET_NAME": "/real/socket",
                                         "EMACS_SERVER_FILE": "/real/auth",
                                         "HOME": "/real/home"}):
            env = ec.child_environment(self.root / "run", self.root / "socket")
            self.assertEqual(os.environ["HOME"], "/real/home")
            self.assertEqual(os.environ["EMACS_SOCKET_NAME"], "/real/socket")
            self.assertNotIn("EMACS_SERVER_FILE", env)
            self.assertEqual(env["EMACS_SOCKET_NAME"], str(self.root / "socket/test"))
            for key in ("HOME", "TMPDIR", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
                self.assertTrue(ec.inside(Path(env[key]), self.root))

    def test_bundle_defaults_follow_selected_executable_symlink(self):
        contents = self.root / "Selected Emacs.app/Contents"
        binary = contents / "MacOS/bin/emacs"
        binary.parent.mkdir(parents=True)
        binary.touch()
        defaults = {"LIBRARY_PATH": "/build/gcc/lib"}
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump({"LSEnvironment": defaults}, stream)
        link = self.root / "emacs"
        link.symlink_to(binary)
        with mock.patch.object(sys, "platform", "darwin"):
            bundle = ec.bundle_environment(link)
        self.assertEqual(bundle["defaults"], defaults)
        self.assertEqual(bundle["plist"], str(contents / "Info.plist"))
        with mock.patch.object(sys, "platform", "linux"):
            self.assertIsNone(ec.bundle_environment(link))

    def test_bundle_defaults_preserve_overrides_and_isolation(self):
        bundle = {"defaults": {"LIBRARY_PATH": "/bundle/lib", "HOME": "/bundle/home",
                               "EMACS_SERVER_FILE": "/bundle/server",
                               "EMACS_SOCKET_NAME": "/bundle/socket"}}
        with mock.patch.dict(os.environ, {}, clear=True):
            env = ec.child_environment(self.root / "run", self.root / "socket", bundle)
            self.assertEqual(env["LIBRARY_PATH"], "/bundle/lib")
            self.assertEqual(env["HOME"], str(self.root / "run/home"))
            self.assertNotIn("EMACS_SERVER_FILE", env)
            self.assertEqual(env["EMACS_SOCKET_NAME"], str(self.root / "socket/test"))
            self.assertNotIn("LIBRARY_PATH", os.environ)
        with mock.patch.dict(os.environ, {"LIBRARY_PATH": "/explicit/lib"}):
            env = ec.child_environment(self.root / "second", self.root / "socket", bundle)
            self.assertEqual(env["LIBRARY_PATH"], "/explicit/lib:/bundle/lib")
        with mock.patch.dict(os.environ, {"LIBRARY_PATH": ""}, clear=True):
            env = ec.child_environment(self.root / "third", self.root / "socket", bundle)
            self.assertEqual(env["LIBRARY_PATH"], "")

    def test_gui_requires_approval_before_any_launch(self):
        with self.assertRaisesRegex(ValueError, "approved"):
            ec.gui(ec.parser().parse_args(["gui", "/nonexistent"]))

    def test_live_load_requires_approval_before_any_connection(self):
        with self.assertRaisesRegex(ValueError, "approved"):
            ec.live_load(ec.parser().parse_args(["live-load", "/nonexistent", "--socket",
                                                 "/real/socket", "--expect-pid", "1",
                                                 "--file", "/file.el"]))


@unittest.skipUnless(EMACS, "Emacs executable unavailable")
class EmacsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="emacs integration ")
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / "original config"
        self.source.mkdir()
        (self.source / "early-init.el").write_text(
            ";;; early-init.el -*- lexical-binding: t; -*-\n"
            "(setq ec-order '(early))\n")
        (self.source / "init.el").write_text(
            "(setq ec-order (append ec-order '(init)))\n"
            "(add-hook 'after-init-hook (lambda () (setq ec-after t)))\n"
            "(add-hook 'emacs-startup-hook (lambda () (setq ec-started t)))\n"
            "(with-temp-file (expand-file-name \"custom.el\" user-emacs-directory)\n"
            "  (insert \";; private state\\n\"))\n"
            "(server-start)\n")
        self.session = self.prepare()

    def tearDown(self):
        # Remove short socket directories too, even after a failed assertion.
        for file in self.root.rglob("session.json"):
            try:
                data = json.loads(file.read_text())
                for record in data["runs"]:
                    directory = Path(record["socket_dir"])
                    marker = directory / ".emacs-config-owner"
                    if marker.exists() and marker.read_text() == data["id"]:
                        shutil.rmtree(str(directory))
            except (OSError, ValueError):
                pass
        self.temp.cleanup()

    def cli(self, *args, code=0):
        result = subprocess.run([sys.executable, str(ec.HERE / "emacs_config.py")] +
                                list(map(str, args)), capture_output=True, text=True, timeout=45)
        if code is not None:
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def prepare(self, *extra, source=None):
        result = self.cli("prepare", "--source", source or self.source,
                          "--emacs", EMACS, "--temp-root", self.root, *extra)
        return Path(json.loads(result.stdout)["session"])

    def run_test(self, *extra, code=0, session=None):
        result = self.cli("test", session or self.session, *extra, code=code)
        report = json.loads(result.stdout)
        return report, Path(report["log"]).read_text()

    def test_full_baseline_state_and_startup_hooks(self):
        original = ec.source_files(self.source)
        ert = self.session / "tests/private.el"
        ert.write_text(
            "(require 'ert)\n"
            "(ert-deftest private-state ()\n"
            " (should (equal ec-order '(early init)))\n"
            " (should ec-after) (should ec-started)\n"
            " (should (file-in-directory-p user-emacs-directory (getenv \"EC_RUN\")))\n"
            " (should (equal (expand-file-name \"~/\") (file-name-as-directory (getenv \"HOME\"))))\n"
            " (should (equal (getenv \"EMACS_SOCKET_NAME\") (expand-file-name server-name server-socket-dir)))\n"
            " (should (file-in-directory-p package-user-dir (getenv \"EC_RUN\"))))\n")
        report, log = self.run_test("--baseline", "--ert", ert)
        self.assertIn("1 results as expected", log)
        self.assertEqual(ec.source_files(self.source), original)
        self.assertFalse((self.session / "baseline/custom.el").exists())
        self.assertFalse((self.session / "candidate/custom.el").exists())
        self.assertTrue((Path(report["run"]) / "home/.emacs.d/custom.el").exists())
        self.assertEqual(self.session.stat().st_mode & 0o777, 0o700)

    def test_each_run_has_distinct_pid_home_and_socket(self):
        first, _ = self.run_test()
        second, _ = self.run_test()
        self.assertNotEqual(first["run"], second["run"])
        data = json.loads((self.session / "session.json").read_text())
        self.assertNotEqual(data["runs"][0]["socket_dir"], data["runs"][1]["socket_dir"])
        self.assertTrue(all(len(os.fsencode(Path(r["socket_dir"]) / "test")) < 100
                            for r in data["runs"]))

    def test_error_and_ert_failure_propagate(self):
        (self.session / "candidate/init.el").write_text('(error "baseline-independent failure")')
        report, log = self.run_test(code=255)
        self.assertIn("baseline-independent failure", log)
        self.run_test("--baseline")
        ert = self.session / "tests/failing.el"
        ert.write_text("(require 'ert) (ert-deftest fails () (should nil))")
        report, log = self.run_test("--minimal", "--ert", ert, code=1)
        self.assertIn("1 unexpected results", log)

    def test_minimal_skips_bad_init(self):
        (self.session / "candidate/init.el").write_text('(error "do not load")')
        activation = self.session / "activation.el"
        activation.write_text('(princ "minimal feature loaded")')
        report, log = self.run_test("--minimal", "--load", activation)
        self.assertIn("minimal feature loaded", log)

    def test_fixtures_are_private(self):
        session = self.prepare("--fixture-dir", "Nextcloud/org/career")
        (session / "candidate/init.el").write_text(
            '(unless (file-directory-p "~/Nextcloud/org/career") (error "missing fixture"))')
        self.run_test(session=session)
        self.assertFalse((self.root / "Nextcloud").exists())

    def test_xdg_config_paths_resolve_to_the_private_copy(self):
        home = self.root / "xdg home"
        config = home / ".config/emacs"
        config.mkdir(parents=True)
        (config / "init.el").write_text(
            '(unless (file-equal-p (expand-file-name "emacs/init.el" (getenv "XDG_CONFIG_HOME")) '
            'user-init-file) (error "XDG config escaped private copy"))')
        session = self.prepare(source=config)
        self.run_test(session=session)

    def test_stale_bytecode_does_not_mask_source(self):
        (self.session / "candidate/init.elc").write_text("invalid bytecode")
        self.run_test()

    def test_directory_spelling_preserves_builtin_library_precedence(self):
        config = self.session / "candidate"
        (config / "lisp").mkdir()
        (config / "lisp/ec-helper.el").write_text("(provide 'ec-helper)")
        grammars = config / "extras/grammars/bin"
        grammars.mkdir(parents=True)
        # A colliding library in a recursively added directory must remain
        # behind the builtin, just as with normal ~/.emacs.d/ startup.
        (grammars / "diff.el").write_text('(error "Loaded grammar instead of builtin")')
        (config / "init.el").write_text('''
(let ((default-directory "~/.emacs.d/"))
  (normal-top-level-add-subdirs-to-load-path))
(let ((default-directory (concat user-emacs-directory "lisp/")))
  (setq load-path
        (append
         (let ((load-path (copy-sequence load-path)))
           (append
            (copy-sequence (normal-top-level-add-to-load-path '(".")))
            (normal-top-level-add-subdirs-to-load-path)))
         load-path)))
(unless (member (expand-file-name "extras/grammars/bin" user-emacs-directory) load-path)
  (error "Regression fixture was not on load-path"))
(require 'ec-helper)
(require 'diff)
(when (file-in-directory-p (locate-library "diff") user-emacs-directory)
  (error "Private grammar library shadows builtin"))
''')
        self.run_test()

    @unittest.skipUnless(sys.platform == "darwin", "macOS app launch environment")
    def test_bundle_environment_reaches_emacs_and_can_be_disabled(self):
        contents = self.root / "Test Emacs.app/Contents"
        binary = contents / "MacOS/Emacs"
        binary.parent.mkdir(parents=True)
        binary.write_text('#!/bin/sh\nexec %s "$@"\n' % shlex.quote(EMACS))
        binary.chmod(0o700)
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump({"LSEnvironment": {"EC_BUNDLE_TEST": "from-selected-app"}}, stream)
        for extra in ([], ["--no-bundle-env"]):
            session = self.prepare("--emacs", binary, *extra)
            metadata = json.loads((session / "session.json").read_text())
            self.assertEqual(metadata["bundle_environment"] is None, bool(extra))
            expected = 'nil' if extra else '"from-selected-app"'
            (session / "candidate/init.el").write_text(
                '(unless (equal (getenv "EC_BUNDLE_TEST") %s) (error "Wrong launch environment"))'
                % expected)
            with mock.patch.dict(os.environ):
                os.environ.pop("EC_BUNDLE_TEST", None)
                self.run_test(session=session)

    def test_diff_detects_concurrent_original_edit(self):
        (self.session / "candidate/init.el").write_text(";; proposed\n")
        result = self.cli("diff", self.session, "--check-source")
        self.assertIn("+;; proposed", result.stdout)
        (self.source / "init.el").write_text(";; user edited meanwhile\n")
        result = self.cli("diff", self.session, "--check-source", code=2)
        self.assertIn("Concurrent original edits", result.stderr)
        self.assertIn("user edited meanwhile", (self.source / "init.el").read_text())

    def test_legacy_source_maps_diff_to_legacy_init(self):
        home = self.root / "legacy home"
        home.mkdir()
        legacy = home / ".emacs"
        legacy.write_text(";; legacy\n")
        session = self.prepare(source=legacy)
        self.run_test(session=session)
        (session / "candidate/init.el").write_text(";; changed legacy\n")
        self.cli("diff", session, "--check-source")
        legacy.write_text(";; concurrent\n")
        self.cli("diff", session, "--check-source", code=2)

    def test_timeout_terminates_only_spawned_process_group(self):
        (self.session / "candidate/init.el").write_text(
            '(let ((p (start-process "child" nil "sleep" "60")))\n'
            ' (with-temp-file (expand-file-name "child-pid" (getenv "EC_RUN"))\n'
            '  (insert (number-to-string (process-id p)))))\n'
            '(sleep-for 60)')
        report, log = self.run_test("--timeout", "1", code=124)
        self.assertTrue(report["timeout"])
        pid = (Path(report["run"]) / "child-pid").read_text()
        status = subprocess.run(["ps", "-p", pid, "-o", "stat="], capture_output=True, text=True)
        self.assertTrue(not status.stdout.strip() or status.stdout.strip().startswith("Z"))

    def test_clean_refuses_active_pid_and_removes_owned_sockets(self):
        self.run_test()
        metadata = self.session / "session.json"
        data = json.loads(metadata.read_text())
        data["runs"][0]["pid"] = os.getpid()
        ec.save_json(metadata, data)
        self.cli("clean", self.session, code=2)
        self.assertTrue(self.session.exists())
        data["runs"][0]["pid"] = None
        ec.save_json(metadata, data)
        sockets = [Path(r["socket_dir"]) for r in data["runs"]]
        self.cli("clean", self.session)
        self.assertFalse(self.session.exists())
        self.assertTrue(all(not p.exists() for p in sockets))

    def test_debian_missing_display_is_actionable_without_launch(self):
        args = ec.parser().parse_args(["gui", str(self.session), "--approved"])
        with mock.patch.object(sys, "platform", "linux"), mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "DISPLAY"):
                ec.gui(args)
        data = json.loads((self.session / "session.json").read_text())
        self.assertEqual(data["runs"], [])

    def test_live_load_uses_explicit_server_and_checks_pid(self):
        root, data = ec.get_session(self.session)
        run, env, record = ec.make_run(root, data)
        command = [EMACS, "-Q", "--batch", "--load", str(ec.BOOTSTRAP), "--eval",
                   '(progn (emacs-config-isolate) (server-start) '
                   '(while t (accept-process-output nil 0.1)))']
        with (run / "server.log").open("w") as output:
            proc = subprocess.Popen(command, env=env, cwd=str(run / "work"),
                                    stdout=output, stderr=output, start_new_session=True)
            try:
                socket = Path(env["EMACS_SOCKET_NAME"])
                for _ in range(100):
                    if socket.exists() or proc.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertTrue(socket.exists(), (run / "server.log").read_text())
                activation = self.session / "activation.el"
                marker = run / "activated"
                activation.write_text('(with-temp-file %s (insert "approved feature"))' % ec.lisp_string(marker))
                common = ("live-load", self.session, "--approved", "--socket", socket,
                          "--file", activation)
                result = self.cli(*common, "--expect-pid", str(proc.pid + 100000), code=None)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(marker.exists())
                self.cli(*common, "--expect-pid", str(proc.pid))
                self.assertEqual(marker.read_text(), "approved feature")
                self.cli("clean", self.session, code=2)
            finally:
                ec.kill_group(proc)
        self.cli("clean", self.session, "--release-live-files")

    def test_normal_startup_wrapper_in_disposable_daemon(self):
        root, data = ec.get_session(self.session)
        run, env, record = ec.make_run(root, data)
        # No comment header: isolation must run BEFORE the very first user form.
        early = run / "home/.emacs.d/early-init.el"
        early.write_text('(unless (and (boundp \'server-socket-dir) '
                         '(equal (directory-file-name server-socket-dir) (getenv "EC_SOCKET_DIR"))) '
                         '(error "Isolation did not precede early-init"))\n' + early.read_text())
        ec.write_gui_early(run)
        init = run / "home/.emacs.d/init.el"
        with init.open("a") as stream:
            stream.write('\n(add-hook \'emacs-startup-hook (lambda () '
                         '(with-temp-file (expand-file-name "startup-proof" (getenv "EC_RUN")) '
                         '(prin1 (list ec-order ec-after (expand-file-name user-emacs-directory) server-socket-dir) (current-buffer)))))\n')
        # Daemon startup exercises normal early/init/hook ordering without opening
        # a GUI or depending on DISPLAY; it does not prove graphical behavior.
        with (run / "startup.log").open("w") as output:
            proc = subprocess.Popen([EMACS, "--no-site-file", "--no-site-lisp", "--fg-daemon"],
                                    env=env, cwd=str(run / "work"), stdout=output,
                                    stderr=output, start_new_session=True)
            try:
                proof = run / "startup-proof"
                for _ in range(100):
                    if proof.exists() or proc.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertTrue(proof.exists(), (run / "startup.log").read_text())
                text = proof.read_text()
                self.assertIn("((early init) t", text)
                self.assertIn(str(run / "home/.emacs.d"), text)
                self.assertIn(env["EC_SOCKET_DIR"], text)
            finally:
                ec.kill_group(proc)


if __name__ == "__main__":
    unittest.main()
