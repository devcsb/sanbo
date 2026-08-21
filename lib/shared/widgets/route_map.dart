import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/services/route_playback.dart';

/// OSM basemap (Carto) + session path.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.fragments,
    this.height = 220,
    this.offlinePreview = false,
    this.progress,
    this.highlightedFragments = const [],
    this.currentPoint,
  });

  final List<List<({double lat, double lon})>> fragments;
  final double height;
  final bool offlinePreview;

  /// Current playback location, with a fragment-local point position.
  final RoutePlaybackCursor? progress;

  /// A timeline segment currently selected by the user.
  final List<List<({double lat, double lon})>> highlightedFragments;

  /// Current fix shown while scrubbing or replaying the route.
  final ({double lat, double lon})? currentPoint;

  static const tileUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static const attribution = '© OpenStreetMap · © CARTO';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latLngFragments = fragments
        .map(
          (fragment) => fragment
              .map((point) => LatLng(point.lat, point.lon))
              .toList(growable: false),
        )
        .toList(growable: false);
    final latLngs = latLngFragments
        .expand((fragment) => fragment)
        .toList(growable: false);
    final highlightedLatLngFragments = highlightedFragments
        .map(
          (fragment) => fragment
              .map((point) => LatLng(point.lat, point.lon))
              .toList(growable: false),
        )
        .toList(growable: false);
    final highlightedLatLngs = highlightedLatLngFragments
        .expand((fragment) => fragment)
        .toList(growable: false);
    final currentLatLng = currentPoint == null
        ? null
        : LatLng(currentPoint!.lat, currentPoint!.lon);
    final center = latLngs.isEmpty
        ? const LatLng(37.5665, 126.9780)
        : latLngs[latLngs.length ~/ 2];

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: latLngs.isEmpty
          ? '산책 경로 지도, 경로 기록 없음'
          : '산책 경로 지도, 위치 기록 ${latLngs.length}개',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: SanboSurfaces.of(context).panelBorder),
          boxShadow: SanboSurfaces.of(context).panelShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: SizedBox(
            height: height,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: latLngs.length < 2 ? 13 : 15,
                    initialCameraFit: latLngs.length >= 2
                        ? CameraFit.coordinates(
                            coordinates: latLngs,
                            padding: const EdgeInsets.all(36),
                            maxZoom: 17,
                          )
                        : null,
                    // Inline glance-preview inside a scrolling page: no drag, or
                    // a vertical swipe starting on the map pans the map instead of
                    // scrolling to the timeline below (scroll dead-zone).
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom,
                    ),
                  ),
                  children: [
                    if (!offlinePreview)
                      TileLayer(
                        urlTemplate: tileUrlTemplate,
                        userAgentPackageName: 'com.sanbo.sanbo',
                        maxZoom: 19,
                        subdomains: const ['a', 'b', 'c', 'd'],
                      )
                    else
                      const ColoredMapBackground(),
                    if (latLngFragments.any((fragment) => fragment.length >= 2))
                      PolylineLayer(
                        polylines: [
                          for (final fragment in latLngFragments)
                            if (fragment.length >= 2)
                              Polyline(
                                points: fragment,
                                color: progress == null
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                strokeWidth: 3.5,
                              ),
                          if (progress != null)
                            for (
                              var index = 0;
                              index < latLngFragments.length;
                              index++
                            )
                              if (index <= progress!.fragmentIndex)
                                if ((index < progress!.fragmentIndex
                                        ? latLngFragments[index].length
                                        : (progress!.pointIndex + 1).clamp(
                                            0,
                                            latLngFragments[index].length,
                                          )) >=
                                    2)
                                  Polyline(
                                    points: latLngFragments[index]
                                        .take(
                                          index < progress!.fragmentIndex
                                              ? latLngFragments[index].length
                                              : (progress!.pointIndex + 1)
                                                    .clamp(
                                                      0,
                                                      latLngFragments[index]
                                                          .length,
                                                    ),
                                        )
                                        .toList(growable: false),
                                    color: theme.colorScheme.primary,
                                    strokeWidth: 4,
                                  ),
                          for (final fragment in highlightedLatLngFragments)
                            if (fragment.length >= 2)
                              Polyline(
                                points: fragment,
                                color: theme.colorScheme.tertiary,
                                strokeWidth: 6,
                              ),
                        ],
                      ),
                    if (latLngs.isNotEmpty || currentLatLng != null)
                      MarkerLayer(
                        markers: [
                          if (latLngs.isNotEmpty)
                            Marker(
                              point: latLngs.first,
                              width: 22,
                              height: 22,
                              child: Semantics(
                                label: '시작 지점',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (latLngs.length > 1)
                            Marker(
                              point: latLngs.last,
                              width: 26,
                              height: 26,
                              child: Semantics(
                                label: '종료 지점',
                                child: Icon(
                                  Icons.location_on_rounded,
                                  size: 26,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                          if (highlightedLatLngs.isNotEmpty)
                            Marker(
                              point:
                                  highlightedLatLngs[highlightedLatLngs
                                          .length ~/
                                      2],
                              width: 38,
                              height: 38,
                              child: Semantics(
                                label: '선택한 활동 구간',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.tertiary
                                        .withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.tertiary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (currentLatLng != null)
                            Marker(
                              point: currentLatLng,
                              width: 30,
                              height: 30,
                              child: Semantics(
                                label: '재생 위치',
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 3,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        blurRadius: 6,
                                        color: Color(0x40000000),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                if (latLngs.isEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHigh
                                .withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSmall,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              '경로 포인트가 없어요',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainer.withValues(
                          alpha: 0.94,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          attribution,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ColoredMapBackground extends StatelessWidget {
  const ColoredMapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
