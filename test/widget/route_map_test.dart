import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sanbo/domain/services/route_playback.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets('RouteMap draws each route fragment as a separate polyline', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            fragments: [
              [(lat: 37.5665, lon: 126.9780), (lat: 37.5670, lon: 126.9785)],
              [(lat: 37.5700, lon: 126.9810), (lat: 37.5705, lon: 126.9815)],
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(
      layer.polylines.where((line) => line.strokeWidth == 3.5),
      hasLength(2),
    );
    expect(layer.polylines.any((line) => line.points.length == 4), isFalse);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('RouteMap empty points shows friendly overlay', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RouteMap(offlinePreview: true, fragments: [])),
      ),
    );
    await tester.pump();
    expect(find.text('경로 포인트가 없어요'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
  });

  testWidgets('RouteMap distinguishes progress, selection, and replay marker', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RouteMap(
            offlinePreview: true,
            fragments: [
              [
                (lat: 37.5665, lon: 126.9780),
                (lat: 37.5670, lon: 126.9785),
                (lat: 37.5675, lon: 126.9790),
              ],
            ],
            progress: RoutePlaybackCursor(fragmentIndex: 0, pointIndex: 1),
            highlightedFragments: [
              [(lat: 37.5670, lon: 126.9785), (lat: 37.5675, lon: 126.9790)],
            ],
            currentPoint: (lat: 37.5670, lon: 126.9785),
          ),
        ),
      ),
    );
    await tester.pump();

    final polylines = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
    expect(polylines.polylines, hasLength(3));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '재생 위치',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '선택한 활동 구간',
      ),
      findsOneWidget,
    );
  });

  testWidgets('missing key preserves geometry without a network client', (
    tester,
  ) async {
    var created = 0;
    await tester.pumpWidget(
      _mapApp(
        keyValue: '',
        factory: () {
          created++;
          return MockClient((_) async => http.Response('', 500));
        },
      ),
    );
    expect(created, 0);
    expect(find.byType(TileLayer), findsNothing);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(find.text(_unavailable), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(RouteMap)).toStringDeep(),
      contains('재생 위치'),
    );
  });

  testWidgets('intentional offline preview does not request or show failure', (
    tester,
  ) async {
    var created = 0;
    await tester.pumpWidget(
      _mapApp(
        offline: true,
        factory: () {
          created++;
          return MockClient((_) async => http.Response('', 500));
        },
      ),
    );
    expect(created, 0);
    expect(find.text(_unavailable), findsNothing);
  });

  for (final failure in ['403', 'transport', 'stream', 'codec']) {
    testWidgets('$failure preserves route and reports no keyed diagnostics', (
      tester,
    ) async {
      final output = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) output.add(message);
      };
      addTearDown(() {
        debugPrint = previousPrint;
      });
      final client = _TrackedClient(
        MockClient.streaming((request, _) async {
          if (failure == 'transport') {
            throw http.ClientException('failed ${request.url}', request.url);
          }
          if (failure == 'stream') {
            return http.StreamedResponse(
              Stream.error(http.ClientException('${request.url}', request.url)),
              200,
            );
          }
          return http.StreamedResponse(
            Stream.value([1, 2, 3]),
            failure == '403' ? 403 : 200,
          );
        }),
      );
      await tester.pumpWidget(
        _mapApp(keyValue: 'audit-test-key-$failure', factory: () => client),
      );
      await _waitForStatus(tester);
      debugPrint = previousPrint;
      expect(find.text(_unavailable), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(RouteMap)).toStringDeep(),
        contains('재생 위치'),
      );
      final requested = client.requests;
      await tester.pump(const Duration(seconds: 1));
      expect(client.requests, requested);
      expect(output.join('\n'), isNot(contains('audit-test-key')));
      expect(output.join('\n'), isNot(contains('?key=')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(client.closed, isTrue);
    });
  }

  testWidgets('provider notice is retained alongside the app status', (
    tester,
  ) async {
    final notice = File(
      'test/fixtures/carto-api-key-required.png',
    ).readAsBytesSync();
    await tester.pumpWidget(
      _mapApp(
        keyValue: 'notice-test-key',
        factory: () => MockClient(
          (_) async => http.Response.bytes(
            notice,
            200,
            headers: {'etag': '"wm-6dc6c2207e69-light"'},
          ),
        ),
      ),
    );
    await _waitForStatus(tester);
    expect(find.text(_unavailable), findsOneWidget);
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget);
    final status = tester.getRect(find.text(_unavailable));
    final map = tester.getRect(find.byType(FlutterMap));
    expect(status.top, greaterThanOrEqualTo(map.bottom));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('playback rebuilds reuse the provider and client', (
    tester,
  ) async {
    var created = 0;
    final client = _TrackedClient(
      MockClient(
        (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
      ),
    );
    http.Client factory() {
      created++;
      return client;
    }

    await tester.pumpWidget(
      _mapApp(keyValue: 'playback-test-key', factory: factory),
    );
    await tester.pump();
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    final requests = client.requests;
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(
        _mapApp(keyValue: 'playback-test-key', factory: factory, point: i),
      );
      await tester.pump();
    }
    expect(created, 1);
    expect(client.requests, requests);
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider,
      same(layer.tileProvider),
    );
    expect(find.text(_unavailable), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(client.closed, isTrue);
  });

  testWidgets('late failures do not affect new configuration or disposed map', (
    tester,
  ) async {
    final pending = Completer<void>();
    final old = _TrackedClient(
      MockClient((r) async {
        await pending.future;
        throw http.ClientException('${r.url}', r.url);
      }),
    );
    final current = _TrackedClient(
      MockClient(
        (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
      ),
    );
    await tester.pumpWidget(
      _mapApp(keyValue: 'late-test-key', factory: () => old),
    );
    await tester.pump();
    expect(old.requests, greaterThan(0));
    await tester.pumpWidget(
      _mapApp(keyValue: 'second-test-key', factory: () => current),
    );
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text(_unavailable), findsNothing);
    expect(old.closed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(current.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending tile requests finish safely after the map is removed', (
    tester,
  ) async {
    final pending = Completer<void>();
    final client = _TrackedClient(
      MockClient((r) async {
        await pending.future;
        throw http.ClientException('${r.url}', r.url);
      }),
    );
    await tester.pumpWidget(
      _mapApp(keyValue: 'unmount-test-key', factory: () => client),
    );
    await tester.pump();
    expect(client.requests, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(client.closed, isFalse);
    pending.complete();
    await tester.pump();
    await tester.pump();
    expect(client.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a reopened map can recover after a failed tile request', (
    tester,
  ) async {
    final failed = _TrackedClient(
      MockClient((_) async => http.Response('', 403)),
    );
    await tester.pumpWidget(
      _mapApp(keyValue: 'retry-test-key', factory: () => failed),
    );
    await _waitForStatus(tester);
    expect(find.text(_unavailable), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final restored = _TrackedClient(
      MockClient(
        (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
      ),
    );
    await tester.pumpWidget(
      _mapApp(keyValue: 'retry-test-key', factory: () => restored),
    );
    await tester.pump();
    expect(restored.requests, greaterThan(0));
    expect(find.text(_unavailable), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('a reopened map reloads after a weak authentication notice', (
    tester,
  ) async {
    final notice = File(
      'test/fixtures/carto-api-key-required.png',
    ).readAsBytesSync();
    await tester.pumpWidget(
      _mapApp(
        keyValue: 'notice-recovery-key',
        factory: () => MockClient(
          (_) async => http.Response.bytes(
            notice,
            200,
            headers: {'etag': 'W/"wm-6dc6c2207e69-light"'},
          ),
        ),
      ),
    );
    await _waitForStatus(tester);
    expect(find.text(_unavailable), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final recovered = _TrackedClient(
      MockClient(
        (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
      ),
    );
    await tester.pumpWidget(
      _mapApp(keyValue: 'notice-recovery-key', factory: () => recovered),
    );
    await tester.pump();
    expect(recovered.requests, greaterThan(0));
    expect(find.text(_unavailable), findsNothing);
    expect(find.byType(PolylineLayer), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final dark in [false, true]) {
    testWidgets('small ${dark ? 'dark' : 'light'} map fits double text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          builder: (_, child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(
            body: RouteMap(
              basemapKey: '',
              fragments: _fragments,
              currentPoint: (lat: 37.5005, lon: 127),
            ),
          ),
        ),
      );
      expect(find.text(_unavailable), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.getBottomRight(find.text(_unavailable)).dx,
        lessThanOrEqualTo(320),
      );
      expect(
        tester.getBottomRight(find.text(_unavailable)).dy,
        lessThanOrEqualTo(640),
      );
    });
  }
}

const _unavailable = '배경 지도를 불러올 수 없어요. 산책 경로와 기록은 그대로 볼 수 있어요.';
const _fragments = [
  [(lat: 37.5, lon: 127.0), (lat: 37.501, lon: 127.0)],
];

Widget _mapApp({
  String keyValue = 'audit-test-key',
  http.Client Function()? factory,
  bool offline = false,
  int point = 0,
}) => MaterialApp(
  home: Scaffold(
    body: RouteMap(
      basemapKey: keyValue,
      tileHttpClientFactory: factory,
      offlinePreview: offline,
      fragments: _fragments,
      currentPoint: (lat: 37.5 + point * 0.00001, lon: 127),
    ),
  ),
);

Future<void> _waitForStatus(WidgetTester tester) async {
  for (var i = 0; i < 100 && find.text(_unavailable).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _TrackedClient extends http.BaseClient {
  _TrackedClient(this.delegate);
  final http.Client delegate;
  int requests = 0;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    return delegate.send(request);
  }

  @override
  void close() {
    closed = true;
    delegate.close();
  }
}
