"""Opt-in Windows suite runner: private snapshot copies and bounded process trees."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import ctypes as c
from ctypes import wintypes as w
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import threading
import time
import zipfile

from snapshot import digest, no_links, safe_name, save, verify


def utc():
    return datetime.now(timezone.utc).isoformat()


def shell_environment():
    env = os.environ.copy()
    # A Python parent does not apply pwsh's Windows PowerShell module-path fixup.
    for key in list(env):
        if key.casefold() == 'psmodulepath':
            del env[key]
    return env


class Limits(c.Structure):
    _fields_ = [('processTime', c.c_int64), ('jobTime', c.c_int64),
                ('flags', w.DWORD), ('minWork', c.c_size_t), ('maxWork', c.c_size_t),
                ('active', w.DWORD), ('affinity', c.c_size_t),
                ('priority', w.DWORD), ('scheduling', w.DWORD)]


class Extended(c.Structure):
    _fields_ = [('basic', Limits), ('io', c.c_uint64 * 6),
                ('processMemory', c.c_size_t), ('jobMemory', c.c_size_t),
                ('peakProcessMemory', c.c_size_t), ('peakJobMemory', c.c_size_t)]


class Accounting(c.Structure):
    _fields_ = [('times', c.c_int64 * 4), ('faults', w.DWORD),
                ('total', w.DWORD), ('active', w.DWORD), ('terminated', w.DWORD)]


kernel = c.WinDLL('kernel32', use_last_error=True)
for name, restype, args in [
    ('CreateJobObjectW', w.HANDLE, [c.c_void_p, w.LPCWSTR]),
    ('SetInformationJobObject', w.BOOL, [w.HANDLE, c.c_int, c.c_void_p, w.DWORD]),
    ('QueryInformationJobObject', w.BOOL, [w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.c_void_p]),
    ('AssignProcessToJobObject', w.BOOL, [w.HANDLE, w.HANDLE]),
    ('OpenProcess', w.HANDLE, [w.DWORD, w.BOOL, w.DWORD]),
    ('QueryFullProcessImageNameW', w.BOOL, [w.HANDLE, w.DWORD, w.LPWSTR, c.POINTER(w.DWORD)]),
    ('TerminateJobObject', w.BOOL, [w.HANDLE, w.UINT]),
    ('CloseHandle', w.BOOL, [w.HANDLE]),
]:
    function = getattr(kernel, name)
    function.restype, function.argtypes = restype, args


def checked(value):
    if not value:
        raise c.WinError(c.get_last_error())
    return value


class Job:
    def __init__(self):
        self.handle = checked(kernel.CreateJobObjectW(None, None))
        info = Extended()
        info.basic.flags = 0x2000  # KILL_ON_JOB_CLOSE; no breakaway allowed.
        try:
            checked(kernel.SetInformationJobObject(self.handle, 9, c.byref(info), c.sizeof(info)))
        except BaseException:
            self.close()
            raise

    def assign(self, process):
        handle = checked(kernel.OpenProcess(0x0101, False, process.pid))  # SET_QUOTA | TERMINATE
        try:
            checked(kernel.AssignProcessToJobObject(self.handle, handle))
        finally:
            checked(kernel.CloseHandle(handle))

    def active(self):
        info = Accounting()
        checked(kernel.QueryInformationJobObject(self.handle, 1, c.byref(info), c.sizeof(info), None))
        return info.active

    def drain(self):
        active = self.active()
        if active:
            checked(kernel.TerminateJobObject(self.handle, 124))
        end = time.monotonic() + 10
        while self.active() and time.monotonic() < end:
            time.sleep(.05)
        if self.active():
            raise RuntimeError('Owned process tree did not terminate')
        return active

    def settle(self):
        # Allow bounded natural teardown; persistent descendants still fail.
        initial = self.active()
        start = time.monotonic()
        while self.active() and time.monotonic() - start < 1:
            time.sleep(.025)
        return initial, time.monotonic() - start

    def members(self):
        capacity = 16
        while True:
            buffer = c.create_string_buffer(8 + c.sizeof(c.c_size_t) * capacity)
            if kernel.QueryInformationJobObject(self.handle, 3, buffer, len(buffer), None):
                break
            if c.get_last_error() != 234:  # ERROR_MORE_DATA
                raise c.WinError(c.get_last_error())
            capacity *= 2
        count = c.cast(buffer, c.POINTER(w.DWORD))[1]
        ids = (c.c_size_t * count).from_buffer(buffer, 8)
        result = []
        for pid in ids:
            row = {'pid': pid, 'image': None}
            handle = kernel.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION
            if handle:
                try:
                    name, length = c.create_unicode_buffer(32768), w.DWORD(32768)
                    if kernel.QueryFullProcessImageNameW(handle, 0, name, c.byref(length)):
                        row['image'] = name.value
                finally:
                    checked(kernel.CloseHandle(handle))
            result.append(row)
        return result

    def close(self):
        if self.handle:
            checked(kernel.CloseHandle(self.handle))
            self.handle = None


def ps(value):
    return "'" + str(value).replace("'", "''") + "'"


def prepare(snapshot, dest, manifest):
    dest.mkdir()
    shutil.copyfile(snapshot / 'manifest.json', dest / 'manifest.json')
    shutil.copyfile(snapshot / 'source.zip', dest / 'source.zip')
    (dest / 'source').mkdir()
    with zipfile.ZipFile(dest / 'source.zip') as archive:
        for name in manifest['files']:
            path = dest / 'source' / safe_name(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(archive.read(name))
    verify(dest)
    (dest / 'temp').mkdir()


def execute(dest, exe, suite, timeout, manifest_hash, stop, deadline):
    row = {'suite': suite, 'directory': str(dest), 'startedUtc': utc(),
           'status': 'Running', 'exitCode': None, 'error': None, 'integrity': 'Pending'}
    start = time.perf_counter()
    job, process = None, None
    try:
        if stop.is_set() or time.monotonic() >= deadline:
            raise InterruptedError('Run cancelled or deadline reached')
        verify(dest)
        env = shell_environment()
        env.update(TEMP=str(dest / 'temp'), TMP=str(dest / 'temp'),
                   ISOLATION_ROOT=str(dest), PYTHONDONTWRITEBYTECODE='1')
        env['PATH'] = str(Path(sys.executable).parent) + os.pathsep + env.get('PATH', '')
        gate = dest / 'go'
        code = ("$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.Encoding]::UTF8; "
                "$end=[DateTime]::UtcNow.AddSeconds(30); "
                f"while(-not (Test-Path -LiteralPath {ps(gate)})) {{ "
                "if([DateTime]::UtcNow -gt $end){exit 124}; Start-Sleep -Milliseconds 25 }; "
                f"& {ps(dest / 'source/tests/Invoke-Tests.ps1')} -PowerShellExe {ps(exe)} "
                f"-TestName {ps(suite)} -LogDirectory {ps(dest / 'logs')}")
        command = [exe, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                   '-EncodedCommand', base64.b64encode(code.encode('utf-16-le')).decode('ascii')]
        job = Job()
        with (dest / 'stdout.log').open('wb') as out, (dest / 'stderr.log').open('wb') as err:
            process = subprocess.Popen(command, cwd=dest / 'source', env=env,
                                       stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            job.assign(process)
            gate.write_text('assigned', encoding='ascii')  # No suite code runs before assignment.
            row['pid'] = process.pid
            limit = time.monotonic() + timeout
            while process.poll() is None:
                if stop.is_set() or time.monotonic() >= deadline:
                    raise InterruptedError('Run cancelled or deadline reached')
                if time.monotonic() >= limit:
                    raise TimeoutError('Suite timeout')
                time.sleep(.05)
            row['exitCode'] = process.returncode
            row['postExitMembers'] = job.members()
            row['postExitProcesses'], row['settleSeconds'] = job.settle()
            row['leftoverProcesses'] = job.drain()
            process.wait(timeout=10)
        if row['error']:
            raise RuntimeError(row['error'])
        if row['leftoverProcesses']:
            raise RuntimeError('Suite left child processes running')
        if row['exitCode'] != 0:
            raise RuntimeError('Suite process failed')
        run = json.loads((dest / 'logs/run.json').read_text(encoding='utf-8-sig'))
        results = json.loads((dest / 'logs/results.json').read_text(encoding='utf-8-sig'))
        if (run['Status'] != 'Passed' or run['SelectedTests'] != [suite]
                or len(results) != 1 or results[0]['Test'] != suite
                or not results[0]['Passed'] or results[0]['ExitCode'] != 0):
            raise RuntimeError('Missing or inconsistent test evidence')
        row['suiteSeconds'] = results[0]['DurationSeconds']
        row['status'] = 'Passed'
    except InterruptedError as error:
        row.update(status='Cancelled', error=str(error))
    except Exception as error:
        row.update(status='Failed', error=str(error))
    finally:
        if job:
            try:
                row.setdefault('leftoverProcesses', job.drain())
            except Exception as error:
                row.update(status='Failed', error=str(error))
            finally:
                job.close()
        if process and process.poll() is None:
            process.kill()  # Gate prevents descendants if job assignment failed.
            process.wait(timeout=10)
        try:
            verify(dest)
            if digest((dest / 'manifest.json').read_bytes()) != manifest_hash:
                raise ValueError('Manifest changed')
            row['integrity'] = 'Passed'
        except Exception as error:
            row.update(status='Failed', integrity='Failed', error=str(error))
        row.update(finishedUtc=utc(), elapsedSeconds=time.perf_counter() - start)
        save(dest / 'result.json', row)
    return row


def select(snapshot, suites=None):
    discovered = sorted(p.name for p in (snapshot / 'source/tests').glob('Test-*.ps1'))
    selected = discovered if suites is None else suites
    if not selected or len(set(selected)) != len(selected) or any(s not in discovered for s in selected):
        raise ValueError('Use unique, exact discovered suite names')
    return discovered, selected


def run(snapshot, output, host, workers=1, suites=None, timeout=600, run_timeout=1800, stop=None):
    start = time.perf_counter()
    snapshot, output = Path(snapshot).absolute(), Path(output).absolute()
    no_links(output)
    if output.exists() or output.is_relative_to(snapshot) or snapshot.is_relative_to(output):
        raise ValueError('Use a fresh destination outside the snapshot')
    if (workers not in (1, 2) or not math.isfinite(timeout) or not math.isfinite(run_timeout)
            or timeout <= 0 or run_timeout <= 0):
        raise ValueError('Only 1/2 workers and positive timeouts are supported')
    manifest = verify(snapshot)
    discovered, suites = select(snapshot, suites)
    exe = shutil.which(host)
    if not exe:
        raise ValueError('Missing shell: ' + host)
    manifest_hash = digest((snapshot / 'manifest.json').read_bytes())
    runner_hash = digest(Path(__file__).read_bytes())
    if manifest['files'].get('ci/isolated.py') != runner_hash:
        raise ValueError('Run the isolated.py implementation captured in this snapshot')
    stop = stop if stop is not None else threading.Event()
    deadline = time.monotonic() + run_timeout
    report = {'status': 'Running', 'startedUtc': utc(), 'workers': workers, 'exe': exe,
              'manifestSha256': manifest_hash, 'runnerSha256': runner_hash,
              'python': sys.version, 'timeout': timeout, 'runTimeout': run_timeout, 'selected': suites,
              'discoveredCount': len(discovered), 'partial': len(suites) != len(discovered),
              'results': []}
    output.mkdir(parents=True)
    save(output / 'run.json', report)
    try:
        report['shellVersion'] = subprocess.check_output(
            [exe, '-NoProfile', '-Command', "Get-Command Get-FileHash,Add-Type -ErrorAction Stop | Out-Null; $PSVersionTable.PSVersion.ToString()"],
            env=shell_environment(), timeout=30).decode().strip()
        # One unmeasured shell warmup per batch; same recipe for 1 and 2 workers.
        subprocess.run([exe, '-NoProfile', '-Command', 'exit 0'], env=shell_environment(), check=True, timeout=30)
        paths = [output / f'{i+1:02d}' for i, s in enumerate(suites)]
        for path in paths:
            if stop.is_set() or time.monotonic() >= deadline:
                raise InterruptedError('Run cancelled or deadline reached during preparation')
            prepare(snapshot, path, manifest)
        report['prepareSeconds'] = time.perf_counter() - start
        execute_start = time.perf_counter()
        pool = ThreadPoolExecutor(max_workers=workers)
        futures = {pool.submit(execute, path, exe, suite, timeout, manifest_hash, stop, deadline): (path, suite)
                   for path, suite in zip(paths, suites)}
        pending = set(futures)
        try:
            while pending:
                try:
                    if time.monotonic() >= deadline:
                        stop.set()
                    done, pending = wait(pending, timeout=.1, return_when=FIRST_COMPLETED)
                    for future in done:
                        path, suite = futures[future]
                        try:
                            row = future.result()
                        except Exception as error:
                            row = {'suite': suite, 'directory': str(path), 'status': 'Failed', 'error': str(error)}
                        report['results'].append(row)
                        save(output / 'run.json', report)
                        print(f"{workers} worker {Path(exe).stem}: {row['suite']} {row['status']} {row.get('elapsedSeconds', 0):.2f}s", flush=True)
                except KeyboardInterrupt:
                    stop.set()
        finally:
            if pending:
                stop.set()
            pool.shutdown(wait=True)
        report['executionSeconds'] = time.perf_counter() - execute_start
        verify(snapshot)
        if digest((snapshot / 'manifest.json').read_bytes()) != manifest_hash:
            raise ValueError('Base manifest changed')
        complete = sorted(r['suite'] for r in report['results']) == sorted(suites)
        report['status'] = ('Cancelled' if stop.is_set() else
                            'Passed' if complete and all(r['status'] == 'Passed' for r in report['results']) else 'Failed')
    except (KeyboardInterrupt, InterruptedError) as error:
        stop.set()
        report.update(status='Cancelled', error=str(error))
    except Exception as error:
        report.update(status='Failed', error=str(error))
    finally:
        report.update(finishedUtc=utc(), totalSeconds=time.perf_counter() - start)
        save(output / 'run.json', report)
        save(output / 'results.json', report['results'])
    print(f"Selected {len(suites)}/{len(discovered)} suites; partial={report['partial']}; {report['status']}", flush=True)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--output')
    parser.add_argument('--host', default='powershell')
    parser.add_argument('--workers', type=int, choices=(1, 2), default=1)
    parser.add_argument('--suite', action='append')
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--timeout', type=float, default=600)
    parser.add_argument('--run-timeout', type=float, default=1800)
    args = parser.parse_args()
    if args.list:
        verify(Path(args.snapshot))
        print('\n'.join(select(Path(args.snapshot), args.suite)[1]))
        sys.exit(0)
    if not args.output:
        parser.error('--output is required unless --list is used')
    result = run(args.snapshot, args.output, args.host, args.workers, args.suite, args.timeout, args.run_timeout)
    print(json.dumps({k: result.get(k) for k in ('status', 'prepareSeconds', 'executionSeconds', 'totalSeconds')}))
    sys.exit(0 if result['status'] == 'Passed' else 130 if result['status'] == 'Cancelled' else 1)
