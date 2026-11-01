#!/usr/bin/env python3
"""Host-only tests: hash inert fixtures and inspect a temporary Git index."""

import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('ui_build_check', Path(__file__).with_name('check-ui-build.py'))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class BuildCheckTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.source = self.root / 'ui/example.go'
        self.source.parent.mkdir()
        self.source.write_text('inert source fixture')
        (self.source.parent / 'go.mod').write_text('module example.invalid/fixture')
        (self.source.parent / 'go.sum').write_text('fixture module checksums')
        self.binary = self.root / checker.BINARY_DIRECTORY / 'installer-ui_example_cpu'
        self.binary.parent.mkdir(parents=True)
        self.binary.write_bytes(b'inert binary fixture; never executed')
        self.binary.chmod(0o755)
        self.manifest = self.root / checker.MANIFEST
        self.manifest.write_text(json.dumps({
            'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in self.source.parent.iterdir()},
            'sha256': {self.binary.name: hashlib.sha256(self.binary.read_bytes()).hexdigest()},
        }))
        self.git('add', '.')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.STDOUT)

    def test_unchanged_build_and_unstaged_edits(self):
        checker.check(self.root)
        checker.check(self.root, staged=True)
        self.source.write_text('unstaged change')
        checker.check(self.root, staged=True)
        with self.assertRaisesRegex(ValueError, 'source differs'):
            checker.check(self.root)
        # Staged validation must never write or stage any content.
        before = self.git('ls-files', '--stage')
        self.git('add', 'ui/example.go')
        with self.assertRaisesRegex(ValueError, 'source differs'):
            checker.check(self.root, staged=True)
        self.assertNotEqual(before, self.git('ls-files', '--stage'))
        after = self.git('ls-files', '--stage')
        with self.assertRaises(ValueError):
            checker.check(self.root, staged=True)
        self.assertEqual(after, self.git('ls-files', '--stage'))

    def test_added_and_deleted_sources(self):
        extra = self.source.parent / 'new.go'
        extra.write_text('new source')
        self.git('add', '.')
        with self.assertRaisesRegex(ValueError, 'source differs'):
            checker.check(self.root, staged=True)
        extra.unlink()
        self.source.unlink()
        self.git('add', '-A')
        with self.assertRaisesRegex(ValueError, 'source differs'):
            checker.check(self.root, staged=True)

    def test_binary_corruption_and_missing_manifest(self):
        self.binary.write_bytes(b'changed executable')
        self.git('add', '.')
        with self.assertRaisesRegex(ValueError, 'binaries differ'):
            checker.check(self.root, staged=True)
        self.manifest.unlink()
        self.git('add', '-A')
        with self.assertRaisesRegex(ValueError, 'Missing'):
            checker.check(self.root, staged=True)

    def test_commit_without_any_ui_is_allowed(self):
        self.git('rm', '-r', '--cached', '.')
        checker.check(self.root, staged=True)


if __name__ == '__main__':
    unittest.main()
