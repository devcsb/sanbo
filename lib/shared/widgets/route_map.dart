import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// OSM basemap (Carto) + session path.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.points,
    this.height = 220,
    this.offlinePreview = false,
  });

  final List<({double lat, double lon})> points;
  final double height;
  final bool offlinePreview;

  static const tileUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

  static const attribution = '© OpenStreetMap · © CARTO';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latLngs = points.map((p) => LatLng(p.lat, p.lon)).toList();
    final center = latLngs.isEmpty
        ? const LatLng(37.5665, 126.9780)
        : latLngs[latLngs.length ~/ 2];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: latLngs.length < 2 ? 13 : 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
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
                if (latLngs.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: latLngs,
                        color: theme.colorScheme.primary,
                        strokeWidth: 3.5,
                      ),
                    ],
                  ),
                if (latLngs.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: latLngs.first,
                        width: 22,
                        height: 22,
                        child: Semantics(
                          label: '시작 지점',
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.brandTeal,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 4,
                                ),
                              ],
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
                              color: AppTheme.brandCoral,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 3,
                                ),
                              ],
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
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          '경로 포인트가 없어요',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF3A4548),
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
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      attribution,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF3A4548),
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
