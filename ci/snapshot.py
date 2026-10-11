"""Local CI source capture and integrity verification; standard library only."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
from datetime import datetime, timezone
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)


def safe_name(name):
    p = PurePosixPath(name)
    if (not name or p.is_absolute() or '\\' in name or ':' in name
            or any(x in ('', '.', '..') for x in name.split('/'))
            or any(x.lower() == '.git' for x in p.parts)):
        raise ValueError('Unsafe source name: ' + name)
    return name


def no_links(path):
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError('Symlink is not supported: ' + str(part))
        if part.exists() and getattr(part.lstat(), 'st_file_attributes', 0) & 0x400:
            raise ValueError('Reparse point is not supported: ' + str(part))


def names(root):
    staged = git(root, 'ls-files', '--stage', '-z').split(b'\0')
    if any(x.startswith((b'120000 ', b'160000 ')) for x in staged):
        raise ValueError('Symlinks and submodules need a separate snapshot recipe')
    raw = git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z')
    return sorted({safe_name(x.decode('utf-8')) for x in raw.split(b'\0') if x})


def work_files(root):
    result = {}
    for name in names(root):
        path = root / name
        no_links(path)
        if not path.exists():
            continue  # Preserve working-tree deletions.
        if not path.is_file():
            raise ValueError('Not a regular source file: ' + name)
        result[name] = path.read_bytes()
    return result


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def create(root, destination, kind):
    root = Path(os.path.abspath(root))
    destination = Path(os.path.abspath(destination))
    no_links(root)
    no_links(destination)
    if destination.exists():
        raise ValueError('Destination already exists; use a fresh directory')
    if root == destination or root.is_relative_to(destination):
        raise ValueError('Destination cannot contain the source repository')
    if destination.is_relative_to(root):
        rel = destination.relative_to(root).as_posix()
        if not rel.startswith('tests/.tmp-ci-snapshots/'):
            raise ValueError('In-repository snapshots must use tests/.tmp-ci-snapshots/<run>')
        ignored = subprocess.run(['git', '-C', str(root), 'check-ignore', '-q', '--', rel]).returncode
        if ignored != 0:
            raise ValueError('Snapshot output must be ignored by Git')
    top = Path(git(root, 'rev-parse', '--show-toplevel').decode('utf-8').strip()).resolve()
    if top != root.resolve():
        raise ValueError('Source must be the repository root')
    head = git(root, 'rev-parse', 'HEAD').decode().strip()
    status = git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all')
    if kind == 'Commit' and status:
        raise ValueError('Commit snapshot requires a clean working tree')
    if kind == 'WorkingTree':
        files = work_files(root)
    else:
        entries = git(root, 'ls-tree', '-rz', head).split(b'\0')
        if any(x.startswith((b'120000 ', b'160000 ')) for x in entries):
            raise ValueError('Symlinks and submodules need a separate snapshot recipe')
        archive = git(root, 'archive', '--format=tar', head)
        files = {}
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            for entry in tar:
                if entry.isdir():
                    continue
                if not entry.isfile():
                    raise ValueError('Unsupported archive entry: ' + entry.name)
                files[safe_name(entry.name)] = tar.extractfile(entry).read()
    if not files:
        raise ValueError('Empty snapshot')
    destination.mkdir(parents=True)
    manifest = {'schemaVersion': 1, 'kind': kind, 'head': head, 'dirty': bool(status),
                'createdUtc': datetime.now(timezone.utc).isoformat(), 'state': 'Creating',
                'files': {n: digest(data) for n, data in sorted(files.items())}}
    save(destination / 'manifest.json', manifest)
    source = destination / 'source'
    source.mkdir()
    with zipfile.ZipFile(destination / 'source.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(files.items()):
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            archive.writestr(name, data)
    # A second pass rejects edits made while a working tree was being captured.
    if (git(root, 'rev-parse', 'HEAD').decode().strip() != head
            or git(root, 'status', '--porcelain=v1', '-z', '--untracked-files=all') != status):
        raise ValueError('Repository changed during capture; retain evidence and retry')
    if kind == 'WorkingTree' and {n: digest(d) for n, d in work_files(root).items()} != manifest['files']:
        raise ValueError('Source bytes changed during capture; retain evidence and retry')
    manifest['archiveSha256'] = digest((destination / 'source.zip').read_bytes())
    manifest['state'] = 'Ready'
    save(destination / 'manifest.json', manifest)
    verify(destination)
    return destination


def generated(name):
    parts = PurePosixPath(name).parts
    return ('__pycache__' in parts or name.startswith(('docs/research/', 'tests/manual/', 'dist/'))
            or (len(parts) > 1 and parts[0] == 'tests' and parts[1].startswith('.tmp-')))


def verify(destination):
    destination = Path(destination)
    no_links(destination)
    for item in ('manifest.json', 'source.zip', 'source'):
        no_links(destination / item)
    manifest = json.loads((destination / 'manifest.json').read_text(encoding='utf-8-sig'))
    if manifest.get('schemaVersion') != 1 or manifest.get('state') != 'Ready':
        raise ValueError('Snapshot is not ready')
    if digest((destination / 'source.zip').read_bytes()) != manifest['archiveSha256']:
        raise ValueError('Archive hash mismatch')
    source = destination / 'source'
    for name, expected in manifest['files'].items():
        path = source / safe_name(name)
        no_links(path)
        if not path.is_file() or digest(path.read_bytes()) != expected:
            raise ValueError('Source hash mismatch: ' + name)
    with zipfile.ZipFile(destination / 'source.zip') as archive:
        if set(archive.namelist()) != set(manifest['files']) or len(archive.namelist()) != len(manifest['files']):
            raise ValueError('Archive inventory mismatch')
        for name, expected in manifest['files'].items():
            if digest(archive.read(name)) != expected:
                raise ValueError('Archived source mismatch: ' + name)
    for parent, dirs, files in os.walk(source, followlinks=False):
        for item in dirs + files:
            path = Path(parent) / item
            name = path.relative_to(source).as_posix()
            if generated(name + '/' if item in dirs else name):
                if item in dirs:
                    dirs.remove(item)
                continue
            safe_name(name)
            no_links(path)
            if item in files and name not in manifest['files']:
                raise ValueError('Unexpected source file: ' + name)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('create')
    p.add_argument('--source', required=True)
    p.add_argument('--destination', required=True)
    p.add_argument('--kind', choices=['WorkingTree', 'Commit'], required=True)
    p = sub.add_parser('verify')
    p.add_argument('--destination', required=True)
    args = parser.parse_args()
    try:
        if args.command == 'create':
            create(args.source, args.destination, args.kind)
        else:
            verify(args.destination)
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        parser.exit(1, str(error) + '\n')
    print('Snapshot ' + args.command + ' PASS')


if __name__ == '__main__':
    main()
