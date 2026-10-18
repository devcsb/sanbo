#!/usr/bin/env python3
"""Build committed Android sources under /tmp; keep inputs and logs private."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from audit_android_artifact import audit_archive


_PROPERTY = re.compile(r'^\s*(storeFile|keyAlias|storePassword|keyPassword)\s*=\s*(.*?)\s*$')


def _escape_property(value: str) -> str:
    result = []
    for char in value:
        if char in '\\ :=#!':
            result.append('\\' + char)
        elif 0x21 <= ord(char) <= 0x7e:
            result.append(char)
        else:
            units = char.encode('utf-16be')
            result.extend('\\u' + units[i:i + 2].hex() for i in range(0, len(units), 2))
    return ''.join(result)


def _signing_text(source: Path, env: dict[str, str]) -> str:
    path = source / 'android/key.properties'
    original = path.read_text(encoding='latin-1') if path.exists() else ''
    props = {}
    for line in original.split('\n'):
        if match := _PROPERTY.fullmatch(line):
            if match[1] in props:
                raise ValueError('ambiguous signing properties')
            props[match[1]] = match[2]
    raw_store = props.get('storeFile') or env.get('SANBO_RELEASE_STORE_FILE', '')
    alias = props.get('keyAlias') or env.get('SANBO_RELEASE_KEY_ALIAS', '')
    # Existing inputs use ordinary POSIX paths/aliases. Escaped Java metadata
    # must be supplied as literal environment values rather than guessed here.
    if not raw_store or not alias or '\\' in raw_store or '\\' in alias:
        raise ValueError('missing or unsupported signing metadata')
    store = Path(raw_store)
    if not store.is_absolute():
        store = source / 'android' / store
    store = store.resolve(strict=True)
    if not store.is_file():
        raise ValueError('missing signing source')
    missing = [
        name for name, variable in [('storePassword', 'SANBO_RELEASE_STORE_PASSWORD'), ('keyPassword', 'SANBO_RELEASE_KEY_PASSWORD')]
        if not props.get(name) and not env.get(variable)
    ]
    if missing and shutil.which('security'):
        password = subprocess.run(
            ['security', 'find-generic-password', '-a', env.get('USER', ''), '-s', 'sanbo-release-keystore', '-w'],
            capture_output=True, text=True, env=env, timeout=20,
        )
        value = password.stdout.rstrip('\n')
        if password.returncode == 0 and value:
            for name in missing:
                variable = 'SANBO_RELEASE_STORE_PASSWORD' if name == 'storePassword' else 'SANBO_RELEASE_KEY_PASSWORD'
                env[variable] = value
    for name, variable in [('storePassword', 'SANBO_RELEASE_STORE_PASSWORD'), ('keyPassword', 'SANBO_RELEASE_KEY_PASSWORD')]:
        if not props.get(name) and not env.get(variable):
            raise ValueError('missing signing password')
    lines = [line for line in original.split('\n') if not (match := _PROPERTY.fullmatch(line)) or match[1] not in {'storeFile', 'keyAlias'}]
    return '\n'.join(lines) + '\nstoreFile=' + _escape_property(str(store)) + '\nkeyAlias=' + _escape_property(alias) + '\n'


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] != '--output':
        print('usage: build_private_android_release.py --output <new-directory>', file=sys.stderr)
        return 2
    os.umask(0o077)
    source = Path(__file__).resolve().parents[1]
    output = Path(sys.argv[2]).absolute()
    env = dict(os.environ)
    created = []
    made_output = False
    try:
        if output.exists() or output.is_symlink() or not output.parent.is_dir():
            raise ValueError('output must be a new directory')
        log_path = output.with_name(output.name + '.private.log')
        if log_path.exists() or log_path.is_symlink():
            raise ValueError('private log already exists')
        key = env.get('CARTO_BASEMAP_KEY', '').strip()
        if not key:
            raise ValueError('missing map key')
        env['CARTO_BASEMAP_KEY'] = key
        private = json.loads(env.get('SANBO_AUDIT_FORBIDDEN_TEXTS', '[]'))
        if not isinstance(private, list) or any(not isinstance(v, str) or not v or len(v.encode('utf-8')) > 4096 for v in private) or len(private) > 99:
            raise ValueError('invalid private audit configuration')
        private.append(str(Path.home()))
        env['SANBO_AUDIT_FORBIDDEN_TEXTS'] = json.dumps(private)
        dirty = subprocess.run(['git', 'status', '--porcelain=v1', '--untracked-files=all'], cwd=source, capture_output=True, text=True, check=True)
        if dirty.stdout.strip():
            raise ValueError('source must be clean and committed')
        tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', 'android/key.properties'], cwd=source, capture_output=True)
        if tracked.returncode == 0:
            raise ValueError('private signing properties must not be tracked')
        revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=source, stderr=subprocess.DEVNULL, text=True).strip()
        signing = _signing_text(source, env)
        with log_path.open('x', encoding='utf-8') as log:
            os.fchmod(log.fileno(), 0o600)
            with tempfile.TemporaryDirectory(prefix='sanbo-release-', dir='/tmp') as temp:
                stage = Path(temp) / 'checkout'
                subprocess.run(['git', 'clone', '--quiet', '--no-hardlinks', '--no-checkout', '--', str(source), str(stage)], stdout=log, stderr=subprocess.STDOUT, env=env, check=True)
                subprocess.run(['git', 'checkout', '--quiet', '--detach', revision], cwd=stage, stdout=log, stderr=subprocess.STDOUT, env=env, check=True)
                with (stage / 'android/key.properties').open('x', encoding='latin-1') as settings:
                    os.fchmod(settings.fileno(), 0o600)
                    settings.write(signing)
                subprocess.run(['bash', 'scripts/run_quality_loop.sh', '--release-apk'], cwd=stage, stdout=log, stderr=subprocess.STDOUT, env=env, check=True)
                artifacts = [
                    stage / f'build/app/outputs/flutter-apk/app-{abi}-release.apk'
                    for abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']
                ] + [stage / 'build/app/outputs/bundle/release/app-release.aab']
                checksums = list((stage / 'build/app/outputs/release').glob('SHA256SUMS_v*.txt'))
                if len(checksums) != 1 or any(not p.is_file() or p.is_symlink() or not p.stat().st_size for p in artifacts):
                    raise ValueError('release artifacts are incomplete')
                for index, artifact in enumerate(artifacts):
                    findings = audit_archive(artifact, forbidden_values=[v.encode('utf-8') for v in private], expected_carto_key=key.encode('utf-8'))
                    if findings:
                        print(json.dumps({'artifact': index, 'findings': findings}), file=log, flush=True)
                        raise ValueError('artifact privacy check failed')
                output.mkdir(mode=0o700)
                made_output = True
                for artifact in artifacts:
                    target = output / artifact.name
                    with target.open('xb') as destination, artifact.open('rb') as incoming:
                        created.append(target)
                        shutil.copyfileobj(incoming, destination)
                manifest = output / checksums[0].name
                with manifest.open('x', encoding='ascii') as stream:
                    created.append(manifest)
                    for artifact in artifacts:
                        copied = output / artifact.name
                        with copied.open('rb') as data:
                            digest = hashlib.file_digest(data, 'sha256').hexdigest()
                        stream.write(f'{digest}  {copied.name}\n')
        print('private Android release: PASS')
        return 0
    except (OSError, ValueError, UnicodeError, subprocess.SubprocessError, KeyboardInterrupt):
        # Preserve existing user files. Only files created above may be removed;
        # an unexpected addition also prevents rmdir from removing the folder.
        for path in created:
            try:
                path.unlink()
            except OSError:
                pass
        if made_output:
            try:
                output.rmdir()
            except OSError:
                pass
        print('private Android release failed; inspect the private sibling log if created', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
