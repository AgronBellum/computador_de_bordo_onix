import 'dart:async';

import 'package:geolocator/geolocator.dart';

class GpsService {
  StreamSubscription<Position>? _positionStream;
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
    Function(double lat, double lng, double distance)? onUpdate,
    Function(Position position)? onPositionReceived,
    Function(Position position)? onPositionIgnored,
    void Function()? onStopped,
    Position? initialPosition,
  }) {
    if (_isTracking) return;

    _isTracking = true;
    _accumulatedDistance = 0;
    _lastPosition = initialPosition;

    final locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
      forceLocationManager: false,
      foregroundNotificationConfig: ForegroundNotificationConfig(
        notificationTitle: 'Computador de bordo ativo',
        notificationText: 'Calculando consumo, distancia e autonomia via GPS.',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        onPositionReceived?.call(position);

        if (position.accuracy > 100) {
          onPositionIgnored?.call(position);
          return;
        }

        if (_lastPosition != null) {
          final distance = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );

          if (distance >= 5.0 && distance <= 500.0) {
            _accumulatedDistance += distance;

            if (!_distanceController.isClosed) {
              _distanceController.add(_accumulatedDistance);
            }

            onUpdate?.call(
              position.latitude,
              position.longitude,
              _accumulatedDistance,
            );
          }
        }

        _lastPosition = position;
      },
      onError: (_) {
        stopTracking();
        onStopped?.call();
      },
      onDone: () {
        stopTracking();
        onStopped?.call();
      },
      cancelOnError: false,
    );
  }

  void stopTracking() {
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
