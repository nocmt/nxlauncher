#!/usr/bin/env python3
"""Internal release primitives: staging-only normalization, license inventory, signing."""
import argparse
import base64
import csv
import ctypes
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MACHO = {b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
         b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}


def run(*args, **kwargs):
    return subprocess.check_output([str(a) for a in args], **kwargs)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def macho(path):
    if path.is_symlink() or not path.is_file(): return False
    with path.open('rb') as stream: return stream.read(4) in MACHO


def replace(source, destination):
    """Atomic publication on one filesystem; never remove an existing app first."""
    source, destination = Path(source), Path(destination)
    if destination.is_symlink(): raise ValueError('Output may not be a symlink')
    if destination.exists() and source.is_dir():
        if sys.platform != 'darwin': raise ValueError('Atomic directory exchange requires macOS')
        libc = ctypes.CDLL(None, use_errno=True)
        rename = libc.renamex_np
        rename.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
        rename.restype = ctypes.c_int
        if rename(os.fsencode(source), os.fsencode(destination), 2):
            number = ctypes.get_errno()
            raise OSError(number, os.strerror(number), str(destination))
    else:
        os.replace(source, destination)


def sign_tree(root, identity, timestamp='none'):
    if identity != '-' and not identity.startswith('Developer ID Application: '):
        raise ValueError('Release signing requires a Developer ID Application identity or explicit ad-hoc -')
    targets = sorted((p for p in Path(root).rglob('*') if macho(p)),
                     key=lambda p: (-len(p.parts), str(p)))
    for path in targets:
        command = ['codesign', '--force', '--sign', identity, '--options', 'runtime',
                   '--timestamp' if timestamp == 'secure' and identity != '-' else '--timestamp=none']
        if path.name == 'dmsh_xlate':
            command += ['--entitlements', str(ROOT / 'Scripts/translator.entitlements.plist')]
        # A secure timestamp comes from Apple's timestamp server, which occasionally drops a
        # request mid-build. Retry those transient failures instead of losing the whole run.
        for attempt in range(4):
            try:
                run(*command, path, stderr=subprocess.STDOUT)
                break
            except subprocess.CalledProcessError:
                if timestamp != 'secure' or attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))
        run('codesign', '--verify', '--strict', path, stderr=subprocess.STDOUT)
        # Also reject developer/homebrew linked dependencies in native binaries.
        dependencies = run('otool', '-L', path, text=True)
        for line in dependencies.splitlines()[1:]:
            dependency = line.strip().split(' (', 1)[0]
            if dependency == str(path):
                continue
            if dependency.startswith('/') and not dependency.startswith(('/usr/lib/', '/System/Library/')):
                if dependency.startswith('/DLC/'):
                    continue
                raise ValueError(f'Non-system absolute Mach-O dependency: {path.name}: {dependency}')
    return len(targets)


def prepare_python(payload, original):
    root = payload / 'python'
    version = run(original / 'bin/python3', '-I', '-c',
                  'import json,platform,sys; print(json.dumps([list(sys.version_info[:3]),sys.platform,platform.machine()]))', text=True)
    actual, system, arch = json.loads(version)
    if actual != [3, 13, 15] or system != 'darwin' or arch != 'arm64':
        raise ValueError('Release requires pinned CPython 3.13.15 macOS arm64')
    if (original / 'BUILD').read_text().strip() != '20260807':
        raise ValueError('Standalone Python build must be 20260807; review licenses before updating')
    # uv rewrites this installation identifier to a local path. Fix only the staging copy.
    dylib = root / 'lib/libpython3.13.dylib'
    run('install_name_tool', '-id', '@rpath/libpython3.13.dylib', dylib)
    for config in root.rglob('_sysconfigdata*.py'):
        text = config.read_text()
        # sysconfig build paths are metadata; use this installation's actual runtime prefix.
        for prefix in {str(original), str(original.resolve())}:
            text = text.replace(prefix, '{NXLAUNCHER_PYTHON_PREFIX}')
        text += '\n# NxLauncher: relocate installer-specific build metadata, not the original environment.\n'
        text += 'import sys as _sys\n'
        text += 'build_time_vars = {k: (v.replace("{NXLAUNCHER_PYTHON_PREFIX}", _sys.prefix) if isinstance(v, str) else v) for k, v in build_time_vars.items()}\n'
        config.write_text(text)
    # Strip local bytecode and install-only headers/static libraries, not licenses/pip.
    for path in sorted(root.rglob('*'), key=lambda p: -len(p.parts)):
        if path.is_file() and (path.suffix in ('.pyc', '.pyo', '.a') or path.name == '.DS_Store'):
            path.unlink()
        elif path.is_dir() and path.name == '__pycache__': shutil.rmtree(path)
    # macOS runtime already includes pip. Remove ensurepip's duplicate Windows
    # launchers and distlib Windows executable stubs only from staging.
    shutil.rmtree(root / 'lib/python3.13/ensurepip', ignore_errors=True)
    for executable in (root / 'lib/python3.13/site-packages/pip/_vendor/distlib').glob('*.exe'):
        executable.unlink()
    # Symlinks from PBS are internal aliases and are preserved; never follow external links.
    for path in root.rglob('*'):
        if path.is_symlink() and (not path.resolve().is_relative_to(root.resolve()) or not path.exists()):
            raise ValueError('Python contains an escaping or broken symlink')
    run(root / 'bin/python3', '-I', '-B', '-c', 'import ssl,sqlite3,ctypes,sysconfig; assert sysconfig.get_path("stdlib")',
        env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
    return {'name': 'CPython / python-build-standalone', 'version': '3.13.15', 'build': '20260807',
            'source': 'https://github.com/astral-sh/python-build-standalone/releases/tag/20260807',
            'provenance_scope': 'local installation reports BUILD and Python version; upstream archive digest not attested',
            'modifications': ['relocatable dylib id', 'dynamic sysconfig prefix', 'remove bytecode/static archives',
                              'remove duplicate ensurepip bundled wheel and macOS-unused distlib Windows executable launchers'],
            'license': 'PSF-2.0 plus bundled component licenses; see licenses/python-build-standalone-20260807'}


def inventory(payload, original):
    licenses = payload / 'licenses'
    shutil.copytree(ROOT / 'Scripts/licenses', licenses)
    if not (payload / 'python').is_dir():
        shutil.copytree(original, payload / 'python', symlinks=True)
    for item in json.loads((licenses / 'provenance.json').read_text()):
        if sha(licenses / item['file']) != item['sha256']:
            raise ValueError('License hash mismatch: ' + item['file'])
    dependencies = [prepare_python(payload, original)]
    wheel_expected = {'backports.zstd': '1.8.0', 'capstone': '5.0.9', 'fonttools': '4.67.0',
                      'lz4': '4.4.5', 'pillow': '13.0.0'}
    from email.parser import BytesParser
    for wheel in sorted((payload / 'wheels').glob('*.whl')):
        with zipfile.ZipFile(wheel) as archive:
            meta = BytesParser().parsebytes(archive.read(next(n for n in archive.namelist() if n.endswith('/METADATA'))))
            name, version = meta['Name'].lower(), meta['Version']
            if wheel_expected.pop(name, None) != version: raise ValueError('Unexpected wheel: ' + wheel.name)
            full = []
            for member in archive.namelist():
                if not member.endswith('/') and any(k in member.lower() for k in ('license', 'notice', 'copying')):
                    target = licenses / ('wheel-' + name + '-' + version) / Path(member).name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() and target.read_bytes() != archive.read(member):
                        target = target.with_name(target.stem + '-' + hashlib.sha256(member.encode()).hexdigest()[:8] + target.suffix)
                    target.write_bytes(archive.read(member)); full.append(str(target.relative_to(payload)))
            if not full: raise ValueError('Wheel has no license text: ' + wheel.name)
            dependencies.append({'name': name, 'version': version, 'artifact': wheel.name,
                                 'source': f'https://pypi.org/project/{name}/{version}/',
                                 'original_sha256': sha(wheel), 'license_files': full,
                                 'modifications': 'native members re-signed, RECORD regenerated for offline installation'})
    if wheel_expected: raise ValueError('Missing required wheels')
    nx = payload / 'nxnative'
    # Retain all vendored licenses in context and provide a convenient extra copy.
    for path in nx.rglob('*'):
        if path.is_file() and any(k in path.name.lower() for k in ('license', 'notice', 'copying', 'patents', 'authors')):
            target = licenses / 'nxnative' / path.relative_to(nx)
            target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(path, target)
    binary = nx / 'dm/gfx/tools/dmsh_xlate_bin'
    expected = json.loads((licenses / 'dll-inventory.json').read_text())['sha256']
    actual = {p.relative_to(binary).as_posix(): sha(p) for p in binary.rglob('*.dll')}
    if actual != expected: raise ValueError('Bundled DLL bytes changed; reverify NuGet provenance and licenses')
    deps = json.loads((binary / 'dmsh_xlate.deps.json').read_text())
    libraries = deps['libraries']
    dependencies.append({'name': 'dmsh_xlate managed dependencies', 'libraries': libraries,
                         'dll_sha256': actual, 'source': 'pinned nxnative and NuGet packages',
                         'limitations': 'prebuilt project DLLs not reproducibly rebuilt; net10 runtime external'})
    dependencies.append({'name': 'Noto Sans SC', **json.loads((ROOT / 'Scripts/fonts/provenance.json').read_text())})
    (payload / 'dependency-manifest.json').write_text(json.dumps({
        'dependencies': dependencies,
        'vendor_path_disclosures': [
            {'artifact': 'nxnative/dm/gfx/tools/dmsh_xlate_bin/Gommon.dll',
             'sha256': '1648a882b8986d660e8e0063445c41abb0641fe57edc49143af165c3f00f2bd7',
             'upstream_commit': '201dfd1280684e9d3ceac8b644236fdac11b6cc2',
             'embedded_vendor_build_path_components': ['C:', 'Users', 'gr33m'],
             'scope': 'Exact NuGet and upstream Git object bytes; vendor build path warning, not publisher path. DLL unchanged.'},
            {'scope': 'Pinned AppDataManager.cs, pip urls.py, Activate.ps1 contain generic documentation examples; exact hashes audited.'}
        ]}, indent=2) + '\n')


def sign_wheels(payload, identity, timestamp):
    for wheel in sorted((payload / 'wheels').glob('*.whl')):
        with tempfile.TemporaryDirectory(prefix='.wheel-', dir=payload.parent) as tmp:
            stage = Path(tmp)
            with zipfile.ZipFile(wheel) as archive:
                for member in archive.infolist():
                    parts = Path(member.filename).parts
                    if member.filename.startswith('/') or '..' in parts or member.file_size > 512 * 1024 * 1024:
                        raise ValueError('Unsafe wheel member')
                archive.extractall(stage)
            sign_tree(stage, identity, timestamp)
            record = next(stage.glob('*.dist-info/RECORD'))
            for signature in (record.with_name('RECORD.jws'), record.with_name('RECORD.p7s')):
                signature.unlink(missing_ok=True)
            rows = []
            for path in sorted(stage.rglob('*')):
                if path.is_file() and path != record:
                    digest = base64.urlsafe_b64encode(hashlib.sha256(path.read_bytes()).digest()).rstrip(b'=').decode()
                    rows.append([path.relative_to(stage).as_posix(), 'sha256=' + digest, str(path.stat().st_size)])
            rows.append([record.relative_to(stage).as_posix(), '', ''])
            with record.open('w', newline='') as stream: csv.writer(stream).writerows(rows)
            with zipfile.ZipFile(wheel, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(stage.rglob('*')):
                    if path.is_file(): archive.write(path, path.relative_to(stage).as_posix())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('publish'); p.add_argument('source', type=Path); p.add_argument('destination', type=Path)
    p = sub.add_parser('payload'); p.add_argument('path', type=Path); p.add_argument('python', type=Path)
    p.add_argument('--identity', required=True); p.add_argument('--timestamp', choices=('none', 'secure'), default='none')
    p = sub.add_parser('sign'); p.add_argument('path', type=Path); p.add_argument('--identity', required=True)
    p.add_argument('--timestamp', choices=('none', 'secure'), default='none')
    args = parser.parse_args()
    if args.command == 'publish': replace(args.source, args.destination)
    elif args.command == 'payload':
        inventory(args.path, args.python)
        count = sign_tree(args.path, args.identity, args.timestamp)
        sign_wheels(args.path, args.identity, args.timestamp)
        print(json.dumps({'signed_macho_files': count, 'wheels_signed': True}))
    elif args.command == 'sign':
        print(json.dumps({'signed_macho_files': sign_tree(args.path, args.identity, args.timestamp)}))


if __name__ == '__main__':
    main()
