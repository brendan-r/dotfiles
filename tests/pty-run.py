#!/usr/bin/env python3
"""Guest-only terminal for a shell check; preserve the child's exit status."""
import errno
import os
from pathlib import Path
import pty
import sys

if not Path('/etc/dotfiles-test-image').is_file():
    sys.exit('Run this through tests/run in a disposable VM.')
if len(sys.argv) < 2:
    sys.exit('A command is required.')

pid, master = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])

captured = bytearray()
try:
    while True:
        try:
            data = os.read(master, 65536)
        except OSError as exc:
            if exc.errno != errno.EIO:
                raise
            break
        if not data:
            break
        captured.extend(data)
finally:
    os.close(master)
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(captured.replace(b'\r\n', b'\n'))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128 + os.WTERMSIG(status))
