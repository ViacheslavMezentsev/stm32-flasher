"""Hardware-free isolated-runner contracts, including nested Windows jobs."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import zipfile
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'ci'))
import isolated
from snapshot import digest, save, verify

HOST = None


class IsolatedTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = Path(tempfile.mkdtemp(prefix='.tmp-ir-', dir=REPO / 'tests'))
        cls.base = cls.root / 's'
        source = cls.base / 'source'
        (source / 'tests').mkdir(parents=True)
        (source / 'bin').mkdir()
        (source / 'ci').mkdir()
        shutil.copyfile(REPO / 'tests/Invoke-Tests.ps1', source / 'tests/Invoke-Tests.ps1')
        for name in ('isolated.py','snapshot.py','Invoke-Isolated.ps1'):
            shutil.copyfile(REPO / 'ci' / name, source / 'ci' / name)
        (source / 'bin/flash.cmd').write_text('# fixture\n')
        good = '''$ErrorActionPreference='Stop'
Get-Command Get-FileHash,Add-Type -ErrorAction Stop | Out-Null
New-Item -ItemType Directory tests/.tmp-shared | Out-Null
if ($env:ISOLATION_VALUE) { throw 'ENV_LEAK' }
$env:ISOLATION_VALUE='local'
$value=$env:ISOLATION_ROOT
Set-Content tests/.tmp-shared/fixed.txt $value
Set-Content (Join-Path $env:TEMP 'fixed.txt') $value
Start-Sleep -Milliseconds 500
if ((Get-Content tests/.tmp-shared/fixed.txt) -ne $value) { throw 'CWD_COLLISION' }
if ((Get-Content (Join-Path $env:TMP 'fixed.txt')) -ne $value) { throw 'TEMP_COLLISION' }
'''
        scripts = {'Test-A.ps1': good, 'Test-B.ps1': good,
                   'Test-Fail.ps1': "throw 'EXPECTED_FAILURE'",
                   'Test-Mutate.ps1': "Set-Content bin/flash.cmd 'mutated'"}
        child = '''$ErrorActionPreference='Stop'
New-Item -ItemType Directory tests/.tmp-child | Out-Null
$p=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 60"' -WindowStyle Hidden -PassThru
Set-Content tests/.tmp-child/pid.txt $p.Id
'''
        scripts['Test-Leak.ps1'] = child
        scripts['Test-Drain.ps1'] = child.replace('Start-Sleep -Seconds 60', 'Start-Sleep -Milliseconds 250')
        scripts['Test-Hang.ps1'] = child + '\nStart-Sleep -Seconds 60\n'
        for name, text in scripts.items():
            (source / 'tests' / name).write_text(text, encoding='utf-8')
        files = {p.relative_to(source).as_posix(): p.read_bytes() for p in source.rglob('*') if p.is_file()}
        with zipfile.ZipFile(cls.base / 'source.zip', 'w') as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        save(cls.base / 'manifest.json', {'schemaVersion':1,'state':'Ready','kind':'Fixture',
             'files':{n:digest(d) for n,d in files.items()},
             'archiveSha256':digest((cls.base / 'source.zip').read_bytes())})
        cls.sequence = 0

    @classmethod
    def tearDownClass(cls):
        # Keep failed-run artifacts for diagnosis; runner inputs remain in this ignored root.
        print('Isolated contract evidence: ' + str(cls.root), flush=True)

    def output(self):
        type(self).sequence += 1
        return self.root / str(self.sequence)

    def assert_children_gone(self, report):
        for row in report['results']:
            pid_file = Path(row['directory']) / 'source/tests/.tmp-child/pid.txt'
            if pid_file.exists():
                pid = int(pid_file.read_text(encoding='utf-8-sig'))
                result = subprocess.run([HOST,'-NoProfile','-Command',
                    f'if(Get-Process -Id {pid} -ErrorAction SilentlyContinue){{exit 1}}'],
                    env=isolated.shell_environment(), capture_output=True, timeout=15)
                self.assertEqual(result.returncode, 0, f'Child remains: {pid}')

    def test_parallel_and_sequential_isolation(self):
        for workers in (1,2):
            report = isolated.run(self.base, self.output(), HOST, workers, ['Test-A.ps1','Test-B.ps1'])
            self.assertEqual(report['status'], 'Passed', report)
            self.assertTrue(report['partial'])
            a,b = report['results']
            overlap = max(datetime.fromisoformat(r['startedUtc']) for r in (a,b)) < min(datetime.fromisoformat(r['finishedUtc']) for r in (a,b))
            self.assertEqual(overlap, workers == 2)
            self.assertNotEqual(a['directory'], b['directory'])
            self.assertTrue(all(r['leftoverProcesses']==0 for r in (a,b)))

    def test_bounded_process_settling(self):
        report = isolated.run(self.base, self.output(), HOST, 1, ['Test-Drain.ps1'])
        self.assertEqual(report['status'], 'Passed', report)
        self.assertEqual(report['results'][0]['leftoverProcesses'], 0)
        self.assertLess(report['results'][0]['settleSeconds'], 1.5)
        self.assert_children_gone(report)

    def test_failures_continue_and_preserve_integrity_evidence(self):
        report = isolated.run(self.base, self.output(), HOST, 2,
                              ['Test-Fail.ps1','Test-Mutate.ps1','Test-Leak.ps1','Test-Hang.ps1','Test-A.ps1'], timeout=5)
        rows = {r['suite']:r for r in report['results']}
        self.assertEqual(report['status'], 'Failed')
        self.assertEqual(len(rows),5)
        self.assertEqual(rows['Test-A.ps1']['status'],'Passed')
        self.assertEqual(rows['Test-Mutate.ps1']['integrity'],'Failed')
        self.assertEqual(rows['Test-Hang.ps1']['error'],'Suite timeout')
        self.assertGreater(rows['Test-Leak.ps1']['leftoverProcesses'],0)
        self.assertTrue(rows['Test-Leak.ps1']['postExitMembers'])
        self.assert_children_gone(report)
        verify(self.base)

    def test_deadline(self):
        report = isolated.run(self.base,self.output(),HOST,1,['Test-Hang.ps1','Test-A.ps1'], run_timeout=6)
        self.assertEqual(report['status'],'Cancelled',report)
        self.assertEqual(len(report['results']),2)
        self.assertTrue(all(r['status']=='Cancelled' for r in report['results']))
        self.assert_children_gone(report)

    def test_cancel_active_and_pending(self):
        dest = self.output()
        stop = threading.Event()
        def cancel_when_child_starts():
            limit = time.monotonic()+15
            while time.monotonic()<limit and not (dest/'01/source/tests/.tmp-child/pid.txt').exists():
                time.sleep(.05)
            stop.set()
        thread = threading.Thread(target=cancel_when_child_starts)
        thread.start()
        try:
            report = isolated.run(self.base,dest,HOST,1,['Test-Hang.ps1','Test-A.ps1'],stop=stop)
        finally:
            stop.set()
            thread.join(timeout=20)
        self.assertEqual(report['status'],'Cancelled',report)
        self.assertEqual(len(report['results']),2)
        self.assert_children_gone(report)

    def test_invalid_selection_destination_and_evidence(self):
        for value in (0, -1, float('inf'), float('nan')):
            with self.assertRaises(ValueError):
                isolated.run(self.base,self.output(),HOST,timeout=value)
            with self.assertRaises(ValueError):
                isolated.run(self.base,self.output(),HOST,run_timeout=value)
        for names in ([],['Test-A.ps1','Test-A.ps1'],['../Test-A.ps1'],['Test-*.ps1']):
            out=self.output()
            with self.assertRaises(ValueError): isolated.run(self.base,out,HOST,2,names)
            self.assertFalse(out.exists())
        with self.assertRaises(ValueError): isolated.run(self.base,self.base,HOST,2,['Test-A.ps1'])
        # A zero exit is insufficient: remove the runner's result file after child completion.
        real=isolated.Job.drain
        def delete_result(job):
            value=real(job)
            for file in out.glob('*/logs/results.json'):
                file.unlink()
            return value
        out=self.output()
        with patch.object(isolated.Job,'drain',delete_result):
            report=isolated.run(self.base,out,HOST,1,['Test-A.ps1'])
        self.assertEqual(report['status'],'Failed')
        with self.assertRaises(ValueError): isolated.run(self.base,out,HOST,1,['Test-A.ps1'])

    def test_cli_and_powershell_entry(self):
        entry=REPO/'ci/Invoke-Isolated.ps1'
        out=self.output()
        prefix=[HOST,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(entry),
                '-SnapshotDirectory',str(self.base),'-PythonExe',sys.executable,'-LogDirectory',str(out)]
        result=subprocess.run(prefix+['-List','-TestName','Test-A.ps1'],capture_output=True,timeout=30,env=isolated.shell_environment())
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertFalse(out.exists())
        result=subprocess.run(prefix+['-Workers','2','-TestName','Test-A.ps1','-PowerShellExe',HOST],
                              capture_output=True,timeout=40,env=isolated.shell_environment())
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        data=json.loads(next(out.glob('*/run.json')).read_text())
        self.assertEqual(data['status'],'Passed')
        self.assertEqual(len(data['results']),1)
        self.assertTrue(data['partial'])
        failed=self.output()
        result=subprocess.run([HOST,'-NoProfile','-ExecutionPolicy','Bypass','-File',str(entry),
            '-SnapshotDirectory',str(self.base),'-PythonExe',sys.executable,
            '-LogDirectory',str(failed),'-TestName','Test-Fail.ps1','-PowerShellExe',HOST],
            capture_output=True,timeout=40,env=isolated.shell_environment())
        self.assertNotEqual(result.returncode,0)
        data=json.loads(next(failed.glob('*/run.json')).read_text())
        self.assertEqual(data['status'],'Failed')
        cancelled=self.output()
        result=subprocess.run([sys.executable,'-B',str(self.base/'source/ci/isolated.py'),
            '--snapshot',str(self.base),'--output',str(cancelled),'--host',HOST,
            '--run-timeout','0.001'],capture_output=True,timeout=30,
            env=isolated.shell_environment())
        self.assertEqual(result.returncode,130,result.stdout+result.stderr)
        self.assertEqual(json.loads((cancelled/'run.json').read_text())['status'],'Cancelled')

    def test_relative_paths_after_set_location(self):
        out=self.output()
        command=(f"Set-Location {isolated.ps(self.root)}; "
                 f"& {isolated.ps(REPO/'ci/Invoke-Isolated.ps1')} -SnapshotDirectory s "
                 f"-PythonExe {isolated.ps(sys.executable)} -PowerShellExe {isolated.ps(HOST)} "
                 f"-LogDirectory {isolated.ps(out.name)} -TestName Test-A.ps1")
        result=subprocess.run([HOST,'-NoProfile','-ExecutionPolicy','Bypass','-Command',command],
                              cwd=REPO,capture_output=True,timeout=40,env=isolated.shell_environment())
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertEqual(json.loads(next(out.glob('*/run.json')).read_text())['status'],'Passed')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--powershell',required=True)
    args,rest=parser.parse_known_args()
    HOST=args.powershell
    unittest.main(argv=[sys.argv[0],*rest],verbosity=2)
