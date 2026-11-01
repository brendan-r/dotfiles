#!/usr/bin/env python3
"""Guest-only installer UI smoke flows. Assert navigation/outcome, never screen layout."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

if not Path('/etc/dotfiles-test-image').is_file():
    sys.exit('VM only')

interrupt = len(sys.argv) > 2 and sys.argv[2] == "interrupt"
install = len(sys.argv) > 2 and sys.argv[2] == 'install'
partial = len(sys.argv) > 2 and sys.argv[2] == 'partial'
pid, terminal = pty.fork()
if pid == 0:
    os.environ['TERM'] = 'xterm-256color'
    args = ['/bin/bash', sys.argv[1] + '/dotfiles', 'install']
    if install or interrupt:
        args += ['--only', 'tools']
    os.execv('/bin/bash', args)

fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 35, 110, 0, 0))
captured = bytearray()
position = 0


def await_text(text):
    global position
    deadline = time.monotonic() + 30
    while text.encode() not in captured[position:]:
        if time.monotonic() > deadline:
            raise AssertionError('Timed out waiting for ' + text)
        if not select.select([terminal], [], [], 0.2)[0]:
            continue
        chunk = os.read(terminal, 65536)
        if not chunk:
            raise AssertionError('Terminal closed before ' + text)
        captured.extend(chunk)
        if b'\x1b[6n' in chunk:
            os.write(terminal, b'\x1b[1;1R')
    position = len(captured)


try:
    if install or interrupt:
        await_text('Space: toggle')
        os.write(terminal, b'\r')
        if install:
            await_text('Installer test prompt:')
            # Exercise a resize while a native prompt owns terminal input.
            fcntl.ioctl(terminal, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 70, 0, 0))
            os.write(terminal, b'test-password\r')
            await_text('Prompt accepted.')
        if interrupt:
            deadline = time.monotonic() + 20
            running = Path(os.environ['DOTFILES_FAKE_PACKAGES']) / 'running'
            while not running.exists():
                if time.monotonic() > deadline:
                    raise AssertionError('Worker did not start')
                if select.select([terminal], [], [], .1)[0]:
                    captured.extend(os.read(terminal, 65536))
            os.write(terminal, b'\x03')
        await_text('Happy Hacking!')
        os.write(terminal, b'\x1b[6~\x1b[H\t\x1b[B\t\r')
    elif partial:
        await_text('Space: toggle')
        os.write(terminal, b'cx\r')
        await_text('Happy Hacking!')
        os.write(terminal, b'\x1b[6~\x1b[H\t\x1b[B\t\r')
    else:
        await_text('Space: toggle')
        # Selection is on the first screen. Exercise toggling and cancellation.
        os.write(terminal, b'x\x1b')

    deadline = time.monotonic() + 10
    while True:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            assert os.waitstatus_to_exitcode(status) == (130 if interrupt else 0)
            break
        if time.monotonic() > deadline:
            raise AssertionError('Menu did not exit')
        # Drain final output while waiting. Darwin's small PTY buffer can block
        # the child in its final summary if the reader only calls waitpid here.
        if select.select([terminal], [], [], 0.05)[0]:
            try:
                captured.extend(os.read(terminal, 65536))
            except OSError as exc:
                if exc.errno != errno.EIO:
                    raise
    if install or partial:
        selection_end = captured.find(b'Happy Hacking!')
        assert b'\x1b[?1049l' not in captured[:selection_end], 'UI returned to the ordinary terminal during installation'
    assert b'test-password' not in captured, 'Password was echoed'
    if interrupt:
        for worker_pid in running.read_text().split():
            state = subprocess.run(['ps', '-o', 'stat=', '-p', worker_pid], capture_output=True, text=True).stdout.strip()
            assert not state or state.startswith('Z'), 'Worker survived cancellation'
except (AssertionError, OSError) as exc:
    print(captured.decode(errors='replace'))
    try:
        os.killpg(pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    worker = Path(os.environ['DOTFILES_FAKE_PACKAGES']) / 'tty-worker'
    if worker.exists():
        try:
            os.killpg(int(worker.read_text()), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    raise AssertionError(str(exc)) from exc
finally:
    os.close(terminal)
