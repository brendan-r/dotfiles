#!/usr/bin/env python3
"""Interrupt a fake install and check that its worker group has stopped."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

if not Path('/etc/dotfiles-test-image').is_file():
    sys.exit('VM only')

store = Path(os.environ['DOTFILES_FAKE_PACKAGES'])
environment = dict(os.environ, DOTFILES_FAKE_WAIT='1')
process = subprocess.Popen(
    ['/bin/bash', sys.argv[1] + '/dotfiles', 'install', '--only', 'tools,later', '--yes'],
    env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True,
)

try:
    deadline = time.monotonic() + 15
    while not (store / 'running').exists():
        if process.poll() is not None or time.monotonic() > deadline:
            raise AssertionError('Fake installation did not start')
        time.sleep(0.05)

    process.send_signal(signal.SIGINT)
    output = process.communicate(timeout=10)[0].decode()
    assert process.returncode == 130, output
    assert not (store / 'sample-tool').exists(), output

    for pid in (store / 'running').read_text().split():
        state = subprocess.run(['ps', '-o', 'stat=', '-p', pid], capture_output=True, text=True).stdout.strip()
        # An orphan may briefly await reaping by init, but must not still run.
        assert not state or state.startswith('Z'), (pid, state, output)
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
