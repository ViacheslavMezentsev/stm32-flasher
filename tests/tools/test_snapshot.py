"""Snapshot and benchmark contracts using disposable repositories and mock CI."""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'ci'))
import snapshot
import benchmark

HOST = None


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix='.tmp-snapshot-', dir=REPO / 'tests'))
        self.root = self.base / 'repo with spaces'
        self.root.mkdir()
        self.g('init', '-q')
        self.g('config', 'core.autocrlf', 'false')
        (self.root / '.gitignore').write_text('ignored/\ntests/.tmp-*/\n', encoding='utf-8')
        (self.root / 'bin').mkdir()
        (self.root / 'bin/flash.cmd').write_bytes(b'# parse only fixture\n')
        (self.root / 'delete.txt').write_bytes(b'delete me\n')
        (self.root / 'ci').mkdir()
        for name in ('snapshot.py', 'Invoke-Snapshot.ps1', 'benchmark.py'):
            shutil.copyfile(REPO / 'ci' / name, self.root / 'ci' / name)
        (self.root / 'ci/Invoke-Local.ps1').write_text('''param($Stage,$Profile,$PowerShellExe,$PythonExe,$LogDirectory,$TestName)
Write-Output 'SNAPSHOT_CHILD'
if ($TestName -eq 'Fail') { throw 'EXPECTED_CHILD_FAILURE' }
if ($TestName -eq 'Mutate') { Set-Content bin/flash.cmd 'changed' }
if ($TestName -eq 'Manifest') { Set-Content ../manifest.json '{}' }
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
Set-Content (Join-Path $LogDirectory 'marker') $PWD.Path
''', encoding='utf-8')
        self.g('add', '.')
        tree = self.g('write-tree').decode().strip()
        # Synthetic object for tests; no real commit, signing config or hooks are changed.
        data = (f'tree {tree}\nauthor CI Fixture <ci@example.invalid> 0 +0000\n'
                'committer CI Fixture <ci@example.invalid> 0 +0000\n\nfixture\n').encode()
        commit = self.g('hash-object', '-t', 'commit', '-w', '--stdin', data=data).decode().strip()
        self.g('update-ref', 'refs/heads/fixture', commit)
        self.g('symbolic-ref', 'HEAD', 'refs/heads/fixture')
        self.dest = self.base / 'snapshot'

    def g(self, *args, data=None):
        return subprocess.check_output(['git', '-C', str(self.root), *args], input=data, stderr=subprocess.PIPE)

    def tearDown(self):
        if self.base.resolve().parent != (REPO / 'tests').resolve() or not self.base.name.startswith('.tmp-snapshot-'):
            raise AssertionError('Unsafe fixture cleanup')
        def remove_readonly(function, path, error):
            if not isinstance(error[1], PermissionError) or not Path(path).resolve().is_relative_to(self.base.resolve()):
                raise error[1]
            os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
            function(path)
        shutil.rmtree(self.base, onerror=remove_readonly)

    def test_working_tree_bytes_deletions_unicode_and_ignored(self):
        (self.root / 'delete.txt').unlink()
        name = '\u043d\u043e\u0432\u044b\u0439 file.txt'
        (self.root / name).write_bytes(b'new\r\nbytes\xff')
        (self.root / 'ignored').mkdir()
        (self.root / 'ignored/private.hex').write_bytes(b'not an input')
        snapshot.create(self.root, self.dest, 'WorkingTree')
        m = snapshot.verify(self.dest)
        self.assertTrue(m['dirty'])
        self.assertNotIn('delete.txt', m['files'])
        self.assertNotIn('ignored/private.hex', m['files'])
        self.assertEqual(m['files'][name], hashlib.sha256(b'new\r\nbytes\xff').hexdigest())
        (self.root / name).write_bytes(b'edit original after capture')
        snapshot.verify(self.dest)
        self.assertEqual((self.dest / 'source' / name).read_bytes(), b'new\r\nbytes\xff')

    def test_commit_and_reuse(self):
        snapshot.create(self.root, self.dest, 'Commit')
        self.assertFalse(snapshot.verify(self.dest)['dirty'])
        with self.assertRaises(ValueError):
            snapshot.create(self.root, self.dest, 'Commit')
        (self.root / 'new.txt').write_text('dirty')
        with self.assertRaises(ValueError):
            snapshot.create(self.root, self.base / 'dirty', 'Commit')

    def test_changes_during_capture(self):
        original = snapshot.work_files
        count = 0
        def changed(root):
            nonlocal count
            count += 1
            files = original(root)
            if count == 2:
                files['delete.txt'] = b'changed during capture'
            return files
        with patch.object(snapshot, 'work_files', changed), self.assertRaises(ValueError):
            snapshot.create(self.root, self.dest, 'WorkingTree')
        self.assertEqual(json.loads((self.dest / 'manifest.json').read_text())['state'], 'Creating')
        with self.assertRaises(ValueError):
            snapshot.verify(self.dest)

    def test_tampering_and_extra_inputs(self):
        snapshot.create(self.root, self.dest, 'WorkingTree')
        target = self.dest / 'source/delete.txt'
        target.write_bytes(b'changed')
        with self.assertRaises(ValueError): snapshot.verify(self.dest)
        target.write_bytes(b'delete me\n')
        extra = self.dest / 'source/ci/injected.ps1'
        extra.write_text('bad')
        with self.assertRaises(ValueError): snapshot.verify(self.dest)
        extra.unlink()
        generated = self.dest / 'source/tests/.tmp-result'
        generated.mkdir(parents=True)
        (generated / 'log').write_text('allowed generated output')
        snapshot.verify(self.dest)
        (self.dest / 'source.zip').write_bytes(b'broken archive')
        with self.assertRaises(ValueError): snapshot.verify(self.dest)

    def test_gitlinks_and_unsafe_destination(self):
        with self.assertRaises(ValueError):
            snapshot.create(self.root, self.root / 'unignored', 'WorkingTree')
        with self.assertRaises(ValueError):
            snapshot.create(self.root, self.base, 'WorkingTree')
        for name in ('../escape', '/absolute', 'C:/drive', '.git/config', 'a/../b'):
            with self.assertRaises(ValueError): snapshot.safe_name(name)
        head = self.g('rev-parse', 'HEAD').decode().strip()
        self.g('update-index', '--add', '--cacheinfo', '160000,' + head + ',submodule')
        with self.assertRaises(ValueError): snapshot.create(self.root, self.dest, 'WorkingTree')

    def test_symlink_index(self):
        blob = self.g('hash-object', '-w', '--stdin', data=b'delete.txt').decode().strip()
        self.g('update-index', '--add', '--cacheinfo', '120000,' + blob + ',link')
        with self.assertRaises(ValueError): snapshot.create(self.root, self.dest, 'WorkingTree')

    @unittest.skipUnless(os.name == 'nt', 'Windows junction')
    def test_junction_rejected_without_touching_target(self):
        target = self.base / 'outside'
        target.mkdir()
        (target / 'sentinel.txt').write_bytes(b'preserve')
        subprocess.run(['cmd.exe', '/d', '/c', 'mklink', '/J', str(self.root / 'linked'), str(target)],
                       capture_output=True, check=True)
        with self.assertRaises(ValueError): snapshot.create(self.root, self.dest, 'WorkingTree')
        self.assertEqual((target / 'sentinel.txt').read_bytes(), b'preserve')

    def test_wrapper_success_failure_and_integrity(self):
        if not HOST:
            self.skipTest('PowerShell host not supplied')
        for mode, success in [('OK', True), ('Fail', False), ('Mutate', False), ('Manifest', False)]:
            dest = self.base / ('run-' + mode)
            result = subprocess.run([HOST, '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                     str(self.root / 'ci/Invoke-Snapshot.ps1'), '-RunDirectory', str(dest),
                                     '-PythonExe', sys.executable, '-Stage', 'Regression', '-TestName', mode],
                                    capture_output=True, timeout=60)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
            outcome = json.loads((dest / 'outcome.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(outcome['Status'], 'Passed' if success else 'Failed')
            self.assertTrue((dest / 'console.log').exists())
            if success:
                self.assertEqual(outcome['Integrity'], 'Passed')
                self.assertEqual(Path((dest / 'logs/marker').read_text(encoding='utf-8-sig').strip()), dest / 'source')
            self.assertEqual((self.root / 'bin/flash.cmd').read_bytes(), b'# parse only fixture\n')

    def test_benchmark_schedule_statistics_and_failure(self):
        snapshot.create(self.root, self.dest, 'WorkingTree')
        cells = [('host', 'empty', 'direct'), ('host', 'empty', 'cmd')]
        seq = benchmark.schedule(cells, 3, 2, 42)
        self.assertEqual(seq, benchmark.schedule(cells, 3, 2, 42))
        self.assertEqual(collections.Counter(cell for _, _, cell in seq), {c: 6 for c in cells})
        for i in range(3):
            first = [c for r, n, c in seq if r == 1 and n == i + 1]
            second = [c for r, n, c in seq if r == 2 and n == i + 1]
            self.assertEqual(first, list(reversed(second)))
        def fake(exe, mode, script):
            return 10.0, 'fixture-version'
        result = benchmark.run(self.dest, [sys.executable], 3, 2, 1, 42, fake)
        report = json.loads(result.read_text())
        self.assertEqual(report['status'], 'Passed')
        self.assertEqual(len(report['samples']), 28)
        self.assertEqual(len(report['summary']), 8)
        self.assertTrue(all(x['count'] == 3 and x['medianMs'] == 10 for x in report['summary']))
        calls = 0
        def fail(exe, mode, script):
            nonlocal calls
            calls += 1
            if calls > 1: raise RuntimeError('EXPECTED_BENCHMARK_FAILURE')
            return 1.0, 'fixture'
        with self.assertRaises(RuntimeError):
            benchmark.run(self.dest, [sys.executable], 1, 1, 1, 42, fail)
        reports = [json.loads(p.read_text()) for p in self.dest.glob('benchmark-*.json')]
        self.assertEqual(sorted(r['status'] for r in reports), ['Failed', 'Passed'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--powershell')
    args, rest = parser.parse_known_args()
    HOST = args.powershell
    unittest.main(argv=[sys.argv[0], *rest], verbosity=2)
