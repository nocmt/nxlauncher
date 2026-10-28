import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / 'Tools' / 'release-audit.py'
FONT = ROOT / 'Scripts' / 'font-policy.py'
# Assembled at runtime: a fixture that proves the scanner rejects key blocks must not
# itself leave a literal key header in the published source tree.
PRIVATE_HEADER = '-----BEGIN ' + 'PRIVATE KEY-----'


class ReleaseAuditTests(unittest.TestCase):
    def run_audit(self, root, kind='payload'):
        return subprocess.run([sys.executable, str(AUDIT), '--root', str(root), '--kind', kind],
                              capture_output=True, text=True)

    def test_payload_rejects_game_keys_and_private_key(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'ok.txt').write_text('safe')
            (root / 'keys').mkdir()
            (root / 'keys' / 'prod.keys').write_text('private')
            (root / 'secret.pem').write_text(PRIVATE_HEADER)
            result = self.run_audit(root)
            self.assertNotEqual(result.returncode, 0)
            report = json.loads(result.stdout)
            self.assertFalse(report['ok'])
            self.assertTrue(any('forbidden file' in x for x in report['findings']))
            self.assertTrue(any('credential' in x for x in report['findings']))

    def test_payload_rejects_personal_path_but_not_runner_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'path.txt').write_bytes(b'/Users/alice/Documents/game')
            (root / 'ci.txt').write_bytes(b'/Users/runner/work/repository')
            result = self.run_audit(root)
            report = json.loads(result.stdout)
            self.assertFalse(report['ok'])
            self.assertTrue(any('personal absolute path' in x and 'path.txt' in x for x in report['findings']))
            self.assertFalse(any('personal absolute path' in x and 'ci.txt' in x for x in report['findings']))

    def test_reviewed_vendor_exception_is_exact_and_never_allows_private_key(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('release_audit_test', AUDIT)
        audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(audit)
        name = 'nxnative/dm/gfx/tools/dmsh_xlate_bin/Gommon.dll'
        data = (ROOT / name).read_bytes()
        self.assertTrue(audit.reviewed_personal_paths(name, data))
        self.assertFalse(audit.reviewed_personal_paths(name, data + b'changed'))
        self.assertFalse(audit.reviewed_personal_paths('nxnative/other.dll', data))
        findings = []
        audit.inspect_bytes(name, data + PRIVATE_HEADER.encode(), findings)
        self.assertTrue(any('credential/key pattern' in item for item in findings))
        self.assertTrue(any('personal absolute path' in item for item in findings))

    def test_ca_exception_only_accepts_reviewed_public_certifi_bundle(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('release_audit_ca_test', AUDIT)
        audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(audit)
        findings = []
        audit.inspect_bytes(audit.CERTIFI_CA, PRIVATE_HEADER.encode(), findings)
        self.assertTrue(any('forbidden file' in item for item in findings))
        self.assertTrue(any('credential/key pattern' in item for item in findings))
        self.assertFalse(audit.reviewed_ca('other.pem', b'-----BEGIN CERTIFICATE-----'))

    def test_font_helper_default_generation_is_redistributable(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'font'
            result = subprocess.run([sys.executable, str(FONT), '--repo', str(ROOT / 'nxnative'), '--out', str(out)],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report['redistributable'])
            self.assertGreater((out / 'standard.ttf').stat().st_size, 10000)
            self.assertGreater((out / 'nintendo_ext.ttf').stat().st_size, 1000)
            self.assertTrue((out / 'OFL.txt').is_file())

    def test_font_helper_explicit_override_is_not_redistributable(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / 'font'
            env = dict(__import__('os').environ, NXLAUNCHER_FONT_PATH=str(ROOT / 'Scripts/fonts' / 'NotoSansSC.ttf.gz'))
            # compressed input is intentionally rejected by fontTools; verify fail-closed rather than labeling it OFL.
            result = subprocess.run([sys.executable, str(FONT), '--repo', str(ROOT / 'nxnative'), '--out', str(out)],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((out / 'OFL.txt').exists())


if __name__ == '__main__':
    unittest.main()
