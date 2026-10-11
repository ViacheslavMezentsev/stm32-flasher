"""Controlled full-suite 1/2-worker comparison on one Windows host."""
import argparse
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys

from snapshot import digest, no_links, save, verify

ORDER = (1, 2, 2, 1)


def number(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError('Invalid duration')
    return value


def inspect_report(directory, workers, selected, manifest_hash, runner_hash):
    report = json.loads((directory / 'run.json').read_text(encoding='utf-8-sig'))
    rows = json.loads((directory / 'results.json').read_text(encoding='utf-8-sig'))
    if (report['status'] != 'Passed' or report['partial'] is not False
            or report['workers'] != workers or report['selected'] != selected
            or report['discoveredCount'] != len(selected)
            or report['manifestSha256'] != manifest_hash or report['runnerSha256'] != runner_hash
            or rows != report['results'] or len(rows) != len(selected)
            or sorted(r['suite'] for r in rows) != selected):
        raise ValueError('Incomplete, failed or mismatched evidence')
    if any(r['status'] != 'Passed' or r['integrity'] != 'Passed'
           or r['exitCode'] != 0 or r['leftoverProcesses'] != 0 for r in rows):
        raise ValueError('Suite failure, changed inputs or leftover processes')
    for key in ('prepareSeconds', 'executionSeconds', 'totalSeconds'):
        number(report[key])
    if report['totalSeconds'] <= 0 or report['totalSeconds'] + .001 < report['prepareSeconds'] + report['executionSeconds']:
        raise ValueError('Inconsistent total duration')
    identity = tuple(report[k] for k in ('exe', 'shellVersion', 'python'))
    if not all(isinstance(v, str) and v.strip() for v in identity):
        raise ValueError('Missing runtime identity')
    return report, identity


def markdown(summary):
    lines = ['# CI Worker Comparison', '', 'Shell: ' + summary['host'],
             'Suites per trial: ' + str(len(summary['selected'])), '', 'Status: ' + summary['status'],
             '', 'Manifest SHA-256: ' + summary['manifestSha256'],
             '', '| Trial | Workers | Status | Total, s |',
             '| --- | ---: | --- | ---: |']
    for trial in summary['trials']:
        report = trial.get('report', {})
        lines.append(f"| {trial['trial']} | {trial['workers']} | {trial['status']} | {report.get('totalSeconds', '-')} |")
    if summary.get('speedup') is not None:
        lines += ['', f"Median total-time ratio (1 / 2 workers): {summary['speedup']:.3f}x",
                  'One ABBA experiment, not a performance guarantee. See comparison.json for raw timings.']
    else:
        lines += ['', 'No speedup claim: comparison is incomplete or failed.']
    return '\n'.join(lines) + '\n'


def run(snapshot, output, host):
    snapshot, output = Path(os.path.abspath(snapshot)), Path(os.path.abspath(output))
    no_links(output)
    if output.exists() or output.is_relative_to(snapshot) or snapshot.is_relative_to(output):
        raise ValueError('Use a fresh output outside the snapshot')
    manifest = verify(snapshot)
    manifest_hash = digest((snapshot / 'manifest.json').read_bytes())
    if manifest['files'].get('ci/compare.py') != digest(Path(__file__).read_bytes()):
        raise ValueError('Run compare.py captured in this snapshot')
    selected = sorted(p.name for p in (snapshot / 'source/tests').glob('Test-*.ps1') if p.is_file())
    if not selected:
        raise ValueError('No suites found')
    exe = shutil.which(host)
    if not exe:
        raise ValueError('Missing shell: ' + host)
    summary = {
        'status': 'Running', 'startedUtc': datetime.now(timezone.utc).isoformat(),
        'manifestSha256': manifest_hash, 'sourceHead': manifest.get('head'),
        'host': exe, 'selected': selected, 'order': list(ORDER), 'trials': [], 'speedup': None,
        'machine': {'platform': platform.platform(), 'processor': platform.processor(), 'cpuCount': os.cpu_count(),
                    'imageOS': os.environ.get('ImageOS'), 'imageVersion': os.environ.get('ImageVersion'),
                    'githubSha': os.environ.get('GITHUB_SHA'), 'python': sys.version},
    }
    output.mkdir(parents=True)
    identity = None
    try:
        for index, workers in enumerate(ORDER, 1):
            trial = {'trial': index, 'workers': workers, 'status': 'Running'}
            summary['trials'].append(trial)
            save(output / 'comparison.json', summary)
            directory = output / f'{index}-w{workers}'
            code = subprocess.run(
                [sys.executable, '-B', '-X', 'utf8', str(snapshot / 'source/ci/isolated.py'),
                 '--snapshot', str(snapshot), '--output', str(directory), '--host', exe,
                 '--workers', str(workers), '--timeout', '600', '--run-timeout', '1800'],
                cwd=snapshot / 'source').returncode
            trial['exitCode'] = code
            try:
                if code != 0:
                    raise ValueError(f'Runner exit code {code}')
                report, current = inspect_report(directory, workers, selected, manifest_hash, manifest['files']['ci/isolated.py'])
                if identity is not None and identity != current:
                    raise ValueError('Runtime identity changed between trials')
                identity = current
                trial.update(status='Passed', report=report)
            except (ValueError, OSError, KeyError, TypeError) as error:
                trial.update(status='Cancelled' if code == 130 else 'Failed', error=str(error))
            save(output / 'comparison.json', summary)
            if code == 130:
                raise InterruptedError('Runner cancelled; remaining trials not started')
        verify(snapshot)
        if digest((snapshot / 'manifest.json').read_bytes()) != manifest_hash:
            raise ValueError('Base manifest changed')
        if all(t['status'] == 'Passed' for t in summary['trials']) and len(summary['trials']) == len(ORDER):
            medians = {}
            for workers in (1, 2):
                reports = [t['report'] for t in summary['trials'] if t['workers'] == workers]
                medians[str(workers)] = {key: statistics.median(r[key] for r in reports)
                                        for key in ('prepareSeconds', 'executionSeconds', 'totalSeconds')}
            summary.update(status='Passed', medians=medians,
                           speedup=medians['1']['totalSeconds'] / medians['2']['totalSeconds'])
        else:
            summary['status'] = 'Failed'
    except (KeyboardInterrupt, InterruptedError) as error:
        summary.update(status='Cancelled', error=str(error))
    except Exception as error:
        summary.update(status='Failed', error=str(error))
    finally:
        summary['finishedUtc'] = datetime.now(timezone.utc).isoformat()
        save(output / 'comparison.json', summary)
        (output / 'summary.md').write_text(markdown(summary), encoding='utf-8')
    return summary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--host', required=True)
    args = parser.parse_args()
    result = run(args.snapshot, args.output, args.host)
    print(markdown(result))
    sys.exit(0 if result['status'] == 'Passed' else 130 if result['status'] == 'Cancelled' else 1)
