"""Resolve the shader ABI used by the host, and validate a completed library."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


TABLE_TOOLS = {'c1_full.tsv': 'c1_guard.py', 'cb_extent.tsv': 'cb_extent.py'}


class ShaderChainError(ValueError):
    pass


def chain_header(repo, profile):
    shared = Path(repo) / 'dm/gfx/nvn/dmsh_chain.h' if repo else Path(profile) / 'dmsh_chain.h'
    return shared if shared.is_file() else Path(profile) / 'dmsh_chain.h'


def chain_of(repo, profile):
    header = chain_header(repo, profile)
    if not header.is_file():
        raise ShaderChainError(f'missing host shader chain header: {header}')
    match = re.search(r'^\s*#define\s+DMSH_CHAIN\s+"([A-Za-z0-9_-]+)"',
                      header.read_text(encoding='utf-8'), re.M)
    if not match:
        raise ShaderChainError(f'invalid DMSH_CHAIN in {header}')
    return match.group(1)


def validate_stamp(library, game, inputs):
    stamp_file = library / 'inputs.tsv'
    stamp = dict(line.split('\t', 1) for line in stamp_file.read_text().splitlines()
                 if '\t' in line and not line.startswith('#')) if stamp_file.is_file() else {}
    if stamp.get('game') != game or stamp.get('inputs') != inputs:
        raise ShaderChainError(f'shader library does not match game {game} / profile inputs {inputs}: '
                               f'{stamp_file}; run the shader build to refresh this cache')


def validate_table(table, prefix):
    with table.open(encoding='utf-8') as stream:
        first = stream.readline()
    if not first.startswith(prefix):
        raise ShaderChainError(f'shader table does not match library chain / inputs: {table}; '
                               'run the shader build')


def restore_tables(repo, profile, game, library, chain, inputs, missing, env):
    # iOS libraries omit translated MSL. Upstream derives both tables from the
    # exact sibling Mac cache, never from another chain or a different profile.
    cache = library.parent.parent / 'cache' / library.name if library.parent.name == 'ios' else library
    validate_stamp(cache, game, inputs)
    shaders = list(cache.glob('*_b.metallib'))
    if not shaders:
        raise ShaderChainError(f'missing Mac shader analysis cache: {cache}; run the shader build')
    for shader in shaders:
        metal, reflection = shader.with_suffix('.metal'), shader.with_suffix('.json')
        if not metal.is_file() or not metal.stat().st_size or not reflection.is_file():
            raise ShaderChainError(f'incomplete Mac shader analysis cache: {shader}; '
                                   'translated MSL and reflection are required; run the shader build')
        try:
            data = json.loads(reflection.read_text(encoding='utf-8'))
        except ValueError as error:
            raise ShaderChainError(f'invalid shader reflection: {reflection}: {error}') from error
        if not isinstance(data, dict) or data.get('chain') != chain or not isinstance(data.get('bindings'), list):
            raise ShaderChainError(f'incompatible shader reflection: {reflection}; run the shader build')
    prefix = f'# chain b-{chain} inputs {inputs} '
    # Generate and check every missing table before publishing any. Hard links
    # install only absent files, preserving existing tables even on a race.
    with tempfile.TemporaryDirectory(prefix='.shader-tables-', dir=profile) as temp:
        for name in missing:
            output = Path(temp) / name
            tool = repo / 'dm/gfx/tools' / TABLE_TOOLS[name]
            result = subprocess.run([sys.executable, str(tool), str(cache), str(output)],
                                    env=env, capture_output=True, text=True)
            if result.returncode:
                raise ShaderChainError(f'cannot regenerate {name}: '
                                       f'{result.stderr.strip() or result.stdout.strip()}')
            if not output.is_file():
                raise ShaderChainError(f'cannot regenerate {name}: {tool} produced no table')
            validate_table(output, prefix)
        for name in missing:
            try:
                os.link(Path(temp) / name, profile / name)
            except FileExistsError:
                validate_table(profile / name, prefix)


def validate_library(repo, profile, game, library):
    repo, profile, library = Path(repo), Path(profile), Path(library)
    chain = chain_of(repo, profile)
    if library.name != f'b-{chain}' or not library.is_dir():
        raise ShaderChainError(f'missing shader libraries for host chain {chain}: {library}; '
                               'run the shader build without deleting the existing work folder')
    if not any(library.glob('*_b.metallib')):
        raise ShaderChainError(f'no compiled shader libraries in {library}')
    if chain_header(repo, profile) == profile / 'dmsh_chain.h':
        return chain
    tool = repo / 'dm/gfx/tools/dmsh_chain.py'
    env = dict(os.environ, DM_GAME=str(profile), PYTHONDONTWRITEBYTECODE='1')
    result = subprocess.run([sys.executable, str(tool), '--inputs'], env=env,
                            capture_output=True, text=True)
    if result.returncode:
        raise ShaderChainError(f'cannot validate shader profile inputs: '
                               f'{result.stderr.strip() or result.stdout.strip()}')
    inputs = result.stdout.strip()
    if not re.fullmatch(r'[0-9a-f]{12}', inputs):
        raise ShaderChainError(f'invalid shader profile inputs from {tool}: {inputs}')
    validate_stamp(library, game, inputs)
    prefix = f'# chain b-{chain} inputs {inputs} '
    missing = []
    for name in TABLE_TOOLS:
        table = profile / name
        if not os.path.lexists(table):
            missing.append(name)
        else:
            validate_table(table, prefix)
    if missing:
        restore_tables(repo, profile, game, library, chain, inputs, missing, env)
    return chain


def resolve_graphics(work, profile, target, requested='auto'):
    if requested not in ('auto', 'nvn', 'vulkan', 'gl'):
        raise ShaderChainError(f'unknown graphics API: {requested}')
    if requested != 'auto':
        return requested
    for line in (Path(profile) / 'game.tsv').read_text().splitlines():
        key, _, value = line.partition('\t')
        if key in ('graphics_api', 'gfx_api', 'gfx') and value.strip() in ('nvn', 'vulkan', 'gl'):
            return value.strip()
    root = Path(work) / ('shader/ios' if target == 'ios' else 'shader')
    found = [api for api, sub in (('vulkan', 'vk'), ('gl', 'gl'))
             if (root / sub / f'{sub}_shaders.metallib').is_file()]
    if len(found) > 1:
        raise ShaderChainError('ambiguous shader resources; pass --graphics-api nvn|vulkan|gl')
    return found[0] if found else 'nvn'


def shader_resources(repo, work, profile, game, target, api):
    work, profile = Path(work), Path(profile)
    if api == 'nvn':
        root = work / ('shader/ios' if target == 'ios' else 'shader/cache')
        name = 'b-' + chain_of(repo, profile)
        library = root / name
        if target == 'ios' and not library.is_dir():
            raise ShaderChainError(f'missing iOS shader libraries: {library} (Mac caches cannot replace iOS libraries)')
        validate_library(repo, profile, game, library)
    else:
        name = 'vk' if api == 'vulkan' else 'gl'
        root = work / ('shader/ios' if target == 'ios' else 'shader')
        library = root / name
        compiled = library / f'{name}_shaders.metallib'
        if not compiled.is_file() or not compiled.stat().st_size:
            raise ShaderChainError(f'missing {target} {api} shader library: {compiled}')
    return [('msl/' + name, library)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--game', default='')
    parser.add_argument('--library', type=Path)
    parser.add_argument('--resources', action='store_true')
    parser.add_argument('--work', type=Path)
    parser.add_argument('--target', choices=('mac', 'ios'), default='mac')
    parser.add_argument('--graphics-api', choices=('auto', 'nvn', 'vulkan', 'gl'), default='auto')
    args = parser.parse_args()
    if args.resources:
        api = resolve_graphics(args.work, args.profile, args.target, args.graphics_api)
        resources = shader_resources(args.repo, args.work, args.profile, args.game, args.target, api)
        print(str(resources[0][1]))
    else:
        print(validate_library(args.repo, args.profile, args.game, args.library)
              if args.library else chain_of(args.repo, args.profile))


if __name__ == '__main__':
    try:
        main()
    except (ShaderChainError, OSError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
