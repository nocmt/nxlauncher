"""Read-only build prerequisites and a GUI-safe subprocess environment (stdlib only)."""

import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile


TOOL_DIRS = ('/opt/homebrew/bin', '/usr/local/bin', '/usr/local/share/dotnet')
DOTNET_ROOTS = ('/opt/homebrew/opt/dotnet/libexec',
                '/usr/local/opt/dotnet/libexec',
                '/opt/homebrew/opt/dotnet@10/libexec',
                '/usr/local/opt/dotnet@10/libexec', '/usr/local/share/dotnet')
PROBE_TIMEOUT = 15


def _valid_root(path):
    return ((path / 'host' / 'fxr').is_dir()
            and (path / 'shared' / 'Microsoft.NETCore.App').is_dir())


def _root(value):
    if not value:
        return None
    path = Path(value).expanduser()
    try:
        return path.resolve() if _valid_root(path) else None
    except (OSError, RuntimeError):
        return None


def _executable_roots(executable):
    """Homebrew's bin/dotnet can be a wrapper, not the runtime's muxer."""
    if executable:
        path = Path(executable)
        try:
            resolved = path.resolve()
        except (OSError, RuntimeError):
            resolved = path
        for parent in (resolved.parent, path.parent):
            yield parent
            yield parent / 'libexec'
            if parent.name == 'bin':
                yield parent.parent / 'libexec'


def _prepend(paths, inherited):
    # Keep inherited entries, including empty entries and nonexistent custom directories.
    return os.pathsep.join(dict.fromkeys([str(p) for p in paths] + inherited.split(os.pathsep)))


def build_environment(environ=None):
    """Copy the inherited environment and repair GUI PATH and .NET apphost lookup.

    Valid explicit DOTNET_ROOT_ARM64/DOTNET_ROOT overrides win. Otherwise roots
    next to the selected dotnet (including Homebrew's bin/../libexec) win over
    unrelated known installations. A bin directory is not a .NET root.
    No processes are started and the supplied mapping is never modified.
    """
    env = dict(os.environ if environ is None else environ)
    home = Path(env.get('HOME') or Path.home())
    env['PATH'] = _prepend((*TOOL_DIRS, home / '.dotnet'), env.get('PATH', os.defpath))
    arm = _root(env.get('DOTNET_ROOT_ARM64'))
    generic = _root(env.get('DOTNET_ROOT'))
    selected = arm or generic
    if selected is None:
        candidates = list(_executable_roots(shutil.which('dotnet', path=env['PATH'])))
        candidates += [Path(p) for p in DOTNET_ROOTS] + [home / '.dotnet']
        selected = next((r for p in candidates if (r := _root(str(p))) is not None), None)
    if selected is not None:
        if arm is None:
            env['DOTNET_ROOT_ARM64'] = str(selected)
        if generic is None:
            env['DOTNET_ROOT'] = str(selected)
        # A custom override must also be reachable when there is no brew muxer.
        dirs = [selected]
        if (selected / 'bin').is_dir():
            dirs.append(selected / 'bin')
        env['PATH'] = _prepend(dirs, env['PATH'])
    else:
        # Invalid roots override the apphost's own discovery, so do not propagate them.
        env.pop('DOTNET_ROOT_ARM64', None)
        env.pop('DOTNET_ROOT', None)
    return env


def _probe(argv, env):
    try:
        result = subprocess.run([str(a) for a in argv], env=env, stdin=subprocess.DEVNULL,
                                capture_output=True, text=True, errors='replace',
                                timeout=PROBE_TIMEOUT, check=False)
        output = (result.stdout or '').strip()
        error = (result.stderr or '').strip()
        return result.returncode == 0, output, error or ('' if result.returncode == 0
                                                       else f'exit {result.returncode}')
    except (OSError, subprocess.SubprocessError) as exc:
        return False, '', str(exc)


# Run inside the selected Python, not inside the launcher's Python. Actual imports
# catch broken native extensions as well as missing packages. One process suffices.
_PYTHON_PROBE = r'''
import importlib, json, sys
modules = {}
for name in ('lz4.block', 'capstone', 'fontTools', 'PIL'):
    try:
        importlib.import_module(name)
        modules[name] = ''
    except Exception as exc:
        modules[name] = str(exc)
zstd = ''
errors = []
for name in ('compression.zstd', 'backports.zstd'):
    try:
        importlib.import_module(name)
        zstd = name
        break
    except Exception as exc:
        errors.append(str(exc))
print(json.dumps({'version': list(sys.version_info[:3]), 'modules': modules,
                  'zstd': zstd, 'zstd_error': '; '.join(errors)}))
'''


def _architecture(info):
    """Parse invariant architecture/RID values, not localized --info headings.

    Only standalone colon-delimited values count: paths/other-architecture listings
    must not make an x64 host pass. RID and architecture must agree when both occur.
    """
    values = re.findall(r'^[ \t]*[^:\n]+:[ \t]*(?:[\w.]+-)?(arm64|aarch64|x64|x86|amd64)[ \t]*$',
                        info, re.M | re.I)
    normalized = {'arm64' if v.lower() in ('arm64', 'aarch64') else v.lower()
                  for v in values}
    return bool(normalized) and normalized == {'arm64'}


def _sdk10(output):
    return bool(re.search(r'^\s*10\.\d+\.\d+(?:[-+][\w.-]+)?\s+\[.+\]\s*$',
                          output, re.M))


def _runtime10(output):
    return bool(re.search(r'^\s*Microsoft\.NETCore\.App\s+10\.\d+\.\d+'
                          r'(?:[-+][\w.-]+)?\s+\[.+\]\s*$', output, re.M))


def _runtime_smoke(root, env):
    """Resolve net10 in the apphost root without compiling, restoring or downloading.

    The deliberately empty assembly must reach CoreCLR's invariant managed
    BadImageFormatException. A hostfxr/framework lookup failure cannot produce
    that exception. Invoke this root's muxer, not an unrelated PATH installation.
    This verifies runtime resolution, not execution of the bundled translator.
    """
    muxer = root / 'dotnet'
    if not muxer.is_file():
        return False, 'The runtime root has no dotnet executable.'
    try:
        with tempfile.TemporaryDirectory(prefix='nxlauncher-doctor-') as tmp:
            dll = Path(tmp) / 'probe.dll'
            dll.write_bytes(b'')
            dll.with_suffix('.runtimeconfig.json').write_text(json.dumps({
                'runtimeOptions': {'tfm': 'net10.0', 'rollForward': 'LatestPatch',
                                   'framework': {'name': 'Microsoft.NETCore.App',
                                                 'version': '10.0.0'}}}), encoding='utf-8')
            probe_env = dict(env, DOTNET_DbgEnableMiniDump='0')
            _, stdout, stderr = _probe([muxer, 'exec', dll], probe_env)
            output = (stdout + '\n' + stderr).strip()
            return ('System.BadImageFormatException' in output,
                    'net10 CoreCLR resolved in ' + str(root)
                    if 'System.BadImageFormatException' in output else output[-2000:])
    except OSError as exc:
        return False, str(exc)


def doctor(repo, python, env):
    """Return JSON-safe readiness checks and suggested commands; never install.

    repo is the nxnative source root. python is the interpreter used for builds.
    env is used as supplied (call build_environment first). No keys or game files
    are inspected. All commands we execute are bounded, captured probes.
    """
    env = dict(env)
    checks, commands = [], []

    def add(id, name, ok, detail, hint='', command=None):
        checks.append(dict(id=id, name=name, ok=bool(ok), detail=str(detail),
                           hint='' if ok else hint))
        if not ok and command and command not in commands:
            commands.append(command)

    def probe(argv):
        ok, output, error = _probe(argv, env)
        return ok, output, (output + '\n' + error).strip()[-2000:]

    xcode_hint = 'Install full Xcode, open it once, and select its Developer directory (not CommandLineTools).'
    xcode_command = 'sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'
    selected_ok, selected, selected_detail = probe(['xcode-select', '-p'])
    full = selected_ok and selected.rstrip('/').endswith('/Contents/Developer')
    version_ok, version, version_detail = probe(['xcodebuild', '-version'])
    add('xcode', 'Full Xcode selected', full and version_ok,
        selected_detail + '\n' + version_detail, xcode_hint, xcode_command)
    for id, name, args, hint in (
        ('iphoneos', 'iPhoneOS SDK', ['--sdk', 'iphoneos', '--show-sdk-path'], xcode_hint),
        ('metal', 'iPhoneOS Metal compiler', ['--sdk', 'iphoneos', '--find', 'metal'],
         'Install the Metal Toolchain component in Xcode Settings > Components.'),
        ('metallib', 'iPhoneOS Metal linker', ['--sdk', 'iphoneos', '--find', 'metallib'],
         'Install the Metal Toolchain component in Xcode Settings > Components.'),
        ('clang', 'Clang compiler', ['--find', 'clang'], xcode_hint),
    ):
        ok, output, detail = probe(['xcrun', *args])
        add(id, name, ok and bool(output), detail or 'No tool path returned.', hint)

    make = shutil.which('make', path=env.get('PATH', os.defpath))
    ok, _, detail = probe([make, '--version']) if make else (False, '', 'make not found in PATH.')
    add('make', 'Make', ok, detail, xcode_hint)
    for tool in ('xcodegen', 'zstd', 'spirv-cross'):
        path = shutil.which(tool, path=env.get('PATH', os.defpath))
        add(tool, tool, bool(path), path or f'{tool} not found in PATH.',
            f'Install {tool} (Homebrew or another package manager).', f'brew install {tool}')

    dotnet = shutil.which('dotnet', path=env.get('PATH', os.defpath))
    dotnet_hint = 'Install the macOS arm64 .NET 10 SDK and runtime; .NET 11 alone is not sufficient.'
    dotnet_command = 'brew install dotnet@10'
    if dotnet:
        info_ok, info, info_detail = probe([dotnet, '--info'])
        sdk_ok, sdks, sdk_detail = probe([dotnet, '--list-sdks'])
        runtime_ok, runtimes, runtime_detail = probe([dotnet, '--list-runtimes'])
    else:
        info_ok = sdk_ok = runtime_ok = False
        info = sdks = runtimes = ''
        info_detail = sdk_detail = runtime_detail = 'dotnet not found in PATH.'
    add('dotnet-arm64', '.NET arm64 host', info_ok and _architecture(info),
        info_detail, dotnet_hint, dotnet_command)
    add('dotnet-sdk', '.NET 10 SDK', sdk_ok and _sdk10(sdks),
        sdk_detail or 'No SDKs reported.', dotnet_hint, dotnet_command)
    add('dotnet-runtime', '.NET 10 runtime', runtime_ok and _runtime10(runtimes),
        runtime_detail or 'No runtimes reported.', dotnet_hint, dotnet_command)
    root = _root(env.get('DOTNET_ROOT_ARM64')) or _root(env.get('DOTNET_ROOT'))
    if root is None:
        root = next((r for p in _executable_roots(dotnet)
                     if (r := _root(str(p))) is not None), None)
    add('dotnet-root', '.NET apphost runtime root', root is not None,
        root or 'No root containing host/fxr and shared/Microsoft.NETCore.App.',
        'Set DOTNET_ROOT_ARM64 to the .NET installation root (Homebrew: opt/dotnet@10/libexec), not bin.',
        dotnet_command)
    smoke_ok, smoke_detail = (_runtime_smoke(root, env) if root is not None
                              else (False, 'No valid .NET runtime root to probe.'))
    add('dotnet-resolution', '.NET 10 apphost runtime resolution', smoke_ok,
        smoke_detail, dotnet_hint, dotnet_command)

    py = str(python) if python else 'python3'
    py_ok, py_output, py_detail = probe([py, '-c', _PYTHON_PROBE])
    data = {}
    if py_ok:
        try:
            data = json.loads(py_output)
            if not isinstance(data, dict):
                data = {}
        except (ValueError, TypeError):
            pass
    version = data.get('version', [])
    version_valid = (isinstance(version, list) and len(version) >= 2
                     and all(isinstance(v, int) for v in version))
    version_ok = version_valid and tuple(version[:2]) >= (3, 12)
    add('python', 'Python 3.12+', py_ok and version_ok,
        (py + ': ' + '.'.join(map(str, version))) if version_valid else
        (py_detail or 'Python probe did not return valid JSON.'),
        'Select a Python 3.12+ interpreter using NXLAUNCHER_PYTHON.',
        'brew install python@3.13' if not version_ok else None)
    modules = data.get('modules', {})
    if not isinstance(modules, dict):
        modules = {}
    for module, package in (('lz4.block', 'lz4'), ('capstone', 'capstone'),
                            ('fontTools', 'fonttools'), ('PIL', 'pillow')):
        ok = py_ok and module in modules and modules[module] == ''
        add('python-' + module, 'Python ' + module, ok,
            'Import succeeded.' if ok else modules.get(module) or 'Python module probe failed.',
            f'Install {package} into the selected build Python.',
            f'{shlex.quote(py)} -m pip install {package}')
    zstd_ok = py_ok and data.get('zstd') in ('compression.zstd', 'backports.zstd')
    add('python-zstd', 'Python zstd', zstd_ok,
        data.get('zstd') if zstd_ok else data.get('zstd_error') or 'Python zstd import failed.',
        'Use Python with compression.zstd, or install backports.zstd in the selected interpreter.',
        f'{shlex.quote(py)} -m pip install backports.zstd')

    translator = Path(repo) / 'dm/gfx/tools/dmsh_xlate_bin/dmsh_xlate' if repo else None
    translator_ok = (translator is not None and translator.is_file()
                     and os.access(translator, os.X_OK))
    add('translator', 'Bundled shader translator', translator_ok,
        translator or 'nxnative repository not found.',
        'Restore the prepared nxnative dependency; the pinned translator must be a file.')
    return {'ready': all(check['ok'] for check in checks),
            'checks': checks, 'commands': commands}
