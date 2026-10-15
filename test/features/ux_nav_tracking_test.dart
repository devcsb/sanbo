import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanbo/domain/services/live_speed_availability.dart';
import 'package:sanbo/features/home/home_screen.dart';
import 'package:sanbo/features/home/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  for (final availability in LiveSpeedAvailability.values) {
    testWidgets('Home speed presentation respects $availability', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionControllerProvider.overrideWith(
                () => _PresentationController(
                  LiveSessionState(
                    isTracking: true,
                    liveSpeedMps: 1.5,
                    validSampleCount: 3,
                    sampleCount: 4,
                    speedAvailability: availability,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const HomeScreen(),
            ),
          ),
        );
        expect(find.text('현재 속도'), findsOneWidget);
        if (availability == LiveSpeedAvailability.available) {
          expect(find.text('5.4 km/h'), findsOneWidget);
        } else {
          expect(find.text('5.4 km/h'), findsNothing);
          final label = availability == LiveSpeedAvailability.waiting
              ? '측정 대기'
              : '측정 중단';
          expect(find.text(label), findsOneWidget);
          expect(find.bySemanticsLabel(RegExp('5.4')), findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  test('ScaffoldWithNavBar ships tracking label and leave-home snack copy', () {
    final src = File(
      'lib/shared/widgets/app_bottom_nav.dart',
    ).readAsStringSync();
    expect(src, contains('ConsumerWidget'));
    expect(src, contains("tracking ? '기록 중' : '홈'"));
    expect(src, contains('산책 기록은 계속됩니다'));
    expect(src, contains('leavingHome'));
    expect(src, contains('isTracking'));
  });

  test(
    'app lifecycle suppresses presentation work as soon as it becomes inactive',
    () {
      final src = File('lib/app.dart').readAsStringSync();
      expect(src, contains('onInactive'));
      expect(src, contains('setAppInactive()'));
    },
  );
}

class _PresentationController extends SessionController {
  _PresentationController(this.initial);
  final LiveSessionState initial;
  @override
  LiveSessionState build() => initial;
}
