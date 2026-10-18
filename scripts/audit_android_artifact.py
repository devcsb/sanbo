#!/usr/bin/env python3
"""Inspect APK/AAB bytes without extracting files or printing private values."""
import json
import os
from pathlib import Path
import re
import struct
import sys
from collections.abc import Sequence
import zipfile


MAX_ARCHIVE_BYTES = 2 * 1024**3
MAX_ENTRY_BYTES = 256 * 1024**2
MAX_TOTAL_BYTES = 1024**3
MAX_ENTRIES = 10000
MAX_METADATA_BYTES = 8 * 1024**2
_CHUNK_BYTES = 1024**2
_OVERLAP_BYTES = 8192
_PERSONAL_PATH = re.compile(
    # AOT strings are adjacent binary records; never consume record bytes as
    # an owner name after a package URI such as features/home/home_screen.dart.
    rb'(?:/Users/|/home/)[A-Za-z0-9_.@+ -]{1,255}/'
    rb'|[A-Za-z]:[\\/]Users[\\/][A-Za-z0-9_.@+ -]{1,255}[\\/]'
)
_PRIVATE_KEY = re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----')
_OTHER_CREDENTIAL = re.compile(
    rb'AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}'
    rb'|(?:ghp_|github_pat_)[A-Za-z0-9_]{30,}|sk_live_[A-Za-z0-9]{16,}'
)


def _content_codes(data: bytes, forbidden_values: Sequence[bytes]) -> set[str]:
    codes = set()
    # At most 256MiB per entry; this second view also catches ASCII in UTF-16.
    # Larger payloads should use a streaming decoder rather than raising caps.
    for view in (data, data.replace(b'\0', b'')):
        if _PERSONAL_PATH.search(view):
            codes.add('personal_path')
        if _PRIVATE_KEY.search(view):
            codes.add('private_key')
        if _OTHER_CREDENTIAL.search(view):
            codes.add('unexpected_credential')
        if any(value in view for value in forbidden_values):
            codes.add('private_text')
    return codes


def _metadata_status(source, size: int) -> str | None:
    source.seek(max(0, size - 65557))
    tail = source.read(65557)
    pos = tail.rfind(b'PK\x05\x06')
    if pos < 0 or len(tail) - pos < 22:
        return 'invalid_archive'
    fields = struct.unpack_from('<4s4H2LH', tail, pos)
    disk, central_disk, disk_count, total_count, central_size, offset, comment_size = fields[1:]
    if pos + 22 + comment_size != len(tail) or disk or central_disk or disk_count != total_count:
        return 'invalid_archive'
    # Android outputs here are small ordinary ZIPs. Refuse ZIP64/multidisk
    # before zipfile can allocate an unbounded central-directory buffer.
    if total_count == 65535 or central_size == 0xffffffff or offset == 0xffffffff:
        return 'resource_limit'
    if total_count > MAX_ENTRIES or central_size > MAX_METADATA_BYTES:
        return 'resource_limit'
    if offset + central_size > size - len(tail) + pos:
        return 'invalid_archive'
    return None


def audit_archive(
    path: Path,
    *,
    forbidden_values: Sequence[bytes] = (),
    expected_carto_key: bytes | None = None,
) -> list[dict[str, object]]:
    if (len(forbidden_values) > 100
            or any(not isinstance(v, bytes) or not 1 <= len(v) <= 4096 for v in forbidden_values)
            or (expected_carto_key is not None and not 1 <= len(expected_carto_key) <= 4096)):
        return [{'code': 'invalid_configuration', 'entry': None}]
    findings = []
    try:
        with Path(path).open('rb') as source:
            initial = os.fstat(source.fileno())
            if initial.st_size > MAX_ARCHIVE_BYTES:
                return [{'code': 'resource_limit', 'entry': None}]
            metadata_error = _metadata_status(source, initial.st_size)
            if metadata_error:
                return [{'code': metadata_error, 'entry': None}]
            # Inspect non-entry bytes too (ZIP comments, extras, signing block).
            source.seek(0)
            overlap = b''
            raw_codes = set()
            read_bytes = 0
            while chunk := source.read(_CHUNK_BYTES):
                read_bytes += len(chunk)
                if read_bytes > MAX_ARCHIVE_BYTES:
                    return [{'code': 'resource_limit', 'entry': None}]
                combined = overlap + chunk
                raw_codes.update(_content_codes(combined, forbidden_values))
                overlap = combined[-_OVERLAP_BYTES:]
            findings.extend({'code': code, 'entry': None} for code in sorted(raw_codes))
            source.seek(0)
            with zipfile.ZipFile(source) as archive:
                entries = archive.infolist()
                if (len(entries) > MAX_ENTRIES
                        or any(e.file_size > MAX_ENTRY_BYTES for e in entries)
                        or sum(e.file_size for e in entries) > MAX_TOTAL_BYTES):
                    return [{'code': 'resource_limit', 'entry': None}]
                seen = set()
                libraries = 0
                for index, entry in enumerate(entries):
                    if entry.filename in seen:
                        findings.append({'code': 'duplicate_entry', 'entry': index})
                        continue
                    seen.add(entry.filename)
                    name = entry.filename.replace('\\', '/').rsplit('/', 1)[-1].lower()
                    if (name in {'key.properties', 'keystore.properties', 'carto-basemap.json', '.env'}
                            or name.startswith('.env.')
                            or name.endswith(('.jks', '.keystore', '.p12', '.pfx', '.key'))):
                        findings.append({'code': 'private_file', 'entry': index})
                    if entry.is_dir():
                        continue
                    data = archive.read(entry)
                    for code in sorted(_content_codes(entry.filename.encode('utf-8') + b'\0' + data, forbidden_values)):
                        findings.append({'code': code, 'entry': index})
                    if name == 'libapp.so':
                        libraries += 1
                        if expected_carto_key is not None and expected_carto_key not in data:
                            findings.append({'code': 'missing_client_key', 'entry': index})
                if expected_carto_key is not None and not libraries:
                    findings.append({'code': 'missing_client_key', 'entry': None})
            final = os.fstat(source.fileno())
            if (initial.st_size, initial.st_mtime_ns, initial.st_ctime_ns) != (final.st_size, final.st_mtime_ns, final.st_ctime_ns):
                findings.append({'code': 'artifact_changed', 'entry': None})
    except (OSError, ValueError, RuntimeError, NotImplementedError, zipfile.BadZipFile, EOFError):
        return [{'code': 'invalid_archive', 'entry': None}]
    return findings


def main() -> int:
    # Avoid argparse echoing caller-supplied paths in error messages.
    if len(sys.argv) < 2:
        print('usage: audit_android_artifact.py <apk-or-aab> [...]', file=sys.stderr)
        return 2
    try:
        private = json.loads(os.environ.get('SANBO_AUDIT_FORBIDDEN_TEXTS', '[]'))
        if not isinstance(private, list) or any(not isinstance(v, str) for v in private):
            raise ValueError()
        values = [v.encode('utf-8') for v in private]
        key = os.environ.get('CARTO_BASEMAP_KEY', '').strip().encode('utf-8') or None
    except (ValueError, UnicodeError):
        print('invalid private audit configuration', file=sys.stderr)
        return 2
    failed = False
    for index, raw_path in enumerate(sys.argv[1:]):
        findings = audit_archive(Path(raw_path), forbidden_values=values, expected_carto_key=key)
        print(json.dumps({'artifact': index, 'status': 'fail' if findings else 'pass', 'findings': findings}))
        failed |= bool(findings)
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
