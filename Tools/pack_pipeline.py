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
from pathlib import Path

# ---- the event vocabulary (the same one the upstream script uses) ----
def emit(**obj):
    obj.setdefault('t', round(__import__('time').time(), 3))
    print(json.dumps(obj, ensure_ascii=False), flush=True)


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


def scan_game_dir(d):
    """The NSP / XCI files in the folder, sorted into base / update / DLC.

    Nintendo's convention: the base game's title ID ends in 000, an update's in 800, and the DLC
    files carry [DLC] in the name (their IDs are the base's + 0x1000 and up)."""
    base, updates, dlc = None, [], []
    files = sorted([p for p in d.iterdir() if p.suffix.lower() in ('.nsp', '.xci')]) if d.is_dir() else []
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


def profile_for(repo, title_id):
    """The game's port: the profile folder in dm/games/. Its presence is what "the game has a port" means."""
    if not repo or not title_id:
        return None
    d = repo / 'dm' / 'games' / title_id
    if not (d / 'game.tsv').is_file():
        return None
    vals = {}
    for line in (d / 'game.tsv').read_text(errors='replace').splitlines():
        if line.startswith('#') or '\t' not in line:
            continue
        k, v = line.split('\t', 1)
        vals.setdefault(k.strip(), v.strip())
    return {
        'dir': str(d),
        'name': vals.get('name', title_id),
        'version': (vals.get('build', '').split() or [''])[1] or vals.get('package', ''),
        'modules': vals.get('modules', ''),
        'fps_target': vals.get('fps_target', ''),
        'mem_pool': vals.get('app_pool', ''),
        'mem_reserve': vals.get('mem_reserve', ''),
        'chain': chain_of(d),
    }


def chain_of(profile_dir):
    f = profile_dir / 'dmsh_chain.h'
    if not f.is_file():
        return ''
    m = re.search(r'#define\s+DMSH_CHAIN\s+"([^"]*)"', f.read_text(errors='replace'))
    return m.group(1) if m else ''


def work_dir_of(game_dir, title_id):
    return game_dir / f'{title_id}_build'


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

    prof = profile_for(repo, title_id)
    if not prof and title_id:
        notes.append('这款游戏还没有移植档案（dm/games/ 下没有），只能出"尽力而为"的包，可能起不来')

    work = work_dir_of(game_dir, title_id) if title_id else None
    built = False
    ver = prof['version'] if prof else ''
    icon = ''
    if work and work.is_dir():
        # the versions the work folder holds
        vers = sorted(p.name for p in (work / 'extract').iterdir() if p.is_dir()) if (work / 'extract').is_dir() else []
        if vers:
            ver = vers[-1]
            built = (work / f'patched_{ver}').is_dir()
            ic = work / 'extract' / ver / 'icon.jpg'
            if ic.is_file():
                icon = str(ic)
    if not built:
        notes.append('还没有编译过：第一次编译要 30–60 分钟（着色器），之后约 10 分钟')

    keys_ok = bool(args.keys) and Path(args.keys).expanduser().is_file()
    if not keys_ok:
        notes.append('还没有选主机密钥（prod.keys）')

    emit(ev='plan', ok=True,
         game_dir=str(game_dir),
         repo=str(repo) if repo else '',
         repo_ok=bool(repo),
         keys=str(args.keys or ''), keys_ok=keys_ok,
         base=str(base) if base else '', base_title_id=title_id,
         updates=[str(u) for u in updates],
         dlc=[str(d) for d in dlc],
         all_files=[str(f) for f in files],
         has_port=bool(prof),
         name=prof['name'] if prof else (base.stem if base else ''),
         version=ver,
         work_dir=str(work) if work else '',
         built=built,
         icon=icon,
         fps_target=prof['fps_target'] if prof else '',
         notes=notes)
    return 0


def cmd_games(args):
    repo = find_repo(args.repo)
    if not repo:
        emit(ev='error', message='nxnative source tree not found (set NXLAUNCHER_REPO or pass --repo)')
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
    for line in p.stdout:
        line = line.rstrip('\n')
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            log(line)
            continue
        if isinstance(obj, dict) and 'ev' in obj:
            emit(**obj)
        else:
            log(line)
    p.wait()
    return p.returncode


def cmd_build(args):
    repo = find_repo(args.repo)
    if not repo:
        emit(ev='error', message='nxnative source tree not found (set NXLAUNCHER_REPO or pass --repo)')
        return 2
    game_dir = Path(args.game_dir).expanduser().resolve()
    if not game_dir.is_dir():
        emit(ev='error', message=f'no such folder: {game_dir}')
        return 2
    if not args.keys or not Path(args.keys).expanduser().is_file():
        emit(ev='error', message='prod.keys not found')
        return 2

    py = find_python()
    cmd = [py, str(repo / 'scripts' / 'build_ipa_from_nsp.py'), str(game_dir),
           '-k', str(Path(args.keys).expanduser()), '--progress', 'json']
    if args.out:
        cmd += ['-o', str(args.out)]
    stage('build', step='the upstream packing script')
    try:
        rc = stream(cmd, cwd=repo)
    except Failed as e:
        stage_end('build', ok=False, summary=str(e))
        return 1
    stage_end('build', ok=rc == 0, summary='the IPA is ready' if rc == 0 else f'the script exited {rc}')
    return 0 if rc == 0 else 1


def cmd_export(args):
    repo = find_repo(args.repo)
    tools = Path(__file__).resolve().parent
    work = Path(args.work).expanduser()
    out = Path(args.out).expanduser()
    game, ver = args.game, args.ver
    # the packaging scripts need to know where the nxnative source tree is
    repo_arg = ['--repo', str(repo)] if repo else []

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
        cmd = ['bash', str(script), str(out)] + repo_arg
        stage('export', step='the iOS IPA')

    try:
        rc = stream(cmd, cwd=repo)
    except Failed as e:
        stage_end('export', ok=False, summary=str(e))
        return 1
    ok = rc == 0 and (out.exists() if out.is_dir() else out.parent.exists())
    stage_end('export', ok=rc == 0, summary=str(out) if rc == 0 else f'the script exited {rc}')
    return 0 if rc == 0 else 1


def main(argv):
    ap = argparse.ArgumentParser(prog='pack_pipeline.py', description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)

    p = sub.add_parser('plan', help='what is in the game folder')
    p.add_argument('--game-dir', required=True)
    p.add_argument('--keys', default='')
    p.add_argument('--repo', default='')
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser('games', help='the games that have a port')
    p.add_argument('--repo', default='')
    p.set_defaults(func=cmd_games)

    p = sub.add_parser('build', help='the full build from the NSPs')
    p.add_argument('--game-dir', required=True)
    p.add_argument('--keys', required=True)
    p.add_argument('--repo', default='')
    p.add_argument('--out', default='')
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
    p.set_defaults(func=cmd_export)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
