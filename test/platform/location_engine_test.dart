import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/models/tracking_mode.dart';
import 'package:sanbo/platform/location/location_engine.dart';
import 'package:sanbo/platform/location/synthetic_location_engine.dart';

void main() {
  test('typed location failures keep UI classification stable', () {
    expect(
      classifyLocationFailure(
        const LocationEngineFailure(LocationFailureKind.permission),
      ),
      LocationFailureKind.permission,
    );
    expect(
      classifyLocationFailure(
        const LocationEngineFailure(LocationFailureKind.streamEnded),
      ),
      LocationFailureKind.streamEnded,
    );
  });

  test('legacy adapter messages remain compatible during migration', () {
    expect(
      classifyLocationFailure(StateError('location_service_disabled')),
      LocationFailureKind.serviceDisabled,
    );
    expect(
      classifyLocationFailure(StateError('location_stream_ended')),
      LocationFailureKind.streamEnded,
    );
  });

  test('synthetic engine can change its profile while running', () async {
    final engine = SyntheticLocationEngine();
    await engine.start();
    addTearDown(engine.dispose);

    await engine.setMode(TrackingMode.highAccuracy);

    expect(engine.mode, TrackingMode.highAccuracy);
  });
}
