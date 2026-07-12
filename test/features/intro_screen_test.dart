import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/app/app_info.dart';
import 'package:sanbo/features/intro/intro_providers.dart';
import 'package:sanbo/features/intro/intro_screen.dart';
import 'package:sanbo/platform/prefs/app_flags.dart';

void main() {
  testWidgets('IntroScreen shows brand tagline and start CTA', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          introSeenProvider.overrideWith((ref) => false),
          appFlagsStoreProvider.overrideWithValue(
            AppFlagsStore(pathOverride: '/tmp/sanbo_intro_test_flags.json'),
          ),
        ],
        child: const MaterialApp(home: IntroScreen()),
      ),
    );
    await tester.pump();

    expect(find.text(AppInfo.nameKo), findsOneWidget);
    expect(find.text(AppInfo.tagline), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
  });
}
