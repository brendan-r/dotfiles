#!/usr/bin/env python3
"""Build only: never execute candidate binaries on the host.

Usage: python3 build.py /absolute/path/to/go /absolute/output/directory
Unit-test executables are emitted beside release executables for VM execution.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

source = Path(__file__).resolve().parent
go = sys.argv[1]
output = Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
# Keep notices alongside the exact module versions used by this build.
modules = subprocess.check_output(
    [go, 'list', '-m', '-f', '{{.Path}}\t{{.Dir}}', 'all'], cwd=source, text=True,
)
for line in modules.splitlines():
    module, _, directory = line.partition('\t')
    if not directory or Path(directory) == source:
        continue
    for notice in Path(directory).glob('LICENSE*'):
        if notice.is_file():
            target = output / 'licenses' / module / notice.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(notice, target)
checksums = {}
for platform in ('darwin', 'linux'):
    for arch in ('arm64', 'amd64'):
        env = dict(os.environ, GOOS=platform, GOARCH=arch, CGO_ENABLED='0')
        binary = output / f'installer-ui_{platform}_{arch}'
        subprocess.run([go, 'build', '-mod=readonly', '-trimpath', '-buildvcs=false', '-ldflags=-s -w', '-o', str(binary), './cmd/installer-ui'], cwd=source, env=env, check=True)
        checksums[binary.name] = hashlib.sha256(binary.read_bytes()).hexdigest()
        subprocess.run([go, 'test', '-c', '-o', str(source / 'test-bin' / f'{platform}_{arch}.test'), '.'], cwd=source, env=env, check=True)
(output / 'BUILD.json').write_text(json.dumps({'toolchain': subprocess.check_output([go, 'version'], text=True).strip(), 'CGO_ENABLED': '0', 'flags': ['-trimpath', '-buildvcs=false', '-ldflags=-s -w'], 'modules': subprocess.check_output([go, 'list', '-m', 'all'], cwd=source, text=True).splitlines(), 'source_sha256': {str(path.relative_to(source)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted([*source.rglob('*.go'), source / 'go.mod', source / 'go.sum'])}, 'sha256': checksums}, indent=2) + '\n')
