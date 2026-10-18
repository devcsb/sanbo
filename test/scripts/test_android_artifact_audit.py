import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import warnings
import zipfile


SCRIPT = Path(__file__).resolve().parents[2] / 'scripts/audit_android_artifact.py'
spec = importlib.util.spec_from_file_location('artifact_audit', SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
KEY = b'client-map-key-test-only-0123456789'


class ArtifactAuditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def archive(self, entries, name='fixture.apk'):
        path = self.root / name
        with warnings.catch_warnings():
            warnings.simplefilter('ignore', UserWarning)
            with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as z:
                for entry, value in entries:
                    z.writestr(entry, value)
        return path

    def codes(self, path, **kwargs):
        return {x['code'] for x in audit.audit_archive(path, **kwargs)}

    def test_public_client_key_is_not_a_private_signing_secret(self):
        path = self.archive([('lib/arm64-v8a/libapp.so', b'prefix ' + KEY)])
        self.assertEqual(audit.audit_archive(path, expected_carto_key=KEY), [])

    def test_missing_key_in_one_aab_abi_is_rejected(self):
        path = self.archive([
            ('base/lib/arm64-v8a/libapp.so', KEY),
            ('base/lib/x86_64/libapp.so', b'wrong build'),
        ], name='fixture.aab')
        self.assertIn('missing_client_key', self.codes(path, expected_carto_key=KEY))

    def test_expected_key_requires_a_flutter_payload(self):
        path = self.archive([('AndroidManifest.xml', b'example')])
        self.assertIn('missing_client_key', self.codes(path, expected_carto_key=KEY))

    def test_home_paths_are_found_in_native_payloads(self):
        paths = [
            '/Users/private-owner/project/registrant.dart',
            '/home/private-owner/project/registrant.dart',
            r'C:\Users\private-owner\project\registrant.dart',
            'C:/Users/private-owner/project/registrant.dart',
        ]
        for value in paths:
            for encoding in ['utf-8', 'utf-16le', 'utf-16be']:
                with self.subTest(path=value, encoding=encoding):
                    path = self.archive([('lib/arm64-v8a/libapp.so', value.encode(encoding))])
                    self.assertIn('personal_path', self.codes(path))

    def test_private_files_and_pem_are_found(self):
        for name in ['android/key.properties', '.env.production', 'private/upload.jks', 'private/signing.p12', 'carto-basemap.json']:
            with self.subTest(name=name):
                self.assertIn('private_file', self.codes(self.archive([(name, b'example')])) )
        path = self.archive([('assets/ordinary.bin', b'-----BEGIN PRIVATE KEY-----\nfixture')])
        self.assertIn('private_key', self.codes(path))

    def test_supplied_private_text_is_found_but_not_returned(self):
        secret = b'private-owner@example.invalid'
        path = self.archive([('assets/ordinary.bin', secret)])
        findings = audit.audit_archive(path, forbidden_values=[secret])
        self.assertIn('private_text', {x['code'] for x in findings})
        self.assertNotIn(secret.decode(), json.dumps(findings))

    def test_duplicate_entry_and_malformed_archive_fail_closed(self):
        duplicate = self.archive([('assets/x', b'one'), ('assets/x', b'two')])
        self.assertIn('duplicate_entry', self.codes(duplicate))
        malformed = self.root / 'broken.apk'
        malformed.write_bytes(b'not zip')
        self.assertIn('invalid_archive', self.codes(malformed))

    def test_private_text_in_zip_comment_is_not_missed(self):
        path = self.archive([('assets/x', b'normal')])
        with zipfile.ZipFile(path, 'a') as z:
            z.comment = b'owner-private@example.invalid'
        self.assertIn('private_text', self.codes(path, forbidden_values=[b'owner-private@example.invalid']))

    def test_resource_limits_precede_content_reading(self):
        path = self.archive([('assets/a', b'a' * 20), ('assets/b', b'b' * 20)])
        for limit, value in [('MAX_ARCHIVE_BYTES', 10), ('MAX_ENTRY_BYTES', 16), ('MAX_TOTAL_BYTES', 30), ('MAX_ENTRIES', 1), ('MAX_METADATA_BYTES', 1)]:
            with self.subTest(limit=limit), mock.patch.object(audit, limit, value):
                self.assertIn('resource_limit', self.codes(path))

    def test_cli_never_prints_input_names_or_private_values(self):
        secret = 'cli-private-owner@example.invalid'
        path = self.archive([(f'assets/{secret}', (secret + '\n' + KEY.decode()).encode())], name=secret + '.apk')
        env = {**os.environ, 'CARTO_BASEMAP_KEY': KEY.decode(), 'SANBO_AUDIT_FORBIDDEN_TEXTS': json.dumps([secret])}
        result = subprocess.run(['python3', str(SCRIPT), str(path)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        output = result.stdout + result.stderr
        self.assertIn('private_text', output)
        self.assertNotIn(secret, output)
        self.assertNotIn(KEY.decode(), output)
        self.assertNotIn('Traceback', output)

    def test_invalid_private_configuration_is_redacted(self):
        path = self.archive([('assets/x', b'normal')])
        env = {**os.environ, 'SANBO_AUDIT_FORBIDDEN_TEXTS': 'private-invalid-config-secret', 'CARTO_BASEMAP_KEY': KEY.decode()}
        result = subprocess.run(['python3', str(SCRIPT), str(path)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('private-invalid-config-secret', result.stdout + result.stderr)
        self.assertNotIn('Traceback', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
