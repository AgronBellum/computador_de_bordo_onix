import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_map.dart';
import '../models/trip_model.dart';
import '../services/audio_alert_service.dart';
import '../services/database_service.dart';
import '../services/gps_service.dart';

class AppProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final GpsService _gps = GpsService();
  final AudioAlertService _audio = AudioAlertService();

  TripModel? _activeTrip;
  List<TripModel> _trips = [];
  bool _isGpsTracking = false;
  String _statusMessage = '';
  bool _isLoading = true;
  bool _isDarkMode = true;
  bool _soundsEnabled = true;
  bool _autoGpsStarting = false;
  bool _lowFuelAlertPlayed = false;
  bool _reserveFuelAlertPlayed = false;
  bool _fullFuelAlertReady = true;
  bool _hundredKmAlertPlayed = false;
  bool _thirtyMinuteAlertPlayed = false;
  bool _suppressNextGpsConnectedAudio = false;
  bool _gpsStoppedByUser = false;
  double _gpsDistance = 0;
  int _gpsUpdateCount = 0;
  int _smartGpsAutoAttempts = 0;
  int _gpsRawPositionCount = 0;
  int _gpsIgnoredPositionCount = 0;
  double? _lastGpsAccuracy;
  double? _lastGpsMovementMeters;
  double? _lastGpsLatitude;
  double? _lastGpsLongitude;
  double? _lastGpsHeading;
  Timer? _startupCareTimer;
  Timer? _thirtyMinuteTripTimer;
  Timer? _gpsWatchdogTimer;
  Timer? _smartGpsStartTimer;
  DateTime? _lastGpsPositionAt;
  double _cityConsumption = 9.0;
  double _tripConsumption = 12.0;
  double _fuelPrice = 5.79;
  double _tankCapacityLiters = 0;
  String _drivingMode = 'city';
  String _vehicleName = 'ONIX';
  String _mapVehicleIcon = 'arrow';
  OfflineRoute? _activeNavigationRoute;
  MapDestination? _activeNavigationDestination;

  double? _lastRemainingFuel;
  double? _lastOdometer;
  double? _lastConsumption;

  TripModel? get activeTrip => _activeTrip;
  List<TripModel> get trips => _trips;
  bool get isGpsTracking => _isGpsTracking;
  String get statusMessage => _statusMessage;
  bool get isLoading => _isLoading;
  bool get isDarkMode => _isDarkMode;
  bool get soundsEnabled => _soundsEnabled;
  double get gpsDistance => _gpsDistance;
  int get gpsUpdateCount => _gpsUpdateCount;
  int get gpsRawPositionCount => _gpsRawPositionCount;
  int get gpsIgnoredPositionCount => _gpsIgnoredPositionCount;
  double? get lastGpsAccuracy => _lastGpsAccuracy;
  double? get lastGpsMovementMeters => _lastGpsMovementMeters;
  double? get lastGpsLatitude => _lastGpsLatitude;
  double? get lastGpsLongitude => _lastGpsLongitude;
  double? get lastGpsHeading => _lastGpsHeading;
  double get cityConsumption => _cityConsumption;
  double get tripConsumption => _tripConsumption;
  double get fuelPrice => _fuelPrice;
  double get tankCapacityLiters => _tankCapacityLiters;
  String get drivingMode => _drivingMode;
  String get vehicleName => _vehicleName;
  String get mapVehicleIcon => _mapVehicleIcon;
  OfflineRoute? get activeNavigationRoute => _activeNavigationRoute;
  MapDestination? get activeNavigationDestination =>
      _activeNavigationDestination;
  bool get isCityMode => _drivingMode == 'city';
  double get selectedConsumption =>
      isCityMode ? _cityConsumption : _tripConsumption;
  double? get lastRemainingFuel => _lastRemainingFuel;
  double? get lastOdometer => _lastOdometer;
  double? get lastConsumption => _lastConsumption;

  double get fuelPercentage {
    if (_activeTrip == null) return 0;

    final fuelReference = _tankCapacityLiters > 0
        ? _tankCapacityLiters
        : _activeTrip!.litersAdded;

    if (fuelReference <= 0) return 0;

    final pct = _activeTrip!.remainingFuel / fuelReference;
    return pct.clamp(0.0, 1.0);
  }

  AppProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadThemeMode();
    await _loadDashboardSettings();
    await _loadRefuelData();
    await _loadTrips();
    await _restoreLastOdometer();
    _syncTripAlertState();
    await _audio.playStartupGreeting();
    _scheduleStartupCareAudio();
    _scheduleThirtyMinuteTripAudio();

    _isLoading = false;
    notifyListeners();

    _scheduleSmartGpsAutoStart();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('is_dark_mode') ?? true;
  }

  Future<void> _loadDashboardSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _cityConsumption = prefs.getDouble('city_consumption') ?? 9.0;
    _tripConsumption = prefs.getDouble('trip_consumption') ?? 12.0;
    _fuelPrice = prefs.getDouble('fuel_price') ?? 5.79;
    _tankCapacityLiters = prefs.getDouble('tank_capacity_liters') ?? 0;
    _soundsEnabled = prefs.getBool('sounds_enabled') ?? true;
    _audio.setEnabled(_soundsEnabled);
    _drivingMode = prefs.getString('driving_mode') ?? 'city';
    _vehicleName = prefs.getString('vehicle_name') ?? 'ONIX';
    _mapVehicleIcon = prefs.getString('map_vehicle_icon') ?? 'arrow';
  }

  Future<void> saveDashboardSettings({
    required double cityConsumption,
    required double tripConsumption,
    required double fuelPrice,
    required double tankCapacityLiters,
    required bool soundsEnabled,
    required String vehicleName,
    required String mapVehicleIcon,
  }) async {
    _cityConsumption = cityConsumption;
    _tripConsumption = tripConsumption;
    _fuelPrice = fuelPrice;
    _tankCapacityLiters = tankCapacityLiters > 0 ? tankCapacityLiters : 0;
    _soundsEnabled = soundsEnabled;
    _audio.setEnabled(_soundsEnabled);
    _vehicleName = vehicleName.trim().isEmpty ? 'ONIX' : vehicleName.trim();
    _mapVehicleIcon = mapVehicleIcon;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('city_consumption', _cityConsumption);
    await prefs.setDouble('trip_consumption', _tripConsumption);
    await prefs.setDouble('fuel_price', _fuelPrice);
    await prefs.setDouble('tank_capacity_liters', _tankCapacityLiters);
    await prefs.setBool('sounds_enabled', _soundsEnabled);
    await prefs.setString('vehicle_name', _vehicleName);
    await prefs.setString('map_vehicle_icon', _mapVehicleIcon);

    await applySelectedConsumption();
    await _audio.playSettingsSaved();
    await _checkFuelLevelAlerts();
    notifyListeners();
  }

  Future<void> setDrivingMode(String mode) async {
    if (mode != 'city' && mode != 'trip') return;
    if (_drivingMode == mode) return;

    _drivingMode = mode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('driving_mode', _drivingMode);

    await applySelectedConsumption();
    if (_drivingMode == 'city') {
      await _audio.playCityMode();
    } else {
      await _audio.playTripMode();
    }
    notifyListeners();
  }

  void setActiveNavigationRoute({
    required OfflineRoute route,
    required MapDestination destination,
  }) {
    _activeNavigationRoute = route;
    _activeNavigationDestination = destination;
    notifyListeners();
  }

  void clearActiveNavigationRoute() {
    if (_activeNavigationRoute == null &&
        _activeNavigationDestination == null) {
      return;
    }

    _activeNavigationRoute = null;
    _activeNavigationDestination = null;
    notifyListeners();
  }

  Future<void> applySelectedConsumption() async {
    if (_activeTrip == null || selectedConsumption <= 0) return;

    _activeTrip = _activeTrip!.withConsumption(selectedConsumption);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();
  }

  Future<void> toggleThemeMode() async {
    _isDarkMode = !_isDarkMode;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);

    notifyListeners();
  }

  Future<void> _loadTrips() async {
    _trips = await _db.getAllTrips();
    _activeTrip = await _db.getActiveTrip();

    if (_activeTrip != null) {
      _lastRemainingFuel = _activeTrip!.remainingFuel;
      _lastOdometer = _activeTrip!.currentOdometer;
      _lastConsumption = _activeTrip!.consumptionPerKm;
    }

    notifyListeners();
  }

  Future<void> _loadRefuelData() async {
    final prefs = await SharedPreferences.getInstance();

    _lastRemainingFuel = prefs.getDouble('last_remaining_fuel');
    _lastOdometer = prefs.getDouble('last_odometer');
    _lastConsumption = prefs.getDouble('last_consumption');
  }

  Future<void> _saveRefuelData() async {
    final prefs = await SharedPreferences.getInstance();

    if (_activeTrip != null) {
      await prefs.setDouble(
        'last_remaining_fuel',
        _activeTrip!.remainingFuel,
      );
      await prefs.setDouble(
        'last_odometer',
        _activeTrip!.currentOdometer,
      );
      await prefs.setDouble(
        'last_consumption',
        _activeTrip!.consumptionPerKm,
      );
    }
  }

  Future<void> _saveLastOdometer(double odometer) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble('last_odometer', odometer);
    await prefs.setString(
      'last_odometer_time',
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> _restoreLastOdometer() async {
    if (_activeTrip == null) return;

    final prefs = await SharedPreferences.getInstance();
    final savedOdometer = prefs.getDouble('last_odometer');
    final savedTime = prefs.getString('last_odometer_time');

    if (savedOdometer != null && savedTime != null) {
      final lastTime = DateTime.parse(savedTime);
      final diff = DateTime.now().difference(lastTime);

      if (diff.inSeconds > 30) {
        if (_activeTrip!.currentOdometer < savedOdometer) {
          _activeTrip!.currentOdometer = savedOdometer;
          await _db.updateTrip(_activeTrip!);
          await _saveRefuelData();
        }

        _statusMessage =
            'Viagem retomada - carro desligado por ${diff.inMinutes}min';
      }
    }

    await _saveLastOdometer(_activeTrip!.currentOdometer);
  }

  Future<void> createTrip({
    required double liters,
    required double consumption,
    required double odometer,
  }) async {
    if (liters <= 0 || consumption <= 0) {
      _statusMessage = 'Litros e consumo devem ser maiores que zero';
      notifyListeners();
      return;
    }

    final totalRange = liters * consumption;

    final trip = TripModel(
      litersAdded: liters,
      consumptionPerKm: consumption,
      initialOdometer: odometer,
      currentOdometer: odometer,
      remainingFuel: liters,
      estimatedRange: totalRange,
      createdAt: DateTime.now(),
    );

    final saved = await _db.createTrip(trip);

    _activeTrip = saved;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _smartGpsAutoAttempts = 0;
    _resetTripAlertState();
    _statusMessage = 'Abastecimento iniciado';

    await _saveLastOdometer(odometer);
    await _saveRefuelData();
    await _loadTrips();

    notifyListeners();
    await _audio.playRefuelRecalculated();
    _syncTripAlertState();
    _scheduleThirtyMinuteTripAudio();
    _gpsStoppedByUser = false;
    _suppressNextGpsConnectedAudio = true;
    _scheduleSmartGpsAutoStart();
  }

  Future<void> refuel({
    required double newLiters,
    required double consumption,
    required double odometer,
    double? previousRemaining,
  }) async {
    if (newLiters <= 0 || consumption <= 0) {
      _statusMessage = 'Litros e consumo devem ser maiores que zero';
      notifyListeners();
      return;
    }

    double remainingFuel = previousRemaining ?? 0;

    if (remainingFuel <= 0 && _activeTrip != null) {
      remainingFuel = _activeTrip!.remainingFuel;
    }

    if (remainingFuel <= 0 && _lastRemainingFuel != null) {
      remainingFuel = _lastRemainingFuel!;
    }

    final totalFuel = remainingFuel + newLiters;
    final totalRange = totalFuel * consumption;

    if (_activeTrip != null) {
      _gps.stopTracking();
      _isGpsTracking = false;

      await _saveRefuelData();
      await _db.endTrip(_activeTrip!.id!);
    }

    final trip = TripModel(
      litersAdded: totalFuel,
      consumptionPerKm: consumption,
      initialOdometer: odometer,
      currentOdometer: odometer,
      remainingFuel: totalFuel,
      estimatedRange: totalRange,
      createdAt: DateTime.now(),
    );

    final saved = await _db.createTrip(trip);

    _activeTrip = saved;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _smartGpsAutoAttempts = 0;
    _resetTripAlertState();
    _statusMessage =
        'Reabastecido: ${newLiters.toStringAsFixed(1)}L + ${remainingFuel.toStringAsFixed(1)}L restantes';

    await _saveLastOdometer(odometer);
    await _saveRefuelData();
    await _loadTrips();

    notifyListeners();
    await _audio.playRefuelRecalculated();
    _syncTripAlertState();
    _scheduleThirtyMinuteTripAudio();
    _gpsStoppedByUser = false;
    _suppressNextGpsConnectedAudio = true;
    _scheduleSmartGpsAutoStart();
  }

  void _scheduleSmartGpsAutoStart({
    Duration delay = const Duration(seconds: 3),
  }) {
    _smartGpsStartTimer?.cancel();

    if (_activeTrip == null || _isGpsTracking || _gpsStoppedByUser) return;
    if (_smartGpsAutoAttempts >= 5) {
      _statusMessage = 'GPS automatico sem sinal - toque para iniciar';
      notifyListeners();
      return;
    }

    _statusMessage = 'GPS automatico preparando sinal...';
    notifyListeners();

    _smartGpsStartTimer = Timer(delay, () async {
      await _trySmartGpsAutoStart();
    });
  }

  Future<void> _trySmartGpsAutoStart() async {
    if (_activeTrip == null || _isGpsTracking || _gpsStoppedByUser) return;
    if (_autoGpsStarting) return;

    _autoGpsStarting = true;
    _smartGpsAutoAttempts++;

    try {
      await startGpsTracking(automatic: true);
    } finally {
      _autoGpsStarting = false;
    }

    if (!_isGpsTracking && !_gpsStoppedByUser && _activeTrip != null) {
      _scheduleSmartGpsAutoStart(delay: const Duration(seconds: 12));
    }
  }

  Future<void> updateOdometer(double newOdometer) async {
    if (_activeTrip == null) return;

    if (newOdometer < _activeTrip!.currentOdometer) {
      _statusMessage = 'KM não pode ser menor que o atual';
      notifyListeners();
      return;
    }

    _activeTrip!.updateFromManualOdometer(newOdometer);

    await _db.updateTrip(_activeTrip!);
    await _saveLastOdometer(newOdometer);
    await _saveRefuelData();

    _statusMessage = 'KM atualizado: ${newOdometer.toStringAsFixed(0)}';

    notifyListeners();
    await _audio.playManualNumbers();
    await _checkDashboardAudioAlerts();
    await _restartGpsTrackingFromCurrentTrip();
  }

  Future<void> setCurrentOdometer(double odometer) async {
    if (_activeTrip == null) return;

    _activeTrip = _activeTrip!.withCurrentOdometer(odometer);
    await _db.updateTrip(_activeTrip!);
    await _saveLastOdometer(odometer);
    await _saveRefuelData();

    _statusMessage = 'KM atual ajustado: ${odometer.toStringAsFixed(0)}';
    notifyListeners();
    await _audio.playManualNumbers();
    await _checkDashboardAudioAlerts();
    await _restartGpsTrackingFromCurrentTrip();
  }

  Future<void> setRemainingFuel(double liters) async {
    if (_activeTrip == null) return;

    _activeTrip = _activeTrip!.withRemainingFuel(liters);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();

    _statusMessage = 'Combustivel ajustado: ${liters.toStringAsFixed(1)}L';
    notifyListeners();
    await _checkFuelLevelAlerts();
  }

  Future<void> setEstimatedRange(double rangeKm) async {
    if (_activeTrip == null) return;

    _activeTrip = _activeTrip!.withEstimatedRange(rangeKm);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();

    _statusMessage = 'Autonomia ajustada: ${rangeKm.toStringAsFixed(0)}km';
    notifyListeners();
  }

  Future<void> setDistanceTraveled(double distanceKm) async {
    if (_activeTrip == null) return;

    _activeTrip = _activeTrip!.withDistanceTraveled(distanceKm);
    await _db.updateTrip(_activeTrip!);
    await _saveLastOdometer(_activeTrip!.currentOdometer);
    await _saveRefuelData();

    _statusMessage = 'Distancia ajustada: ${distanceKm.toStringAsFixed(1)}km';
    notifyListeners();
    await _checkDashboardAudioAlerts();
    await _restartGpsTrackingFromCurrentTrip();
  }

  Future<void> setConsumption(double consumption) async {
    if (_activeTrip == null || consumption <= 0) return;

    _activeTrip = _activeTrip!.withConsumption(consumption);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();

    _statusMessage = 'Consumo ajustado: ${consumption.toStringAsFixed(1)}km/L';
    notifyListeners();
  }

  Future<void> startGpsTracking({bool automatic = false}) async {
    if (!automatic) {
      _gpsStoppedByUser = false;
      _smartGpsStartTimer?.cancel();
    }

    if (_isGpsTracking && _gps.isTracking) return;

    final suppressGpsConnectedAudio = _suppressNextGpsConnectedAudio;

    if (_activeTrip == null) {
      _statusMessage = 'Inicie um abastecimento primeiro';
      notifyListeners();
      return;
    }

    final hasPermission = await _gps.requestPermission();

    if (!hasPermission) {
      _statusMessage = 'Permissão de GPS negada - verifique configurações';
      notifyListeners();
      return;
    }

    final initialPos = await _gps.getCurrentPosition();

    if (initialPos == null) {
      _statusMessage = automatic
          ? 'GPS ainda sem sinal - toque para iniciar quando estiver pronto'
          : 'GPS indisponivel - aguardando sinal...';
      notifyListeners();
      return;
    }

    _isGpsTracking = true;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _gpsRawPositionCount = 0;
    _gpsIgnoredPositionCount = 0;
    _smartGpsAutoAttempts = 0;
    _lastGpsAccuracy = initialPos.accuracy;
    _lastGpsMovementMeters = null;
    _lastGpsLatitude = initialPos.latitude;
    _lastGpsLongitude = initialPos.longitude;
    _lastGpsHeading = initialPos.heading >= 0 ? initialPos.heading : null;
    _lastGpsPositionAt = DateTime.now();
    _statusMessage = 'GPS ativo - sinal OK, rastreando...';
    _suppressNextGpsConnectedAudio = false;

    notifyListeners();
    if (!suppressGpsConnectedAudio) {
      await _audio.playGpsConnected();
    }

    _gps.startTracking(
      initialPosition: initialPos,
      onPositionReceived: (position) {
        _gpsRawPositionCount++;
        _lastGpsAccuracy = position.accuracy;
        _lastGpsHeading = _headingForPosition(position);
        _lastGpsLatitude = position.latitude;
        _lastGpsLongitude = position.longitude;
        _lastGpsPositionAt = DateTime.now();
        _checkNavigationArrival(position.latitude, position.longitude);
        if (_gpsRawPositionCount == 1) {
          _statusMessage = 'GPS recebendo posicoes: $_gpsRawPositionCount';
          notifyListeners();
        }
      },
      onMovementMeasured: (position, movementMeters) {
        _lastGpsMovementMeters = movementMeters;
        if (_gpsRawPositionCount % 5 == 0) {
          _statusMessage = 'GPS recebendo posicoes: $_gpsRawPositionCount';
          notifyListeners();
        }
      },
      onPositionIgnored: (position, reason) {
        _gpsIgnoredPositionCount++;
        _lastGpsAccuracy = position.accuracy;
        _lastGpsHeading = _headingForPosition(position);
        _lastGpsLatitude = position.latitude;
        _lastGpsLongitude = position.longitude;
        _statusMessage = 'GPS ignorou ponto: $reason';
        notifyListeners();
      },
      onStopped: () {
        _handleGpsStopped();
      },
      onUpdate: (lat, lng, distance, deltaMeters) async {
        if (_activeTrip == null) return;

        _gpsDistance = distance;
        _gpsUpdateCount++;
        _lastGpsHeading = _headingFromCoordinates(
              _lastGpsLatitude,
              _lastGpsLongitude,
              lat,
              lng,
            ) ??
            _lastGpsHeading;
        _lastGpsLatitude = lat;
        _lastGpsLongitude = lng;
        _checkNavigationArrival(lat, lng);

        final deltaKm = deltaMeters / 1000;
        final newOdometer = _activeTrip!.currentOdometer + deltaKm;
        _activeTrip!.updateFromGps(newOdometer, lat, lng);

        _statusMessage = 'GPS: +${deltaKm.toStringAsFixed(3)}km | '
            'Total: ${_activeTrip!.distanceTraveled.toStringAsFixed(1)}km | '
            'Atualizacoes: $_gpsUpdateCount';

        await _db.updateTrip(_activeTrip!);
        await _saveLastOdometer(newOdometer);
        await _saveRefuelData();

        await _db.addGpsPoint(
          _activeTrip!.id!,
          GpsPoint(
            latitude: lat,
            longitude: lng,
            odometer: newOdometer,
            timestamp: DateTime.now(),
          ),
        );

        notifyListeners();
        await _checkDashboardAudioAlerts();
      },
    );

    _startGpsWatchdog();
  }

  Future<void> _restartGpsTrackingFromCurrentTrip() async {
    if (_activeTrip == null || !_isGpsTracking) return;

    _gps.stopTracking();
    _isGpsTracking = false;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _gpsRawPositionCount = 0;
    _gpsIgnoredPositionCount = 0;
    _lastGpsAccuracy = null;
    _lastGpsMovementMeters = null;
    _lastGpsLatitude = null;
    _lastGpsLongitude = null;
    _lastGpsHeading = null;
    _suppressNextGpsConnectedAudio = true;

    await startGpsTracking();
  }

  Future<void> reconnectGpsTracking() async {
    if (_activeTrip == null) return;

    _gps.stopTracking();
    _isGpsTracking = false;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _gpsRawPositionCount = 0;
    _gpsIgnoredPositionCount = 0;
    _lastGpsAccuracy = null;
    _lastGpsMovementMeters = null;
    _lastGpsLatitude = null;
    _lastGpsLongitude = null;
    _lastGpsHeading = null;
    _lastGpsPositionAt = null;
    _suppressNextGpsConnectedAudio = false;
    _statusMessage = 'Reconectando GPS...';
    notifyListeners();

    await startGpsTracking();
  }

  double? _headingForPosition(Position position) {
    if (position.heading >= 0) return position.heading;
    return _headingFromCoordinates(
      _lastGpsLatitude,
      _lastGpsLongitude,
      position.latitude,
      position.longitude,
    );
  }

  double? _headingFromCoordinates(
    double? fromLat,
    double? fromLon,
    double toLat,
    double toLon,
  ) {
    if (fromLat == null || fromLon == null) return null;
    if (fromLat == toLat && fromLon == toLon) return null;

    final lat1 = fromLat * math.pi / 180;
    final lat2 = toLat * math.pi / 180;
    final deltaLon = (toLon - fromLon) * math.pi / 180;
    final y = math.sin(deltaLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  void _checkNavigationArrival(double lat, double lon) {
    final destination = _activeNavigationDestination;
    if (destination == null || _activeNavigationRoute == null) return;

    final meters = Geolocator.distanceBetween(
      lat,
      lon,
      destination.position.dy,
      destination.position.dx,
    );
    if (meters > 35) return;

    _activeNavigationRoute = null;
    _activeNavigationDestination = null;
    _statusMessage = 'Destino alcancado';
    notifyListeners();
  }

  void _startGpsWatchdog() {
    _gpsWatchdogTimer?.cancel();
    _gpsWatchdogTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_activeTrip == null) return;

      if (!_gps.isTracking) {
        _handleGpsStopped();
        return;
      }

      final lastPositionAt = _lastGpsPositionAt;
      if (lastPositionAt == null) return;

      final silence = DateTime.now().difference(lastPositionAt);
      if (silence.inSeconds >= 90) {
        _statusMessage = 'GPS ativo, mas sem novas posicoes ha '
            '${silence.inSeconds}s';
        notifyListeners();
      }
    });
  }

  void _handleGpsStopped() {
    if (!_isGpsTracking) return;

    _isGpsTracking = false;
    _statusMessage = _gpsStoppedByUser
        ? 'GPS pausado pelo usuario'
        : 'GPS parou - tentando iniciar novamente em alguns segundos';
    notifyListeners();

    if (!_gpsStoppedByUser) {
      _scheduleSmartGpsAutoStart(delay: const Duration(seconds: 12));
    }
  }

  void _resetTripAlertState() {
    _lowFuelAlertPlayed = false;
    _reserveFuelAlertPlayed = false;
    _fullFuelAlertReady = true;
    _hundredKmAlertPlayed = false;
    _thirtyMinuteAlertPlayed = false;
  }

  void _syncTripAlertState() {
    if (_activeTrip == null) {
      _resetTripAlertState();
      return;
    }

    _lowFuelAlertPlayed = fuelPercentage <= 0.18;
    _reserveFuelAlertPlayed = fuelPercentage <= 0.16;
    _fullFuelAlertReady = fuelPercentage < 1.0;
    _hundredKmAlertPlayed = _activeTrip!.distanceTraveled >= 100;
    _thirtyMinuteAlertPlayed =
        DateTime.now().difference(_activeTrip!.createdAt).inMinutes >= 30;
  }

  void _scheduleStartupCareAudio() {
    _startupCareTimer?.cancel();
    _startupCareTimer = Timer(const Duration(minutes: 1), () {
      _audio.playStartupCare();
    });
  }

  void _scheduleThirtyMinuteTripAudio() {
    _thirtyMinuteTripTimer?.cancel();

    if (_activeTrip == null || _thirtyMinuteAlertPlayed) return;

    final elapsed = DateTime.now().difference(_activeTrip!.createdAt);
    final remaining = const Duration(minutes: 30) - elapsed;

    if (remaining <= Duration.zero) {
      _thirtyMinuteAlertPlayed = true;
      _audio.playThirtyMinuteTrip();
      return;
    }

    _thirtyMinuteTripTimer = Timer(remaining, () {
      if (_activeTrip == null || _thirtyMinuteAlertPlayed) return;

      _thirtyMinuteAlertPlayed = true;
      _audio.playThirtyMinuteTrip();
    });
  }

  Future<void> _checkDashboardAudioAlerts() async {
    await _checkFuelLevelAlerts();
    await _checkHundredKmAlert();
    await _checkThirtyMinuteTripAlert();
  }

  Future<void> _checkFuelLevelAlerts() async {
    if (_activeTrip == null) return;

    final pct = fuelPercentage;

    if (pct < 1.0) {
      _fullFuelAlertReady = true;
    }

    if (pct >= 1.0 && _fullFuelAlertReady) {
      _fullFuelAlertReady = false;
      await _audio.playFullFuel();
    }

    if (pct > 0.20) {
      _lowFuelAlertPlayed = false;
      _reserveFuelAlertPlayed = false;
      return;
    }

    if (pct <= 0.18 && !_lowFuelAlertPlayed) {
      _lowFuelAlertPlayed = true;
      await _audio.playLowFuel();
    }

    if (pct <= 0.16 && !_reserveFuelAlertPlayed) {
      _reserveFuelAlertPlayed = true;
      await _audio.playReserveFuel();
    }
  }

  Future<void> _checkHundredKmAlert() async {
    if (_activeTrip == null || _hundredKmAlertPlayed) return;
    if (_activeTrip!.distanceTraveled < 100) return;

    _hundredKmAlertPlayed = true;
    await _audio.playHundredKmPosto();
  }

  Future<void> _checkThirtyMinuteTripAlert() async {
    if (_activeTrip == null || _thirtyMinuteAlertPlayed) return;

    final elapsed = DateTime.now().difference(_activeTrip!.createdAt);
    if (elapsed.inMinutes < 30) return;

    _thirtyMinuteAlertPlayed = true;
    await _audio.playThirtyMinuteTrip();
  }

  Future<void> stopGpsTracking() async {
    _gpsStoppedByUser = true;
    _smartGpsStartTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gps.stopTracking();

    if (_activeTrip != null) {
      await _db.updateTrip(_activeTrip!);
      await _saveRefuelData();
    }

    _isGpsTracking = false;
    _statusMessage =
        'GPS pausado - percorrido: ${_gpsDistance.toStringAsFixed(0)}m';

    notifyListeners();
  }

  Future<void> endCurrentTrip() async {
    if (_activeTrip == null) return;

    _lastRemainingFuel = _activeTrip!.remainingFuel;
    _lastOdometer = _activeTrip!.currentOdometer;
    _lastConsumption = _activeTrip!.consumptionPerKm;

    await _saveRefuelData();

    _gps.stopTracking();
    _isGpsTracking = false;
    _gpsWatchdogTimer?.cancel();
    _smartGpsStartTimer?.cancel();

    await _db.updateTrip(_activeTrip!);
    await _db.endTrip(_activeTrip!.id!);

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_odometer_time');

    _activeTrip = null;
    _gpsDistance = 0;
    _gpsUpdateCount = 0;
    _thirtyMinuteTripTimer?.cancel();
    _resetTripAlertState();
    _statusMessage = 'Viagem finalizada';

    notifyListeners();
  }

  Future<void> deleteTrip(int id) async {
    await _db.deleteTrip(id);
    await _loadTrips();
  }

  @override
  void dispose() {
    _startupCareTimer?.cancel();
    _thirtyMinuteTripTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _smartGpsStartTimer?.cancel();
    _gps.dispose();
    _audio.dispose();
    super.dispose();
  }
}
