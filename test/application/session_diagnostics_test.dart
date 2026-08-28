import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/application/diagnostics/session_diagnostics.dart';

void main() {
  test('diagnostics compute intervals without retaining raw samples', () async {
    final diagnostics = SessionDiagnostics();
    final first = DateTime(2026, 8, 29, 10, 0, 0);

    diagnostics.recordCallback(first);
    diagnostics.recordCallback(first.add(const Duration(seconds: 2)));
    diagnostics.recordCallback(first.add(const Duration(seconds: 5)));
    await diagnostics.measureFlush(() async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });

    final snapshot = diagnostics.snapshot();
    expect(snapshot.callbackCount, 3);
    expect(
      snapshot.averageCallbackInterval,
      const Duration(seconds: 2, milliseconds: 500),
    );
    expect(snapshot.flushCount, 1);
    expect(snapshot.lastFlushDuration, isNotNull);
  });

  test('reset clears the current session counters', () {
    final diagnostics = SessionDiagnostics();
    diagnostics.recordCallback(DateTime(2026, 8, 29));
    diagnostics.reset();

    final snapshot = diagnostics.snapshot();
    expect(snapshot.callbackCount, 0);
    expect(snapshot.flushCount, 0);
    expect(snapshot.averageCallbackInterval, isNull);
    expect(snapshot.lastFlushDuration, isNull);
  });
}
