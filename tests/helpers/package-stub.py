#!/usr/bin/env python3
"""Guest-only package manager stand-in; record mutations, not incidental queries."""
import os
from pathlib import Path
import subprocess
import sys
import termios

if not Path('/etc/dotfiles-test-image').is_file():
    sys.exit('VM only')

store = Path(os.environ['DOTFILES_FAKE_PACKAGES'])
name = Path(sys.argv[0]).name
args = sys.argv[1:]

if name == 'sudo':
    if args == ['-v']:
        sys.exit(0)
    if args and args[0] == '-n':
        args = args[1:]
    sys.exit(subprocess.call(args))

if name == 'dpkg-query':
    if not (store / args[-1]).exists():
        sys.exit(1)
    print('install ok installed', end='')
elif args[0] == '--prefix':
    print(store)
elif args[0] == 'list':
    if not (store / args[-1]).exists():
        sys.exit(1)
    print(args[-1], 'test-version')
elif args == ['analytics', 'off']:
    assert os.environ.get('HOMEBREW_NO_ANALYTICS') == '1'
    (store / 'analytics-disabled').touch()
elif args[0] == 'install':
    with (store / 'calls').open('a') as log:
        log.write(name + ' ' + ' '.join(args) + '\n')
    if os.environ.get('DOTFILES_FAKE_TERMINAL'):
        # Like sudo's terminal restoration, this stops a background group unless
        # the runner deliberately handles SIGTTOU. Exercise a real PTY, not ANSI.
        (store / 'tty-worker').write_text(str(os.getpgrp()))
        terminal = os.open('/dev/tty', os.O_RDWR)
        termios.tcsetattr(terminal, termios.TCSANOW, termios.tcgetattr(terminal))
        os.close(terminal)
    if os.environ.get('DOTFILES_FAKE_PROMPT'):
        terminal = os.open('/dev/tty', os.O_RDWR)
        settings = termios.tcgetattr(terminal)
        hidden = list(settings)
        hidden[3] &= ~termios.ECHO
        try:
            termios.tcsetattr(terminal, termios.TCSANOW, hidden)
            os.write(terminal, b'Installer test prompt: ')
            assert os.read(terminal, 100).strip() == b'test-password'
        finally:
            termios.tcsetattr(terminal, termios.TCSANOW, settings)
            os.close(terminal)
        print('Prompt accepted.', flush=True)
    if os.environ.get('DOTFILES_FAKE_FAILURE'):
        print('injected installation failure', file=sys.stderr)
        sys.exit(23)
    if os.environ.get('DOTFILES_FAKE_WAIT'):
        if os.environ.get('DOTFILES_FAKE_STUBBORN'):
            child = subprocess.Popen([
                sys.executable, '-c',
                'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                'print("ready", flush=True); time.sleep(60)',
            ], stdout=subprocess.PIPE)
            assert child.stdout.readline().strip() == b'ready'
        else:
            child = subprocess.Popen(['sleep', '60'])
        (store / 'running').write_text(str(os.getpid()) + ' ' + str(child.pid))
        child.wait()
    (store / args[-1]).touch()
elif args[0] != 'update':
    sys.exit('Unexpected package command: ' + repr(args))
