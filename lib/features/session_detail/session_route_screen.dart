import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../domain/services/route_playback.dart';
import '../../shared/widgets/route_map.dart';

class SessionRouteScreen extends StatefulWidget {
  const SessionRouteScreen({
    super.key,
    required this.fragments,
    this.geometry,
    this.highlightedGeometry,
    this.highlightedFragments = const [],
    this.progress,
    this.currentPoint,
    this.offlinePreview = false,
  });
  final List<List<({double lat, double lon})>> fragments, highlightedFragments;
  final RouteMapGeometry? geometry, highlightedGeometry;
  final RoutePlaybackCursor? progress;
  final ({double lat, double lon})? currentPoint;
  final bool offlinePreview;
  @override
  State<SessionRouteScreen> createState() => _SessionRouteScreenState();
}

class _SessionRouteScreenState extends State<SessionRouteScreen> {
  final _controller = MapController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _zoom(double delta) => _controller.move(
    _controller.camera.center,
    (_controller.camera.zoom + delta).clamp(1, 19),
  );
  void _pan(double latitude, double longitude) {
    final camera = _controller.camera;
    final step = 90 / (1 << camera.zoom.round().clamp(1, 19));
    _controller.move(
      LatLng(
        (camera.center.latitude + latitude * step).clamp(-85, 85),
        (camera.center.longitude + longitude * step).clamp(-180, 180),
      ),
      camera.zoom,
    );
  }

  void _fit() {
    final geometry =
        widget.geometry ?? RouteMapGeometry.fromFragments(widget.fragments);
    if (geometry.points.length < 2) {
      _controller.move(geometry.center, 13);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: geometry.points,
        padding: const EdgeInsets.all(36),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('이번 경로')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Column(
            children: [
              RouteMap(
                fragments: widget.fragments,
                geometry: widget.geometry,
                highlightedGeometry: widget.highlightedGeometry,
                highlightedFragments: widget.highlightedFragments,
                progress: widget.progress,
                currentPoint: widget.currentPoint,
                mapController: _controller,
                interactionFlags: InteractiveFlag.all,
                offlinePreview: widget.offlinePreview,
                height: (constraints.maxHeight - 160).clamp(180, 1200),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  IconButton(
                    tooltip: '확대',
                    onPressed: () => _zoom(1),
                    icon: const Icon(Icons.add),
                  ),
                  IconButton(
                    tooltip: '축소',
                    onPressed: () => _zoom(-1),
                    icon: const Icon(Icons.remove),
                  ),
                  IconButton(
                    tooltip: '전체 경로 맞춤',
                    onPressed: _fit,
                    icon: const Icon(Icons.fit_screen),
                  ),
                  IconButton(
                    tooltip: '북쪽으로 이동',
                    onPressed: () => _pan(1, 0),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: '남쪽으로 이동',
                    onPressed: () => _pan(-1, 0),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                  IconButton(
                    tooltip: '서쪽으로 이동',
                    onPressed: () => _pan(0, -1),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  IconButton(
                    tooltip: '동쪽으로 이동',
                    onPressed: () => _pan(0, 1),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
