#!/usr/bin/env python3
"""Export an existing iOS build using the upstream IPA packer."""
import argparse
import filecmp
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys


PAYLOAD = 'Payload/DmIOS.app'
APP_REL = 'ipa/build/ios/pkg/dd/Build/Products/Release-iphoneos/DmIOS.app'


class ExportError(Exception):
    pass


def require_file(path, description):
    if not path.is_file():
        raise ExportError(f'missing {description}: {path}')
    return path


def profile_values(profile):
    values = {}
    for line in (profile / 'game.tsv').read_text(encoding='utf-8').splitlines():
        if not line.strip() or line.lstrip().startswith('#') or '\t' not in line:
            continue
        key, value = line.split('\t', 1)
        values.setdefault(key.strip(), value.strip())
    return values


def resolve_profile(repo, work, selected):
    """Use game.py's search order, including the work's provisional profiles."""
    match = re.fullmatch(r'([0-9a-fA-F]{16})(?:_build|-work)', work.name)
    work_game = match.group(1).upper() if match else ''
    selected = selected.upper() if selected else ''
    if selected and not re.fullmatch(r'[0-9A-F]{16}', selected):
        raise ExportError('--game must be a 16-digit base game title ID')
    if selected and work_game and selected != work_game:
        raise ExportError(f'--game {selected} does not match work game {work_game}')
    if not selected:
        selected = work_game
    if not selected:
        profiles = sorted(p.parent.name for p in (work / 'profile').glob('*/game.tsv')
                          if re.fullmatch(r'[0-9a-fA-F]{16}', p.parent.name))
        if len(profiles) != 1:
            raise ExportError('cannot determine game from --work; pass --game explicitly')
        selected = profiles[0].upper()
    env = dict(os.environ)
    extra = [p for p in env.get('DM_GAMES_DIR', '').split(os.pathsep) if p]
    local = str(work / 'profile')
    if local not in extra:
        extra.append(local)
    env['DM_GAMES_DIR'] = os.pathsep.join(extra)
    game_script = require_file(repo / 'dm/games/game.py', 'upstream profile resolver')
    result = subprocess.run([sys.executable, str(game_script), 'dir', selected],
                            env=env, text=True, capture_output=True)
    if result.returncode:
        raise ExportError(f'cannot resolve game {selected}: {result.stderr.strip() or result.stdout.strip()}')
    profile = Path(result.stdout.strip()).resolve()
    require_file(profile / 'game.tsv', f'profile for {selected}')
    return selected, profile, profile_values(profile), env


def resource_sources(work, profile, values, version):
    romfs = work / 'extract' / version / 'RomFS'
    if not romfs.is_dir():
        raise ExportError(f'missing RomFS for {version}: {romfs}')
    marker = values.get('romfs_marker', '')
    if not marker or Path(marker).is_absolute() or '..' in Path(marker).parts:
        raise ExportError(f'missing or invalid romfs_marker in {profile / "game.tsv"}')
    if not (romfs / marker).exists():
        raise ExportError(f'missing RomFS marker: {romfs / marker}')
    ios = work / 'shader/ios'
    header = profile / 'dmsh_chain.h'
    match = re.search(r'^\s*#define\s+DMSH_CHAIN\s+"([^"/]+)"',
                      header.read_text(encoding='utf-8') if header.is_file() else '', re.M)
    chain = f'b-{match.group(1)}' if match else ''
    nvn = ios / chain if chain else None
    has_nvn = nvn and nvn.is_dir() and any(nvn.glob('*_b.metallib'))
    gfx = os.environ.get('GFXAPI', '')
    if gfx and gfx not in ('nvn', 'vulkan'):
        raise ExportError(f'unknown GFXAPI: {gfx}')
    if gfx == 'vulkan' or (not gfx and not has_nvn and (ios / 'vk/vk_shaders.metallib').is_file()):
        require_file(ios / 'vk/vk_shaders.metallib', 'iOS Vulkan shader library')
        msl_dir = 'vk'
    else:
        if not has_nvn:
            raise ExportError(f'missing iOS shader libraries: {ios / (chain or "b-<DMSH_CHAIN>")} '
                              '(expected *_b.metallib; shader/cache contains macOS libraries)')
        msl_dir = chain
    sources = [(f'msl/{msl_dir}', ios / msl_dir)]
    aoc = work / 'aoc'
    if aoc.exists():
        if not aoc.is_dir():
            raise ExportError(f'add-on content is not a directory: {aoc}')
        sources.append(('aoc', aoc))
    sources.append(('romfs', romfs))
    return sources


def tree_entries(root):
    """Inventory without following directory symlinks, like pack_ipa.py."""
    entries = {}
    for parent, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name
            entries[path.relative_to(root)] = path
    return entries


def compare_resource(source, bundled):
    if not bundled.is_dir() or bundled.is_symlink():
        raise ExportError(f'signed app is missing complete resources: {bundled}; '
                          'assemble all resources and sign the complete bundle before export')
    expected, actual = tree_entries(source), tree_entries(bundled)
    if expected.keys() != actual.keys():
        raise ExportError(f'signed app resource inventory differs from {source}: {bundled}; '
                          'assemble all resources and sign the complete bundle before export')
    for relative, src in expected.items():
        dst = actual[relative]
        if src.is_symlink():
            equal = dst.is_symlink() and os.readlink(src) == os.readlink(dst)
        elif src.is_dir():
            equal = dst.is_dir() and not dst.is_symlink()
        else:
            equal = dst.is_file() and not dst.is_symlink() and filecmp.cmp(src, dst, shallow=False)
        if not equal:
            raise ExportError(f'signed app resource differs from {src}: {dst}; reassemble and re-sign')


def validate_signed(app, sources, env):
    for relative, source in sources:
        compare_resource(source, app / relative)
    msl_dirs = {relative.split('/')[1] for relative, _ in sources if relative.startswith('msl/')}
    if (app / 'msl').is_symlink():
        raise ExportError(f'signed app shader directory must be bundled, not a symlink: {app / "msl"}')
    if {p.name for p in (app / 'msl').iterdir()} != msl_dirs:
        raise ExportError(f'signed app has unexpected shader resources: {app / "msl"}; reassemble and re-sign')
    if not any(relative == 'aoc' for relative, _ in sources) and (app / 'aoc').exists():
        raise ExportError(f'signed app has unexpected add-on content: {app / "aoc"}; reassemble and re-sign')
    require_file(app / 'embedded.mobileprovision', 'signed app provisioning profile')
    require_file(app / '_CodeSignature/CodeResources', 'signed app resource seal')
    result = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                            env=env, text=True, capture_output=True)
    if result.returncode:
        raise ExportError(f'complete app signature is not valid: {result.stderr.strip() or result.stdout.strip()}')
    print('Complete app bundle signature verified.', flush=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--signed', action='store_true', help='require an already signed complete app bundle')
    parser.add_argument('--work', required=True, help='selected game work folder')
    parser.add_argument('--out', help='output IPA (default: profile IPA name beside work)')
    parser.add_argument('--repo', default=os.environ.get('NXLAUNCHER_REPO') or str(Path(__file__).resolve().parents[1] / 'nxnative'))
    parser.add_argument('--game', default='', help='base title ID (otherwise inferred from work)')
    parser.add_argument('--ver', default='', help='extracted version (default: profile package)')
    args = parser.parse_args(argv)
    work, repo = Path(args.work).expanduser().resolve(), Path(args.repo).expanduser().resolve()
    game, profile, values, env = resolve_profile(repo, work, args.game)
    version = args.ver or values.get('package', '')
    if not version or version in ('.', '..') or '/' in version or '\\' in version:
        raise ExportError('pass --ver or set a valid package in the selected game profile')
    app = work / APP_REL
    require_file(app / 'Info.plist', 'built app Info.plist')
    with (app / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    executable = info.get('CFBundleExecutable', 'DmIOS')
    if not executable or Path(executable).name != executable:
        raise ExportError(f'invalid CFBundleExecutable in {app / "Info.plist"}')
    require_file(app / executable, 'built app executable')
    sources = resource_sources(work, profile, values, version)
    packer = require_file(repo / 'dm/ios/tools/pack_ipa.py', 'upstream IPA packer')
    default_name = values.get('ipa', f'{game}.ipa')
    if Path(default_name).name != default_name:
        raise ExportError(f'invalid ipa filename in {profile / "game.tsv"}')
    default_out = work.parent / default_name
    if args.signed:
        default_out = default_out.with_name(default_out.stem + '-signed.ipa')
        validate_signed(app, sources, env)
    out = Path(args.out).expanduser().resolve() if args.out else default_out
    # Writing an archive within a mapped tree could make the packer include its own output.
    for source in [app] + [source for _, source in sources]:
        if out == source or source.resolve() in out.parents:
            raise ExportError(f'output must be outside resource directories: {out}')
    out.parent.mkdir(parents=True, exist_ok=True)
    command = [sys.executable, str(packer), str(out), '--store', values.get('zip_store', '')]
    maps = [(PAYLOAD, app)]
    if not args.signed:
        for relative in ('_CodeSignature', 'embedded.mobileprovision', 'msl', 'aoc', 'romfs'):
            command.extend(['--skip', f'{PAYLOAD}/{relative}'])
        maps.extend((f'{PAYLOAD}/{relative}', source) for relative, source in sources)
    command.extend(f'{archive}={source}' for archive, source in maps)
    print(f'Exporting {game} {version} ({"signed" if args.signed else "unsigned"}) → {out}', flush=True)
    subprocess.run(command, env=env, check=True)
    if not out.is_file():
        raise ExportError(f'upstream packer did not create {out}')
    print(f'IPA exported: {out}', flush=True)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ExportError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
