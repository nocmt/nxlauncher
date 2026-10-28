"""Small filesystem fixtures run the real upstream ZIP writer, never a game export."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / 'Tools'
UPSTREAM = ROOT / 'nxnative'
GAME = '0100123456789000'
OTHER_GAME = '01007EF00011E000'
APP_REL = 'ipa/build/ios/pkg/dd/Build/Products/Release-iphoneos/DmIOS.app'
PREFIX = 'Payload/DmIOS.app/'


class IPAExportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='ipa fixture ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.repo = self.root / "仓库 O'Brien $(false)"
        self.work = self.root / '游戏 路径' / f'{GAME}_build'
        self.app = self.work / APP_REL
        self.out = self.root / '输出 目录' / '游戏 unsigned.ipa'
        self.profile = self.work / 'profile' / GAME
        self.profile.mkdir(parents=True)
        (self.profile / 'game.tsv').write_text(
            f'title_id\t{GAME}\nname\t所选游戏\npackage\tv2\n'
            'ipa\t所选 游戏.ipa\nromfs_marker\tData/marker.bin\nzip_store\t.packed\n',
            encoding='utf-8')
        (self.profile / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "selected-chain"\n')
        for relative in ('dm/games/game.py', 'dm/ios/tools/pack_ipa.py'):
            dst = self.repo / relative
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(UPSTREAM / relative, dst)
        # An unrelated built-in profile must never become the default.
        unrelated = self.repo / 'dm/games' / OTHER_GAME
        unrelated.mkdir()
        (unrelated / 'game.tsv').write_text('package\tv999\nipa\twrong.ipa\nzip_store\t.bin\n')
        self.app.mkdir(parents=True)
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'DmIOS', 'CFBundleIdentifier': f'org.nxnative.{GAME.lower()}',
        }))
        self.put(self.app / 'DmIOS', b'binary fixture')
        (self.app / 'DmIOS').chmod(0o755)
        self.put(self.app / '_CodeSignature/CodeResources', b'fixture seal, not a real signature')
        self.put(self.app / 'embedded.mobileprovision', b'fixture profile')
        self.put(self.app / 'romfs/stale.bin', b'stale')
        self.put(self.app / 'msl/stale.metallib', b'stale')
        self.put(self.app / 'aoc/99/stale.bin', b'stale')
        self.romfs = self.work / 'extract/v2/RomFS'
        self.put(self.romfs / 'Data/marker.bin', b'marker')
        self.put(self.romfs / '文件 空间.packed', b'pack me uncompressed' * 100)
        self.put(self.work / 'extract/v1/RomFS/incorrect-version.bin', b'wrong version')
        self.msl = self.work / 'shader/ios/b-selected-chain'
        self.put(self.msl / 'selected_b.metallib', b'ios shader fixture')
        self.put(self.work / 'shader/ios/b-obsolete/old_b.metallib', b'obsolete iOS library')
        self.put(self.work / 'shader/cache/b-selected-chain/mac_b.metallib', b'macOS shader fixture')
        self.aoc = self.work / 'aoc'
        self.put(self.aoc / '1/追加 文件.bin', b'dlc fixture')
        self.bin_dir = self.root / 'mock tools'
        self.bin_dir.mkdir()
        self.codesign_log = self.root / 'codesign.json'
        codesign = self.bin_dir / 'codesign'
        codesign.write_text(
            '#!/bin/sh\nexec "$PYTHON" - "$@" <<\'PY\'\n'
            'import json, os, sys\n'
            'from pathlib import Path\n'
            'Path(os.environ["CODESIGN_LOG"]).write_text(json.dumps(sys.argv[1:]))\n'
            'sys.exit(int(os.environ.get("CODESIGN_EXIT", "0")))\nPY\n')
        codesign.chmod(0o755)
        self.env = dict(os.environ, PYTHON=sys.executable, CODESIGN_LOG=str(self.codesign_log),
                        PATH=str(self.bin_dir) + os.pathsep + os.environ.get('PATH', ''))
        for key in ('DM_GAMES_DIR', 'DM_GAMES_FIRST', 'GAME', 'DM_GAME', 'GFXAPI', 'CODESIGN_EXIT'):
            self.env.pop(key, None)

    @staticmethod
    def put(path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def run_export(self, signed=False, args=None, env=None):
        script = TOOLS / ('make-signed-ipa.sh' if signed else 'make-unsigned-ipa.sh')
        command = ['bash', str(script), '--repo', str(self.repo), '--work', str(self.work)]
        if args is None:
            command += ['--out', str(self.out)]
        else:
            command += args
        return subprocess.run(command, env=env or self.env, capture_output=True, text=True)

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_failure(self, result, message):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stdout + result.stderr)
        self.assertFalse(self.out.exists())

    def assemble_signed_fixture(self):
        for name, source in [('romfs', self.romfs), ('msl', self.work / 'shader/ios'), ('aoc', self.aoc)]:
            shutil.rmtree(self.app / name)
            if name == 'msl':
                shutil.copytree(self.msl, self.app / 'msl/b-selected-chain')
            else:
                shutil.copytree(source, self.app / name)

    def test_unsigned_full_mapping_unicode_spaces_and_no_signatures(self):
        result = self.run_export(args=['--game', GAME, '--ver', 'v2', '--out', str(self.out)])
        self.assert_success(result)
        with zipfile.ZipFile(self.out) as archive:
            names = archive.namelist()
            self.assertEqual(len(names), len(set(names)))
            self.assertEqual(archive.read(PREFIX + 'DmIOS'), b'binary fixture')
            self.assertEqual(archive.read(PREFIX + 'msl/b-selected-chain/selected_b.metallib'), b'ios shader fixture')
            self.assertEqual(archive.read(PREFIX + 'aoc/1/追加 文件.bin'), b'dlc fixture')
            self.assertEqual(archive.read(PREFIX + 'romfs/Data/marker.bin'), b'marker')
            packed = archive.getinfo(PREFIX + 'romfs/文件 空间.packed')
            self.assertEqual(packed.compress_type, zipfile.ZIP_STORED)
            self.assertTrue(archive.getinfo(PREFIX + 'DmIOS').external_attr >> 16 & 0o111)
            self.assertFalse(any('CodeSignature' in n or 'embedded.mobileprovision' in n for n in names))
            self.assertFalse(any('stale' in n or 'mac_b' in n or 'obsolete' in n or 'incorrect-version' in n for n in names))
        self.assertFalse(self.codesign_log.exists())
        self.assertTrue((self.app / '_CodeSignature/CodeResources').is_file())

    def test_infers_selected_game_version_and_output_from_work_profile(self):
        self.assert_success(self.run_export(args=[]))
        self.assertTrue((self.work.parent / '所选 游戏.ipa').is_file())
        self.assertFalse((self.work.parent / 'wrong.ipa').exists())

    def test_infers_game_from_single_profile_for_custom_work_name(self):
        moved = self.work.with_name('自定义 工作')
        self.work.rename(moved)
        self.work = moved
        self.assert_success(self.run_export())

    def test_no_game_does_not_fall_back_to_repository_profile(self):
        shutil.rmtree(self.work / 'profile')
        moved = self.work.with_name('unknown work')
        self.work.rename(moved)
        self.work = moved
        self.assert_failure(self.run_export(), 'cannot determine game')

    def test_explicit_wrong_game_is_rejected(self):
        self.assert_failure(self.run_export(args=['--game', OTHER_GAME, '--out', str(self.out)]),
                            'does not match work game')

    def test_explicit_version_uses_requested_romfs(self):
        romfs = self.work / 'extract/v3/RomFS'
        self.put(romfs / 'Data/marker.bin', b'version 3 marker')
        self.assert_success(self.run_export(args=['--ver', 'v3', '--out', str(self.out)]))
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + 'romfs/Data/marker.bin'), b'version 3 marker')
            self.assertNotIn(PREFIX + 'romfs/文件 空间.packed', archive.namelist())

    def test_missing_requested_romfs_fails(self):
        self.assert_failure(self.run_export(args=['--ver', 'v404', '--out', str(self.out)]), 'missing RomFS for v404')

    def test_missing_marker_fails(self):
        (self.romfs / 'Data/marker.bin').unlink()
        self.assert_failure(self.run_export(), 'missing RomFS marker')

    def test_shared_header_exports_without_per_game_header(self):
        shared = self.repo / 'dm/gfx/nvn/dmsh_chain.h'
        shared.parent.mkdir(parents=True)
        shared.write_text('#define DMSH_CHAIN "selected-chain"\n')
        (self.profile / 'dmsh_chain.h').unlink()
        tool = self.repo / 'dm/gfx/tools/dmsh_chain.py'
        tool.parent.mkdir(parents=True)
        shutil.copyfile(UPSTREAM / 'dm/gfx/tools/dmsh_chain.py', tool)
        digest = subprocess.check_output([sys.executable, str(tool), '--inputs'],
                                         env=dict(self.env, DM_GAME=str(self.profile)), text=True).strip()
        self.put(self.msl / 'inputs.tsv', f'game\t{GAME}\ninputs\t{digest}\n'.encode())
        for name in ('c1_full.tsv', 'cb_extent.tsv'):
            (self.profile / name).write_text(f'# chain b-selected-chain inputs {digest} fixture\n')
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertIn(PREFIX + 'msl/b-selected-chain/selected_b.metallib', archive.namelist())

    def test_portable_profile_repairs_tables_from_mac_cache_but_packages_ios(self):
        shared = self.repo / 'dm/gfx/nvn/dmsh_chain.h'
        shared.parent.mkdir(parents=True)
        shared.write_text('#define DMSH_CHAIN "selected-chain"\n')
        (self.profile / 'dmsh_chain.h').unlink()
        for name in ('dmsh_chain.py', 'c1_guard.py', 'cb_extent.py'):
            tool = self.repo / 'dm/gfx/tools' / name
            tool.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(UPSTREAM / 'dm/gfx/tools' / name, tool)
        digest = subprocess.check_output(
            [sys.executable, str(self.repo / 'dm/gfx/tools/dmsh_chain.py'), '--inputs'],
            env=dict(self.env, DM_GAME=str(self.profile)), text=True).strip()
        cache = self.work / 'shader/cache/b-selected-chain'
        stamp = f'game\t{GAME}\ninputs\t{digest}\n'.encode()
        self.put(self.msl / 'inputs.tsv', stamp)
        self.put(cache / 'inputs.tsv', stamp)
        self.put(cache / 'mac_b.metal', b'auto value = (*spvDescriptorSet0.vp_c1)._m0[unknown];\n')
        self.put(cache / 'mac_b.json', json.dumps({'chain': 'selected-chain', 'bindings': []}).encode())
        self.assert_success(self.run_export())
        self.assertIn('\nmac\n', (self.profile / 'c1_full.tsv').read_text())
        self.assertTrue((self.profile / 'cb_extent.tsv').read_text().startswith(
            f'# chain b-selected-chain inputs {digest} '))
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + 'msl/b-selected-chain/selected_b.metallib'),
                             b'ios shader fixture')
            self.assertFalse(any('mac_b' in n for n in archive.namelist()))

    def test_missing_ios_shaders_does_not_fall_back_to_mac_cache(self):
        shutil.rmtree(self.msl)
        self.assert_failure(self.run_export(), 'missing iOS shader libraries')

    def test_vulkan_shader_mapping(self):
        shutil.rmtree(self.msl)
        self.put(self.work / 'shader/ios/vk/vk_shaders.metallib', b'vulkan library')
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + 'msl/vk/vk_shaders.metallib'), b'vulkan library')
            self.assertFalse(any('b-selected-chain' in n for n in archive.namelist()))

    def test_romfs_image_mapping_and_marker(self):
        import struct
        shutil.rmtree(self.romfs)
        tool = self.repo / 'dm/tools/romfs.py'
        tool.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(UPSTREAM / 'dm/tools/romfs.py', tool)
        payload = b'image fixture'
        names = b'Datamarker.bin'
        ent = struct.Struct('<QQIHBB')
        index = (ent.pack(1, 1, 0, 0, 0, 0) + ent.pack(2, 1, 0, 4, 0, 0)
                 + ent.pack(32, len(payload), 4, 10, 1, 0) + names)
        image = self.romfs.with_name('RomFS.img')
        image.write_bytes(struct.pack('<8sQQQ', b'DMROMFS1', 32 + len(payload), len(index), 3) + payload + index)
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + 'romfs.img'), image.read_bytes())
            self.assertFalse(any(n.startswith(PREFIX + 'romfs/') for n in archive.namelist()))

    def test_gl_shader_mapping_without_nvn_header(self):
        shutil.rmtree(self.msl)
        (self.profile / 'dmsh_chain.h').unlink()
        self.put(self.work / 'shader/ios/gl/gl_shaders.metallib', b'GL library')
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + 'msl/gl/gl_shaders.metallib'), b'GL library')
            self.assertFalse(any('b-selected-chain' in n for n in archive.namelist()))

    def test_wrong_platform_gl_cache_is_rejected(self):
        shutil.rmtree(self.msl)
        self.put(self.work / 'shader/gl/gl_shaders.metallib', b'Mac GL library')
        self.env['GFXAPI'] = 'gl'
        self.assert_failure(self.run_export(), 'missing ios gl shader library')

    def test_optional_aoc_absent_omits_stale_bundled_aoc(self):
        shutil.rmtree(self.aoc)
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertFalse(any(n.startswith(PREFIX + 'aoc') for n in archive.namelist()))

    def test_broken_aoc_path_fails(self):
        shutil.rmtree(self.aoc)
        self.aoc.write_text('not a directory')
        self.assert_failure(self.run_export(), 'add-on content is not a directory')

    def test_profile_search_order_matches_dm_games_first(self):
        builtin = self.repo / 'dm/games' / GAME
        shutil.copytree(self.profile, builtin)
        with (builtin / 'game.tsv').open('a') as stream:
            stream.write('# built-in profile\n')
        # First values win, as with upstream game.py.
        text = (builtin / 'game.tsv').read_text().replace('zip_store\t.packed', 'zip_store\t.bin')
        (builtin / 'game.tsv').write_text(text)
        env_profile = self.root / 'external profile' / GAME
        shutil.copytree(self.profile, env_profile)
        text = (env_profile / 'game.tsv').read_text().replace('zip_store\t.packed', 'zip_store\t.metallib:.packed')
        (env_profile / 'game.tsv').write_text(text)
        self.env['DM_GAMES_DIR'] = str(env_profile.parent)
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.getinfo(PREFIX + 'romfs/Data/marker.bin').compress_type, zipfile.ZIP_STORED)
            self.assertEqual(archive.getinfo(PREFIX + 'romfs/文件 空间.packed').compress_type, zipfile.ZIP_DEFLATED)
        self.env['DM_GAMES_FIRST'] = '1'
        self.assert_success(self.run_export())
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.getinfo(PREFIX + 'romfs/文件 空间.packed').compress_type, zipfile.ZIP_STORED)
            self.assertEqual(archive.getinfo(PREFIX + 'msl/b-selected-chain/selected_b.metallib').compress_type,
                             zipfile.ZIP_STORED)

    def test_signed_incomplete_app_fails_before_codesign_or_packing(self):
        self.assert_failure(self.run_export(signed=True), 'signed app is missing complete resources')
        self.assertFalse(self.codesign_log.exists())

    def test_signed_complete_bundle_is_verified_and_packed_without_injection(self):
        self.assemble_signed_fixture()
        self.assert_success(self.run_export(signed=True))
        self.assertEqual(json.loads(self.codesign_log.read_text()),
                         ['--verify', '--deep', '--strict', str(self.app)])
        with zipfile.ZipFile(self.out) as archive:
            self.assertEqual(archive.read(PREFIX + '_CodeSignature/CodeResources'), b'fixture seal, not a real signature')
            self.assertEqual(archive.read(PREFIX + 'embedded.mobileprovision'), b'fixture profile')
            self.assertEqual(archive.read(PREFIX + 'aoc/1/追加 文件.bin'), b'dlc fixture')
            self.assertEqual(archive.read(PREFIX + 'msl/b-selected-chain/selected_b.metallib'), b'ios shader fixture')
            self.assertEqual(archive.read(PREFIX + 'romfs/文件 空间.packed'), b'pack me uncompressed' * 100)

    def test_signed_changed_resource_with_same_size_and_time_fails(self):
        self.assemble_signed_fixture()
        bundled = self.app / 'romfs/Data/marker.bin'
        source_stat = (self.romfs / 'Data/marker.bin').stat()
        bundled.write_bytes(b'WRONG!')
        os.utime(bundled, ns=(source_stat.st_atime_ns, source_stat.st_mtime_ns))
        self.assert_failure(self.run_export(signed=True), 'signed app resource differs')
        self.assertFalse(self.codesign_log.exists())

    def test_signed_missing_profile_or_resource_seal_fails(self):
        self.assemble_signed_fixture()
        (self.app / 'embedded.mobileprovision').unlink()
        self.assert_failure(self.run_export(signed=True), 'missing signed app provisioning profile')
        self.assertFalse(self.codesign_log.exists())

    def test_signed_invalid_signature_fails_without_output(self):
        self.assemble_signed_fixture()
        self.env['CODESIGN_EXIT'] = '1'
        self.assert_failure(self.run_export(signed=True), 'complete app signature is not valid')
        self.assertTrue(self.codesign_log.exists())

    def test_signed_extra_stale_shader_directory_fails(self):
        self.assemble_signed_fixture()
        self.put(self.app / 'msl/old/old_b.metallib', b'stale')
        self.assert_failure(self.run_export(signed=True), 'unexpected shader resources')
        self.assertFalse(self.codesign_log.exists())

    def test_missing_app_executable_fails(self):
        (self.app / 'DmIOS').unlink()
        self.assert_failure(self.run_export(), 'missing built app executable')

    def test_missing_profile_fails_without_unrelated_game_fallback(self):
        shutil.rmtree(self.work / 'profile')
        self.assert_failure(self.run_export(), f'cannot resolve game {GAME}')

    def test_packer_failure_is_reported_and_preserves_previous_output(self):
        self.put(self.out, b'previous IPA')
        (self.repo / 'dm/ios/tools/pack_ipa.py').write_text('raise SystemExit(7)\n')
        result = self.run_export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('exit status 7', result.stderr)
        self.assertEqual(self.out.read_bytes(), b'previous IPA')

    def test_output_inside_source_tree_fails(self):
        result = self.run_export(args=['--out', str(self.romfs / 'recursive.ipa')])
        self.assert_failure(result, 'output must be outside resource directories')
        self.assertFalse((self.romfs / 'recursive.ipa').exists())

    def test_signed_missing_resource_seal_fails(self):
        self.assemble_signed_fixture()
        (self.app / '_CodeSignature/CodeResources').unlink()
        self.assert_failure(self.run_export(signed=True), 'missing signed app resource seal')
        self.assertFalse(self.codesign_log.exists())

    def test_signed_symlinked_shader_root_fails(self):
        self.assemble_signed_fixture()
        shutil.rmtree(self.app / 'msl')
        # Only the selected shader directory is present in this external root.
        external = self.root / 'external msl'
        shutil.copytree(self.msl, external / self.msl.name)
        (self.app / 'msl').symlink_to(external, target_is_directory=True)
        self.assert_failure(self.run_export(signed=True), 'must be bundled, not a symlink')
        self.assertFalse(self.codesign_log.exists())

    def test_both_wrappers_validate_arguments_and_show_help(self):
        for signed in (False, True):
            with self.subTest(signed=signed):
                result = self.run_export(signed=signed, args=['--ver'])
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('expected one argument', result.stderr)
                result = self.run_export(signed=signed, args=['--help'])
                self.assert_success(result)
                for flag in ('--work', '--out', '--repo', '--game', '--ver'):
                    self.assertIn(flag, result.stdout)


if __name__ == '__main__':
    unittest.main()
