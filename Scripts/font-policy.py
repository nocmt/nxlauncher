#!/usr/bin/env python3
"""Generate fresh shared-font stand-ins; never copy cached/system font outlines."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def font_python(repo):
    candidates = []
    if os.environ.get('NXLAUNCHER_PYTHON'):
        candidates.append(Path(os.environ['NXLAUNCHER_PYTHON']))
    root = Path(repo).resolve().parent
    candidates.extend((root / '.venv/bin/python3', root / '.venv/bin/python'))
    candidates.append(Path(os.sys.executable))
    for candidate in candidates:
        if candidate.is_file():
            probe = subprocess.run([str(candidate), '-c', 'import fontTools'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if probe.returncode == 0:
                return str(candidate)
    raise RuntimeError('No Python interpreter with fontTools is available; set NXLAUNCHER_PYTHON')


def generate(repo, out):
    assets = Path(__file__).resolve().parent / 'fonts'
    provenance = json.loads((assets / 'provenance.json').read_text())
    override = os.environ.get('NXLAUNCHER_FONT_PATH')
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.fonts-', dir=out) as tmp:
        stage = Path(tmp)
        data = (Path(override).expanduser().read_bytes() if override else
                gzip.decompress((assets / 'NotoSansSC.ttf.gz').read_bytes()))
        if not override and hashlib.sha256(data).hexdigest() != provenance['sha256']:
            raise ValueError('Bundled font hash mismatch')
        standard = stage / 'standard.ttf'
        standard.write_bytes(data)
        # Explicit second argument is mandatory: upstream's historical default is commercial.
        subprocess.run([font_python(repo), str(Path(repo) / 'dm/tools/make_ext_font.py'),
                        str(stage / 'nintendo_ext.ttf'), str(standard)],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        provenance = dict(provenance, redistributable=not bool(override),
                          generated_extension='nxnative procedural button shapes + explicit letter font')
        if override:
            provenance = {'redistributable': False, 'source': 'explicit user-provided font',
                          'warning': 'Personal use only unless user independently secures redistribution rights.'}
        else:
            shutil.copyfile(assets / 'OFL.txt', stage / 'OFL.txt')
        (stage / 'font-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
        for file in stage.iterdir():
            os.replace(file, out / file.name)
    return {'standard': str(out / 'standard.ttf'), 'extension': str(out / 'nintendo_ext.ttf'),
            'redistributable': not bool(override)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(generate(args.repo, args.out)))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Font generation failed: {error}\n')


if __name__ == '__main__':
    main()
