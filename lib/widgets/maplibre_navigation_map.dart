import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/offline_map.dart';

class MapLibreNavigationMap extends StatefulWidget {
  const MapLibreNavigationMap({
    super.key,
    required this.map,
    required this.pointsOfInterest,
    required this.origin,
    required this.viewCenter,
    required this.viewLatSpan,
    required this.heading,
    required this.route,
    required this.destination,
    required this.darkMode,
    required this.followCar,
    required this.onUserGesture,
    required this.onPoiTap,
  });

  final OfflineMapData map;
  final List<MapPoi> pointsOfInterest;
  final Offset? origin;
  final Offset? viewCenter;
  final double viewLatSpan;
  final double? heading;
  final OfflineRoute? route;
  final Offset? destination;
  final bool darkMode;
  final bool followCar;
  final VoidCallback onUserGesture;
  final ValueChanged<MapPoi> onPoiTap;

  @override
  State<MapLibreNavigationMap> createState() => _MapLibreNavigationMapState();
}

class _MapLibreNavigationMapState extends State<MapLibreNavigationMap> {
  MapLibreMapController? _controller;
  Timer? _gestureDebounce;
  DateTime? _ignoreCameraMoveUntil;
  String? _lastRouteKey;
  String? _lastStationKey;
  String? _lastDestinationKey;

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    controller.onCircleTapped.add(_handleCircleTap);
    await _syncCamera(animated: false);
  }

  Future<void> _onStyleLoaded() async {
    await _syncAnnotations(force: true);
  }

  @override
  void didUpdateWidget(covariant MapLibreNavigationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCamera(animated: true);
    _syncAnnotations();
  }

  @override
  void dispose() {
    _gestureDebounce?.cancel();
    _controller?.onCircleTapped.remove(_handleCircleTap);
    super.dispose();
  }

  void _handleGesture() {
    final ignoreUntil = _ignoreCameraMoveUntil;
    if (ignoreUntil != null && DateTime.now().isBefore(ignoreUntil)) return;

    _gestureDebounce?.cancel();
    _gestureDebounce = Timer(const Duration(milliseconds: 160), () {
      if (mounted) widget.onUserGesture();
    });
  }

  void _handleCircleTap(Circle circle) {
    final data = circle.data;
    final index = data?['poiIndex'];
    if (index is! int || index < 0 || index >= widget.pointsOfInterest.length) {
      return;
    }
    widget.onPoiTap(widget.pointsOfInterest[index]);
  }

  Future<void> _syncCamera({required bool animated}) async {
    final controller = _controller;
    if (controller == null) return;
    if (!widget.followCar && widget.viewCenter == null) return;

    final center = widget.followCar
        ? widget.origin ?? widget.map.center
        : widget.viewCenter ?? widget.map.center;
    final position = CameraPosition(
      target: _latLng(center),
      zoom: widget.followCar
          ? (widget.origin == null ? 13.0 : 17.8)
          : _zoomForLatSpan(widget.viewLatSpan),
      bearing:
          widget.followCar && widget.origin != null ? widget.heading ?? 0 : 0,
      tilt: widget.followCar && widget.origin != null ? 45 : 0,
    );
    final update = CameraUpdate.newCameraPosition(position);

    _ignoreCameraMoveUntil =
        DateTime.now().add(const Duration(milliseconds: 700));
    if (animated) {
      await controller.animateCamera(
        update,
        duration: const Duration(milliseconds: 450),
      );
    } else {
      await controller.moveCamera(update);
    }
  }

  Future<void> _syncAnnotations({bool force = false}) async {
    final controller = _controller;
    if (controller == null) return;

    await _syncStations(controller, force: force);
    await _syncDestination(controller, force: force);
    await _syncRoute(controller, force: force);
  }

  Future<void> _syncStations(
    MapLibreMapController controller, {
    required bool force,
  }) async {
    final key =
        '${widget.map.name}:${widget.pointsOfInterest.length}:${widget.pointsOfInterest.map((poi) => poi.kind).join(',')}';
    if (!force && key == _lastStationKey) return;
    _lastStationKey = key;
    _lastDestinationKey = null;

    await controller.clearCircles();

    final pois = widget.pointsOfInterest.take(240).toList();
    final options = <CircleOptions>[];
    final data = <Map<String, dynamic>>[];
    for (var i = 0; i < pois.length; i++) {
      final poi = pois[i];
      options.add(
        CircleOptions(
          geometry: _latLng(poi.position),
          circleColor: _poiColor(poi.kind),
          circleRadius: 6.2,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 1.1,
          circleOpacity: 0.96,
        ),
      );
      data.add({'poiIndex': i});
    }

    if (options.isNotEmpty) {
      await controller.addCircles(options, data);
    }
  }

  Future<void> _syncDestination(
    MapLibreMapController controller, {
    required bool force,
  }) async {
    final destination = widget.destination;
    final key = destination == null
        ? 'none'
        : '${destination.dx.toStringAsFixed(6)},${destination.dy.toStringAsFixed(6)}';
    if (!force && key == _lastDestinationKey) return;
    _lastDestinationKey = key;

    final stationCount = widget.pointsOfInterest.take(240).length;
    if (controller.circles.length > stationCount) {
      await controller.removeCircles(controller.circles.skip(stationCount));
    }

    if (destination == null) return;
    await controller.addCircle(
      CircleOptions(
        geometry: _latLng(destination),
        circleColor: '#39D8B6',
        circleRadius: 8,
        circleStrokeColor: '#022B3A',
        circleStrokeWidth: 2,
      ),
    );
  }

  Future<void> _syncRoute(
    MapLibreMapController controller, {
    required bool force,
  }) async {
    final points = _routePointsFromCar();
    final key = points
        .map(
          (point) =>
              '${point.dx.toStringAsFixed(5)},${point.dy.toStringAsFixed(5)}',
        )
        .join('|');
    if (!force && key == _lastRouteKey) return;
    _lastRouteKey = key;

    await controller.clearLines();
    if (points.length < 2) return;

    await controller.addLine(
      LineOptions(
        geometry: points.map(_latLng).toList(),
        lineColor: '#39D8B6',
        lineWidth: 7,
        lineOpacity: 0.94,
      ),
    );
  }

  List<Offset> _routePointsFromCar() {
    final raw = widget.route?.points;
    if (raw == null || raw.length < 2) return const [];

    final origin = widget.origin;
    if (origin == null) return raw;

    var nearestIndex = 0;
    var best = double.infinity;
    for (var i = 0; i < raw.length; i++) {
      final d = _distanceMeters(origin, raw[i]);
      if (d < best) {
        best = d;
        nearestIndex = i;
      }
    }

    return [origin, ...raw.skip(nearestIndex + 1)];
  }

  double _distanceMeters(Offset a, Offset b) {
    const earthRadius = 6371000.0;
    final lat1 = a.dy * math.pi / 180;
    final lat2 = b.dy * math.pi / 180;
    final dLat = (b.dy - a.dy) * math.pi / 180;
    final dLon = (b.dx - a.dx) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  LatLng _latLng(Offset lonLat) => LatLng(lonLat.dy, lonLat.dx);

  double _zoomForLatSpan(double latSpan) {
    if (latSpan <= 0.004) return 17.4;
    if (latSpan <= 0.012) return 15.8;
    if (latSpan <= 0.03) return 14.5;
    if (latSpan <= 0.06) return 13.5;
    return 12.4;
  }

  String _poiColor(String kind) {
    switch (kind) {
      case 'farmacia':
        return '#F0C56A';
      case 'supermercado':
        return '#C6A9FF';
      case 'posto':
      default:
        return '#31E981';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      key: ValueKey('maplibre-${widget.darkMode}'),
      styleString: MapLibreStyles.openfreemapLiberty,
      initialCameraPosition: CameraPosition(
        target: _latLng(widget.origin ?? widget.map.center),
        zoom: widget.origin == null ? 13.0 : 17.8,
        bearing: widget.origin == null ? 0 : widget.heading ?? 0,
        tilt: widget.origin == null ? 0 : 45,
      ),
      myLocationEnabled: true,
      myLocationRenderMode: MyLocationRenderMode.compass,
      compassEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      trackCameraPosition: true,
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      onCameraMove: (_) => _handleGesture(),
    );
  }
}
