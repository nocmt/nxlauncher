import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'Tools'
PIPELINE_SCRIPT = TOOLS / 'pack_pipeline.py'

# pack_pipeline imports toolchain as a sibling script rather than as a package.
_added_tools_path = str(TOOLS) not in sys.path
if _added_tools_path:
    sys.path.insert(0, str(TOOLS))
try:
    spec = importlib.util.spec_from_file_location('pack_pipeline', PIPELINE_SCRIPT)
    pipeline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pipeline)
finally:
    if _added_tools_path:
        sys.path.remove(str(TOOLS))

import toolchain


class PackPipelineTests(unittest.TestCase):
    def make_layout(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        repo = root / 'nxnative'
        (repo / 'dm' / 'games').mkdir(parents=True)
        (repo / 'scripts').mkdir()
        upstream = repo / 'scripts' / 'build_ipa_from_nsp.py'
        upstream.write_text('# test fixture\n', encoding='utf-8')
        game_dir = root / 'game'
        game_dir.mkdir()
        keys = root / 'prod.keys'
        keys.write_text('test-only secret material\n', encoding='utf-8')
        return root, repo, game_dir, keys, upstream

    @staticmethod
    def events(output):
        return [json.loads(line) for line in output.getvalue().splitlines()]

    def test_doctor_emits_dependencies_event_from_helper_report(self):
        report = {
            'ready': False,
            'checks': [{'id': 'xcode', 'name': 'Full Xcode selected', 'ok': False,
                        'detail': 'not selected', 'hint': 'select Xcode'}],
            'commands': ['sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer'],
        }
        repo = Path('/fixture/nxnative')
        output = io.StringIO()
        args = argparse.Namespace(repo='/fixture/nxnative')

        with (mock.patch.object(pipeline, 'find_repo', return_value=repo),
              mock.patch.object(pipeline, 'find_python', return_value='/fixture/python'),
              mock.patch.object(pipeline, 'doctor', return_value=report) as doctor,
              contextlib.redirect_stdout(output)):
            result = pipeline.cmd_doctor(args)

        self.assertEqual(result, 0)
        doctor.assert_called_once_with(repo, '/fixture/python', os.environ)
        emitted, = self.events(output)
        self.assertEqual(set(emitted), {'ev', 'ready', 'checks', 'commands', 't'})
        self.assertEqual(emitted['ev'], 'dependencies')
        self.assertEqual({key: emitted[key] for key in report}, report)
        self.assertIsInstance(emitted['t'], (int, float))

    def test_build_preflight_failure_stops_before_stream_or_key_reads(self):
        _, repo, game_dir, keys, _ = self.make_layout()
        report = {
            'ready': False,
            'checks': [{'id': 'xcode', 'name': 'Full Xcode selected', 'ok': False,
                        'detail': 'not selected', 'hint': 'select Xcode'}],
            'commands': [],
        }
        output = io.StringIO()
        args = argparse.Namespace(repo=str(repo), game_dir=str(game_dir),
                                  keys=str(keys), out='')

        with (mock.patch.object(pipeline, 'find_python', return_value='/fixture/python'),
              mock.patch.object(pipeline, 'doctor', return_value=report) as doctor,
              mock.patch.object(pipeline, 'stream') as stream,
              mock.patch.object(subprocess, 'Popen') as popen,
              mock.patch.object(Path, 'open', autospec=True) as path_open,
              mock.patch.object(Path, 'read_text', autospec=True) as read_text,
              mock.patch.object(Path, 'read_bytes', autospec=True) as read_bytes,
              contextlib.redirect_stdout(output)):
            result = pipeline.cmd_build(args)

        self.assertEqual(result, 2)
        doctor.assert_called_once()
        stream.assert_not_called()
        popen.assert_not_called()
        path_open.assert_not_called()
        read_text.assert_not_called()
        read_bytes.assert_not_called()
        emitted = self.events(output)
        self.assertEqual([event['ev'] for event in emitted], ['dependencies', 'error'])
        self.assertEqual(emitted[0]['ready'], False)
        self.assertIn('Build dependencies are not ready', emitted[1]['message'])

    def test_build_entrypoint_inherits_repaired_runtime_environment(self):
        _, repo, game_dir, keys, upstream = self.make_layout()
        report = {'ready': True, 'checks': [], 'commands': []}
        repaired = {
            'PATH': '/fixture/repaired/bin',
            'DOTNET_ROOT_ARM64': '/fixture/dotnet-arm64',
            'DOTNET_ROOT': '/fixture/dotnet-arm64',
        }
        process = mock.Mock()
        process.stdout = iter([])
        process.wait.return_value = 0
        process.returncode = 0
        popen_calls = []

        def fake_popen(command, **kwargs):
            popen_calls.append((command, kwargs, dict(os.environ)))
            return process

        def fake_doctor(doctor_repo, python, env, **kwargs):
            self.assertEqual(doctor_repo, repo.resolve())
            self.assertEqual(env['PATH'], repaired['PATH'])
            self.assertEqual(env['DOTNET_ROOT_ARM64'], repaired['DOTNET_ROOT_ARM64'])
            return report

        title = '0100123456789000'
        (game_dir / f'Fixture [{title}].nsp').touch()
        profile = repo / 'dm/games' / title
        profile.mkdir()
        (profile / 'game.tsv').write_text(f'name\tFixture\npackage\tv1\ntitle_id\t{title}\n')
        work = game_dir / f'{title}_build'
        (work / 'extract/v1/RomFS').mkdir(parents=True)
        (work / 'patched_v1').mkdir()
        (work / 'patched_v1/main').write_bytes(b'module')
        (work / 'shader/gl').mkdir(parents=True)
        (work / 'shader/gl/gl_shaders.metallib').write_bytes(b'shader')
        (work / 'tools').mkdir()
        (work / 'tools/dmhost').write_bytes(b'fixture host')
        argv = [str(PIPELINE_SCRIPT), 'build', '--game-dir', str(game_dir),
                '--keys', str(keys), '--repo', str(repo), '--target', 'mac',
                '--graphics-api', 'gl', '--no-export']
        output = io.StringIO()
        with (mock.patch.dict(os.environ, {
                  'HOME': str(game_dir.parent),
                  'PATH': '/fixture/original/bin',
                  'NXLAUNCHER_PYTHON': sys.executable,
              }, clear=True),
              mock.patch.object(toolchain, 'build_environment', return_value=repaired) as env_builder,
              mock.patch.object(toolchain, 'doctor', side_effect=fake_doctor) as doctor,
              mock.patch.object(subprocess, 'run', return_value=mock.Mock(returncode=0, stdout='', stderr='')),
              mock.patch.object(subprocess, 'Popen', side_effect=fake_popen),
              mock.patch.object(sys, 'argv', argv),
              contextlib.redirect_stdout(output)):
            with self.assertRaises(SystemExit) as exit_result:
                runpy.run_path(str(PIPELINE_SCRIPT), run_name='__main__')

        self.assertEqual(exit_result.exception.code, 0)
        env_builder.assert_called_once_with()
        doctor.assert_called_once()
        self.assertEqual(len(popen_calls), 1)
        command, kwargs, inherited_env = popen_calls[0]
        self.assertEqual(command[0], sys.executable)
        self.assertIn(str(upstream.resolve()), command)
        self.assertIn('--no-runtime-capture', command)
        self.assertEqual(command[command.index('--platform') + 1], 'mac')
        self.assertEqual(kwargs['cwd'], repo.resolve())
        self.assertEqual(kwargs['env']['NX_NO_RUNTIME_CAPTURE'], '1')
        self.assertEqual(inherited_env['PATH'], repaired['PATH'])
        self.assertEqual(inherited_env['DOTNET_ROOT_ARM64'], repaired['DOTNET_ROOT_ARM64'])
        emitted = self.events(output)
        self.assertEqual([event['ev'] for event in emitted],
                         ['session', 'dependencies', 'stage', 'stage_end'])
        self.assertTrue(emitted[-1]['ok'])
        self.assertEqual(emitted[-1]['summary'], 'mac build complete')
        self.assertTrue(pipeline.manifest_path(work, 'mac').is_file())


    def test_plan_finds_provisional_profile_in_selected_work(self):
        _, repo, game_dir, keys, _ = self.make_layout()
        title = '01008CF01BAAC000'
        (game_dir / f'智慧的再现 [{title}][APP].nsp').touch()
        work = game_dir / f'{title}_build'
        profile = work / 'profile' / title
        profile.mkdir(parents=True)
        (profile / 'game.tsv').write_text('name\tEchoes of Wisdom\nbuild\tv196608\t1.1.0\npackage\tv196608\n')
        (work / 'extract' / 'v196608').mkdir(parents=True)
        (work / 'patched_v196608').mkdir()
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = pipeline.cmd_plan(argparse.Namespace(repo=str(repo), game_dir=str(game_dir), keys=str(keys)))
        plan, = self.events(output)
        self.assertEqual(result, 0)
        self.assertEqual(plan['name'], 'Echoes of Wisdom')
        self.assertEqual(plan['version'], 'v196608')
        self.assertFalse(plan['built'])  # Legacy directories are not evidence of a completed target build.
        self.assertTrue(plan['has_port'])

    def test_export_forwards_named_options_and_selected_work_profile(self):
        root, repo, _, _, _ = self.make_layout()
        work = root / '智慧的再现 build'
        work.mkdir()
        out = root / '导出 folder' / 'Echoes of Wisdom.ipa'
        args = argparse.Namespace(repo=str(repo), work=str(work), out=str(out),
                                  game='01008CF01BAAC000', ver='v196608',
                                  target='ios-ipa-unsigned', dlc='', name='', display='')
        def export(command, **kwargs):
            self.assertEqual(command[2:10], ['--out', str(out.resolve()), '--work', str(work.resolve()),
                                          '--game', args.game, '--ver', args.ver])
            self.assertIn(str(work.resolve() / 'profile'), kwargs['env']['DM_GAMES_DIR'].split(os.pathsep))
            out.write_bytes(b'fixture IPA')
            return 0
        with mock.patch.object(pipeline, 'stream', side_effect=export), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(pipeline.cmd_export(args), 0)

    def test_export_rejects_success_without_artifact(self):
        root, repo, work, _, _ = self.make_layout()
        args = argparse.Namespace(repo=str(repo), work=str(work), out=str(root / 'missing.ipa'),
                                  game='01008CF01BAAC000', ver='v196608',
                                  target='ios-ipa-unsigned', dlc='', name='', display='')
        output = io.StringIO()
        with mock.patch.object(pipeline, 'stream', return_value=0), contextlib.redirect_stdout(output):
            self.assertEqual(pipeline.cmd_export(args), 1)
        self.assertFalse(next(e for e in self.events(output) if e['ev'] == 'stage_end')['ok'])


    def test_manifest_identity_and_output_invalidation(self):
        root, repo, game_dir, keys, _ = self.make_layout()
        title = '0100123456789000'
        game = game_dir / f'Fixture [{title}].nsp'
        game.write_bytes(b'game fixture')
        profile = root / 'derived' / title
        profile.mkdir(parents=True)
        (profile / 'game.tsv').write_text('package\tv10\nname\tDerived\n')
        work = game_dir / f'{title}_build'
        output = work / 'patched_v10/main'
        output.parent.mkdir(parents=True)
        output.write_bytes(b'module')
        data = {'schema': 1, 'status': 'complete', 'target': 'mac', 'title_id': title,
                'version': 'v10', 'profile_id': title, 'graphics_api': 'gl',
                'profile': {'dir': str(profile), 'digest': pipeline.profile_digest(profile)},
                'repo_revision': pipeline.repo_identity(repo), 'inputs': pipeline.input_identity([game]),
                'outputs': [{'path': 'patched_v10/main', 'size': output.stat().st_size,
                             'mtime_ns': output.stat().st_mtime_ns}]}
        pipeline.atomic_json(pipeline.manifest_path(work, 'mac'), data)
        self.assertTrue(pipeline.manifest_valid(work, 'mac', [game], repo))
        self.assertFalse(pipeline.manifest_valid(work, 'ios', [game], repo))
        (profile / 'game.tsv').write_text('package\tv20\n')
        self.assertFalse(pipeline.manifest_valid(work, 'mac', [game], repo))
        (profile / 'game.tsv').write_text('package\tv10\nname\tDerived\n')
        output.write_bytes(b'changed')
        self.assertFalse(pipeline.manifest_valid(work, 'mac', [game], repo))
        output.write_bytes(b'module')
        data['outputs'][0]['mtime_ns'] = output.stat().st_mtime_ns
        pipeline.atomic_json(pipeline.manifest_path(work, 'mac'), data)
        game.write_bytes(b'different game')
        self.assertFalse(pipeline.manifest_valid(work, 'mac', [game], repo))

    def test_numeric_versions_and_rebuild_preserve_user_data(self):
        root, _, _, _, _ = self.make_layout()
        self.assertEqual(sorted(['v9', 'v100', 'v20'], key=pipeline.version_key), ['v9', 'v20', 'v100'])
        for name in ('extract/v1', 'profile/id', 'run/save', 'shader/cache', 'patched_v1', 'ipa'):
            (root / name).mkdir(parents=True, exist_ok=True)
            (root / name / 'keep').write_bytes(b'fixture')
        pipeline.rebuild_outputs(root)
        for name in ('extract/v1', 'profile/id', 'run/save'):
            self.assertTrue((root / name / 'keep').is_file())
        for name in ('shader', 'patched_v1', 'ipa'):
            self.assertFalse((root / name).exists())

    def test_diagnostics_allowlist_and_redaction(self):
        import zipfile
        root, _, _, _, _ = self.make_layout()
        state = root / 'state'
        with mock.patch.dict(os.environ, NXLAUNCHER_STATE_DIR=str(state)):
            session = pipeline.Session('build', 'mac')
            pipeline.atomic_json(session.path / 'session.json', {'path': '/Users/private/Game/file.nsp',
                'prod_keys': 'NEVER_EXPORT', 'token': 'NEVER_TOKEN'})
            (session.path / 'events.jsonl').write_text(json.dumps({'ev': 'log', 'line': 'header_key = abc123'}) + '\n')
            (session.path / 'subprocess.log').write_text('secret=NEVER_SECRET\n/Users/private/save/data\n' + 'a'*64)
            (session.path / 'prod.keys').write_text('RAW_KEY_PAYLOAD')
            (session.path / 'game.nsp').write_text('RAW_GAME_PAYLOAD')
            (session.path / 'save').mkdir()
            (session.path / 'save/private').write_text('RAW_SAVE_PAYLOAD')
            session.finish(1)
            launcher = root / 'launcher.log'
            launcher.write_text('/Users/private/launcher password=PRIVATE_PASSWORD')
            out = root / 'diag.zip'
            with contextlib.redirect_stdout(io.StringIO()):
                pipeline.cmd_diagnostics(argparse.Namespace(out=str(out), session=session.id, launcher_log=str(launcher)))
            with zipfile.ZipFile(out) as archive:
                self.assertEqual(set(archive.namelist()), {'system.json', 'session-0/session.json',
                    'session-0/events.jsonl', 'session-0/subprocess.log', 'launcher.log'})
                text = '\n'.join(archive.read(name).decode() for name in archive.namelist())
                for secret in ('NEVER_EXPORT', 'NEVER_TOKEN', 'NEVER_SECRET', 'abc123', 'PRIVATE_PASSWORD',
                               'RAW_KEY_PAYLOAD', 'RAW_GAME_PAYLOAD', 'RAW_SAVE_PAYLOAD', '/Users/private', 'a'*64):
                    self.assertNotIn(secret, text)
                json.loads(archive.read('session-0/session.json'))
                json.loads(archive.read('session-0/events.jsonl'))

    def test_session_persists_complete_events_and_failed_status(self):
        root, _, _, _, _ = self.make_layout()
        with mock.patch.dict(os.environ, NXLAUNCHER_STATE_DIR=str(root / 'state')):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(pipeline.main(['export', '--target', 'mac-app', '--work', str(root / 'missing'),
                                                '--out', str(root / 'out.app'), '--repo', str(root / 'missing')]), 2)
            session, = (root / 'state/sessions').iterdir()
            meta = json.loads((session / 'session.json').read_text())
            self.assertEqual(meta['status'], 'failed')
            events = [json.loads(line) for line in (session / 'events.jsonl').read_text().splitlines()]
            self.assertEqual(events[0]['ev'], 'session')
            self.assertTrue(events[-1]['error_id'])
            self.assertTrue(events[-1]['hint'])


if __name__ == '__main__':
    unittest.main()
