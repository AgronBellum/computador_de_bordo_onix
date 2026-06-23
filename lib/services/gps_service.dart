import 'dart:async';

import 'package:geolocator/geolocator.dart';

class GpsService {
  StreamSubscription<Position>? _positionStream;
  Timer? _pollingTimer;
  Position? _lastPosition;

  double _accumulatedDistance = 0;
  bool _isTracking = false;

  final StreamController<double> _distanceController =
      StreamController<double>.broadcast();

  Stream<double> get distanceStream => _distanceController.stream;

  bool get isTracking => _isTracking;
  double get accumulatedDistance => _accumulatedDistance;

  Future<bool> requestPermission() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();

      serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return false;
      }
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      return null;
    }
  }

  void startTracking({
    Function(
      double lat,
      double lng,
      double totalDistanceMeters,
      double deltaMeters,
    )? onUpdate,
    Function(Position position)? onPositionReceived,
    Function(Position position, String reason)? onPositionIgnored,
    Function(Position position, double movementMeters)? onMovementMeasured,
    void Function()? onStopped,
    Position? initialPosition,
  }) {
    if (_isTracking) return;

    _isTracking = true;
    _accumulatedDistance = 0;
    _lastPosition = initialPosition;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
      forceLocationManager: true,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Computador de bordo ativo',
        notificationText: 'Calculando consumo, distancia e autonomia via GPS.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    void handlePosition(Position position) {
      onPositionReceived?.call(position);

      if (position.accuracy > 200) {
        onPositionIgnored?.call(
          position,
          'sinal fraco (${position.accuracy.toStringAsFixed(0)}m)',
        );
      }

      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        onMovementMeasured?.call(position, distance);

        if (distance >= 3.0 && distance <= 1000.0) {
          _accumulatedDistance += distance;

          if (!_distanceController.isClosed) {
            _distanceController.add(_accumulatedDistance);
          }

          onUpdate?.call(
            position.latitude,
            position.longitude,
            _accumulatedDistance,
            distance,
          );
        } else if (distance > 1000.0) {
          onPositionIgnored?.call(
            position,
            'salto GPS (${distance.toStringAsFixed(0)}m)',
          );
        }
      }

      _lastPosition = position;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      handlePosition,
      onError: (_) {
        _positionStream?.cancel();
        _positionStream = null;
      },
      onDone: () {
        _positionStream = null;
      },
      cancelOnError: false,
    );

    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isTracking) return;

      final position = await getCurrentPosition();
      if (!_isTracking || position == null) return;

      handlePosition(position);
    });
  }

  void stopTracking() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _positionStream?.cancel();
    _positionStream = null;
    _isTracking = false;
    _lastPosition = null;
  }

  void reset() {
    _accumulatedDistance = 0;
    _lastPosition = null;

    if (!_distanceController.isClosed) {
      _distanceController.add(_accumulatedDistance);
    }
  }

  void dispose() {
    stopTracking();

    if (!_distanceController.isClosed) {
      _distanceController.close();
    }
  }
}
