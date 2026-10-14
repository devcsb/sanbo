import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanbo/shared/widgets/carto_basemap.dart';

void main() {
  final uri = Uri.parse(
    'https://a.basemaps.cartocdn.com/test?key=audit-test-key',
  );
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );

  test('key is encoded without changing tile placeholders', () {
    expect(cartoTileUrlTemplate(' \n '), isNull);
    expect(
      cartoTileUrlTemplate(' a&b?x=+ '),
      '$cartoBaseTileUrlTemplate?key=a%26b%3Fx%3D%2B',
    );
    expect(cartoBaseTileUrlTemplate, contains('{s}'));
    expect(cartoBaseTileUrlTemplate, contains('/{z}/{x}/{y}.png'));
  });

  test('normal PNG and headers are preserved', () async {
    var notices = 0;
    final client = CartoTileClient(
      MockClient((request) async {
        expect(request.url, uri);
        expect(request.headers['user-agent'], 'sanbo-test');
        return http.Response.bytes(png, 200, headers: {'etag': 'normal-tile'});
      }),
      onAuthenticationNotice: () => notices++,
    );
    addTearDown(client.close);
    final result = await client.get(uri, headers: {'user-agent': 'sanbo-test'});
    expect(result.bodyBytes, png);
    expect(result.headers['etag'], 'normal-tile');
    expect(notices, 0);
  });

  test('HTTP200 authentication notice is retained and reported', () async {
    final notice = File(
      'test/fixtures/carto-api-key-required.png',
    ).readAsBytesSync();
    expect(notice.length, 2049);
    expect(notice.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    var reported = 0;
    final client = CartoTileClient(
      MockClient(
        (_) async => http.Response.bytes(
          notice,
          200,
          headers: {'etag': '"wm-da89c20e77c1-light"'},
        ),
      ),
      onAuthenticationNotice: () => reported++,
    );
    addTearDown(client.close);
    final result = await client.get(uri);
    expect(result.bodyBytes, notice);
    expect(reported, 1);
  });

  for (final status in [401, 403, 429, 500]) {
    test('HTTP$status produces an error without a key or URL', () async {
      final client = CartoTileClient(
        MockClient((_) async => http.Response('key=audit-test-key', status)),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(uri),
        throwsA(
          isA<CartoBasemapUnavailable>().having(
            (e) => e.toString(),
            'safe message',
            '배경 지도 요청 실패',
          ),
        ),
      );
    });
  }

  test('transport exception cannot expose the request URI', () async {
    final client = CartoTileClient(
      MockClient((_) async {
        throw http.ClientException('request failed: $uri', uri);
      }),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(uri),
      throwsA(
        isA<CartoBasemapUnavailable>().having(
          (e) => e.toString(),
          'safe message',
          '배경 지도 요청 실패',
        ),
      ),
    );
  });

  test('body stream exception is sanitized before image loading', () async {
    final client = CartoTileClient(
      MockClient.streaming((_, __) async {
        return http.StreamedResponse(
          Stream<List<int>>.error(
            http.ClientException('body failed: $uri', uri),
          ),
          200,
        );
      }),
    );
    addTearDown(client.close);
    await expectLater(client.get(uri), throwsA(isA<CartoBasemapUnavailable>()));
  });

  testWidgets('total request and body wait have a fifteen-second bound', (
    tester,
  ) async {
    final pending = Completer<http.StreamedResponse>();
    final client = CartoTileClient(
      MockClient.streaming((_, __) => pending.future),
    );
    addTearDown(client.close);
    final assertion = expectLater(
      client.get(uri),
      throwsA(isA<CartoBasemapUnavailable>()),
    );
    await tester.pump(const Duration(seconds: 15));
    await assertion;
    pending.complete(http.StreamedResponse(Stream.value(png), 200));
    await tester.pump();
  });

  test('closing the tile client closes its underlying client', () {
    final delegate = _ClosingClient();
    CartoTileClient(delegate).close();
    expect(delegate.closed, isTrue);
  });
}

class _ClosingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();
  @override
  void close() => closed = true;
}
