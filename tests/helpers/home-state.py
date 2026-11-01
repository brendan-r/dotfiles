#!/usr/bin/env python3
"""Save/restore only installer-owned paths in the disposable account's real HOME."""
import json
import os
from pathlib import Path
import shutil
import sys
import subprocess

if not Path('/etc/dotfiles-test-image').is_file() or os.environ.get('DOTFILES_TEST_GUEST') != '1':
    sys.exit('Guest only')
action, home, state, root = sys.argv[1:]
home, state = Path(home), Path(state)

def copy(src, dst):
    if src.is_symlink():
        dst.symlink_to(os.readlink(src))
    elif src.is_dir():
        shutil.copytree(src, dst, symlinks=True)
    elif src.exists():
        shutil.copy2(src, dst)

if action == 'save':
    names = {'.local', 'projects'}
    mappings = subprocess.check_output(
        ['/bin/bash', str(Path(root) / 'os/catalog_links.sh'), root, 'all'], text=True)
    for row in mappings.splitlines():
        names.add(row.split('\t')[2].split('/')[0])
    if any(name in ('', '.', '..', '.ssh', 'Library') for name in names):
        sys.exit('Unexpected restore target')
    state.mkdir()
    (state / 'names.json').write_text(json.dumps(sorted(names)))
    for name in names:
        copy(home / name, state / name)
elif action == 'restore':
    for name in json.loads((state / 'names.json').read_text()):
        target = home / name
        if target.is_symlink() or target.is_file():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        copy(state / name, target)
else:
    sys.exit('Unknown action')
