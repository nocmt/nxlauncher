import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / 'Tools' / 'toolchain.py'
spec = importlib.util.spec_from_file_location('toolchain_under_test', SCRIPT)
toolchain = importlib.util.module_from_spec(spec)
spec.loader.exec_module(toolchain)


class ToolchainFixture(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()

    def make_runtime_root(self, path):
        (path / 'host' / 'fxr').mkdir(parents=True)
        (path / 'shared' / 'Microsoft.NETCore.App').mkdir(parents=True)
        return path


class BuildEnvironmentTests(ToolchainFixture):
    def setUp(self):
        super().setUp()
        # Keep discovery independent of runtimes installed on the test machine.
        roots = mock.patch.object(toolchain, 'DOTNET_ROOTS', ())
        roots.start()
        self.addCleanup(roots.stop)
        which = mock.patch.object(toolchain.shutil, 'which', return_value=None)
        self.which = which.start()
        self.addCleanup(which.stop)
        self.env = {'HOME': str(self.root), 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'}

    def test_minimal_gui_path_gets_homebrew_and_user_dotnet_directories(self):
        result = toolchain.build_environment(self.env)

        self.assertEqual(result['PATH'].split(os.pathsep), [
            *toolchain.TOOL_DIRS, str(self.root / '.dotnet'),
            '/usr/bin', '/bin', '/usr/sbin', '/sbin',
        ])
        self.which.assert_called_once_with('dotnet', path=result['PATH'])
        self.assertNotIn('DOTNET_ROOT', result)
        self.assertNotIn('DOTNET_ROOT_ARM64', result)

    def test_homebrew_wrapper_finds_bin_parent_libexec_before_known_roots(self):
        prefix = self.root / 'Cellar' / 'dotnet' / '10.0.100'
        runtime = self.make_runtime_root(prefix / 'libexec')
        wrapper = prefix / 'bin' / 'dotnet'
        wrapper.parent.mkdir()
        wrapper.touch()
        unrelated = self.make_runtime_root(self.root / 'unrelated')
        self.which.return_value = str(wrapper)

        with mock.patch.object(toolchain, 'DOTNET_ROOTS', (str(unrelated),)):
            result = toolchain.build_environment(self.env)

        self.assertEqual(result['DOTNET_ROOT_ARM64'], str(runtime))
        self.assertEqual(result['DOTNET_ROOT'], str(runtime))
        self.assertEqual(result['PATH'].split(os.pathsep)[0], str(runtime))

    def test_invalid_explicit_roots_are_removed_without_a_fallback(self):
        runtime = self.make_runtime_root(self.root / 'runtime')
        invalid_bin = runtime / 'bin'
        invalid_bin.mkdir()
        env = dict(self.env, DOTNET_ROOT_ARM64=str(invalid_bin),
                   DOTNET_ROOT=str(self.root / 'missing'))

        result = toolchain.build_environment(env)

        self.assertNotIn('DOTNET_ROOT_ARM64', result)
        self.assertNotIn('DOTNET_ROOT', result)
        self.assertNotIn(str(invalid_bin), result['PATH'].split(os.pathsep))
        self.assertEqual(env['DOTNET_ROOT_ARM64'], str(invalid_bin))

    def test_valid_generic_root_replaces_invalid_arm64_override(self):
        runtime = self.make_runtime_root(self.root / 'runtime')
        (runtime / 'bin').mkdir()
        env = dict(self.env, DOTNET_ROOT_ARM64=str(self.root / 'missing'),
                   DOTNET_ROOT=str(runtime))

        result = toolchain.build_environment(env)

        self.assertEqual(result['DOTNET_ROOT'], str(runtime))
        self.assertEqual(result['DOTNET_ROOT_ARM64'], str(runtime))
        self.assertEqual(result['PATH'].split(os.pathsep)[:2],
                         [str(runtime), str(runtime / 'bin')])
        self.which.assert_not_called()

    def test_valid_explicit_arm64_root_wins_and_preserves_valid_generic_override(self):
        arm = self.make_runtime_root(self.root / 'arm')
        generic = self.make_runtime_root(self.root / 'generic')

        result = toolchain.build_environment(dict(
            self.env, DOTNET_ROOT_ARM64=str(arm), DOTNET_ROOT=str(generic)))

        self.assertEqual(result['DOTNET_ROOT_ARM64'], str(arm))
        self.assertEqual(result['DOTNET_ROOT'], str(generic))
        self.assertEqual(result['PATH'].split(os.pathsep)[0], str(arm))
        self.which.assert_not_called()

    def test_versioned_root_fallback_replaces_invalid_explicit_roots(self):
        runtime = self.make_runtime_root(self.root / 'dotnet@10' / 'libexec')
        env = dict(self.env, DOTNET_ROOT_ARM64=str(self.root / 'missing'),
                   DOTNET_ROOT=str(self.root / 'bin'))
        candidates = (str(self.root / 'dotnet' / 'libexec'), str(runtime))

        with mock.patch.object(toolchain, 'DOTNET_ROOTS', candidates):
            result = toolchain.build_environment(env)

        self.assertEqual(result['DOTNET_ROOT_ARM64'], str(runtime))
        self.assertEqual(result['DOTNET_ROOT'], str(runtime))
        self.assertEqual(result['PATH'].split(os.pathsep)[0], str(runtime))

    def test_inherited_environment_is_copied_and_custom_path_entries_survive(self):
        missing = str(self.root / 'missing')
        inherited = f'/custom::{missing}:/custom:/opt/homebrew/bin'
        env = dict(self.env, PATH=inherited, KEEP_ME='yes', EMPTY_VALUE='')
        before = dict(env)

        result = toolchain.build_environment(env)

        self.assertIsNot(result, env)
        self.assertEqual(env, before)
        self.assertEqual(result['KEEP_ME'], 'yes')
        self.assertEqual(result['EMPTY_VALUE'], '')
        entries = result['PATH'].split(os.pathsep)
        self.assertEqual(entries[-3:], ['/custom', '', missing])
        self.assertEqual(entries.count('/custom'), 1)
        self.assertEqual(entries.count('/opt/homebrew/bin'), 1)


class DoctorTests(ToolchainFixture):
    def setUp(self):
        super().setUp()
        self.runtime = self.make_runtime_root(self.root / 'runtime')
        self.repo = self.root / 'repo'
        self.translator = (self.repo / 'dm' / 'gfx' / 'tools'
                           / 'dmsh_xlate_bin' / 'dmsh_xlate')
        self.translator.parent.mkdir(parents=True)
        self.translator.write_text('fixture', encoding='utf-8')
        self.translator.chmod(0o755)
        self.python = str(self.root / 'build python' / 'python3')
        self.env = {'PATH': '/fixture/bin', 'DOTNET_ROOT_ARM64': str(self.runtime)}
        self.dotnet = '/fixture/bin/dotnet'
        self.info = ' RID: osx-arm64\n Architecture: arm64'
        self.sdks = '10.0.100 [/fixture/sdk]'
        self.runtimes = 'Microsoft.NETCore.App 10.0.0 [/fixture/shared]'
        self.python_data = {
            'version': [3, 13, 1],
            'modules': {name: '' for name in ('lz4.block', 'capstone', 'fontTools', 'PIL')},
            'zstd': 'backports.zstd', 'zstd_error': '',
        }
        found = {name: '/fixture/bin/' + name
                 for name in ('make', 'xcodegen', 'zstd', 'spirv-cross', 'dotnet')}
        for name, kwargs in (
            ('_probe', {'side_effect': self.fake_probe}),
            ('_runtime_smoke', {'return_value': (True, 'net10 resolved')}),
        ):
            patcher = mock.patch.object(toolchain, name, **kwargs)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)
        patcher = mock.patch.object(toolchain.shutil, 'which',
                                    side_effect=lambda name, path=None: found.get(name))
        self.which = patcher.start()
        self.addCleanup(patcher.stop)

    def fake_probe(self, argv, env):
        self.assertEqual(env, self.env)
        args = tuple(map(str, argv))
        outputs = {
            ('xcode-select', '-p'): '/Applications/Xcode.app/Contents/Developer',
            ('xcodebuild', '-version'): 'Xcode 16.0',
            ('/fixture/bin/make', '--version'): 'GNU Make 4.4',
            (self.dotnet, '--info'): self.info,
            (self.dotnet, '--list-sdks'): self.sdks,
            (self.dotnet, '--list-runtimes'): self.runtimes,
            (self.python, '-c', toolchain._PYTHON_PROBE): json.dumps(self.python_data),
        }
        if args[0] == 'xcrun':
            return True, '/fixture/xcode/' + args[-1], ''
        self.assertIn(args, outputs, 'Unexpected external probe')
        return True, outputs[args], ''

    def run_doctor(self):
        return toolchain.doctor(self.repo, self.python, self.env)

    @staticmethod
    def checks(report):
        return {check['id']: check for check in report['checks']}

    def test_rejects_x64_unknown_or_conflicting_architecture_despite_arm64_paths(self):
        for info in (
            ' RID: osx-x64\n Architecture: x64\n Base Path: /sdk/arm64/',
            ' RID: osx-x64\n Architecture: arm64',
            ' Base Path: /sdk/arm64/\nOther architectures found:\n arm64',
        ):
            with self.subTest(info=info):
                self.info = info
                report = self.run_doctor()
                checks = self.checks(report)
                self.assertFalse(report['ready'])
                self.assertFalse(checks['dotnet-arm64']['ok'])
                self.assertTrue(checks['dotnet-sdk']['ok'])
                self.assertTrue(checks['dotnet-runtime']['ok'])

    def test_rejects_missing_net10_sdk_or_runtime_independently(self):
        for sdk, runtime, failed in (
            ('11.0.100 [/fixture/sdk]', self.runtimes, 'dotnet-sdk'),
            (self.sdks, 'Microsoft.NETCore.App 11.0.0 [/fixture/shared]', 'dotnet-runtime'),
        ):
            with self.subTest(failed=failed):
                self.sdks, self.runtimes = sdk, runtime
                report = self.run_doctor()
                failures = {item['id'] for item in report['checks'] if not item['ok']}
                self.assertEqual(failures, {failed})
                self.assertFalse(report['ready'])
                self.assertEqual(report['commands'].count('brew install dotnet@10'), 1)

    def test_translator_directory_does_not_substitute_for_nested_executable(self):
        self.translator.unlink()
        report = self.run_doctor()
        self.assertTrue(self.translator.parent.is_dir())
        self.assertFalse(self.checks(report)['translator']['ok'])
        self.assertFalse(report['ready'])

        self.translator.mkdir()
        report = self.run_doctor()
        self.assertFalse(self.checks(report)['translator']['ok'])
        self.assertFalse(report['ready'])

    def test_translator_file_must_be_executable(self):
        self.translator.chmod(0o644)
        report = self.run_doctor()
        self.assertTrue(self.translator.is_file())
        self.assertFalse(self.checks(report)['translator']['ok'])
        self.assertFalse(report['ready'])

    def test_missing_python_modules_report_errors_and_selected_interpreter_commands(self):
        self.python_data['modules']['lz4.block'] = 'No module named lz4.block'
        self.python_data['modules'].pop('PIL')
        self.python_data.update(zstd='', zstd_error='No zstd module available')

        report = self.run_doctor()
        checks = self.checks(report)

        self.assertFalse(report['ready'])
        self.assertTrue(checks['python']['ok'])
        self.assertTrue(checks['python-capstone']['ok'])
        self.assertTrue(checks['python-fontTools']['ok'])
        for check_id in ('python-lz4.block', 'python-PIL', 'python-zstd'):
            self.assertFalse(checks[check_id]['ok'])
        self.assertIn('No module named lz4.block', checks['python-lz4.block']['detail'])
        self.assertEqual(checks['python-zstd']['detail'], 'No zstd module available')
        self.assertCountEqual(report['commands'], [
            f"'{self.python}' -m pip install {package}"
            for package in ('lz4', 'pillow', 'backports.zstd')
        ])

    def test_ready_with_nested_translator_executable_and_successful_probes(self):
        before = dict(self.env)
        report = self.run_doctor()

        self.assertTrue(report['ready'])
        self.assertEqual(len(report['checks']), 21)
        self.assertTrue(all(item['ok'] for item in report['checks']))
        self.assertEqual(report['commands'], [])
        self.assertEqual(self.checks(report)['translator']['detail'], str(self.translator))
        self._runtime_smoke.assert_called_once_with(self.runtime, self.env)
        self.which.assert_any_call('dotnet', path=self.env['PATH'])
        self._probe.assert_any_call([self.python, '-c', toolchain._PYTHON_PROBE], self.env)
        self.assertEqual(self.env, before)


if __name__ == '__main__':
    unittest.main()
