#!/usr/bin/env python3
"""Bounded company instructions and reviewed handoffs; never execute their content."""
from __future__ import annotations

import argparse
import base64
import contextlib
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import pwd
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

MAX_FILES = 128
MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 64 * 1024 * 1024
BASE = Path('/etc/vdm-opencode/company')
FORBIDDEN = re.compile(r'^(?:\.env(?:\..*)?|auth\.json|mcp-auth\.json|credentials?(?:\..*)?|secrets?(?:\..*)?|id_(?:rsa|ed25519|ecdsa)(?:\..*)?)$|\.(?:pem|key|p12|pfx)$', re.I)
SECRET = re.compile(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|hv[sb]\.[A-Za-z0-9_-]{20,})\b|\b(?:Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{16,}|\b(?:api[_-]?key|access[_-]?token|token|secret|password|authorization)["\x27]?\s*[:=]\s*["\x27]?[A-Za-z0-9_./+~=-]{12,}', re.I)


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_path(value: str, *, instructions: bool = False) -> str:
    if not isinstance(value, str) or len(value) > 240 or not re.fullmatch(r'[A-Za-z0-9_./-]+', value):
        raise ValueError('File paths must contain only letters, numbers, dots, slashes, underscores and hyphens')
    parts = value.split('/')
    if any(p in ('', '.', '..') or (p.startswith('.') and not (i == 0 and p == '.artifacts')) or FORBIDDEN.search(p) for i, p in enumerate(parts)):
        raise ValueError('Hidden, credential, absolute and traversal paths cannot be transferred')
    if instructions and not value.lower().endswith('.md'):
        raise ValueError('Company instructions must be Markdown files')
    if not instructions and PurePosixPath(value).suffix.lower() not in ('.md', '.txt', '.json', '.xml', '.csv', '.diff', '.patch', '.zip'):
        raise ValueError('Handoffs allow Markdown, text, JSON, XML, CSV, diffs, patches and ZIP artifacts only')
    return value


def check_content(data: bytes, path: str, *, archive: bool = False) -> None:
    if len(data) > MAX_FILE:
        raise ValueError('A selected file exceeds the 16 MiB limit')
    if SECRET.search(data):
        raise ValueError('Possible credential material detected; redact the selected content before transfer')
    if archive and (path.lower().endswith(('.zip', '.tar', '.gz', '.tgz', '.xz', '.bz2', '.7z', '.rar')) or data.startswith((b'PK\x03\x04', b'\x1f\x8b', b'\xfd7zXZ\x00', b'7z\xbc\xaf\x27\x1c', b'Rar!'))):
        raise ValueError('Nested archives are not accepted in a handoff')
    if path.lower().endswith('.zip'):
        if archive:
            raise ValueError('Nested archives are not accepted in a handoff')
        with zipfile.ZipFile(io.BytesIO(data)) as bundle:
            entries = bundle.infolist()
            if len(entries) > 5000 or sum(e.file_size for e in entries) > MAX_TOTAL:
                raise ValueError('Archive expansion exceeds the handoff limits')
            names: set[str] = set()
            for entry in entries:
                name = entry.filename.rstrip('/')
                # Source-code/assets are allowed inside an extension archive, but
                # hidden paths, credentials, links and nested archives are not.
                if name in names or not name or len(name) > 240 or not re.fullmatch(r'[A-Za-z0-9_./-]+', name):
                    raise ValueError('Unsafe or duplicate archive member')
                names.add(name)
                if any(p in ('', '.', '..') or p.startswith('.') or FORBIDDEN.search(p) for p in name.split('/')):
                    raise ValueError('Unsafe or credential archive member')
                mode = entry.external_attr >> 16
                if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)) or entry.flag_bits & 1:
                    raise ValueError('Links, special files and encrypted archives are not accepted')
                if not entry.is_dir():
                    if entry.file_size > MAX_FILE:
                        raise ValueError('Archive member exceeds the size limit')
                    check_content(bundle.read(entry), name, archive=True)


def read_json(stream: object) -> dict:
    raw = stream.read(MAX_TOTAL * 2 + 1)
    if len(raw) > MAX_TOTAL * 2:
        raise ValueError('Transfer exceeds the size limit')
    result = json.loads(raw)
    if not isinstance(result, dict):
        raise ValueError('Expected a JSON object')
    return result


def read_regular(root: Path, relative: str, limit: int = MAX_FILE) -> bytes:
    """Walk and open through directory descriptors; reject symlink races."""
    flags = os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC
    fd = os.open('/', flags | os.O_DIRECTORY)
    try:
        for part in (*root.absolute().parts[1:], *PurePosixPath(relative).parts[:-1]):
            if part in ('', '.', '..'):
                raise ValueError('Unsafe path component')
            nxt = os.open(part, flags | os.O_DIRECTORY, dir_fd=fd)
            os.close(fd)
            fd = nxt
        child = os.open(PurePosixPath(relative).name, flags | os.O_NONBLOCK, dir_fd=fd)
        with os.fdopen(child, 'rb') as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1 or info.st_size > limit:
                raise ValueError('Only bounded, regular, single-link files are accepted')
            data = stream.read(limit + 1)
            if len(data) > limit:
                raise ValueError('File grew beyond the size limit')
            return data
    finally:
        os.close(fd)


def encode_file(path: str, data: bytes) -> dict:
    return {'path': path, 'sha256': digest(data), 'data': base64.b64encode(data).decode()}


def decode_files(bundle: dict, *, instructions: bool) -> list[tuple[str, bytes]]:
    files = bundle.get('files')
    if not isinstance(files, list) or not 1 <= len(files) <= MAX_FILES:
        raise ValueError('Select between 1 and 128 files')
    output: list[tuple[str, bytes]] = []
    seen: set[str] = set()
    total = 0
    for item in files:
        path = safe_path(item['path'], instructions=instructions)
        if path in seen:
            raise ValueError('Duplicate selected file')
        seen.add(path)
        data = base64.b64decode(item['data'], validate=True)
        if digest(data) != item['sha256']:
            raise ValueError('File checksum mismatch')
        check_content(data, path)
        if instructions:
            data.decode('utf-8')
            if len(data) > 1024 * 1024:
                raise ValueError('An instruction file exceeds 1 MiB')
        total += len(data)
        if total > (8 * 1024 * 1024 if instructions else MAX_TOTAL):
            raise ValueError('Selected files exceed the aggregate size limit')
        output.append((path, data))
    return output


def from_git(repository: Path, revision: str) -> dict:
    def git(*args: str) -> bytes:
        return subprocess.run(['git', '-C', str(repository), *args], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout
    if not re.fullmatch(r'[A-Za-z0-9_./-]+', revision) or revision.startswith('-'):
        raise ValueError('Unsafe Git revision')
    commit = git('rev-parse', '--verify', revision + '^{commit}').decode().strip()
    if not re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}', commit):
        raise ValueError('Git did not resolve a full commit identity')
    def blob(path: str) -> bytes:
        entry = git('ls-tree', '-z', commit, '--', path)
        if not entry.startswith((b'100644 blob ', b'100755 blob ')) or entry.count(b'\0') != 1:
            raise ValueError('Company instructions must be committed regular files')
        # Bound git output before reading potentially large committed content.
        size = int(git('cat-file', '-s', commit + ':' + path))
        if size > 1024 * 1024:
            raise ValueError('Company file exceeds 1 MiB')
        return git('show', commit + ':' + path)
    manifest = json.loads(blob('company-context.json'))
    if set(manifest) != {'schema', 'name', 'instructions'} or manifest['schema'] != 1:
        raise ValueError('Invalid company-context.json schema')
    if not isinstance(manifest['name'], str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_. -]{0,79}', manifest['name']):
        raise ValueError('Invalid company context name')
    if not isinstance(manifest['instructions'], list) or not 1 <= len(manifest['instructions']) <= MAX_FILES:
        raise ValueError('Company manifest must explicitly select 1–128 Markdown files')
    files = []
    total = 0
    for name in manifest['instructions']:
        safe_path(name, instructions=True)
        data = blob(name)
        total += len(data)
        if total > 8 * 1024 * 1024:
            raise ValueError('Company instructions exceed the 8 MiB aggregate limit')
        files.append(encode_file(name, data))
    bundle = {'schema': 1, 'kind': 'company-context', 'name': manifest['name'], 'revision': commit, 'files': files}
    decode_files(bundle, instructions=True)
    bundle['snapshot'] = digest(canonical(bundle))
    return bundle


def check_bundle(bundle: dict) -> list[tuple[str, bytes]]:
    if set(bundle) != {'schema', 'kind', 'name', 'revision', 'files', 'snapshot'} or bundle['schema'] != 1 or bundle['kind'] != 'company-context':
        raise ValueError('Invalid company snapshot envelope')
    if not isinstance(bundle['revision'], str) or not re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}', bundle['revision']):
        raise ValueError('Company snapshot requires an exact Git commit')
    if bundle['snapshot'] != digest(canonical({k: v for k, v in bundle.items() if k != 'snapshot'})):
        raise ValueError('Company snapshot checksum mismatch')
    validate_provenance({k: v for k, v in bundle.items() if k != 'files'})
    return decode_files(bundle, instructions=True)


def validate_provenance(value: dict | None) -> dict | None:
    if value is None:
        return None
    if not isinstance(value, dict) or set(value) != {'schema', 'kind', 'name', 'revision', 'snapshot'} or value['schema'] != 1 or value['kind'] != 'company-context':
        raise ValueError('Invalid company provenance')
    if not isinstance(value['name'], str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_. -]{0,79}', value['name']):
        raise ValueError('Invalid company provenance name')
    if not isinstance(value['revision'], str) or not re.fullmatch(r'[a-f0-9]{40}|[a-f0-9]{64}', value['revision']):
        raise ValueError('Invalid company provenance commit')
    if not isinstance(value['snapshot'], str) or not re.fullmatch(r'[a-f0-9]{64}', value['snapshot']):
        raise ValueError('Invalid company provenance snapshot')
    if SECRET.search(canonical(value)):
        raise ValueError('Possible credential material in company provenance')
    return value


def private_directory(path: Path) -> None:
    path.mkdir(mode=0o755, parents=True, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise ValueError('Company configuration must be a root-owned directory without group/other writes')


def atomic_json(path: Path, value: dict, *, owner: tuple[int, int] = (0, 0), mode: int = 0o644) -> None:
    # Hold the directory descriptor across creation/rename: an agent controls
    # its OpenCode config directory and may replace it while we synchronize.
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    directory = os.open('/', flags)
    for part in path.absolute().parent.parts[1:]:
        try:
            child = os.open(part, flags, dir_fd=directory)
        except BaseException:
            os.close(directory)
            raise
        os.close(directory)
        directory = child
    temporary = '.company-' + secrets.token_hex(16)
    try:
        fd = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, mode, dir_fd=directory)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(canonical(value) + b'\n')
            stream.flush()
            os.fchmod(stream.fileno(), mode)
            os.fchown(stream.fileno(), *owner)
            os.fsync(stream.fileno())
        os.replace(temporary, path.name, src_dir_fd=directory, dst_dir_fd=directory)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary, dir_fd=directory)
        os.close(directory)


def install_context(bundle: dict, config: Path, base: Path = BASE) -> None:
    if os.geteuid() != 0:
        raise ValueError('Installing company instructions requires guest root')
    files = check_bundle(bundle)
    private_directory(base.parent)
    private_directory(base)
    private_directory(base / 'snapshots')
    lock = os.open(base / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock, 'w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        target = base / 'snapshots' / bundle['snapshot']
        if not target.exists():
            staging = Path(tempfile.mkdtemp(prefix='.snapshot-', dir=base))
            try:
                for name, data in files:
                    path = staging / name
                    path.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                    path.write_bytes(data)
                    path.chmod(0o444)
                (staging / 'provenance.json').write_bytes(canonical({k: v for k, v in bundle.items() if k != 'files'}) + b'\n')
                (staging / 'provenance.json').chmod(0o444)
                staging.chmod(0o755)
                os.rename(staging, target)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        # Do not trust an existing snapshot solely because its name is a hash.
        for name, data in files:
            path = target / name
            info = path.lstat()
            if info.st_uid != 0 or info.st_mode & 0o022 or read_regular(target, name) != data:
                raise ValueError('Existing company snapshot differs or has unsafe ownership')
        config_data = read_regular(config.parent, config.name, 1024 * 1024)
        current = json.loads(config_data)
        previous = current.get('instructions', [])
        if not isinstance(previous, list) or not all(isinstance(p, str) for p in previous):
            raise ValueError('OpenCode instructions must be an array of strings')
        prefix = str(base / 'snapshots') + '/'
        current['instructions'] = [p for p in previous if not p.startswith(prefix)] + [str(target / n) for n, _ in files]
        info = config.stat()
        atomic_json(config, current, owner=(info.st_uid, info.st_gid), mode=stat.S_IMODE(info.st_mode))
        active = {k: v for k, v in bundle.items() if k != 'files'}
        active['files'] = [{'path': n, 'sha256': digest(d)} for n, d in files]
        atomic_json(base / 'active.json', active)


def verify_context(config: Path, base: Path = BASE) -> dict | None:
    if not (base / 'active.json').exists():
        if base.exists() or base.is_symlink():
            raise ValueError('Company configuration exists without its active provenance; synchronize it again')
        return None
    active = json.loads(read_regular(base, 'active.json', 1024 * 1024))
    active_info = (base / 'active.json').lstat()
    if active_info.st_uid != 0 or active_info.st_mode & 0o022:
        raise ValueError('Unsafe company provenance ownership')
    if not re.fullmatch(r'[a-f0-9]{64}', active['snapshot']):
        raise ValueError('Invalid active company snapshot')
    for parent in (base.parent, base, base / 'snapshots', base / 'snapshots' / active['snapshot']):
        info = parent.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise ValueError('Unsafe company snapshot ownership')
    instructions = json.loads(read_regular(config.parent, config.name, 1024 * 1024)).get('instructions', [])
    recovered = []
    for item in active['files']:
        name = safe_path(item['path'], instructions=True)
        target = base / 'snapshots' / active['snapshot']
        info = (target / name).lstat()
        data = read_regular(target, name)
        if info.st_uid != 0 or info.st_mode & 0o022 or digest(data) != item['sha256']:
            raise ValueError('Company instructions changed after synchronization')
        recovered.append(encode_file(name, data))
        if str(target / name) not in instructions:
            raise ValueError('OpenCode is missing a managed company instruction')
    check_bundle({**active, 'files': recovered})
    return {k: v for k, v in active.items() if k != 'files'}


def export_handoff(workspace: Path, paths: list[str], user: str, company: dict | None) -> dict:
    if not 1 <= len(paths) <= MAX_FILES or len(paths) != len(set(paths)):
        raise ValueError('Select between 1 and 128 distinct files')
    for path in paths:
        safe_path(path)
    validate_provenance(company)
    if os.geteuid() == 0:
        account = pwd.getpwnam(user)
        if account.pw_uid == 0:
            raise ValueError('Handoffs must be read as an unprivileged worker user')
        os.initgroups(user, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)
    files = []
    total = 0
    for path in paths:
        data = read_regular(workspace, path, min(MAX_FILE, MAX_TOTAL - total))
        total += len(data)
        check_content(data, path)
        files.append(encode_file(path, data))
    bundle = {'schema': 1, 'kind': 'review-handoff', 'company': company, 'files': files}
    decode_files(bundle, instructions=False)
    return bundle


def receive_handoff(bundle: dict, destination: Path) -> None:
    if set(bundle) != {'schema', 'kind', 'company', 'files'} or bundle['schema'] != 1 or bundle['kind'] != 'review-handoff':
        raise ValueError('Invalid handoff envelope')
    files = decode_files(bundle, instructions=False)
    validate_provenance(bundle['company'])
    destination = destination.absolute()
    if destination.exists() or destination.is_symlink() or not destination.parent.is_dir():
        raise ValueError('Choose a new output directory below an existing parent')
    parent = destination.parent.stat()
    if parent.st_uid != os.geteuid() or parent.st_mode & 0o022:
        raise ValueError('Handoff parent must be owned by the caller and not group/other writable')
    # Reject writable ancestry, not only a writable direct parent: otherwise an
    # untrusted host user could rename that private parent and substitute a link.
    # Root-owned sticky temporary directories preserve ownership on child renames.
    for ancestor in destination.parents:
        info = ancestor.lstat()
        if stat.S_ISLNK(info.st_mode):
            raise ValueError('Handoff destination cannot traverse a symlink')
        if info.st_uid not in (0, os.geteuid()) or (info.st_mode & 0o022 and not (info.st_uid == 0 and info.st_mode & stat.S_ISVTX)):
            raise ValueError('Handoff destination has untrusted writable ancestry')
    destination.mkdir(mode=0o700)
    try:
        for name, data in files:
            path = destination / 'files' / name
            path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with path.open('xb') as stream:
                stream.write(data)
            path.chmod(0o600)
        manifest = {k: v for k, v in bundle.items() if k != 'files'}
        manifest['files'] = [{'path': n, 'sha256': digest(d), 'bytes': len(d)} for n, d in files]
        (destination / 'handoff.json').write_bytes(canonical(manifest) + b'\n')
        (destination / 'handoff.json').chmod(0o600)
    except BaseException:
        shutil.rmtree(destination)
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    source = sub.add_parser('source')
    source.add_argument('repository', type=Path)
    source.add_argument('revision', nargs='?', default='HEAD')
    install = sub.add_parser('install')
    install.add_argument('bundle', type=Path)
    install.add_argument('config', type=Path)
    verify = sub.add_parser('verify')
    verify.add_argument('config', type=Path)
    verify.add_argument('--required', action='store_true')
    export = sub.add_parser('export')
    export.add_argument('workspace', type=Path)
    export.add_argument('user')
    export.add_argument('config', type=Path)
    export.add_argument('files', nargs='+')
    receive = sub.add_parser('receive')
    receive.add_argument('destination', type=Path)
    args = parser.parse_args()
    if args.command == 'source':
        print(json.dumps(from_git(args.repository, args.revision)))
    elif args.command == 'install':
        with args.bundle.open('rb') as stream:
            install_context(read_json(stream), args.config)
    elif args.command == 'verify':
        result = verify_context(args.config)
        if args.required and result is None:
            raise ValueError('No company standards are configured; synchronize them before this session')
        print(json.dumps(result))
    elif args.command == 'export':
        company = verify_context(args.config)
        print(json.dumps(export_handoff(args.workspace, args.files, args.user, company)))
    elif args.command == 'receive':
        receive_handoff(read_json(sys.stdin.buffer), args.destination)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        # Never echo file contents, decoded credentials, or subprocess stderr.
        print(f'Company context/handoff refused: {type(error).__name__}: {error}', file=sys.stderr)
        sys.exit(1)
