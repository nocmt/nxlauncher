#!/usr/bin/env python3
"""Offline, fail-closed release audit. Never reads game folders or starts games."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import zipfile

TOOLS = {'launcher.c', 'make-icns.py', 'make-info-plist.py', 'make-ipa.py',
         'make-mac-app.sh', 'make-signed-ipa.sh', 'make-unsigned-ipa.sh',
         'pack_pipeline.py', 'prepare-nxnative.py', 'shader_chain.py', 'toolchain.py'}
PROHIBITED = re.compile(r'(?i)(?:^|/)(?:prod\.keys|title\.keys|keys|saves?|backups?|\.git|\.venv|__pycache__|\.env)(?:/|$)|\.(?:nsp|xci|nsz|ncz|nca|sav|p12|p8|pem|mobileprovision|pdb|pyc)$')
PERSONAL = re.compile(rb'/Users/(?!runner(?:/|\b)|build(?:/|\b)|builder(?:/|\b)|username(?:/|\b)|user(?:/|\b))[A-Za-z0-9_.-]+(?:/|\b)|/home/(?!runner(?:/|\b)|build(?:/|\b)|builder(?:/|\b)|username(?:/|\b)|user(?:/|\b))[A-Za-z0-9_.-]+(?:/|\b)|[A-Z]:\\Users\\(?!runner)[A-Za-z0-9_.-]+\\')
SECRETS = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----|\b(?:gh[pousr]_[A-Za-z0-9]{30,}|glpat-[A-Za-z0-9_-]{20,})\b|^(?:master_key_[0-9a-f]{2}|aes_kek_generation_source|titlekek_[0-9a-f]{2})\s*=\s*[0-9a-f]{32}\s*$', re.I | re.M)
MAX_MEMBER = 512 * 1024 * 1024
# Exact immutable vendor artifacts reviewed against pinned upstream/NuGet/PBS sources.
# A matching hash alone does not waive the independent credential scan.
REVIEWED_VENDOR_PATHS = {
    'nxnative/dm/gfx/tools/dmsh_xlate_bin/Gommon.dll':
        ('1648a882b8986d660e8e0063445c41abb0641fe57edc49143af165c3f00f2bd7', {b'C:\\Users\\gr33m\\'}),
    'nxnative/dm/third_party/ryujinx/src/Ryujinx.Common/Configuration/AppDataManager.cs':
        ('bffe2a3055f10dd03d9242b3cdbb9db45efc8fb3baf97789793cc3aca9458ed0', {b'C:\\Users\\user\\'}),
    'python/lib/python3.13/site-packages/pip/_internal/utils/urls.py':
        ('2505ab440a171c1a4fb18f408a3eb56ec6633102c272ecab50ed51e96fc1c08a', {b'/Users/foo'}),
    'python/lib/python3.13/venv/scripts/common/Activate.ps1':
        ('eb8ce20f580877d300c4fed60a7f36daa18715d35c50bb3596d6995d023b4ffe', {b'C:\\Users\\MyUser\\'}),
}
CERTIFI_CA = 'python/lib/python3.13/site-packages/pip/_vendor/certifi/cacert.pem'
CERTIFI_CA_SHA256 = 'bbc7e9c01d7551bb8a159b5dedd989b8ee3ce105aff522b68eb1b01bf854cab0'


def vendor_leaf(name):
    # Archive parents precede !; canonical tgz member paths start with ./.
    return name.rsplit('!', 1)[-1].removeprefix('./')


def reviewed_personal_paths(name, data):
    leaf = vendor_leaf(name)
    record = REVIEWED_VENDOR_PATHS.get(leaf)
    return bool(record and hashlib.sha256(data).hexdigest() == record[0]
                and set(PERSONAL.findall(data)) == record[1])


def reviewed_ca(name, data):
    return (vendor_leaf(name) == CERTIFI_CA and b'PRIVATE KEY' not in data
            and hashlib.sha256(data).hexdigest() == CERTIFI_CA_SHA256)


def safe_name(name):
    path = PurePosixPath(name)
    return not path.is_absolute() and '..' not in path.parts and '\\' not in name


def inspect_bytes(name, data, findings, depth=0):
    if depth > 5:
        findings.append(f'archive nesting limit: {name}')
        return
    if PROHIBITED.search(name) and not reviewed_ca(name, data):
        findings.append(f'forbidden file: {name}')
    if PERSONAL.search(data) and not reviewed_personal_paths(name, data):
        findings.append(f'personal absolute path: {name}')
    if SECRETS.search(data):
        findings.append(f'credential/key pattern: {name}')
    if name.endswith(('.whl', '.zip')):
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for member in archive.infolist():
                    if not safe_name(member.filename) or member.file_size > MAX_MEMBER:
                        findings.append(f'unsafe archive member: {name}!{member.filename}')
                    elif not member.is_dir():
                        inspect_bytes(name + '!' + member.filename, archive.read(member), findings, depth + 1)
        except (ValueError, OSError, zipfile.BadZipFile):
            findings.append(f'invalid ZIP: {name}')
    elif name.endswith(('.tgz', '.tar.gz')):
        try:
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
                for member in archive:
                    if not safe_name(member.name) or member.size > MAX_MEMBER:
                        findings.append(f'unsafe archive member: {name}!{member.name}')
                    elif member.issym() or member.islnk():
                        target = PurePosixPath(member.name).parent / member.linkname
                        # Reject escaping links; internal Python aliases are necessary.
                        parts = []
                        for part in target.parts:
                            if part == '..':
                                if parts: parts.pop()
                                else: findings.append(f'escaping link: {name}!{member.name}')
                            elif part != '.': parts.append(part)
                        if PurePosixPath(member.linkname).is_absolute():
                            findings.append(f'absolute link: {name}!{member.name}')
                    elif member.isfile():
                        inspect_bytes(name + '!' + member.name, archive.extractfile(member).read(), findings, depth + 1)
                    elif not member.isdir():
                        findings.append(f'special archive member: {name}!{member.name}')
        except (OSError, tarfile.TarError):
            findings.append(f'invalid tar: {name}')


def allowed_payload(name):
    parts = PurePosixPath(name).parts
    if not parts: return False
    if parts[0] == 'Tools': return len(parts) == 2 and parts[1] in TOOLS
    if parts[0] == 'Scripts':
        return name == 'Scripts/font-policy.py' or name.startswith('Scripts/fonts/')
    return parts[0] in {'nxnative', 'python', 'wheels', 'licenses'} or name in {
        'VERSION', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'dependency-manifest.json'}


def audit(root, kind='payload'):
    root = Path(root).resolve()
    findings, entries = [], []
    if not root.is_dir(): return ['audit root is missing'], []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            if not path.resolve().is_relative_to(root) or not path.exists():
                findings.append(f'escaping or broken link: {rel}')
            continue
        if not path.is_file(): continue
        if kind == 'payload' and not allowed_payload(rel):
            findings.append(f'not on payload allowlist: {rel}')
        if kind == 'app':
            allowed = {'Contents/Info.plist', 'Contents/MacOS/NxLauncher'}
            resources = {'AppIcon.png', 'AppIcon.icns', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
                         'nxlauncher-home.tgz', 'release-signing.json'}
            # The Dock-icon choices the settings shows; names are fixed, never user input.
            variants = {'Contents/Resources/IconVariants/' + name
                        for name in ('solid.png', 'outline.png', 'retro.png')}
            if not (rel in allowed or rel.startswith('Contents/_CodeSignature/') or
                    rel.startswith('Contents/Resources/licenses/') or rel in variants or
                    rel in {'Contents/Resources/' + name for name in resources}):
                findings.append(f'not on app allowlist: {rel}')
        data = path.read_bytes()
        inspect_bytes(rel, data, findings)
        entries.append({'path': rel, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    if kind == 'app':
        for rel in ('Contents/MacOS/NxLauncher', 'Contents/Info.plist', 'Contents/Resources/AppIcon.png',
                    'Contents/Resources/AppIcon.icns', 'Contents/Resources/LICENSE',
                    'Contents/Resources/THIRD_PARTY_NOTICES.md', 'Contents/Resources/nxlauncher-home.tgz',
                    'Contents/Resources/IconVariants/solid.png',
                    'Contents/Resources/IconVariants/outline.png',
                    'Contents/Resources/IconVariants/retro.png'):
            if not (root / rel).is_file(): findings.append(f'missing app file: {rel}')
    return sorted(set(findings)), entries


def history(repo):
    findings, warnings = [], []
    listing = subprocess.check_output(['git', '-C', str(repo), 'rev-list', '--objects', '--all'], text=True)
    checked = 0
    for line in listing.splitlines():
        oid, _, name = line.partition(' ')
        if not name: continue
        if PROHIBITED.search(name): findings.append(f'prohibited history path: {name} ({oid})')
        kind = subprocess.check_output(['git', '-C', str(repo), 'cat-file', '-t', oid], text=True).strip()
        if kind != 'blob': continue
        checked += 1
        data = subprocess.check_output(['git', '-C', str(repo), 'cat-file', 'blob', oid])
        if SECRETS.search(data): findings.append(f'credential pattern in history: {name} ({oid})')
        if PERSONAL.search(data): warnings.append(f'personal-path history warning: {name} ({oid})')
    return {'ok': not findings, 'checked_blobs': checked, 'findings': sorted(set(findings)),
            'warnings': sorted(set(warnings)), 'scope': 'all locally reachable refs; no remote/unreachable-object or image OCR guarantee'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--kind', choices=('payload', 'app', 'history'), default='payload')
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    if args.kind == 'history': result = history(args.root)
    else:
        findings, entries = audit(args.root, args.kind)
        result = {'ok': not findings, 'kind': args.kind, 'files': entries, 'findings': findings}
    if args.manifest: args.manifest.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
