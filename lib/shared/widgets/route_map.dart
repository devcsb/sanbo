import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// OSM-compatible raster basemap (Carto Voyager) + session polyline.
/// No commercial map SDK and no third-party map API key.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.points,
    this.height = 220,
    /// When true, skips network tiles (widget/unit tests).
    this.offlinePreview = false,
  });

  final List<({double lat, double lon})> points;
  final double height;
  final bool offlinePreview;

  /// Public OSM data via CartoCDN. Free for moderate app use; no API key.
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
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                if (latLngs.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: latLngs.first,
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.circle,
                          size: 16,
                          color: Colors.green.shade700,
                        ),
                      ),
                      if (latLngs.length > 1)
                        Marker(
                          point: latLngs.last,
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.location_on,
                            size: 28,
                            color: Colors.red.shade700,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            Positioned(
              left: 8,
              bottom: 6,
              right: 8,
              child: IgnorePointer(
                child: Text(
                  attribution,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.black87,
                    backgroundColor: Colors.white70,
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

/// Neutral background when tiles are disabled (tests / offline).
class ColoredMapBackground extends StatelessWidget {
  const ColoredMapBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Color(0xFFE8EEF0));
  }
}
