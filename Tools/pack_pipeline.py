#!/usr/bin/env python3
"""NxLauncher pipeline: the one place that knows how to turn a game folder into an IPA or a Mac .app.

Every command writes **one JSON object per line** on stdout -- the same event vocabulary the
upstream packing script emits with `--progress json` (stage / step / progress / stage_end / say),
so a GUI can draw a progress bar from a single stream. Plain output lines of the tools it runs
are passed through as {"ev":"log"}.

Commands
  plan    --game-dir DIR [--keys FILE] [--repo DIR]
          What is in the folder: the base game, the update, the DLC, the keys, whether the game
          has a port (a profile in dm/games/), the name, the icon, and whether it is already built.
  build   --game-dir DIR --keys FILE [--repo DIR] [--out FILE]
          The upstream packing script (extract -> rewrite -> shaders -> app -> IPA).
  export  --target mac-app|ios-ipa|ios-ipa-unsigned --work DIR --game ID --ver VER --out PATH
          [--repo DIR] [--dlc DIR] [--keys FILE]
          The Mac .app or the iOS IPA from an already built work folder.
  doctor  [--repo DIR]
          Check the build toolchain and report missing dependencies without installing anything.
  games   [--repo DIR]
          The games that have a port (a profile), with their name and version.

Exit codes: 0 = fine, 1 = a stage failed, 2 = the arguments or the environment are wrong.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import hashlib
import platform
import tempfile
import time
import uuid
import zipfile
from pathlib import Path

from toolchain import build_environment, doctor
from shader_chain import chain_of as host_chain_of, ShaderChainError, resolve_graphics, shader_resources

SESSION = None
BUILD_RESULT = {}
# Import the official build entrypoint without changing the submodule. Record
# the actual profile/version/API selected by upstream, including derived IDs.
UPSTREAM_ENTRY = r'''
import importlib.util, json, os, sys
script = sys.argv.pop(1)
spec = importlib.util.spec_from_file_location('nxlauncher_upstream', script)
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)
def blocked(*a, **kw):
    raise u.BuildError('NX_RUNTIME_CAPTURE_REQUIRED: automatic game execution is disabled; prepare runtime capture caches manually')
# Older upstream revisions get the same fail-closed boundary.
for name in ('boot_mac',):
    if hasattr(u, name): setattr(u, name, blocked)
original = u.report_profile_status
def report(g, reg, version, derived, provisional, artifact='IPA', *a, **kw):
    original(g, reg, version, derived, provisional, artifact, *a, **kw)
    print(json.dumps(dict(ev='build_result', profile_id=g.id, profile_dir=str(g.dir),
                          version=version, derived=bool(derived), provisional=bool(provisional))), flush=True)
u.report_profile_status = report
args = sys.argv[1:]
if '--no-runtime-capture' not in open(script).read():
    args = [a for a in args if a != '--no-runtime-capture']
try:
    u.main(u.parse_args(args))
except u.BuildError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(1)
'''
ERRORS = {
    'NX_DEPENDENCIES': '运行 doctor --target {target}，在环境面板确认后手动执行建议的修复命令，再重试。',
    'NX_BUILD_FAILED': '查看本次会话日志；修复首个失败阶段后使用同一游戏目录重试（已有提取文件会保留）。',
    'NX_EXPORT_FAILED': '选择新的导出路径，检查磁盘空间，再使用 export 命令重试。',
    'NX_INPUT_INVALID': '检查所选游戏目录、prod.keys、仓库和输出位置，再重试。',
    'NX_MANIFEST_INVALID': '使用 build --target {target} --rebuild 重新生成完整构建；不会删除游戏、密钥或存档。',
    'NX_RUNTIME_CAPTURE_REQUIRED': '这款游戏需要运行时着色器捕获，当前安全构建不会自动启动游戏。请手动按上游说明准备捕获缓存后重试。',
    'NX_INTERRUPTED': '操作已中断。使用原参数重试，已完成的提取缓存不会删除。',
    'NX_INTERNAL': '查看会话日志并使用 diagnostics --out diagnostics.zip 导出脱敏诊断。',
}


def error(error_id, message, target='mac'):
    emit(ev='error', error_id=error_id, message=str(message),
         hint=ERRORS.get(error_id, ERRORS['NX_INTERNAL']).format(target=target))


def session_root():
    return Path(os.environ.get('NXLAUNCHER_STATE_DIR') or
                Path.home() / 'Library/Application Support/NxLauncher/Pipeline')


class Session:
    def __init__(self, command, target):
        self.id = time.strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:12]
        self.path = session_root() / 'sessions' / self.id
        self.path.mkdir(parents=True, mode=0o700)
        self.log = self.path / 'events.jsonl'
        self.stream = self.log.open('x', encoding='utf-8')
        self.log.chmod(0o600)
        self.meta = {'schema': 1, 'session_id': self.id, 'command': command,
                     'target': target, 'started': time.time(), 'status': 'running'}
        self.save()

    def save(self):
        atomic_json(self.path / 'session.json', self.meta)

    def finish(self, code):
        self.meta.update(status='completed' if code == 0 else 'failed', exit_code=code,
                         ended=time.time())
        self.save()
        self.stream.close()


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, ensure_ascii=False, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def redact(text):
    text = str(text).replace(str(Path.home()), '<HOME>')
    text = re.sub(r'(?i)(?:[A-Za-z]:)?/(?:[^\s\"\'<>]+/?)+', '<PATH>', text)
    text = re.sub(r'(?i)\b[0-9a-f]{32,}\b', '<REDACTED>', text)
    text = re.sub(r'(?i)(?:[\w.-]*(?:key|token|password|secret)[\w.-]*)\s*[=:]\s*[^\s,}]+', '<SECRET>', text)
    return text

def redact_json(value):
    if isinstance(value, dict):
        return {key: ('<SECRET>' if re.search(r'key|token|password|secret', key, re.I)
                      else redact_json(item)) for key, item in value.items()}
    if isinstance(value, list):
        return [redact_json(item) for item in value]
    return redact(value) if isinstance(value, str) else value


def redact_document(text, name):
    try:
        if name.endswith('.json'):
            return json.dumps(redact_json(json.loads(text)), ensure_ascii=False, indent=2)
        if name.endswith('.jsonl'):
            return '\n'.join(json.dumps(redact_json(json.loads(line)), ensure_ascii=False)
                             for line in text.splitlines() if line.strip()) + '\n'
    except ValueError:
        pass
    return redact(text)


# ---- the event vocabulary (the same one the upstream script uses) ----
def emit(**obj):
    obj.setdefault('t', round(time.time(), 3))
    if SESSION:
        obj.setdefault('session_id', SESSION.id)
    line = json.dumps(obj, ensure_ascii=False)
    if SESSION:
        SESSION.stream.write(line + '\n')
        SESSION.stream.flush()
    print(line, flush=True)


def stage(name, step=''):
    emit(ev='stage', name=name, step=step)


def stage_end(name, ok=True, summary=''):
    emit(ev='stage_end', name=name, ok=ok, summary=summary)


def say(msg):
    emit(ev='say', msg=msg)


def log(line):
    emit(ev='log', line=line.rstrip('\n'))


class Failed(Exception):
    pass


# ---- where things live ----
def find_repo(explicit):
    """The nxnative source tree: the one given, or NXLAUNCHER_REPO, or next to this repository."""
    cands = []
    if explicit:
        cands.append(Path(explicit))
    if os.environ.get('NXLAUNCHER_REPO'):
        cands.append(Path(os.environ['NXLAUNCHER_REPO']))
    here = Path(__file__).resolve().parent.parent     # <repo>/Tools/pack_pipeline.py
    cands += [here / 'nxnative', here.parent / 'nxnative-src', here / 'vendor' / 'nxnative']
    for c in cands:
        if (c / 'dm' / 'games').is_dir() and (c / 'scripts' / 'build_ipa_from_nsp.py').is_file():
            return c.resolve()
    return None


def find_python():
    """The interpreter for the upstream script: it needs lz4, capstone and fontTools.

    The repository's own venv (bootstrap.sh makes it) comes first, then NXLAUNCHER_PYTHON, then
    whatever python3 is in the PATH."""
    here = Path(__file__).resolve().parent.parent
    cands = []
    if os.environ.get('NXLAUNCHER_PYTHON'):
        cands.append(Path(os.environ['NXLAUNCHER_PYTHON']))
    cands += [here / '.venv' / 'bin' / 'python3', here / '.venv' / 'bin' / 'python',
              Path('/usr/bin/python3'), Path(sys.executable)]
    for c in cands:
        if not c.exists():
            continue
        try:
            out = subprocess.run([str(c), '-c', 'import lz4, capstone, fontTools'],
                                 capture_output=True, timeout=20)
            if out.returncode == 0:
                return str(c)
        except (OSError, subprocess.SubprocessError):
            continue
    return 'python3'      # the upstream script will report what is missing


# ---- the game folder ----
TITLE_RE = re.compile(r'\[([0-9A-Fa-f]{16})\]')
DLC_RE = re.compile(r'\[DLC\]', re.I)
# The dump tools name a cartridge "… [v.xci" (the bracket is never closed) and a package "… .nsp",
# so the extension is matched on the end of the name rather than on Path.suffix -- a file written
# as "… [v.xci]" would be skipped by suffix (its suffix is ".xci]").
EXT_RE = re.compile(r'\.(nsp|xci)\]?$', re.I)
ID_RE = re.compile(r'\s*\[[0-9A-Fa-f]{16}\]')


def scan_game_dir(d):
    """The NSP / XCI files in the folder, sorted into base / update / DLC.

    Nintendo's convention: the base game's title ID ends in 000, an update's in 800, and the DLC
    files carry [DLC] in the name (their IDs are the base's + 0x1000 and up)."""
    base, updates, dlc = None, [], []
    files = sorted([p for p in d.iterdir() if p.is_file() and EXT_RE.search(p.name)]) if d.is_dir() else []
    for f in files:
        m = TITLE_RE.search(f.name)
        tid = m.group(1).upper() if m else ''
        if DLC_RE.search(f.name):
            dlc.append(f)
        elif tid.endswith('800'):
            updates.append(f)
        elif base is None:
            base = f
        else:
            updates.append(f)
    return base, updates, dlc, files


def file_info(f):
    """What the interface shows for a file.

    The title ID and the name are kept apart on purpose: the ID is 16 characters and always fits,
    the name can be long. A folder can hold several updates and several DLC, so the interface needs
    the ID of each one on its own line rather than one joined string."""
    m = TITLE_RE.search(f.name)
    # The name without the title ID in it (the ID is shown on its own), with the leftover spaces
    # tidied up: "Some Game [0100…E800] [v1114112].nsp" -> "Some Game [v1114112].nsp".
    label = re.sub(r'\s+', ' ', ID_RE.sub(' ', f.name)).strip()
    label = re.sub(r'\s+(\.[A-Za-z0-9]+)$', r'\1', label)
    return {
        'path': str(f),
        'name': f.name,
        'label': label,
        'title_id': m.group(1).upper() if m else '',
    }


def profile_for(repo, title_id, work=None):
    """Find the repository profile or the provisional profile from this build."""
    if not title_id:
        return None
    extra = [Path(p) for p in os.environ.get('DM_GAMES_DIR', '').split(os.pathsep) if p]
    if work:
        extra.append(Path(work) / 'profile')
    roots = ([repo / 'dm' / 'games'] if repo else [])
    roots = extra + roots if os.environ.get('DM_GAMES_FIRST') else roots + extra
    d = next((root / title_id for root in roots if (root / title_id / 'game.tsv').is_file()), None)
    if d is None:
        # Profiles can have descriptive IDs; title_id remains the stable game identity.
        for root in roots:
            for entry in sorted(root.glob('*/game.tsv')):
                if re.search(r'^title_id\s+' + re.escape(title_id) + r'\s*$', entry.read_text(errors='replace'), re.M | re.I):
                    d = entry.parent
                    break
            if d is not None:
                break
    if d is None:
        return None
    vals = {}
    for line in (d / 'game.tsv').read_text(errors='replace').splitlines():
        if line.startswith('#') or '\t' not in line:
            continue
        k, v = line.split('\t', 1)
        vals.setdefault(k.strip(), v.strip())
    try:
        chain = host_chain_of(repo, d)
    except ShaderChainError:
        # Planning must still describe unbuilt/provisional games; export performs the strict check.
        chain = ''
    return {
        'dir': str(d),
        'name': vals.get('name', title_id),
        'version': vals.get('package', '') or (vals.get('build', '').split() or [''])[0],
        'modules': vals.get('modules', ''),
        'fps_target': vals.get('fps_target', ''),
        'mem_pool': vals.get('app_pool', ''),
        'mem_reserve': vals.get('mem_reserve', ''),
        'chain': chain,
    }


def work_dir_of(game_dir, title_id):
    return game_dir / f'{title_id}_build'


def version_key(value):
    return tuple(int(n) for n in re.findall(r'\d+', value)) or (0,)


def read_json(path):
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def manifest_path(work, target):
    return work / '.nxlauncher' / f'build-{target}.json'


def input_identity(files):
    # Never read game or key contents. Size and nanosecond timestamps detect replacements.
    return [{'name': p.name, 'size': p.stat().st_size, 'mtime_ns': p.stat().st_mtime_ns}
            for p in files]


def profile_digest(profile):
    digest = hashlib.sha256()
    for name in ('game.tsv', 'patches.py', 'shader_map.tsv', 'pso_manifest.tsv',
                 'c1_full.tsv', 'cb_extent.tsv', 'dmsh_chain.h'):
        path = Path(profile) / name
        if path.is_file():
            digest.update(name.encode())
            digest.update(path.read_bytes())
    return digest.hexdigest()


def repo_identity(repo):
    try:
        result = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD'],
                                capture_output=True, text=True, timeout=10)
        return result.stdout.strip() if result.returncode == 0 else ''
    except (OSError, subprocess.SubprocessError):
        return ''


def manifest_valid(work, target, files=None, repo=None):
    data = read_json(manifest_path(work, target))
    if data.get('schema') != 1 or data.get('status') != 'complete' or data.get('target') != target:
        return False
    if files is not None and data.get('inputs') != input_identity(files):
        return False
    if repo and data.get('repo_revision') != repo_identity(repo):
        return False
    prof = data.get('profile', {})
    directory = prof.get('dir', '')
    if not directory or not (Path(directory) / 'game.tsv').is_file():
        return False
    if prof.get('digest') != profile_digest(directory):
        return False
    outputs = data.get('outputs', [])
    if not outputs:
        return False
    for item in outputs:
        relative = Path(item.get('path', ''))
        if relative.is_absolute() or '..' in relative.parts:
            return False
        path = work / relative
        if not path.is_file() or path.stat().st_size != item.get('size') or path.stat().st_mtime_ns != item.get('mtime_ns'):
            return False
    return True


def completed_outputs(repo, work, profile, game, version, target, graphics_api):
    patched = work / f'patched_{version}'
    if not patched.is_dir() or not any(p.is_file() for p in patched.iterdir()):
        raise Failed(f'no complete rewritten modules: {patched}')
    romfs = work / 'extract' / version / 'RomFS'
    image = romfs.with_name('RomFS.img')
    if not romfs.is_dir() and not image.is_file():
        raise Failed(f'no extracted RomFS: {romfs}')
    api = resolve_graphics(work, profile, target, graphics_api)
    resources = shader_resources(repo, work, profile, game, target, api)
    paths = [p for p in patched.rglob('*') if p.is_file()]
    if image.is_file():
        paths.append(image)
    for _, source in resources:
        paths.extend(p for p in source.rglob('*') if p.is_file())
    if target == 'ios':
        app = work / 'ipa/build/ios/pkg/dd/Build/Products/Release-iphoneos/DmIOS.app'
        if not (app / 'Info.plist').is_file():
            # New upstream uses a separate xcode derived data tree.
            app = work / 'xcode-derived-data/Build/Products/Release-iphoneos/DmIOS.app'
        paths += [app / 'Info.plist', app / 'DmIOS']
    else:
        hosts = [work / 'tools/dmhost', work / 'host/dmhost', repo / 'dm/host/dmhost']
        host = next((p for p in hosts if p.is_file()), None)
        if not host:
            raise Failed('Mac build did not produce a host executable')
        # Keep an immutable per-work copy so another game build cannot invalidate this one.
        own = work / '.nxlauncher/dmhost'
        own.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(host, own)
        paths.append(own)
    inventory = []
    for path in paths:
        if not path.is_file() or not path.stat().st_size:
            raise Failed(f'missing or empty build output: {path}')
        st = path.stat()
        inventory.append({'path': str(path.relative_to(work)), 'size': st.st_size,
                          'mtime_ns': st.st_mtime_ns})
    return api, inventory


def cmd_plan(args):
    game_dir = Path(args.game_dir).expanduser().resolve()
    repo = find_repo(args.repo)
    notes = []
    if not game_dir.is_dir():
        emit(ev='plan', ok=False, error=f'no such folder: {game_dir}')
        return 2

    base, updates, dlc, files = scan_game_dir(game_dir)
    title_id = ''
    if base:
        m = TITLE_RE.search(base.name)
        title_id = m.group(1).upper() if m else ''

    work = work_dir_of(game_dir, title_id) if title_id else None
    target = getattr(args, 'target', 'mac')
    if title_id:
        for candidate in sorted(game_dir.glob('*_build')):
            identity = read_json(manifest_path(candidate, target))
            if identity.get('title_id') == title_id:
                work = candidate
                break
    saved = read_json(manifest_path(work, target)) if work else {}
    prof = profile_for(repo, title_id, work)
    if saved.get('profile', {}).get('dir'):
        directory = Path(saved['profile']['dir'])
        if (directory / 'game.tsv').is_file():
            prof = profile_for(repo, saved.get('profile_id', title_id), work)
    if work and (work / 'profile' / title_id / 'game.tsv').is_file():
        # A derived build shadows an existing built-in profile for all subsequent exports.
        prof = profile_for(None, title_id, work)
    if not prof and title_id:
        notes.append('这款游戏还没有移植档案（dm/games/ 下没有），只能出"尽力而为"的包，可能起不来')
    elif prof and (Path(prof['dir']) / 'game.tsv').read_text(errors='replace').startswith('# Provisional'):
        notes.append('当前使用自动生成的临时移植档案，尚未验证游戏运行兼容性')
    built = False
    ver = prof['version'] if prof else ''
    icon = ''
    if work and work.is_dir():
        # the versions the work folder holds
        vers = sorted((p.name for p in (work / 'extract').iterdir() if p.is_dir()), key=version_key) if (work / 'extract').is_dir() else []
        if vers:
            ver = vers[-1]
            ic = work / 'extract' / ver / 'icon.jpg'
            if ic.is_file():
                icon = str(ic)
    target = getattr(args, 'target', 'mac')
    built_targets = {t: bool(work and manifest_valid(work, t, files, repo)) for t in ('mac', 'ios')}
    built = built_targets[target]
    if built:
        ver = saved.get('version', ver)
    if not built:
        notes.append('当前目标尚无匹配输入的完整构建记录；已有缓存可继续使用')

    keys_ok = bool(args.keys) and Path(args.keys).expanduser().is_file()
    if not keys_ok:
        notes.append('还没有选主机密钥（prod.keys）')

    emit(ev='plan', ok=True,
         game_dir=str(game_dir),
         repo=str(repo) if repo else '',
         repo_ok=bool(repo),
         keys=str(args.keys or ''), keys_ok=keys_ok,
         base=file_info(base) if base else None, base_title_id=title_id,
         updates=[file_info(u) for u in updates],
         dlc=[file_info(u) for u in dlc],
         all_files=[str(f) for f in files],
         has_port=bool(prof),
         name=prof['name'] if prof else (base.stem if base else ''),
         version=ver,
         work_dir=str(work) if work else '',
         built=built, target=target, built_targets=built_targets,
         build_status='complete' if built else 'not-built',
         profile_id=Path(prof['dir']).name if prof else title_id,
         graphics_api=saved.get('graphics_api', 'auto'),
         icon=icon,
         fps_target=prof['fps_target'] if prof else '',
         notes=notes)
    return 0


def cmd_games(args):
    repo = find_repo(args.repo)
    if not repo:
        error('NX_INPUT_INVALID', 'nxnative source tree not found (set NXLAUNCHER_REPO or pass --repo)')
        return 2
    out = []
    for d in sorted((repo / 'dm' / 'games').iterdir()):
        if not d.is_dir() or not (d / 'game.tsv').is_file():
            continue
        p = profile_for(repo, d.name)
        if p:
            out.append({'title_id': d.name, 'name': p['name'], 'version': p['version']})
    emit(ev='games', games=out, count=len(out))
    return 0


def stream(cmd, cwd=None, env=None, label=None):
    """Run a tool, pass its output through as log events, and return its exit code.
    A line that is a JSON object is passed on as an event (the upstream script's progress)."""
    if label:
        say(label)
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, bufsize=1, errors='replace')
    except OSError as e:
        raise Failed(f'cannot run {cmd[0]}: {e}')
    global BUILD_RESULT
    BUILD_RESULT = {}
    captured = None
    if SESSION:
        captured = (SESSION.path / 'subprocess.log').open('a', encoding='utf-8')
    for line in p.stdout:
        if captured:
            captured.write(line)
            captured.flush()
        line = line.rstrip('\n')
        if not line:
            continue
        if 'NX_RUNTIME_CAPTURE_REQUIRED' in line or ('runtime capture' in line.lower() and 'disabled' in line.lower()):
            BUILD_RESULT['runtime_capture_required'] = True
        try:
            obj = json.loads(line)
        except ValueError:
            log(line)
            continue
        if isinstance(obj, dict) and 'ev' in obj:
            if obj['ev'] == 'build_result':
                BUILD_RESULT.update(obj)
            if obj['ev'] == 'error':
                obj.setdefault('error_id', 'NX_BUILD_FAILED')
                obj.setdefault('hint', ERRORS['NX_BUILD_FAILED'])
            emit(**obj)
        else:
            log(line)
    p.wait()
    if captured:
        captured.close()
    return p.returncode


def dependency_report(args, repo):
    if not hasattr(args, 'target'):
        return doctor(repo, find_python(), os.environ)
    return doctor(repo, find_python(), os.environ, target=args.target,
                  graphics_api=getattr(args, 'graphics_api', 'auto'))


def cmd_doctor(args):
    report = dependency_report(args, find_repo(args.repo))
    emit(ev='dependencies', **report)
    return 0


def require_build_dependencies(repo, args=None):
    report = dependency_report(args, repo) if args else doctor(repo, find_python(), os.environ)
    emit(ev='dependencies', **report)
    if report['ready']:
        return True
    missing = ', '.join(c['name'] for c in report['checks'] if not c['ok'])
    error('NX_DEPENDENCIES', f'Build dependencies are not ready: {missing}. See the build environment panel.',
          getattr(args, 'target', 'mac'))
    return False


def rebuild_outputs(work, shaders_only=False):
    # Deliberately small allowlist: never remove extract, profile, run, keys or saves.
    names = ['shader', 'ipa', 'xcode-derived-data']
    if not shaders_only:
        names += [p.name for p in work.glob('patched_*')]
        names += ['tools', 'host']
    for name in names:
        path = work / name
        if path.is_symlink():
            path.unlink()
        elif path.is_dir():
            shutil.rmtree(path)
    for target in ('mac', 'ios'):
        manifest_path(work, target).unlink(missing_ok=True)


def cmd_build(args):
    repo = find_repo(args.repo)
    target = getattr(args, 'target', 'ios')  # old direct-call interface
    if not repo:
        error('NX_INPUT_INVALID', 'nxnative source tree not found (set NXLAUNCHER_REPO or pass --repo)')
        return 2
    game_dir = Path(args.game_dir).expanduser().resolve()
    if not game_dir.is_dir():
        error('NX_INPUT_INVALID', f'no such folder: {game_dir}')
        return 2
    if not args.keys or not Path(args.keys).expanduser().is_file():
        error('NX_INPUT_INVALID', 'prod.keys not found')
        return 2
    if not require_build_dependencies(repo, args):
        return 2
    base, _, _, files = scan_game_dir(game_dir)
    title = TITLE_RE.search(base.name).group(1).upper() if base and TITLE_RE.search(base.name) else ''
    strict = hasattr(args, 'target')
    if strict and not title:
        error('NX_INPUT_INVALID', 'Cannot identify base title ID from the selected game filenames.')
        return 2
    known = profile_for(repo, title)
    profile_id = Path(known['dir']).name if known else title
    work = work_dir_of(game_dir, profile_id)
    if getattr(args, 'rebuild', False) or getattr(args, 'rebuild_shaders', False):
        rebuild_outputs(work, shaders_only=not getattr(args, 'rebuild', False))
    if strict:
        atomic_json(manifest_path(work, target), {'schema': 1, 'status': 'building', 'target': target,
                                               'session_id': SESSION.id if SESSION else ''})
    py = find_python()
    cmd = [py, str(repo / 'scripts' / 'build_ipa_from_nsp.py'), str(game_dir),
           '-k', str(Path(args.keys).expanduser()), '--progress', 'json']
    if strict:
        cmd += ['--platform', target, '--keep-extracted', '--no-heap-check', '--no-runtime-capture']
    if args.out and target == 'ios':
        cmd += ['-o', str(args.out)]
    elif strict and target == 'ios':
        cmd += ['-o', str(game_dir / f'{profile_id}.ipa')]
    env = dict(os.environ, NX_NO_RUNTIME_CAPTURE='1')
    env['NXLAUNCHER_FONT_HELPER'] = str(Path(__file__).resolve().parents[1] / 'Scripts/font-policy.py')
    if strict:
        cmd = [py, '-c', UPSTREAM_ENTRY] + cmd[1:]
    stage('build', step=f'the upstream {target} packing script')
    try:
        rc = stream(cmd, cwd=repo, **({'env': env} if strict else {}))
    except Failed as exc:
        error('NX_BUILD_FAILED', exc, target)
        stage_end('build', ok=False, summary=str(exc))
        return 1
    if rc:
        error('NX_RUNTIME_CAPTURE_REQUIRED' if BUILD_RESULT.get('runtime_capture_required') else 'NX_BUILD_FAILED',
              f'The {target} script exited {rc}.', target)
        stage_end('build', ok=False, summary=f'the script exited {rc}')
        return 1
    if not strict:
        stage_end('build', summary='the IPA is ready')
        return 0
    # Upstream may choose a profile alias (its folder is not always the title ID).
    profile_id = BUILD_RESULT.get('profile_id', profile_id)
    work = work_dir_of(game_dir, profile_id)
    prof = profile_for(None, profile_id, work) or profile_for(repo, profile_id, work)
    if not prof:
        error('NX_MANIFEST_INVALID', 'Build completed without a resolvable game profile.', target)
        stage_end('build', ok=False, summary='missing build profile')
        return 1
    versions = sorted((p.name for p in (work / 'extract').iterdir() if p.is_dir()), key=version_key)
    version = BUILD_RESULT.get('version') or (versions[-1] if versions else prof['version'])
    try:
        api, outputs = completed_outputs(repo, work, Path(prof['dir']), profile_id, version, target,
                                         getattr(args, 'graphics_api', 'auto'))
    except (Failed, ShaderChainError, OSError) as exc:
        error('NX_MANIFEST_INVALID', exc, target)
        stage_end('build', ok=False, summary=str(exc))
        return 1
    atomic_json(manifest_path(work, target), {
        'schema': 1, 'status': 'complete', 'target': target, 'title_id': title,
        'profile_id': Path(prof['dir']).name, 'version': version, 'graphics_api': api,
        'profile': {'dir': prof['dir'], 'digest': profile_digest(prof['dir'])},
        'inputs': input_identity(files), 'repo_revision': repo_identity(repo), 'outputs': outputs,
        'session_id': SESSION.id if SESSION else '', 'completed': time.time()})
    stage_end('build', summary=f'{target} build complete')
    if target == 'mac' and not getattr(args, 'no_export', False):
        output = args.out or str(game_dir / (re.sub(r'[/\\:]', '_', prof['name']) + '.app'))
        return cmd_export(argparse.Namespace(repo=str(repo), work=str(work), out=output,
                    game=profile_id, ver=version, target='mac-app', dlc=str(work / 'aoc'),
                    name='', display='', graphics_api=api, require_manifest=True))
    if target == 'ios':
        output = Path(args.out).expanduser() if args.out else game_dir / f'{profile_id}.ipa'
        if output.is_file():
            emit(ev='artifact', target='ios-ipa-unsigned', path=str(output.resolve()),
                 game=title, version=version, graphics_api=api)
    return 0


def cmd_export(args):
    repo = find_repo(args.repo)
    tools = Path(__file__).resolve().parent
    work = Path(args.work).expanduser().resolve()
    out = Path(args.out).expanduser().resolve()
    game, ver = args.game, args.ver
    target = 'mac' if args.target == 'mac-app' else 'ios'
    saved = read_json(manifest_path(work, target))
    if not game:
        game = saved.get('title_id', '')
    if not ver:
        ver = saved.get('version', '')
    if getattr(args, 'require_manifest', False) and not manifest_valid(work, target, repo=repo):
        error('NX_MANIFEST_INVALID', 'No matching complete build manifest for export.', target)
        return 2
    if not repo or not work.is_dir():
        error('NX_INPUT_INVALID', f'nxnative source tree or build folder not found: {work}')
        return 2
    if out.exists():
        error('NX_INPUT_INVALID', f'导出位置已存在，请选择新的文件名或文件夹：{out}')
        return 2
    out.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    profiles = str(work / 'profile')
    env['DM_GAMES_DIR'] = os.pathsep.join(filter(None, [profiles, env.get('DM_GAMES_DIR', '')]))
    if (work / 'profile' / game / 'game.tsv').is_file():
        env['DM_GAMES_FIRST'] = '1'
    api = getattr(args, 'graphics_api', saved.get('graphics_api', 'auto'))
    if api != 'auto':
        env['GFXAPI'] = api
    env['NXLAUNCHER_FONT_HELPER'] = str(tools.parent / 'Scripts/font-policy.py')
    repo_arg = ['--repo', str(repo)]

    if args.target == 'mac-app':
        script = tools / 'make-mac-app.sh'
        cmd = ['bash', str(script), '--game', game, '--work', str(work), '--ver', ver, '--out', str(out)] + repo_arg
        if args.dlc:
            cmd += ['--dlc', str(Path(args.dlc).expanduser())]
        if args.name:
            cmd += ['--name', args.name]
        if args.display:
            cmd += ['--display', args.display]
        stage('export', step='the Mac .app')
    else:
        script = tools / ('make-signed-ipa.sh' if args.target == 'ios-ipa' else 'make-unsigned-ipa.sh')
        cmd = ['bash', str(script), '--out', str(out), '--work', str(work),
               '--game', game, '--ver', ver] + repo_arg
        stage('export', step='the iOS IPA')

    try:
        rc = stream(cmd, cwd=repo, env=env)
    except Failed as e:
        error('NX_EXPORT_FAILED', e, target)
        stage_end('export', ok=False, summary=str(e))
        return 1
    ok = rc == 0 and (out.is_dir() if args.target == 'mac-app' else out.is_file() and out.stat().st_size > 0)
    summary = str(out) if ok else (f'the script exited {rc}' if rc else f'export did not create {out}')
    stage_end('export', ok=ok, summary=summary)
    if ok:
        emit(ev='artifact', target=args.target, path=str(out), game=game, version=ver,
             graphics_api=api)
    else:
        error('NX_EXPORT_FAILED', summary, target)
    return 0 if ok else 1


def cmd_diagnostics(args):
    root = session_root() / 'sessions'
    sessions = sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink()),
                      key=lambda p: p.name) if root.is_dir() else []
    selected = getattr(args, 'session', '')
    if selected:
        if not re.fullmatch(r'[A-Za-z0-9_-]+', selected):
            raise Failed('invalid session ID')
        sessions = [p for p in sessions if p.name == selected]
    elif sessions:
        sessions = [p for p in sessions if not SESSION or p.name != SESSION.id][-1:]
    out = Path(args.out).expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.diagnostics-', suffix='.zip', dir=out.parent)
    os.close(fd)
    try:
        with zipfile.ZipFile(temp, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('system.json', json.dumps({'schema': 1, 'system': platform.system(),
                                  'release': platform.release(), 'machine': platform.machine(),
                                  'python': platform.python_version()}))
            # Fixed filenames only. Never recurse through a work/game/state directory.
            for index, session in enumerate(sessions):
                for name in ('session.json', 'events.jsonl', 'subprocess.log'):
                    path = session / name
                    if path.is_file() and not path.is_symlink():
                        archive.writestr(f'session-{index}/{name}', redact_document(path.read_text(errors='replace'), name))
            launcher = getattr(args, 'launcher_log', '')
            if launcher:
                path = Path(launcher).expanduser()
                # Only the explicitly selected text log; never infer sibling files.
                if path.is_symlink() or not path.is_file() or path.suffix.lower() not in ('.log', '.txt', '.jsonl'):
                    raise Failed('--launcher-log must be a regular .log, .txt or .jsonl file')
                if path.stat().st_size > 32 * 1024 * 1024:
                    raise Failed('--launcher-log exceeds 32 MiB')
                archive.writestr('launcher.log', redact_document(path.read_text(errors='replace'), path.name))
        os.replace(temp, out)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    emit(ev='artifact', target='diagnostics', path=str(out))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog='pack_pipeline.py', description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('plan', help='what is in the game folder')
    p.add_argument('--game-dir', required=True)
    p.add_argument('--keys', default='')
    p.add_argument('--repo', default='')
    p.add_argument('--target', choices=('mac', 'ios'), default='mac')
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser('doctor', help='check build dependencies without installing anything')
    p.add_argument('--repo', default='')
    p.add_argument('--target', choices=('mac', 'ios'), default='mac')
    p.add_argument('--graphics-api', choices=('auto', 'nvn', 'vulkan', 'gl'), default='auto')
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser('games', help='the games that have a port')
    p.add_argument('--repo', default='')
    p.set_defaults(func=cmd_games)

    p = sub.add_parser('build', help='the full build from the NSPs')
    p.add_argument('--game-dir', required=True)
    p.add_argument('--keys', required=True)
    p.add_argument('--repo', default='')
    p.add_argument('--out', default='')
    p.add_argument('--target', choices=('mac', 'ios'), default='mac')
    p.add_argument('--graphics-api', choices=('auto', 'nvn', 'vulkan', 'gl'), default='auto')
    p.add_argument('--rebuild', action='store_true')
    p.add_argument('--rebuild-shaders', action='store_true')
    p.add_argument('--no-export', action='store_true')
    p.set_defaults(func=cmd_build)

    p = sub.add_parser('export', help='the Mac .app or the iOS IPA from a built folder')
    p.add_argument('--target', required=True, choices=('mac-app', 'ios-ipa', 'ios-ipa-unsigned'))
    p.add_argument('--work', required=True)
    p.add_argument('--game', default='')
    p.add_argument('--ver', default='')
    p.add_argument('--out', required=True)
    p.add_argument('--repo', default='')
    p.add_argument('--dlc', default='')
    p.add_argument('--name', default='')
    p.add_argument('--display', default='')
    p.add_argument('--graphics-api', choices=('auto', 'nvn', 'vulkan', 'gl'), default='auto')
    p.add_argument('--require-manifest', action='store_true')
    p.set_defaults(func=cmd_export)

    p = sub.add_parser('diagnostics', help='export a redacted allowlist of diagnostic text')
    p.add_argument('--out', required=True)
    p.add_argument('--session', default='')
    p.add_argument('--launcher-log', default='')
    p.set_defaults(func=cmd_diagnostics)

    args = ap.parse_args(argv)
    global SESSION
    SESSION = Session(args.cmd, getattr(args, 'target', ''))
    emit(ev='session', log_path=str(SESSION.log))
    code = 1
    try:
        code = args.func(args)
    except KeyboardInterrupt:
        error('NX_INTERRUPTED', 'Operation interrupted.')
        code = 130
    except (OSError, ValueError, Failed, subprocess.SubprocessError) as exc:
        error('NX_INTERNAL', exc)
        code = 1
    finally:
        SESSION.finish(code)
        SESSION = None
    return code


if __name__ == '__main__':
    os.environ.update(build_environment())
    sys.exit(main(sys.argv[1:]))
