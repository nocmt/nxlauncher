import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('shader_chain', ROOT / 'Tools/shader_chain.py')
shader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shader)
GAME = '01006F8002326000'


class ShaderChainTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(prefix='shader chain 空间 ')
        self.addCleanup(tmp.cleanup)
        self.repo = Path(tmp.name)
        self.profile = self.repo / 'external profile' / GAME
        self.profile.mkdir(parents=True)
        self.shared = self.repo / 'dm/gfx/nvn/dmsh_chain.h'
        self.shared.parent.mkdir(parents=True)
        self.shared.write_text('#define DMSH_CHAIN "new-chain"\n')
        self.lib = self.repo / 'cache/b-new-chain'
        self.lib.mkdir(parents=True)
        (self.lib / 'test_b.metallib').write_bytes(b'fixture')
        for rel in ('dm/games/game.py', 'dm/gfx/tools/dmsh_chain.py',
                    'dm/gfx/tools/c1_guard.py', 'dm/gfx/tools/cb_extent.py'):
            dest = self.repo / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / 'nxnative' / rel, dest)
        (self.profile / 'game.tsv').write_text(f'title_id\t{GAME}\nshader_versions\tv2\n')
        sys.path.insert(0, str(self.repo / 'dm/games'))
        try:
            game_spec = importlib.util.spec_from_file_location('fixture_game', self.repo / 'dm/games/game.py')
            game = importlib.util.module_from_spec(game_spec)
            game_spec.loader.exec_module(game)
            chain_spec = importlib.util.spec_from_file_location('fixture_chain', self.repo / 'dm/gfx/tools/dmsh_chain.py')
            chain = importlib.util.module_from_spec(chain_spec)
            chain_spec.loader.exec_module(chain)
            self.inputs = chain.inputs(game.Game(self.profile))
        finally:
            sys.path.pop(0)
        (self.lib / 'inputs.tsv').write_text(f'game\t{GAME}\ninputs\t{self.inputs}\n')
        for name in ('c1_full.tsv', 'cb_extent.tsv'):
            (self.profile / name).write_text(f'# chain b-new-chain inputs {self.inputs} fixture\n')

    def analysis_cache(self):
        (self.lib / 'test_b.metal').write_text(
            'constant float4* vp_c1 [[id(1)]];\n'
            'constant float4* vp_c2 [[id(2)]];\n'
            'auto a = (*spvDescriptorSet0.vp_c1)._m0[unknown];\n'
            'auto b = (*spvDescriptorSet0.vp_c2)._m0[3];\n')
        (self.lib / 'test_b.json').write_text(json.dumps({
            'chain': 'new-chain', 'c1': '00' * 16,
            'bindings': [{'kind': 'cbuf', 'reg': 2, 'msl_name': 'vp_c2'}],
        }))

    def remove_tables(self):
        for name in shader.TABLE_TOOLS:
            (self.profile / name).unlink()

    def test_missing_tables_regenerated_with_real_upstream_tools(self):
        self.analysis_cache()
        self.remove_tables()
        before = {p.name: p.read_bytes() for p in self.lib.iterdir()}
        self.assertEqual(self.validate(), 'new-chain')
        self.assertIn('\ntest\n', (self.profile / 'c1_full.tsv').read_text())
        self.assertIn('\ntest\t2:64\n', (self.profile / 'cb_extent.tsv').read_text())
        self.assertEqual({p.name: p.read_bytes() for p in self.lib.iterdir()}, before)
        tables = {n: (self.profile / n).read_bytes() for n in shader.TABLE_TOOLS}
        self.assertEqual(self.validate(), 'new-chain')
        self.assertEqual(tables, {n: (self.profile / n).read_bytes() for n in tables})

    def test_only_missing_table_is_regenerated(self):
        self.analysis_cache()
        original = (self.profile / 'c1_full.tsv').read_bytes()
        (self.profile / 'cb_extent.tsv').unlink()
        self.validate()
        self.assertEqual((self.profile / 'c1_full.tsv').read_bytes(), original)
        self.assertIn('test\t2:64', (self.profile / 'cb_extent.tsv').read_text())

    def test_incomplete_cache_is_rejected_without_publishing(self):
        for omitted in ('test_b.metal', 'test_b.json'):
            with self.subTest(omitted=omitted):
                self.analysis_cache()
                (self.lib / omitted).unlink()
                for name in shader.TABLE_TOOLS:
                    (self.profile / name).unlink(missing_ok=True)
                with self.assertRaisesRegex(shader.ShaderChainError, 'incomplete Mac shader analysis cache'):
                    self.validate()
                self.assertFalse(any((self.profile / n).exists() for n in shader.TABLE_TOOLS))

    def test_incompatible_reflection_is_rejected(self):
        self.analysis_cache()
        self.remove_tables()
        for content in ('bad json', '[]', '{"chain": "obsolete", "bindings": []}'):
            with self.subTest(content=content):
                (self.lib / 'test_b.json').write_text(content)
                with self.assertRaisesRegex(shader.ShaderChainError, 'shader reflection'):
                    self.validate()
                self.assertFalse((self.profile / 'c1_full.tsv').exists())

    def test_producer_failure_does_not_publish_partial_tables(self):
        self.analysis_cache()
        self.remove_tables()
        (self.repo / 'dm/gfx/tools/cb_extent.py').write_text(
            'from pathlib import Path\nimport sys\n'
            'Path(sys.argv[2]).write_text("partial")\nraise SystemExit("fixture failure")\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'cannot regenerate cb_extent.tsv.*fixture failure'):
            self.validate()
        self.assertFalse(any((self.profile / n).exists() for n in shader.TABLE_TOOLS))
        self.assertFalse(list(self.profile.glob('.shader-tables-*')))

    def test_invalid_producer_output_is_not_published(self):
        self.analysis_cache()
        self.remove_tables()
        (self.repo / 'dm/gfx/tools/c1_guard.py').write_text(
            'from pathlib import Path\nimport sys\nPath(sys.argv[2]).write_text("wrong header")\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'table does not match'):
            self.validate()
        self.assertFalse((self.profile / 'c1_full.tsv').exists())

    def test_missing_table_does_not_replace_stale_table(self):
        self.analysis_cache()
        (self.profile / 'c1_full.tsv').unlink()
        (self.profile / 'cb_extent.tsv').write_text('stale')
        with self.assertRaisesRegex(shader.ShaderChainError, 'table does not match'):
            self.validate()
        self.assertFalse((self.profile / 'c1_full.tsv').exists())
        self.assertEqual((self.profile / 'cb_extent.tsv').read_text(), 'stale')

    def ios_library(self):
        ios = self.repo / 'ios' / self.lib.name
        ios.mkdir(parents=True)
        (ios / 'test_b.metallib').write_bytes(b'iOS fixture')
        shutil.copyfile(self.lib / 'inputs.tsv', ios / 'inputs.tsv')
        return ios

    def test_ios_repair_uses_matching_mac_cache(self):
        self.analysis_cache()
        self.remove_tables()
        ios = self.ios_library()
        self.assertEqual(shader.validate_library(self.repo, self.profile, GAME, ios), 'new-chain')
        self.assertIn('\ntest\n', (self.profile / 'c1_full.tsv').read_text())
        self.assertFalse((ios / 'test_b.metal').exists())

    def test_ios_repair_rejects_wrong_or_absent_mac_stamp(self):
        self.analysis_cache()
        self.remove_tables()
        ios = self.ios_library()
        for stamp in ('game\twrong\ninputs\t' + self.inputs, 'game\t' + GAME + '\ninputs\told', ''):
            with self.subTest(stamp=stamp):
                (self.lib / 'inputs.tsv').write_text(stamp)
                with self.assertRaisesRegex(shader.ShaderChainError, 'does not match game'):
                    shader.validate_library(self.repo, self.profile, GAME, ios)
                self.assertFalse((self.profile / 'c1_full.tsv').exists())

    def test_wrong_ios_stamp_is_rejected_before_repair(self):
        self.analysis_cache()
        self.remove_tables()
        ios = self.ios_library()
        (ios / 'inputs.tsv').write_text('game\twrong\ninputs\t' + self.inputs)
        with self.assertRaisesRegex(shader.ShaderChainError, 'does not match game'):
            shader.validate_library(self.repo, self.profile, GAME, ios)
        self.assertFalse((self.profile / 'c1_full.tsv').exists())

    def validate(self):
        return shader.validate_library(self.repo, self.profile, GAME, self.lib)

    def test_shared_header_without_per_game_header(self):
        self.assertEqual(self.validate(), 'new-chain')

    def test_shared_header_wins_over_obsolete_profile_header(self):
        (self.profile / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "obsolete"\n')
        self.assertEqual(self.validate(), 'new-chain')

    def test_legacy_layout_is_supported(self):
        self.shared.unlink()
        (self.profile / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "new-chain"\n')
        (self.lib / 'inputs.tsv').unlink()
        self.assertEqual(self.validate(), 'new-chain')

    def test_invalid_shared_header_does_not_fall_back(self):
        self.shared.write_text('invalid')
        (self.profile / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "new-chain"\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'invalid DMSH_CHAIN'):
            self.validate()

    def test_other_game_stamp_is_rejected(self):
        (self.lib / 'inputs.tsv').write_text(f'game\twrong\ninputs\t{self.inputs}\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'does not match game'):
            self.validate()

    def test_missing_stamp_is_rejected(self):
        (self.lib / 'inputs.tsv').unlink()
        with self.assertRaisesRegex(shader.ShaderChainError, 'does not match game'):
            self.validate()

    def test_changed_profile_inputs_are_rejected(self):
        (self.profile / 'game.tsv').write_text('shader_versions\tv3\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'does not match game'):
            self.validate()

    def test_stale_derived_table_is_rejected(self):
        (self.profile / 'cb_extent.tsv').write_text('# chain b-old inputs old fixture\n')
        with self.assertRaisesRegex(shader.ShaderChainError, 'table does not match'):
            self.validate()

    def test_obsolete_cache_is_never_selected(self):
        obsolete = self.lib.with_name('b-obsolete')
        self.lib.rename(obsolete)
        with self.assertRaisesRegex(shader.ShaderChainError, 'missing shader libraries for host chain'):
            shader.validate_library(self.repo, self.profile, GAME, obsolete)


if __name__ == '__main__':
    unittest.main()
