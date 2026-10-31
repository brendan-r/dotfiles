#!/usr/bin/env python3
"""Guest-only probes invoked as individual Bats cases; no separate test runner."""
import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

if not Path('/etc/dotfiles-test-image').is_file() or os.environ.get('DOTFILES_TEST_GUEST') != '1':
    sys.exit('Guest only')
root = Path(__file__).resolve().parents[2]
loader = importlib.machinery.SourceFileLoader('harness', str(root / 'tests/run'))
spec = importlib.util.spec_from_loader(loader.name, loader)
h = importlib.util.module_from_spec(spec)
loader.exec_module(h)


def streaming():
    started = time.monotonic()
    arrival = []
    class Sink(io.StringIO):
        def write(self, text):
            if text:
                arrival.append(time.monotonic() - started)
            return super().write(text)
    sink = Sink()
    with tempfile.TemporaryFile() as log, contextlib.redirect_stdout(sink):
        result = h.run([sys.executable, '-c',
                        'import time; print("first", flush=True); time.sleep(1); print("last")'],
                       stream_log=log, timeout=4)
        log.seek(0)
        assert log.read() == b'first\nlast\n'
    assert result.returncode == 0
    assert arrival[0] < 0.8, arrival
    assert arrival[-1] >= 1
    assert sink.getvalue() == 'first\nlast\n'


def silent_timeout():
    with tempfile.TemporaryDirectory() as tmp:
        pidfile = Path(tmp) / 'pid'
        started = time.monotonic()
        with tempfile.TemporaryFile() as log:
            try:
                h.run([sys.executable, '-c',
                       'import os,time,sys; open(sys.argv[1],"w").write(str(os.getpid())); time.sleep(60)',
                       pidfile], timeout=0.5, stream_log=log)
            except subprocess.TimeoutExpired:
                pass
            else:
                raise AssertionError('Timeout was ignored')
        assert time.monotonic() - started < 5
        pid = int(pidfile.read_text())
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        raise AssertionError('Timed-out child remains alive')


def interrupted_stream():
    class Interrupted(io.StringIO):
        def write(self, _text):
            raise KeyboardInterrupt
    with tempfile.TemporaryDirectory() as tmp:
        pidfile = Path(tmp) / 'pid'
        with tempfile.TemporaryFile() as log, contextlib.redirect_stdout(Interrupted()):
            try:
                h.run([sys.executable, '-c',
                       'import os,time,sys; open(sys.argv[1],"w").write(str(os.getpid())); print("partial",flush=True); time.sleep(60)',
                       pidfile], timeout=5, stream_log=log)
            except KeyboardInterrupt:
                pass
            else:
                raise AssertionError('Interrupt swallowed')
            log.seek(0)
            assert log.read() == b'partial\n'
        try:
            os.kill(int(pidfile.read_text()), 0)
        except ProcessLookupError:
            return
        raise AssertionError('Interrupted child remains alive')


def transport_failure():
    with tempfile.TemporaryFile() as log:
        result = h.run([sys.executable, '-c', 'print("transport broke"); raise SystemExit(255)'],
                       stream_log=log, check=False)
        log.seek(0)
        assert log.read() == b'transport broke\n'
    assert result.returncode == 255


def continuation():
    seen = []
    def fail():
        raise h.TestFailure('assertion failed')
    def setup_fail():
        raise RuntimeError('setup failed')
    result = h.run_suites([('assertion', fail), ('setup', setup_fail), ('remaining', lambda: seen.append(1))])
    assert result == 1 and seen == [1]
    seen.clear()
    def interrupt():
        raise KeyboardInterrupt
    try:
        h.run_suites([('interrupt', interrupt), ('forbidden', lambda: seen.append(1))])
    except KeyboardInterrupt:
        pass
    else:
        raise AssertionError('Interrupt swallowed')
    assert seen == []


def cleanup_failure():
    def broken():
        raise OSError('stop failed')
    try:
        with h.cleanup('stop', broken):
            raise h.TestFailure('assertion failed')
    except RuntimeError as exc:
        assert 'assertion failed' in str(exc) and 'stop failed' in str(exc)
    else:
        raise AssertionError('Cleanup error swallowed')
    h.tart = lambda *args, **kwargs: None
    h.inventory = lambda: [{'Name': 'owned', 'Running': True}]
    try:
        h.stop_vm('owned')
    except RuntimeError as exc:
        assert 'still running' in str(exc)
    else:
        raise AssertionError('Unconfirmed stop reported success')


def formatting():
    assert h.choose_format('auto', tty=True, environ={'TERM': 'xterm'}) == ('pretty', True)
    assert h.choose_format('auto', tty=False, environ={'TERM': 'xterm'}) == ('tap', False)
    assert h.choose_format('auto', tty=True, environ={'TERM': 'dumb'}) == ('tap', False)
    assert h.choose_format('auto', tty=True, environ={'TERM': 'xterm', 'NO_COLOR': ''}) == ('tap', False)
    assert h.choose_format('pretty', tty=False, environ={'NO_COLOR': ''}) == ('pretty', False)
    env = {**os.environ, 'BATS_ROOT': str(root / 'tests/vendor/bats-core'),
           'BATS_LIBDIR': 'lib', 'DOTFILES_TEST_COLOR': '1', 'DOTFILES_TEST_INTERACTIVE': '0'}
    env.pop('NO_COLOR', None)
    protocol = '1..3\nbegin 1 pass\nok 1 pass in 3ms\nbegin 2 fail\nnot ok 2 fail in 4ms\n# diagnostic\nbegin 3 skipped\nok 3 skipped # skip unavailable\n'
    result = subprocess.run([root / 'tests/format-pretty'], input=protocol, text=True,
                            stdout=subprocess.PIPE, env=env, check=True)
    for text in ['\033[32m✓', '\033[31m✗', '\033[33m−', '3 ms', 'diagnostic', '3 tests: 1 passed, 1 failed, 1 skipped']:
        assert text in result.stdout, result.stdout
    env['NO_COLOR'] = ''
    plain = subprocess.run([root / 'tests/format-pretty'], input=protocol, text=True,
                           stdout=subprocess.PIPE, env=env, check=True).stdout
    assert '\033' not in plain and '✓' in plain
    assert '→' not in result.stdout and '→' not in plain

    # The host explicitly enables in-place output across piped VM transports.
    # Verify raw bytes: text-mode subprocess output would normalize CR to LF.
    env.pop('NO_COLOR')
    env['DOTFILES_TEST_INTERACTIVE'] = '1'
    env['DOTFILES_TEST_COLUMNS'] = '24'
    long_name = 'a_very_long_test_name_that_would_wrap'
    interactive_protocol = ('1..3\nbegin 1 ' + long_name + '\nok 1 ' + long_name +
                            ' in 3ms\nbegin 2 fail\n# during test\nnot ok 2 fail in 4ms\n'
                            '# failure detail\nbegin 3 skipped\nok 3 skipped # skip unavailable\n')
    raw = subprocess.run([root / 'tests/format-pretty'], input=interactive_protocol.encode(),
                         stdout=subprocess.PIPE, env=env, check=True).stdout
    assert b'\r\033[K' in raw
    first_row = raw.split(b'\r', 1)[0].decode()
    assert '\n' not in first_row and len(first_row) < 24 and first_row.endswith('...'), first_row
    assert ('✓ ' + long_name.replace('_', ' ') + ' (3 ms)') in raw.decode().replace('\033[32m', '').replace('\033[0m', '')
    # Feed one byte at a time to exercise split UTF-8, escapes, and PTY CRLF.
    saved = io.BytesIO()
    log = h.PlainLog(saved)
    for byte in raw.replace(b'\n', b'\r\n'):
        log.write(bytes([byte]))
    log.close()
    transcript = saved.getvalue().decode()
    assert '\033' not in transcript and '\r' not in transcript and '→' not in transcript, transcript
    assert transcript.count('✓') == 1 and transcript.count('✗') == 1 and transcript.count('−') == 1
    assert 'during test' in transcript and 'failure detail' in transcript
    assert long_name.replace('_', ' ') in transcript
    partial = io.BytesIO()
    log = h.PlainLog(partial)
    log.write('  → interrupted'.encode())
    log.close()
    assert partial.getvalue().decode() == '  → interrupted'

    # Exercise grouped presentation, including repeated groups, a platform
    # change, and a result without a preceding live-progress event.
    grouped_protocol = (
        '1..4\n'
        'begin 1 [macos] dotfiles__install__keeps_original_files\n'
        'ok 1 [macos] dotfiles__install__keeps_original_files in 3ms\n'
        'begin 2 [macos] dotfiles__install__rejects_conflicting_files\n'
        'not ok 2 [macos] dotfiles__install__rejects_conflicting_files in 4ms\n'
        '# failure detail\n'
        'begin 3 [macos] runner__processes__stops_child\n'
        'ok 3 [macos] runner__processes__stops_child # skip unavailable\n'
        'ok 4 [debian] runner__processes__stops_child in 2ms\n'
    )
    env['NO_COLOR'] = ''
    for interactive in ('0', '1'):
        env['DOTFILES_TEST_INTERACTIVE'] = interactive
        grouped = subprocess.run([root / 'tests/format-pretty'], input=grouped_protocol.encode(),
                                 stdout=subprocess.PIPE, env=env, check=True).stdout
        saved = io.BytesIO()
        log = h.PlainLog(saved)
        log.write(grouped)
        log.close()
        lines = saved.getvalue().decode().splitlines()
        assert [line for line in lines if line.startswith('[')] == [
            '[macos] dotfiles / install', '[macos] runner / processes', '[debian] runner / processes'
        ], lines
        expected_rows = [
            '  ✓ keeps original files (3 ms)', '  ✗ rejects conflicting files (4 ms)',
            '    failure detail', '  − stops child (skipped: unavailable)',
            '  ✓ stops child (2 ms)',
        ]
        assert [line for line in lines if line.startswith('  ')] == expected_rows, lines
        assert lines[-1] == '4 tests: 2 passed, 1 failed, 1 skipped, 0 not run', lines


def vm_lifecycle():
    # Exercise the real execute_suite/boot/cleanup branches with command fakes.
    # No extra VMs or candidate commands are launched by this regression case.
    original_root, original_state = h.ROOT, h.STATE
    original_popen = h.subprocess.Popen
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        h.ROOT = base
        h.STATE = base / 'state'
        h.STATE.mkdir()
        (h.STATE / 'debian.json').write_text(json.dumps({'image': h.IMAGES['debian']['image']}))
        public = base / 'snapshot/public'
        public.mkdir(parents=True)
        (public.parent / 'public.tar').touch()
        provenance = public.parent / 'work/tests/vendor/bats-core/UPSTREAM.json'
        provenance.parent.mkdir(parents=True)
        provenance.write_text('{"version":"1.14.0"}')
        h.tart_binary = lambda: '/fake/tart'
        h.exists = lambda name: True
        for scenario in ('pass', 'assertion', 'setup', 'transport', 'stop'):
            calls = []
            running = [True]
            processes = []
            class Process:
                def __init__(self, *args, **kwargs):
                    self.done = False
                    processes.append(self)
                def poll(self):
                    return 0 if self.done else None
                def wait(self, timeout=None):
                    self.done = True
                    return 0
            def terminate(proc):
                proc.done = True
            def fake_tart(*args, **kwargs):
                calls.append(args)
                code = 0
                out = '' if kwargs.get('text') else b''
                if args[0] == 'stop':
                    if scenario == 'stop':
                        raise OSError('injected stop failure')
                    running[0] = False
                if '/usr/bin/script' in args:
                    code = 1 if scenario == 'assertion' else 255 if scenario == 'transport' else 0
                    kwargs['stream_log'].write(b'partial guest results\n')
                if args[0] == 'exec' and args[2] == 'cat':
                    code = 1 if scenario == 'transport' else 0
                    out = '1\n' if scenario == 'assertion' else '0\n'
                return subprocess.CompletedProcess(args, code, out)
            def ready(name):
                if scenario == 'setup':
                    raise RuntimeError('injected agent failure')
            h.subprocess.Popen = Process
            h.terminate_process = terminate
            h.tart = fake_tart
            h.inventory = lambda: [{'Name': next(args[2] for args in calls if args[0] == 'clone'), 'Running': running[0]}]
            h.wait_agent = ready
            failure = None
            text = io.StringIO()
            with contextlib.redirect_stdout(text):
                try:
                    h.execute_suite('debian', 'unit', public, 'fixed-revision')
                except (RuntimeError, OSError) as exc:
                    failure = exc
            assert any(args[0] == 'stop' for args in calls), calls
            assert all(proc.done for proc in processes), scenario
            deleted = any(args[0] == 'delete' for args in calls)
            assert deleted == (scenario == 'pass'), (scenario, calls)
            if scenario == 'pass':
                assert failure is None, failure
            elif scenario == 'assertion':
                assert isinstance(failure, h.TestFailure), failure
            else:
                assert failure is not None and not isinstance(failure, h.TestFailure), failure
            if scenario == 'stop':
                assert 'stop unconfirmed' in text.getvalue()
            elif scenario != 'pass':
                assert 'Retained guest (stopped)' in text.getvalue()
    h.subprocess.Popen = original_popen
    h.ROOT, h.STATE = original_root, original_state


# Bats chooses the probe and owns naming, status, diagnostics, and reporting.
globals()[sys.argv[1]]()
