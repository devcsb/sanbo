import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PROJECT = Path(__file__).resolve().parents[2]
KEY = 'client-map-key-fixture-only-0123456789'


class PrivateReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'source'
        (self.repo / 'scripts').mkdir(parents=True)
        (self.repo / 'android').mkdir()
        self.output = self.root / 'release'
        self.capture = self.root / 'capture.json'
        for name in ['build_private_android_release.py', 'audit_android_artifact.py']:
            shutil.copyfile(PROJECT / 'scripts' / name, self.repo / 'scripts' / name)
        (self.repo / '.gitignore').write_text('android/key.properties\n*.jks\nbuild/\n')
        (self.repo / 'pubspec.yaml').write_text('version: 0.9.4+18\n')
        (self.repo / 'android/build.gradle.kts').write_text('// fixture Android project\n')
        (self.repo / 'private-signing.jks').write_bytes(b'fixture signing material')
        (self.repo / 'android/key.properties').write_text(
            'storeFile=../private-signing.jks\nkeyAlias=fixture\nstorePassword=fixture-store-secret\nkeyPassword=fixture-key-secret\n'
        )
        (self.repo / 'scripts/run_quality_loop.sh').write_text(
            '#!/bin/sh\nexec python3 scripts/fake_release.py "$@"\n'
        )
        (self.repo / 'scripts/fake_release.py').write_text(r'''
import json, os
from pathlib import Path
import sys, zipfile
props = dict(line.split('=', 1) for line in Path('android/key.properties').read_text().splitlines() if '=' in line)
Path(os.environ['RELEASE_TEST_CAPTURE']).write_text(json.dumps({
    'cwd': str(Path.cwd()),
    'storeFile': props['storeFile'],
    'sourceExists': Path(props['storeFile']).is_file(),
    'mode': Path('android/key.properties').stat().st_mode & 0o777,
    'args': sys.argv[1:],
    'commit': os.popen('git rev-parse HEAD').read().strip(),
    'storePasswordEnv': os.environ.get('SANBO_RELEASE_STORE_PASSWORD'),
    'keyPasswordEnv': os.environ.get('SANBO_RELEASE_KEY_PASSWORD'),
}))
print(os.environ['CARTO_BASEMAP_KEY'])
if os.environ.get('RELEASE_TEST_FAIL') == 'yes':
    raise SystemExit(73)
key = os.environ['CARTO_BASEMAP_KEY'].encode()
for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']:
    p = Path(f'build/app/outputs/flutter-apk/app-{abi}-release.apk')
    p.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(p, 'w') as z:
        z.writestr(f'lib/{abi}/libapp.so', key + b' ' + str(Path.cwd()).encode() + os.environ.get('RELEASE_TEST_PRIVATE_PATH', '').encode())
p = Path('build/app/outputs/bundle/release/app-release.aab')
p.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(p, 'w') as z:
    z.writestr('base/lib/arm64-v8a/libapp.so', key)
p = Path('build/app/outputs/release/SHA256SUMS_v0.9.4.txt')
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text('fixture checksums\n')
''')
        self.git('init', '--quiet')
        self.git('add', '.')
        self.git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '--quiet', '-m', 'fixture')
        self.head = self.git('rev-parse', 'HEAD').stdout.strip()
        self.properties_before = (self.repo / 'android/key.properties').read_bytes()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], capture_output=True, text=True, check=True)

    def run_build(self, *, key=KEY, fail=False, extra_env=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith('SANBO_RELEASE_') and k not in {'CARTO_BASEMAP_KEY', 'SANBO_AUDIT_FORBIDDEN_TEXTS'}}
        env.update({'CARTO_BASEMAP_KEY': key, 'SANBO_AUDIT_FORBIDDEN_TEXTS': '[]', 'RELEASE_TEST_CAPTURE': str(self.capture), 'RELEASE_TEST_FAIL': 'yes' if fail else 'no'})
        env.update(extra_env or {})
        return subprocess.run(['python3', str(self.repo / 'scripts/build_private_android_release.py'), '--output', str(self.output)], env=env, capture_output=True, text=True, timeout=30)

    def assert_redacted(self, result):
        output = result.stdout + result.stderr
        for value in [KEY, 'fixture-store-secret', 'fixture-key-secret']:
            self.assertNotIn(value, output)
        self.assertNotIn('Traceback', output)

    def test_clean_head_builds_under_tmp_preserving_private_signing_source(self):
        result = self.run_build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_redacted(result)
        facts = json.loads(self.capture.read_text())
        stage = Path(facts['cwd'])
        self.assertTrue(str(stage).startswith(('/tmp/', '/private/tmp/')))
        self.assertFalse(stage.exists())
        self.assertEqual(facts['commit'], self.head)
        self.assertEqual(facts['args'], ['--release-apk'])
        self.assertTrue(Path(facts['storeFile']).samefile(self.repo / 'private-signing.jks'))
        self.assertTrue(facts['sourceExists'])
        self.assertEqual(facts['mode'], 0o600)
        self.assertEqual((self.repo / 'android/key.properties').read_bytes(), self.properties_before)
        self.assertEqual(self.git('status', '--porcelain').stdout, '')
        self.assertEqual({p.name for p in self.output.iterdir()}, {
            'app-arm64-v8a-release.apk', 'app-armeabi-v7a-release.apk',
            'app-x86_64-release.apk', 'app-release.aab', 'SHA256SUMS_v0.9.4.txt',
        })
        self.assertEqual(self.output.stat().st_mode & 0o777, 0o700)
        self.assertEqual((self.root / 'release.private.log').stat().st_mode & 0o777, 0o600)

    def test_build_failure_cleans_stage_and_keeps_only_private_log(self):
        result = self.run_build(fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assert_redacted(result)
        stage = Path(json.loads(self.capture.read_text())['cwd'])
        self.assertFalse(stage.exists())
        self.assertFalse(self.output.exists())
        self.assertIn(KEY, (self.root / 'release.private.log').read_text())
        self.assertEqual((self.repo / 'android/key.properties').read_bytes(), self.properties_before)

    def test_existing_output_is_never_overwritten(self):
        self.output.mkdir()
        marker = self.output / 'keep'
        marker.write_text('original')
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), 'original')
        self.assertFalse(self.capture.exists())
        self.assert_redacted(result)

    def test_private_path_in_compiled_output_prevents_candidate_copy(self):
        result = self.run_build(extra_env={'RELEASE_TEST_PRIVATE_PATH': '/Users/private-owner/project/registrant.dart'})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.output.exists())
        self.assertIn('personal_path', (self.root / 'release.private.log').read_text())
        self.assertNotIn('private-owner', result.stdout + result.stderr)
        self.assert_redacted(result)

    def test_existing_log_is_never_overwritten(self):
        log = self.root / 'release.private.log'
        log.write_text('original')
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(log.read_text(), 'original')
        self.assertFalse(self.capture.exists())

    def test_dirty_source_is_rejected_without_building(self):
        (self.repo / 'pubspec.yaml').write_text('uncommitted change')
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())
        self.assertEqual((self.repo / 'pubspec.yaml').read_text(), 'uncommitted change')
        self.assert_redacted(result)

    def test_missing_map_key_or_signing_source_is_rejected(self):
        result = self.run_build(key='')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())
        (self.repo / 'private-signing.jks').unlink()
        result = self.run_build()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.capture.exists())
        self.assert_redacted(result)

    def test_keychain_password_whitespace_is_preserved(self):
        (self.repo / 'android/key.properties').write_text('storeFile=../private-signing.jks\nkeyAlias=fixture\n')
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        security = bin_dir / 'security'
        security.write_text("#!/bin/sh\nprintf ' fixture-keychain-secret \\n'\n")
        security.chmod(0o700)
        result = self.run_build(extra_env={'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']})
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        facts = json.loads(self.capture.read_text())
        self.assertEqual(facts['storePasswordEnv'], ' fixture-keychain-secret ')
        self.assertEqual(facts['keyPasswordEnv'], ' fixture-keychain-secret ')
        self.assertNotIn('fixture-keychain-secret', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
