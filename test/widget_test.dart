import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/session_warning.dart';
import 'package:sanbo/features/home/home_screen.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:sanbo/shared/widgets/route_map.dart';

void main() {
  testWidgets('start button and map attribution smoke', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('산보')),
          body: const Column(
            children: [
              Text('산책 시작'),
              RouteMap(
                offlinePreview: true,
                fragments: [
                  [
                    (lat: 37.5665, lon: 126.9780),
                    (lat: 37.5670, lon: 126.9785),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('산책 시작'), findsOneWidget);
    expect(find.text('산보'), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(find.byType(RouteMap), findsOneWidget);
  });

  testWidgets('high-speed warning renders accessible two-action banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_WarningSessionController.new),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '기록 종료'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '계속 기록'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(TextButton, '계속 기록')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      find.bySemanticsLabel(
        '산책 기록을 계속할까요?. 이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('기록 종료'), findsOneWidget);
    expect(find.bySemanticsLabel('계속 기록'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionControllerProvider.overrideWith(_WarningSessionController.new),
        ],
        child: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MaterialApp(home: HomeScreen()),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _WarningSessionController extends SessionController {
  @override
  LiveSessionState build() {
    return const LiveSessionState(
      isTracking: true,
      activeWarning: SessionWarning(
        kind: SessionWarningKind.highSpeed,
        title: '산책 기록을 계속할까요?',
        message: '이동 속도가 매우 빨라요. 산책을 마쳤다면 기록을 종료해 주세요.',
        actions: {
          SessionWarningAction.stopRecording,
          SessionWarningAction.continueRecording,
        },
      ),
    );
  }
}
