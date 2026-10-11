"""No hardware: fake runner processes and strict comparison evidence contracts."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'ci'))
import compare
from snapshot import digest, save

FAKE = r"""
import argparse,json,sys
from pathlib import Path
from hashlib import sha256
p=argparse.ArgumentParser()
for name in ('snapshot','output','host','workers'): p.add_argument('--'+name,required=True)
a,_=p.parse_known_args()
s,o=Path(a.snapshot),Path(a.output)
o.mkdir(parents=True)
mode=(s.parent/'mode').read_text()
if mode=='cancel': sys.exit(130)
if mode=='missing': sys.exit(0)
m=json.loads((s/'manifest.json').read_text())
names=['Test-A.ps1','Test-B.ps1']
rows=[dict(suite=n,status='Passed',integrity='Passed',exitCode=0,leftoverProcesses=0) for n in names]
t=20 if a.workers=='1' else 10
r=dict(status='Passed',partial=False,workers=int(a.workers),selected=names,
discoveredCount=2,manifestSha256=sha256((s/'manifest.json').read_bytes()).hexdigest(),
runnerSha256=m['files']['ci/isolated.py'],results=rows,
prepareSeconds=1,executionSeconds=t-1,totalSeconds=t,exe=a.host,
shellVersion='fixture',python=sys.version)
if mode=='partial': r['partial']=True
if mode=='identity' and o.name.startswith('2-'): r['shellVersion']='different'
if mode=='mutation': (s/'source/tests/Test-A.ps1').write_text('changed')
(o/'run.json').write_text(json.dumps(r))
(o/'results.json').write_text(json.dumps(rows))
sys.exit(7 if mode=='exit' else 0)
"""


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='.tmp-compare-', dir=REPO/'tests'))
        self.base = self.root/'s'
        source = self.base/'source'
        (source/'ci').mkdir(parents=True)
        (source/'tests').mkdir()
        (source/'ci/isolated.py').write_text(FAKE)
        (source/'ci/compare.py').write_bytes((REPO/'ci/compare.py').read_bytes())
        (source/'ci/snapshot.py').write_bytes((REPO/'ci/snapshot.py').read_bytes())
        for name in ('Test-A.ps1','Test-B.ps1'):
            (source/'tests'/name).write_text("# not executed\n")
        files={p.relative_to(source).as_posix():p.read_bytes() for p in source.rglob('*') if p.is_file()}
        with zipfile.ZipFile(self.base/'source.zip','w') as z:
            for name,data in files.items(): z.writestr(name,data)
        save(self.base/'manifest.json',{'schemaVersion':1,'state':'Ready','head':'fixture',
            'files':{n:digest(d) for n,d in files.items()},
            'archiveSha256':digest((self.base/'source.zip').read_bytes())})
        (self.root/'mode').write_text('ok')

    def test_success_and_existing_output(self):
        out=self.root/'out'
        r=compare.run(self.base,out,sys.executable)
        self.assertEqual(r['status'],'Passed',r)
        self.assertEqual([t['workers'] for t in r['trials']],[1,2,2,1])
        self.assertEqual(r['speedup'],2)
        self.assertEqual(r['medians']['1']['totalSeconds'],20)
        self.assertEqual(len(list(out.glob('*/run.json'))),4)
        with self.assertRaises(ValueError): compare.run(self.base,out,sys.executable)

    def test_failure_preserved_and_other_trials_continue(self):
        for mode in ('missing','partial','identity','exit','mutation'):
            with self.subTest(mode=mode):
                # Mutation is last; preserve the broken snapshot and its evidence.
                (self.root/'mode').write_text(mode)
                r=compare.run(self.base,self.root/mode,sys.executable)
                self.assertEqual(r['status'],'Failed',r)
                self.assertIsNone(r['speedup'])
                self.assertEqual(len(r['trials']),4)
                self.assertNotIn('Median total-time ratio',compare.markdown(r))

    def test_cli_cancel_and_failure(self):
        for mode,code,count in (('cancel',130,1),('exit',1,4),('ok',0,4)):
            (self.root/'mode').write_text(mode)
            out=self.root/mode
            result=subprocess.run([sys.executable,'-B',str(self.base/'source/ci/compare.py'),
                '--snapshot',str(self.base),'--output',str(out),'--host',sys.executable],
                capture_output=True,timeout=20)
            self.assertEqual(result.returncode,code,result.stdout+result.stderr)
            r=json.loads((out/'comparison.json').read_text())
            self.assertEqual(len(r['trials']),count)
            if code: self.assertIsNone(r['speedup'])

    def test_evidence_rejects_invalid_reports(self):
        r=compare.run(self.base,self.root/'good',sys.executable)
        good=r['trials'][0]['report']
        directory=self.root/'evidence'
        directory.mkdir()
        cases=[
            lambda x:x.update(status='Running'),
            lambda x:x.update(partial=True),
            lambda x:x.update(workers=2),
            lambda x:x.update(manifestSha256='wrong'),
            lambda x:x.update(runnerSha256='wrong'),
            lambda x:x.update(discoveredCount=3),
            lambda x:x.update(selected=['Test-A.ps1']),
            lambda x:x.update(totalSeconds=float('nan')),
            lambda x:x.update(totalSeconds=0),
            lambda x:x.update(executionSeconds=999),
            lambda x:x.update(python=''),
            lambda x:x['results'][0].update(status='Failed'),
            lambda x:x['results'][0].update(integrity='Failed'),
            lambda x:x['results'][0].update(exitCode=1),
            lambda x:x['results'][0].update(leftoverProcesses=1),
            lambda x:x['results'][1].update(suite='Test-A.ps1'),
        ]
        for mutate in cases:
            bad=copy.deepcopy(good)
            mutate(bad)
            save(directory/'run.json',bad)
            save(directory/'results.json',bad['results'])
            with self.assertRaises(ValueError):
                compare.inspect_report(directory,1,good['selected'],good['manifestSha256'],good['runnerSha256'])
        save(directory/'run.json',good)
        save(directory/'results.json',[])
        with self.assertRaises(ValueError):
            compare.inspect_report(directory,1,good['selected'],good['manifestSha256'],good['runnerSha256'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
