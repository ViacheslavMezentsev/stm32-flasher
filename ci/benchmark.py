"""Sequential, counterbalanced Windows PowerShell process benchmark (no MCU)."""
import argparse
import base64
from datetime import datetime, timezone
import os
from pathlib import Path
import random
import shutil
import statistics
import subprocess
import sys
import time
import uuid

from snapshot import digest, save, verify


def encoded(script):
    return base64.b64encode(script.encode('utf-16-le')).decode('ascii')


def execute(exe, mode, script):
    args = [exe, '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded(script)]
    command = args
    if mode == 'cmd':
        comspec = os.environ.get('ComSpec', r'C:\Windows\System32\cmd.exe')
        command = f'"{comspec}" /d /v:off /s /c ""{exe}" -NoProfile -NonInteractive -EncodedCommand {args[-1]}"'
    start = time.perf_counter()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        # Only terminate the process tree started by this measurement.
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        process.kill() if process.poll() is None else None
        stdout, stderr = process.communicate(timeout=5)
        raise RuntimeError('Benchmark process timed out; no success result recorded')
    elapsed = (time.perf_counter() - start) * 1000
    if process.returncode:
        raise RuntimeError(f'Exit {process.returncode}: {stderr.decode("utf-8", errors="replace")}')
    return elapsed, stdout.decode('utf-8', errors='replace').strip()


def schedule(cells, rounds, repeats, seed):
    rng = random.Random(seed)
    order = []
    for repeat in range(repeats):
        if repeat % 2 == 0:
            blocks = []
            for _ in range(rounds):
                block = list(cells)
                rng.shuffle(block)
                blocks.append(block)
        for round_number in range(rounds):
            block = blocks[round_number] if repeat % 2 == 0 else list(reversed(blocks[round_number]))
            for cell in block:
                order.append((repeat + 1, round_number + 1, cell))
    return order


def run(directory, hosts, rounds=8, repeats=2, warmup=2, seed=1729, executor=execute):
    if min(rounds, repeats, warmup) < 1:
        raise ValueError('Rounds, repeats and warmup must be positive')
    directory = Path(directory).resolve()
    manifest = verify(directory)
    manifest_hash = digest((directory / 'manifest.json').read_bytes())
    tool_hash = digest(Path(__file__).read_bytes())
    if manifest['files'].get('ci/benchmark.py') != tool_hash:
        raise ValueError('Use the benchmark implementation captured in this snapshot')
    output = directory / ('benchmark-' + uuid.uuid4().hex + '.json')
    report = {'status': 'Running', 'startedUtc': datetime.now(timezone.utc).isoformat(),
              'manifestSha256': manifest_hash, 'kind': manifest['kind'], 'head': manifest['head'],
              'dirty': manifest['dirty'], 'python': sys.version, 'platform': sys.platform,
              'benchmarkSha256': tool_hash,
              'rounds': rounds, 'repeats': repeats, 'warmup': warmup, 'seed': seed,
              'hosts': [], 'samples': [], 'summary': [], 'error': None}
    save(output, report)
    print('Benchmark evidence: ' + str(output), flush=True)
    try:
        flash = str(directory / 'source/bin/flash.cmd').replace("'", "''")
        scripts = {'empty': 'exit 0', 'parse': (
            "$ErrorActionPreference='Stop'; $t=$null; $e=$null; "
            "[System.Management.Automation.Language.Parser]::ParseInput("
            f"[IO.File]::ReadAllText('{flash}'),[ref]$t,[ref]$e)|Out-Null; "
            "if($e.Count){exit 1}; exit 0")}
        if 'bin/flash.cmd' not in manifest['files']:
            raise ValueError('Snapshot has no flash.cmd input')
        cells = []
        seen = set()
        for host in hosts:
            exe = shutil.which(host)
            if not exe:
                raise ValueError('Missing host: ' + host)
            key = os.path.normcase(os.path.abspath(exe))
            if key in seen:
                raise ValueError('Duplicate host: ' + host)
            seen.add(key)
            _, version = executor(exe, 'direct', '$PSVersionTable.PSVersion.ToString()')
            report['hosts'].append({'exe': exe, 'version': version})
            for workload in scripts:
                for mode in ('direct', 'cmd'):
                    cells.append((exe, workload, mode))
        if not cells:
            raise ValueError('At least one host is required')
        for phase, sequence in (
            ('warmup', schedule(cells, warmup, 1, seed)),
            ('measured', schedule(cells, rounds, repeats, seed + 1)),
        ):
            for repeat, round_number, (exe, workload, mode) in sequence:
                row = {'phase': phase, 'repeat': repeat, 'round': round_number,
                       'exe': exe, 'workload': workload, 'mode': mode}
                try:
                    row['milliseconds'], _ = executor(exe, mode, scripts[workload])
                    row['status'] = 'Passed'
                except Exception as error:
                    row.update(status='Failed', error=str(error))
                    report['samples'].append(row)
                    save(output, report)
                    raise
                report['samples'].append(row)
                save(output, report)
        for exe, workload, mode in cells:
            for repeat in range(1, repeats + 1):
                values = [r['milliseconds'] for r in report['samples'] if r['phase'] == 'measured'
                          and (r['exe'], r['workload'], r['mode'], r['repeat']) == (exe, workload, mode, repeat)]
                report['summary'].append({'exe': exe, 'workload': workload, 'mode': mode,
                                          'repeat': repeat, 'count': len(values),
                                          'medianMs': statistics.median(values), 'minMs': min(values), 'maxMs': max(values)})
        verify(directory)
        if digest((directory / 'manifest.json').read_bytes()) != manifest_hash:
            raise ValueError('Manifest changed during measurement')
        report['status'] = 'Passed'
    except Exception as error:
        report['status'] = 'Failed'
        report['error'] = str(error)
        raise
    finally:
        report['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        save(output, report)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--host', action='append', dest='hosts')
    parser.add_argument('--rounds', type=int, default=8)
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--warmup', type=int, default=2)
    parser.add_argument('--seed', type=int, default=1729)
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('This benchmark requires Windows; Linux cannot exercise CMD/PS5.1')
    try:
        output = run(args.snapshot, args.hosts or ['powershell', 'pwsh'], args.rounds, args.repeats, args.warmup, args.seed)
        print('Benchmark PASS: ' + str(output))
    except Exception as error:
        parser.exit(1, str(error) + '\n')


if __name__ == '__main__':
    main()
