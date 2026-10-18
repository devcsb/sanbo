import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  const secret = 'audit-key-a&b?x=+';
  final helper = File('scripts/prepare_carto_defines.py').absolute.path;
  final quality = File('scripts/run_quality_loop.sh').absolute;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sanbo-carto-test-');
  });
  tearDown(() async => temp.delete(recursive: true));

  Future<ProcessResult> prepare(List<String> arguments, {String? key}) =>
      Process.run(
        'python3',
        [helper, ...arguments],
        environment: {...Platform.environment, 'CARTO_BASEMAP_KEY': key ?? ''},
      );

  for (final key in ['', ' \t\n ']) {
    test(
      'missing or blank key fails without creating a file: ${key.length}',
      () async {
        final target = File('${temp.path}/defines.json');
        final result = await prepare([target.path], key: key);
        expect(result.exitCode, isNonZero);
        expect(result.stderr, contains('CARTO_BASEMAP_KEY is required'));
        expect(target.existsSync(), isFalse);
      },
    );
  }

  test(
    'JSON preserves key characters and uses private file permissions',
    () async {
      final target = File('${temp.path}/defines.json');
      final result = await prepare([target.path], key: '  $secret\n');
      expect(result.exitCode, 0);
      expect(jsonDecode(target.readAsStringSync()), {
        'CARTO_BASEMAP_KEY': secret,
      });
      expect(target.statSync().mode & 0x1ff, 0x180); // 0600
      expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
    },
  );

  test('an existing file is never overwritten', () async {
    final target = File('${temp.path}/defines.json')
      ..writeAsStringSync('original');
    final result = await prepare([target.path], key: secret);
    expect(result.exitCode, isNonZero);
    expect(target.readAsStringSync(), 'original');
    expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
  });

  test('a symlink cannot replace the requested output', () async {
    final original = File('${temp.path}/original')
      ..writeAsStringSync('original');
    final link = Link('${temp.path}/defines.json')..createSync(original.path);
    final result = await prepare([link.path], key: secret);
    expect(result.exitCode, isNonZero);
    expect(original.readAsStringSync(), 'original');
    expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
  });

  for (final args in [
    <String>[],
    ['one', 'two'],
    ['missing-parent/defines.json'],
  ]) {
    test(
      'invalid arguments or output errors do not reveal the key: $args',
      () async {
        final result = await prepare(args, key: secret);
        expect(result.exitCode, isNonZero);
        expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
        expect(result.stderr, isNot(contains('Traceback')));
      },
    );
  }

  for (final mode in ['--release-apk', '--all-apk']) {
    test('$mode rejects blank keys before Git or Flutter is called', () async {
      final bin = Directory('${temp.path}/bin')..createSync();
      final marker = File('${temp.path}/external-called');
      for (final name in ['git', 'flutter']) {
        final stub = File('${bin.path}/$name')
          ..writeAsStringSync(
            '#!/bin/sh\nprintf called >> "\$CALLED"\nexit 78\n',
          );
        await Process.run('chmod', ['+x', stub.path]);
      }
      final result = await Process.run(
        'bash',
        [quality.path, mode],
        environment: {
          ...Platform.environment,
          'PATH': '${bin.path}:${Platform.environment['PATH']}',
          'CALLED': marker.path,
          'CARTO_BASEMAP_KEY': mode == '--all-apk' ? ' \t ' : '',
        },
      );
      expect(result.exitCode, isNonZero);
      expect(result.stderr, contains('CARTO_BASEMAP_KEY is required'));
      expect(marker.existsSync(), isFalse);
    });
  }

  for (final scenario in ['no-key', 'key', 'build-failure']) {
    test(
      'debug gate passes defines privately and cleans up: $scenario',
      () async {
        final project = Directory('${temp.path}/project')..createSync();
        final scripts = Directory('${project.path}/scripts')..createSync();
        quality.copySync('${scripts.path}/run_quality_loop.sh');
        File(helper).copySync('${scripts.path}/prepare_carto_defines.py');
        File('${scripts.path}/verify_prd_trd.py').writeAsStringSync('pass\n');
        final bin = Directory('${temp.path}/bin')..createSync();
        final tmp = Directory('${temp.path}/tmp')..createSync();
        final calls = File('${temp.path}/calls');
        final capture = File('${temp.path}/captured.json');
        final python = await Process.run('python3', [
          '-c',
          'import sys; print(sys.executable)',
        ]);
        final stubs = {
          // The Python tooling suite is tested separately; keep the real
          // interpreter for this test's define generation and file handling.
          'python3': r'''#!/bin/sh
if [ "$1" = -m ] && [ "$2" = unittest ]; then exit 0; fi
exec "$REAL_PYTHON" "$@"
''',
          'git':
              '#!/bin/sh\nif [ "\$1" = describe ]; then echo v0.9.1; fi\nexit 0\n',
          'flutter': r'''#!/bin/bash
printf '%s\n' "$@" >> "$CALLS"
previous=""
for argument in "$@"; do
  if [[ "$previous" == --dart-define-from-file ]]; then
    cp "$argument" "$DEFINE_CAPTURE"
  fi
  previous="$argument"
done
if [[ "$1" == build && "$FAIL_BUILD" == yes ]]; then exit 73; fi
''',
        };
        for (final entry in stubs.entries) {
          final file = File('${bin.path}/${entry.key}')
            ..writeAsStringSync(entry.value);
          await Process.run('chmod', ['+x', file.path]);
        }
        final result = await Process.run(
          'bash',
          ['${scripts.path}/run_quality_loop.sh', '--debug-apk'],
          environment: {
            ...Platform.environment,
            'PATH': '${bin.path}:${Platform.environment['PATH']}',
            'TMPDIR': tmp.path,
            'CALLS': calls.path,
            'DEFINE_CAPTURE': capture.path,
            'FAIL_BUILD': scenario == 'build-failure' ? 'yes' : 'no',
            'CARTO_BASEMAP_KEY': scenario == 'no-key' ? '' : secret,
            'REAL_PYTHON': (python.stdout as String).trim(),
          },
        );
        expect(
          result.exitCode,
          scenario == 'build-failure' ? 73 : 0,
          reason: '${result.stdout}${result.stderr}',
        );
        final arguments = calls.readAsStringSync();
        expect(arguments, isNot(contains(secret)));
        expect('${result.stdout}${result.stderr}', isNot(contains(secret)));
        if (scenario == 'no-key') {
          expect(arguments, isNot(contains('--dart-define-from-file')));
          expect(capture.existsSync(), isFalse);
        } else {
          expect(arguments, contains('--dart-define-from-file'));
          expect(jsonDecode(capture.readAsStringSync()), {
            'CARTO_BASEMAP_KEY': secret,
          });
        }
        expect(tmp.listSync(), isEmpty);
      },
    );
  }
}
