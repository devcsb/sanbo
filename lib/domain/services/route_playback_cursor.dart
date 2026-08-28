/// Immutable playback position within a partitioned route.
class RoutePlaybackCursor {
  const RoutePlaybackCursor({
    required this.fragmentIndex,
    required this.pointIndex,
  });

  final int fragmentIndex;
  final int pointIndex;

  bool get startsFragment => pointIndex == 0;

  /// Returns draw bounds without allocating prefixes for completed fragments.
  ///
  /// [fragmentLengths] contains only immutable fragment sizes. Consumers can
  /// use [RoutePlaybackVisibility.completedFragmentCount] to reuse those
  /// lists and materialize a prefix only for the active fragment.
  RoutePlaybackVisibility visibleFragments({
    required List<int> fragmentLengths,
  }) {
    if (fragmentLengths.isEmpty) return const RoutePlaybackVisibility.empty();
    final lastIndex = fragmentLengths.length - 1;
    final activeIndex = fragmentIndex < 0
        ? 0
        : fragmentIndex > lastIndex
        ? lastIndex
        : fragmentIndex;
    final length = fragmentLengths[activeIndex].clamp(0, 1 << 30);
    final requestedCount = pointIndex + 1;
    final activePointCount = requestedCount < 0
        ? 0
        : requestedCount > length
        ? length
        : requestedCount;
    return RoutePlaybackVisibility(
      fragmentCount: fragmentLengths.length,
      completedFragmentCount: activeIndex,
      activeFragmentIndex: activeIndex,
      activePointCount: activePointCount,
    );
  }
}

/// Allocation-free route visibility metadata for one playback tick.
class RoutePlaybackVisibility {
  const RoutePlaybackVisibility({
    required this.fragmentCount,
    required this.completedFragmentCount,
    required this.activeFragmentIndex,
    required this.activePointCount,
  });

  const RoutePlaybackVisibility.empty()
    : fragmentCount = 0,
      completedFragmentCount = 0,
      activeFragmentIndex = 0,
      activePointCount = 0;

  final int fragmentCount;
  final int completedFragmentCount;
  final int activeFragmentIndex;
  final int activePointCount;

  bool isCompleted(int index) => index >= 0 && index < completedFragmentCount;

  @override
  bool operator ==(Object other) =>
      other is RoutePlaybackVisibility &&
      other.fragmentCount == fragmentCount &&
      other.completedFragmentCount == completedFragmentCount &&
      other.activeFragmentIndex == activeFragmentIndex &&
      other.activePointCount == activePointCount;

  @override
  int get hashCode => Object.hash(
    fragmentCount,
    completedFragmentCount,
    activeFragmentIndex,
    activePointCount,
  );
}
