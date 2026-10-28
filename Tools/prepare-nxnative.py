#!/usr/bin/env python3
"""Apply or verify NxLauncher's patch series against its exact upstream commit."""
import argparse
from contextlib import contextmanager
import hashlib
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


class PatchError(Exception):
    pass


# Scripts/make-home-archive.sh removes these after verification. No patch may
# depend on files that disappear from the distributable source tree.
ARCHIVE_PRUNED = ('dm/host/gen', 'dm/ios/Gen',
                  'dm/tools/nx_extract/obj', 'dm/tools/nx_extract/bin')


def reject_pruned_paths(names):
    for name in names:
        folded = name.casefold()
        for excluded in ARCHIVE_PRUNED:
            excluded = excluded.casefold()
            if (folded == excluded or folded.startswith(excluded + '/') or
                    excluded.startswith(folded + '/')):
                raise PatchError(f'patch modifies archive-pruned generated path: {name}')


@contextmanager
def index_lock(path):
    """Exclude ordinary Git writers, without ever rewriting the user's index."""
    lock = Path(str(path) + '.lock')
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError as error:
        raise PatchError('nxnative index is locked; another Git operation may be running') from error
    try:
        yield
    finally:
        # Do not remove a lock that somebody replaced behind our back.
        if lock.exists() and os.path.samestat(os.fstat(fd), lock.stat()):
            lock.unlink()
        os.close(fd)


def path_stat(repo, name):
    """lstat a tree leaf, never traversing a symlink in its ancestors."""
    path = repo
    for part in Path(name).parts[:-1]:
        path /= part
        try:
            if not stat.S_ISDIR(path.lstat().st_mode):
                return None
        except FileNotFoundError:
            return None
    try:
        return (repo / name).lstat()
    except FileNotFoundError:
        return None


def matches_entry(repo, name, entry, algorithm):
    mode, oid = entry
    info = path_stat(repo, name)
    if info is None:
        return False
    path = repo / name
    if mode == '120000':
        if not stat.S_ISLNK(info.st_mode):
            return False
        data = os.fsencode(os.readlink(path))
        return hashlib.new(algorithm, b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == oid
    if not stat.S_ISREG(info.st_mode) or bool(info.st_mode & stat.S_IXUSR) != (mode == '100755'):
        return False
    digest = hashlib.new(algorithm, b'blob ' + str(info.st_size).encode() + b'\0')
    # Bypass Git's stat cache, assume-unchanged/skip-worktree, filters and filemode
    # settings. Verification is of actual bytes/types/modes, including new files.
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == oid


def tree_dirs(entries):
    return {str(parent) for name in entries for parent in Path(name).parents if str(parent) != '.'}


def matches_tree(repo, expected, other, algorithm):
    if not all(matches_entry(repo, name, entry, algorithm) for name, entry in expected.items()):
        return False
    directories = tree_dirs(expected)
    for name in other.keys() - expected.keys():
        info = path_stat(repo, name)
        if info is not None and not (name in directories and stat.S_ISDIR(info.st_mode)):
            return False
    return True


def check_collisions(repo, baseline, target):
    """Unrelated untracked/ignored data is allowed, but never overwritten.

    A directory may become a file only if every existing descendant belongs to
    the baseline and is removed by the target (including no extra empty dirs).
    """
    removed = baseline.keys() - target.keys()
    baseline_dirs = tree_dirs(baseline)
    collisions = []
    for name in target.keys() - baseline.keys():
        blocked = False
        for parent in reversed(Path(name).parents):
            if str(parent) == '.':
                continue
            info = path_stat(repo, str(parent))
            if info is not None and not stat.S_ISDIR(info.st_mode):
                if str(parent) not in removed:
                    collisions.append(str(parent))
                blocked = True
                break
        if blocked:
            continue
        info = path_stat(repo, name)
        if info is None:
            continue
        if stat.S_ISDIR(info.st_mode) and name in baseline_dirs:
            descendants = []
            for directory, dirs, files in os.walk(repo / name, followlinks=False):
                descendants.extend(str((Path(directory) / child).relative_to(repo))
                                   for child in dirs + files)
            if all(child in removed or child in baseline_dirs for child in descendants):
                continue
        collisions.append(name)
    if collisions:
        raise PatchError('nxnative has existing patch files: ' + ', '.join(sorted(set(collisions))))


def install_file(source, destination):
    """Exclusive installation: unlike rename/checkout, never overwrite a collision.

    Staging lives on the worktree filesystem. Hard-linking also gives rollback
    an inode identity for our own writes, including symlinks.
    """
    os.link(source, destination, follow_symlinks=False)


def checkout_tree(repo, baseline, target, algorithm, git, unchanged):
    """Prepare all bytes first; journal reversible, exclusive filesystem edits.

    This is a multi-file transaction, not crash-atomic. On exceptions (including
    interrupts) restore original inodes, not blobs reconstructed through Git.
    If another writer changes a path during the transaction, keep their data
    and retain the recovery directory rather than clobbering it on rollback.
    """
    changed = sorted(name for name in baseline.keys() | target.keys()
                     if baseline.get(name) != target.get(name))
    work = Path(tempfile.mkdtemp(prefix='.nxlauncher-prepare-', dir=repo))
    backups, installed, created_dirs, removed_dirs = [], [], [], []
    keep_recovery = False
    try:
        for number, name in enumerate(changed):
            if name not in target:
                continue
            mode, oid = target[name]
            data = git('cat-file', 'blob', oid).stdout
            staged = work / f'new-{number}'
            if mode == '120000':
                os.symlink(os.fsdecode(data), staged)
            else:
                staged.write_bytes(data)
                permissions = 0o755 if mode == '100755' else 0o644
                old = path_stat(repo, name)
                if old is not None and stat.S_ISREG(old.st_mode):
                    permissions = stat.S_IMODE(old.st_mode)
                    if bool(permissions & stat.S_IXUSR) != (mode == '100755'):
                        permissions = permissions | 0o111 if mode == '100755' else permissions & ~0o111
                staged.chmod(permissions)
            installed.append((name, staged, False))

        unchanged()
        if not matches_tree(repo, baseline, {}, algorithm):
            raise PatchError('nxnative differs from the pinned upstream; preserve local edits')
        check_collisions(repo, baseline, target)
        for number, name in enumerate(changed):
            if name in baseline:
                if not matches_entry(repo, name, baseline[name], algorithm):
                    raise PatchError(f'nxnative changed during preparation: {name}')
                saved = work / f'old-{number}'
                # Journal before moving, so an interrupt just after rename is safe.
                backups.append((name, saved))
                (repo / name).rename(saved)
                if not matches_entry(work, saved.name, baseline[name], algorithm):
                    raise PatchError(f'nxnative changed during preparation: {name}')

        for position, (name, staged, _) in enumerate(installed):
            destination = repo / name
            for parent in reversed(Path(name).parents):
                if str(parent) == '.':
                    continue
                path = repo / parent
                info = path_stat(repo, str(parent))
                if info is None:
                    created_dirs.append(path)
                    path.mkdir()
                elif not stat.S_ISDIR(info.st_mode):
                    raise PatchError(f'existing patch files: {parent}')
            if destination.is_dir() and not destination.is_symlink():
                # Only empty, preflight-approved baseline directories may go.
                directories = [Path(d) for d, _, _ in os.walk(destination)]
                for directory in reversed(directories):
                    info = directory.stat()
                    directory.rmdir()
                    removed_dirs.append((directory, info))
            installed[position] = (name, staged, True)
            install_file(staged, destination)

        unchanged()
        if not matches_tree(repo, target, baseline, algorithm):
            raise PatchError('patch application finished, but the resulting tree does not match')
    except BaseException as error:
        problems = []
        for name, staged, attempted in reversed(installed):
            if not attempted:
                continue
            try:
                info = path_stat(repo, name)
                if info is not None:
                    if (not os.path.samestat(info, staged.lstat()) or
                            not matches_entry(repo, name, target[name], algorithm)):
                        raise PatchError(f'concurrent change at {name}')
                    (repo / name).unlink()
            except (OSError, PatchError) as failure:
                problems.append(str(failure))
        for directory in reversed(created_dirs):
            try:
                directory.rmdir()
            except FileNotFoundError:
                pass
            except OSError as failure:
                problems.append(str(failure))
        for directory, info in reversed(removed_dirs):
            try:
                directory.mkdir(mode=stat.S_IMODE(info.st_mode))
            except OSError as failure:
                problems.append(str(failure))
        for name, saved in backups:
            if not os.path.lexists(saved):
                continue
            try:
                # Exclusive restoration also refuses to overwrite concurrent data.
                install_file(saved, repo / name)
            except OSError as failure:
                problems.append(str(failure))
        if problems:
            keep_recovery = True
            raise PatchError(f'preparation failed ({error}); rollback needs attention: '
                             f'{"; ".join(problems)}; original files retained in {work}') from error
        raise
    finally:
        if not keep_recovery:
            shutil.rmtree(work)


def export_tree(destination, target_oid, target, algorithm, git):
    """Export only verified Git blobs, never ignored build products or user data.

    The temporary index's tree is the snapshot we verified, so a concurrent
    worktree edit cannot race a later recursive copy into the release archive.
    The destination must not exist; publish it only after checking exported bytes.
    """
    destination = Path(destination).absolute()
    if os.path.lexists(destination):
        raise PatchError(f'export destination already exists: {destination}')
    with tempfile.TemporaryDirectory(prefix='.nxlauncher-export-', dir=destination.parent) as tmp:
        tmp = Path(tmp)
        archive, source = tmp / 'source.tar', tmp / 'source'
        source.mkdir()
        git('archive', '--format=tar', f'--output={archive}', target_oid)
        result = subprocess.run(['tar', '-xf', str(archive), '-C', str(source)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise PatchError(f'cannot extract verified source: {os.fsdecode(result.stderr).strip()}')
        # Git export-ignore/export-subst attributes must not silently omit or
        # rewrite source files that were verified in the worktree.
        if not matches_tree(source, target, {}, algorithm):
            raise PatchError('exported source differs from the verified patch tree')
        for name in ARCHIVE_PRUNED:
            path = source / name
            if path.is_dir() and not path.is_symlink():
                shutil.rmtree(path)
            elif os.path.lexists(path):
                path.unlink()
        source.rename(destination)


def prepare(repo, patch_dir, check=False, export_dir=None):
    if export_dir is not None and not check:
        raise PatchError('source export requires --check; it never applies patches')
    repo, patch_dir = Path(repo).resolve(), Path(patch_dir).resolve()
    # Do not let inherited Git repository/index routing redirect any operation.
    env = dict(os.environ)
    for key in ('GIT_INDEX_FILE', 'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR',
                'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES',
                'GIT_NAMESPACE', 'GIT_PREFIX', 'GIT_SHALLOW_FILE'):
        env.pop(key, None)
    env['GIT_OPTIONAL_LOCKS'] = '0'

    def git(*args, index=None):
        command_env = dict(env)
        if index is not None:
            command_env['GIT_INDEX_FILE'] = str(index)
        result = subprocess.run(['git', '-C', str(repo), *args], env=command_env,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise PatchError(os.fsdecode(result.stderr).strip() or
                             os.fsdecode(result.stdout).strip() or f'git {args[0]} failed')
        return result

    if Path(os.fsdecode(git('rev-parse', '--show-toplevel').stdout).strip()).resolve() != repo:
        raise PatchError('nxnative must be the root of its worktree')
    base = (patch_dir / 'base-commit').read_text().strip()
    series = [line.strip() for line in (patch_dir / 'series').read_text().splitlines()
              if line.strip() and not line.lstrip().startswith('#')]
    patches = []
    for name in series:
        path = (patch_dir / name).resolve()
        if path.parent != patch_dir or not path.is_file():
            raise PatchError(f'invalid patch in series: {name}')
        patches.append(path)
    head = os.fsdecode(git('rev-parse', 'HEAD').stdout).strip()
    if head != base:
        raise PatchError(f'nxnative is at {head}; this series requires {base}')

    def entries(output, index=False):
        result = {}
        for record in output.split(b'\0'):
            if not record:
                continue
            metadata, raw_name = record.split(b'\t', 1)
            mode, kind, oid = metadata.split(b' ')
            if index:
                mode, oid, stage = mode, kind, oid
                if stage != b'0':
                    raise PatchError('nxnative has staged changes (unmerged index)')
            name = os.fsdecode(raw_name)
            if (Path(name).is_absolute() or any(part in ('.', '..') or part.lower() == '.git'
                                               for part in name.split('/'))):
                raise PatchError(f'unsafe patch path: {name}')
            if mode not in (b'100644', b'100755', b'120000'):
                raise PatchError(f'unsupported tree entry mode {os.fsdecode(mode)}: {name}')
            result[name] = (os.fsdecode(mode), os.fsdecode(oid))
        return result

    baseline = entries(git('ls-tree', '-rz', base).stdout)
    algorithm = os.fsdecode(git('rev-parse', '--show-object-format').stdout).strip()
    index_path = Path(os.fsdecode(git('rev-parse', '--path-format=absolute', '--git-path', 'index').stdout).strip())
    with index_lock(index_path):
        index_bytes = index_path.read_bytes() if index_path.exists() else None
        if entries(git('ls-files', '--stage', '-z').stdout, index=True) != baseline:
            raise PatchError('nxnative has staged changes; preserve them before preparing patches')

        def unchanged():
            current = index_path.read_bytes() if index_path.exists() else None
            if git('rev-parse', 'HEAD').stdout.strip() != base.encode() or current != index_bytes:
                raise PatchError('nxnative HEAD or index changed during preparation')

        with tempfile.TemporaryDirectory(prefix='nxlauncher-patches-') as tmp:
            index = Path(tmp) / 'index'
            git('read-tree', base, index=index)
            for path in patches:
                before = git('write-tree', index=index).stdout.strip().decode('ascii')
                git('apply', '--cached', '--whitespace=error', str(path), index=index)
                touched = git('diff', '--cached', '--no-renames', '--name-only', '-z',
                              before, index=index).stdout
                reject_pruned_paths(os.fsdecode(name) for name in touched.split(b'\0') if name)
            target_oid = git('write-tree', index=index).stdout.strip().decode('ascii')
            target = entries(git('ls-tree', '-rz', target_oid).stdout)
            unchanged()
            if matches_tree(repo, target, baseline, algorithm):
                if export_dir is not None:
                    export_tree(export_dir, target_oid, target, algorithm, git)
                    unchanged()
                print(f'nxnative {head[:12]}: all {len(patches)} patches verified; tree {target_oid}')
                return
            if not matches_tree(repo, baseline, {}, algorithm):
                raise PatchError('nxnative differs from both the pinned upstream and the complete patch series; '
                                 'preserve local edits before proceeding')
            check_collisions(repo, baseline, target)
            if check:
                raise PatchError('patches are not applied; run python3 Tools/prepare-nxnative.py')
            checkout_tree(repo, baseline, target, algorithm, git, unchanged)
        print(f'nxnative {head[:12]}: all {len(patches)} patches verified')


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='verify without changing the dependency')
    parser.add_argument('--repo', type=Path, default=root / 'nxnative')
    parser.add_argument('--patch-dir', type=Path, default=root / 'patches')
    parser.add_argument('--export', type=Path, dest='export_dir',
                        help='with --check, export verified source to a new directory (no build products)')
    args = parser.parse_args()
    try:
        prepare(args.repo, args.patch_dir, args.check, args.export_dir)
    except (PatchError, OSError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
