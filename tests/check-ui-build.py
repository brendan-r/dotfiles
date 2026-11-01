#!/usr/bin/env python3
"""Compare UI sources/binaries with their build manifest; never execute them."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


MANIFEST = 'os/vendor/installer-ui/BUILD.json'
BINARY_DIRECTORY = 'os/vendor/installer-ui/'
REBUILD = 'python3 ui/build.py /absolute/path/to/go os/vendor/installer-ui'


def relevant(path):
    return (path == MANIFEST or
            path in ('ui/go.mod', 'ui/go.sum') or
            (path.startswith('ui/') and path.endswith('.go')) or
            (path.startswith(BINARY_DIRECTORY + 'installer-ui_') and
             '/' not in path[len(BINARY_DIRECTORY):]))


def index_files(root):
    """Read blobs from the index, including when an alternate index is in use."""
    listing = subprocess.check_output(
        ['git', '-C', str(root), 'ls-files', '--stage', '-z', '--', 'ui', BINARY_DIRECTORY])
    entries = []
    for entry in listing.split(b'\0'):
        if not entry:
            continue
        metadata, name = entry.split(b'\t', 1)
        path = name.decode('utf-8')
        if not relevant(path):
            continue
        mode, oid, stage = metadata.decode().split()
        if stage != '0':
            raise ValueError(f'Resolve the staged conflict first: {path}')
        if mode not in ('100644', '100755'):
            raise ValueError(f'Expected a regular staged file: {path}')
        entries.append((path, mode, oid))

    # One Git process reads all blobs; no checkout, filters, hooks or compilation.
    data = subprocess.check_output(
        ['git', '-C', str(root), 'cat-file', '--batch'],
        input=''.join(oid + '\n' for _, _, oid in entries).encode())
    files, offset = {}, 0
    for path, mode, _oid in entries:
        end = data.index(b'\n', offset)
        _hash, kind, size = data[offset:end].split()
        if kind != b'blob':
            raise ValueError(f'Expected a Git blob: {path}')
        start, size = end + 1, int(size)
        files[path] = (data[start:start + size], mode == '100755')
        offset = start + size + 1
    return files


def working_files(root):
    files = {}
    paths = [*root.joinpath('ui').rglob('*.go'), root / 'ui/go.mod',
             root / 'ui/go.sum', root / MANIFEST,
             *root.joinpath(BINARY_DIRECTORY).glob('installer-ui_*')]
    for path in paths:
        if path.is_symlink():
            raise ValueError(f'Expected a regular file: {path}')
        if path.is_file():
            files[path.relative_to(root).as_posix()] = (
                path.read_bytes(), bool(path.stat().st_mode & 0o111))
    return files


def check(root, staged=False):
    files = index_files(root) if staged else working_files(root)
    # Older commits may contain no UI at all (e.g. an independent archive commit).
    if staged and not files:
        return
    if MANIFEST not in files:
        raise ValueError(f'Missing {MANIFEST}')
    manifest = json.loads(files[MANIFEST][0])
    if not isinstance(manifest, dict):
        raise ValueError('Expected a JSON object in the UI build manifest')
    sources = {path[3:]: hashlib.sha256(data).hexdigest()
               for path, (data, _) in files.items() if path.startswith('ui/')}
    if not {'go.mod', 'go.sum'} <= sources.keys():
        raise ValueError('UI module files are missing')
    if sources != manifest.get('source_sha256'):
        raise ValueError('UI source differs from the build manifest (including added/deleted files)')
    binaries = {path[len(BINARY_DIRECTORY):]: hashlib.sha256(data).hexdigest()
                for path, (data, _) in files.items()
                if path.startswith(BINARY_DIRECTORY) and path != MANIFEST}
    if not binaries or binaries != manifest.get('sha256'):
        raise ValueError('UI binaries differ from the build manifest or are missing')
    for name in binaries:
        if not files[BINARY_DIRECTORY + name][1]:
            raise ValueError(f'UI binary is not executable: {name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true', help='Check index contents, not working files')
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        check(args.root.resolve(), args.staged)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'UI build check failed: {error}', file=sys.stderr)
        print(f'Rebuild explicitly:\n  {REBUILD}', file=sys.stderr)
        if args.staged:
            print('Then stage the matching UI source, binaries and BUILD.json.\n'
                  'Unstaged edits are deliberately excluded from this check.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
