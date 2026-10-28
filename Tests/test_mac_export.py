import os
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
GAME = '01006F8002326000'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang') and
                     shutil.which('codesign'), 'requires macOS signing tools')
class MacExportTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix='mac export 空间 ')
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / 'repo'
        profile = self.repo / 'dm/games' / GAME
        profile.mkdir(parents=True)
        shutil.copyfile(ROOT / 'nxnative/dm/games/game.py', profile.parent / 'game.py')
        (profile / 'game.tsv').write_text(
            f'title_id\t{GAME}\nname\tFixture\nbuild\tv1 1.0\nipa\tFixture.ipa\n')
        (profile / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "fixture"\n')
        host = self.repo / 'dm/host'
        host.mkdir(parents=True)
        source = host / 'host.c'
        source.write_text('int main(void) { return 0; }\n')
        subprocess.run(['clang', str(source), '-o', str(host / 'dmhost')], check=True,
                       capture_output=True)
        (host / 'Makefile').write_text('dmhost:\n\t@true\n')
        # Fake the font policy boundary, never depend on a local font or fontTools.
        self.font_log = self.root / 'font-call.json'
        self.font_helper = self.root / 'font-helper.py'
        self.font_helper.write_text(
            'import argparse,json,os\nfrom pathlib import Path\n'
            'p=argparse.ArgumentParser();p.add_argument("--repo");p.add_argument("--out");a=p.parse_args()\n'
            'Path(os.environ["FONT_LOG"]).write_text(json.dumps(vars(a)))\n'
            'out=Path(a.out);out.mkdir(parents=True,exist_ok=True)\n'
            '[(out/n).write_bytes(b"open fixture font") for n in ("standard.ttf","nintendo_ext.ttf")]\n'
            'print(json.dumps({"redistributable":True,"standard":str(out/"standard.ttf"),"extension":str(out/"nintendo_ext.ttf")}))\n')
        self.work = self.root / 'work'
        for name in ('extract/v1/RomFS', 'patched_v1', 'shader/cache/b-fixture'):
            (self.work / name).mkdir(parents=True)
        (self.work / 'shader/cache/b-fixture/test_b.metallib').write_bytes(b'fixture')
        (self.work / 'extract/v1/RomFS/base').write_bytes(b'base')
        (self.work / 'patched_v1/module').write_bytes(b'module')

    def export(self, nested):
        dlc = self.work / 'aoc/1000'
        if nested:
            dlc /= 'RomFS'
        dlc.mkdir(parents=True)
        (dlc / 'content').write_bytes(b'dlc')
        app = self.root / 'Fixture.app'
        result = subprocess.run(
            ['bash', str(ROOT / 'Tools/make-mac-app.sh'), '--repo', str(self.repo),
             '--game', GAME, '--work', str(self.work), '--ver', 'v1', '--out', str(app),
             '--python', sys.executable, '--dlc', str(self.work / 'aoc')],
            env=dict(os.environ, DM_GAMES_DIR='', DM_GAMES_FIRST='',
                     NXLAUNCHER_FONT_HELPER=str(self.font_helper), FONT_LOG=str(self.font_log)),
            capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        call = json.loads(self.font_log.read_text())
        self.assertEqual(call['repo'], str(self.repo))
        self.assertIn('.nxlauncher-export.', call['out'])
        self.assertFalse(list(self.root.glob('.nxlauncher-export.*')))
        self.assertEqual((app / 'Contents/Resources/font/standard.ttf').read_bytes(), b'open fixture font')
        self.assertEqual((app / 'Contents/Resources/aoc/1000/content').read_bytes(), b'dlc')
        self.assertFalse((app / 'Contents/Resources/aoc/1000/RomFS').exists())
        verified = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                                  capture_output=True, text=True)
        self.assertEqual(verified.returncode, 0, verified.stderr)
        self.assertIn(f'nxnative/{GAME}'.encode(), (app / 'Contents/MacOS/BotW').read_bytes())

    def test_flat_dlc_and_complete_bundle_signature(self):
        self.export(nested=False)

    def test_wrapped_dlc_and_complete_bundle_signature(self):
        self.export(nested=True)


if __name__ == '__main__':
    unittest.main()
