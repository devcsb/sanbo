import 'package:flutter_test/flutter_test.dart';
import 'package:sanbo/domain/services/route_playback_cursor.dart';

void main() {
  const lengths = [3, 2, 4];

  test(
    'cursor matches the visible route prefix at first, middle, and last indexes',
    () {
      expect(
        const RoutePlaybackCursor(
          fragmentIndex: 0,
          pointIndex: 0,
        ).visibleFragments(fragmentLengths: lengths),
        const RoutePlaybackVisibility(
          fragmentCount: 3,
          completedFragmentCount: 0,
          activeFragmentIndex: 0,
          activePointCount: 1,
        ),
      );
      expect(
        const RoutePlaybackCursor(
          fragmentIndex: 1,
          pointIndex: 0,
        ).visibleFragments(fragmentLengths: lengths),
        const RoutePlaybackVisibility(
          fragmentCount: 3,
          completedFragmentCount: 1,
          activeFragmentIndex: 1,
          activePointCount: 1,
        ),
      );
      expect(
        const RoutePlaybackCursor(
          fragmentIndex: 2,
          pointIndex: 3,
        ).visibleFragments(fragmentLengths: lengths),
        const RoutePlaybackVisibility(
          fragmentCount: 3,
          completedFragmentCount: 2,
          activeFragmentIndex: 2,
          activePointCount: 4,
        ),
      );
    },
  );

  test('cursor clamps invalid positions to a safe empty or last view', () {
    expect(
      const RoutePlaybackCursor(
        fragmentIndex: -1,
        pointIndex: -5,
      ).visibleFragments(fragmentLengths: lengths),
      const RoutePlaybackVisibility(
        fragmentCount: 3,
        completedFragmentCount: 0,
        activeFragmentIndex: 0,
        activePointCount: 0,
      ),
    );
    expect(
      const RoutePlaybackCursor(
        fragmentIndex: 99,
        pointIndex: 99,
      ).visibleFragments(fragmentLengths: lengths),
      const RoutePlaybackVisibility(
        fragmentCount: 3,
        completedFragmentCount: 2,
        activeFragmentIndex: 2,
        activePointCount: 4,
      ),
    );
    expect(
      const RoutePlaybackCursor(
        fragmentIndex: 0,
        pointIndex: 0,
      ).visibleFragments(fragmentLengths: const []),
      const RoutePlaybackVisibility.empty(),
    );
  });
}
