import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / 'Tools' / 'prepare-nxnative.py'
spec = importlib.util.spec_from_file_location('prepare_nxnative', SCRIPT)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


class PrepareTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.repo = Path(self.tmp.name) / 'repo'
        self.repo.mkdir()
        self.patches = Path(self.tmp.name) / 'patches'
        self.patches.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.invalid')
        (self.repo / 'tracked').write_text('upstream\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        self.base = self.git('rev-parse', 'HEAD').strip()
        (self.patches / 'base-commit').write_text(self.base + '\n')
        (self.repo / 'tracked').write_text('patched\n')
        (self.patches / 'one.patch').write_text(self.git('diff'))
        self.git('restore', 'tracked')
        (self.patches / 'two.patch').write_text(
            'diff --git a/added b/added\nnew file mode 100644\n'
            '--- /dev/null\n+++ b/added\n@@ -0,0 +1 @@\n+new\n')
        (self.patches / 'series').write_text('one.patch\ntwo.patch\n')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True)

    def run_prepare(self, check=False):
        prepare.prepare(self.repo, self.patches, check)

    def test_apply_check_and_repeat_leave_index_at_upstream(self):
        self.run_prepare()
        self.run_prepare(check=True)
        self.run_prepare()
        self.assertEqual((self.repo / 'added').read_text(), 'new\n')
        self.assertEqual((self.repo / 'tracked').read_text(), 'patched\n')
        self.assertEqual(self.git('diff', '--cached'), '')
        self.assertEqual(self.git('rev-parse', 'HEAD').strip(), self.base)

    def test_check_is_read_only(self):
        with self.assertRaisesRegex(prepare.PatchError, 'not applied'):
            self.run_prepare(check=True)
        self.assertEqual((self.repo / 'tracked').read_text(), 'upstream\n')
        self.assertFalse((self.repo / 'added').exists())

    def test_reject_partial_application(self):
        self.git('apply', str(self.patches / 'one.patch'))
        with self.assertRaisesRegex(prepare.PatchError, 'differs'):
            self.run_prepare()
        self.assertFalse((self.repo / 'added').exists())

    def test_reject_untracked_collision(self):
        (self.repo / 'added').write_text('user work\n')
        with self.assertRaisesRegex(prepare.PatchError, 'existing patch files'):
            self.run_prepare()
        self.assertEqual((self.repo / 'tracked').read_text(), 'upstream\n')
        self.assertEqual((self.repo / 'added').read_text(), 'user work\n')

    def test_reject_user_changes_even_after_full_application(self):
        self.run_prepare()
        (self.repo / 'tracked').write_text('user work\n')
        with self.assertRaisesRegex(prepare.PatchError, 'differs'):
            self.run_prepare()

    def test_validate_whole_series_before_changing_worktree(self):
        (self.patches / 'two.patch').write_text('invalid patch\n')
        with self.assertRaises(prepare.PatchError):
            self.run_prepare()
        self.assertEqual((self.repo / 'tracked').read_text(), 'upstream\n')

    def test_reject_wrong_base(self):
        (self.patches / 'base-commit').write_text('0' * 40 + '\n')
        with self.assertRaisesRegex(prepare.PatchError, 'requires'):
            self.run_prepare()

    def test_reject_staged_changes(self):
        (self.repo / 'tracked').write_text('user work\n')
        self.git('add', 'tracked')
        with self.assertRaisesRegex(prepare.PatchError, 'staged changes'):
            self.run_prepare()

    def test_reject_parent_file_collision_without_partial_apply(self):
        (self.patches / 'two.patch').write_text(
            'diff --git a/dir/added b/dir/added\nnew file mode 100644\n'
            '--- /dev/null\n+++ b/dir/added\n@@ -0,0 +1 @@\n+new\n')
        (self.repo / 'dir').write_text('user work\n')
        with self.assertRaisesRegex(prepare.PatchError, 'existing patch files'):
            self.run_prepare()
        self.assertEqual((self.repo / 'tracked').read_text(), 'upstream\n')
        self.assertEqual((self.repo / 'dir').read_text(), 'user work\n')
        self.assertEqual(self.git('diff', '--cached'), '')

    def test_failed_final_install_restores_original_tree(self):
        original = prepare.install_file
        calls = 0

        def fail_once(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError('injected final install failure')
            original(source, destination)

        with mock.patch.object(prepare, 'install_file', side_effect=fail_once):
            with self.assertRaisesRegex(OSError, 'injected final install failure'):
                self.run_prepare()
        self.assertEqual((self.repo / 'tracked').read_text(), 'upstream\n')
        self.assertFalse((self.repo / 'added').exists())
        self.assertEqual(self.git('status', '--porcelain'), '')
        self.assertFalse(list(self.repo.glob('.nxlauncher-prepare-*')))

    def test_reject_archive_pruned_patch_before_modifying_tree(self):
        (self.patches / 'two.patch').write_text(
            'diff --git a/dm/host/gen/feature.h b/dm/host/gen/feature.h\nnew file mode 100644\n'
            '--- /dev/null\n+++ b/dm/host/gen/feature.h\n@@ -0,0 +1 @@\n+new\n')
        with self.assertRaisesRegex(prepare.PatchError, 'archive-pruned'):
            self.run_prepare()
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_reject_paths_outside_patch_directory(self):
        (self.patches / 'series').write_text('../outside.patch\n')
        with self.assertRaisesRegex(prepare.PatchError, 'invalid patch'):
            self.run_prepare()


if __name__ == '__main__':
    unittest.main()
