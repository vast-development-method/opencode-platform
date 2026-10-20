"""Behavioral checks for committed instructions and bounded review handoffs."""
import base64
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('company_context', ROOT / 'image/files/usr/local/libexec/vdm-company-context.py')
context = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(context)


class CompanyContextTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repository = self.root / 'company'
        self.repository.mkdir()
        self.git('init', '-q')
        self.git('config', 'user.name', 'Context test')
        self.git('config', 'user.email', 'context@example.invalid')
        (self.repository / 'standards').mkdir()
        (self.repository / 'standards/engineering.md').write_text('Review generated code and record decisions.\n')
        self.manifest = {'schema': 1, 'name': 'Test Company', 'instructions': ['standards/engineering.md']}
        self.commit()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repository), *args], check=True, capture_output=True).stdout

    def commit(self):
        (self.repository / 'company-context.json').write_text(json.dumps(self.manifest))
        self.git('add', '.')
        self.git('commit', '-qm', 'Committed company instructions')

    def snapshot(self):
        return context.from_git(self.repository, 'HEAD')

    def test_only_committed_selected_documents_are_loaded(self):
        before = self.snapshot()
        (self.repository / 'standards/engineering.md').write_text('Unreviewed local changes must stay local.\n')
        (self.repository / '.env').write_text('private material')
        after = self.snapshot()
        self.assertEqual(before, after)
        self.assertEqual(len(after['files']), 1)
        self.assertIn(b'Review generated code', base64.b64decode(after['files'][0]['data']))

    def test_explicit_older_revision_is_stable(self):
        first = self.snapshot()
        (self.repository / 'standards/engineering.md').write_text('New reviewed standards.\n')
        self.commit()
        self.assertNotEqual(self.snapshot()['snapshot'], first['snapshot'])
        self.assertEqual(context.from_git(self.repository, first['revision']), first)

    def test_symlink_instruction_is_rejected(self):
        (self.repository / 'standards/linked.md').symlink_to('engineering.md')
        self.manifest['instructions'].append('standards/linked.md')
        self.commit()
        with self.assertRaises(ValueError):
            self.snapshot()

    def test_traversal_and_duplicate_instructions_are_rejected(self):
        for paths in (['../elsewhere.md'], ['standards/engineering.md'] * 2):
            with self.subTest(paths=paths):
                self.manifest['instructions'] = paths
                self.commit()
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    self.snapshot()

    def test_credential_content_is_rejected(self):
        (self.repository / 'standards/engineering.md').write_text('Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456\n')
        self.commit()
        with self.assertRaisesRegex(ValueError, 'credential'):
            self.snapshot()

    def test_modified_snapshot_is_rejected(self):
        bundle = self.snapshot()
        bundle['files'][0]['data'] = base64.b64encode(b'changed').decode()
        with self.assertRaises(ValueError):
            context.check_bundle(bundle)

    def test_descriptor_reads_reject_links_and_special_files(self):
        (self.root / 'target.txt').write_text('ordinary review text')
        (self.root / 'linked.txt').symlink_to('target.txt')
        (self.root / 'other').mkdir()
        (self.root / 'directory').symlink_to('other', target_is_directory=True)
        os.link(self.root / 'target.txt', self.root / 'hardlink.txt')
        os.mkfifo(self.root / 'fifo.txt')
        for path in ('linked.txt', 'hardlink.txt', 'fifo.txt', 'directory/file.txt'):
            with self.subTest(path=path), self.assertRaises((ValueError, OSError)):
                context.read_regular(self.root, path)

    def test_export_path_allowlist_rejects_credentials_and_traversal(self):
        for path in ('../report.md', '/etc/passwd', '.env', 'folder/id_ed25519', 'auth.json', 'secret.key', '.git/config', 'report.sh'):
            with self.subTest(path=path), self.assertRaises(ValueError):
                context.safe_path(path)
        self.assertEqual(context.safe_path('.artifacts/compile/component.zip'), '.artifacts/compile/component.zip')

    def test_archives_are_checked_before_export(self):
        for path, data in (('../escape.php', b'code'), ('.env', b'private'), ('safe.php', b'password="abcdefghijklmnop"')):
            stream = io.BytesIO()
            with zipfile.ZipFile(stream, 'w') as archive:
                archive.writestr(path, data)
            with self.subTest(path=path), self.assertRaises(ValueError):
                context.check_content(stream.getvalue(), 'component.zip')
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive:
            archive.writestr('component/example.php', '<?php echo "example";')
        context.check_content(stream.getvalue(), 'component.zip')

    def test_handoff_survives_source_removal_with_verified_metadata(self):
        source = self.root / 'report.md'
        source.write_text('Reviewed task outcome.\n')
        data = context.read_regular(self.root, 'report.md')
        bundle = {'schema': 1, 'kind': 'review-handoff', 'company': None, 'files': [context.encode_file('report.md', data)]}
        output = self.root / 'review'
        context.receive_handoff(bundle, output)
        source.unlink()
        self.assertEqual((output / 'files/report.md').read_bytes(), data)
        manifest = json.loads((output / 'handoff.json').read_text())
        self.assertEqual(manifest['files'][0]['sha256'], context.digest(data))
        self.assertEqual((output / 'files/report.md').stat().st_mode & 0o777, 0o600)
        with self.assertRaises(ValueError):
            context.receive_handoff(bundle, output)

    def test_handoff_tampering_never_creates_output(self):
        record = context.encode_file('report.md', b'review')
        record['sha256'] = '0' * 64
        bundle = {'schema': 1, 'kind': 'review-handoff', 'company': None, 'files': [record]}
        output = self.root / 'review'
        with self.assertRaises(ValueError):
            context.receive_handoff(bundle, output)
        self.assertFalse(output.exists())

    def test_export_limits_are_checked_before_allocating_payload(self):
        with mock.patch.object(context, 'read_regular') as read:
            with self.assertRaises(ValueError):
                context.export_handoff(self.root, [f'file-{i}.md' for i in range(129)], 'nobody', None)
            read.assert_not_called()
        (self.root / 'one.md').write_bytes(b'12345678')
        (self.root / 'two.md').write_bytes(b'12345678')
        with mock.patch.object(context.os, 'geteuid', return_value=1001), mock.patch.object(context, 'MAX_TOTAL', 12):
            with self.assertRaises(ValueError):
                context.export_handoff(self.root, ['one.md', 'two.md'], 'nobody', None)

    def test_untrusted_provenance_is_rejected(self):
        record = context.encode_file('report.md', b'review')
        provenance = {'schema': 1, 'kind': 'company-context', 'name': 'Company', 'revision': 'a' * 40, 'snapshot': 'b' * 64}
        for bad in ({**provenance, 'credential': 'private'}, {**provenance, 'name': 'github_pat_' + 'a' * 30}, {**provenance, 'revision': 'unverified'}):
            bundle = {'schema': 1, 'kind': 'review-handoff', 'company': bad, 'files': [record]}
            with self.subTest(provenance=bad), self.assertRaises(ValueError):
                context.receive_handoff(bundle, self.root / 'review')
            self.assertFalse((self.root / 'review').exists())

    def test_private_parent_with_writable_grandparent_is_rejected(self):
        shared = self.root / 'shared'
        shared.mkdir(mode=0o777)
        shared.chmod(0o777)
        private = shared / 'private'
        private.mkdir(mode=0o700)
        bundle = {'schema': 1, 'kind': 'review-handoff', 'company': None, 'files': [context.encode_file('report.md', b'review')]}
        with self.assertRaisesRegex(ValueError, 'ancestry'):
            context.receive_handoff(bundle, private / 'review')

    @unittest.skipUnless(os.geteuid() == 0, 'Guest-root installation check; run with sudo for this case')
    def test_installed_context_preserves_instructions_and_detects_changes(self):
        config = self.root / 'opencode.json'
        config.write_text(json.dumps({'instructions': ['PROJECT.md'], 'mcp': {'company': {'enabled': True}}}))
        base = self.root / 'etc/company'
        bundle = self.snapshot()
        context.install_context(bundle, config, base)
        installed = json.loads(config.read_text())
        self.assertEqual(installed['instructions'][0], 'PROJECT.md')
        self.assertTrue(installed['mcp']['company']['enabled'])
        self.assertEqual(context.verify_context(config, base)['revision'], bundle['revision'])
        context.install_context(bundle, config, base)
        self.assertEqual(len(json.loads(config.read_text())['instructions']), 2)
        doc = base / 'snapshots' / bundle['snapshot'] / 'standards/engineering.md'
        doc.chmod(0o644)
        doc.write_text('tampered\n')
        with self.assertRaises(ValueError):
            context.verify_context(config, base)

    @unittest.skipUnless(os.geteuid() == 0, 'Guest-root installation check; run with sudo for this case')
    def test_company_update_preserves_old_snapshot_and_replaces_only_managed_paths(self):
        config = self.root / 'opencode.json'
        config.write_text(json.dumps({'instructions': ['PROJECT.md']}))
        base = self.root / 'etc/company'
        first = self.snapshot()
        context.install_context(first, config, base)
        (self.repository / 'standards/engineering.md').write_text('Updated approved standards.\n')
        self.commit()
        second = self.snapshot()
        context.install_context(second, config, base)
        self.assertTrue((base / 'snapshots' / first['snapshot']).is_dir())
        instructions = json.loads(config.read_text())['instructions']
        self.assertEqual(len(instructions), 2)
        self.assertIn(second['snapshot'], instructions[1])
        self.assertEqual(context.verify_context(config, base)['snapshot'], second['snapshot'])


if __name__ == '__main__':
    unittest.main()
