class TripModel {
  final int? id;
  final double litersAdded;

  // Este valor representa km/L
  final double consumptionPerKm;

  final double initialOdometer;
  double currentOdometer;
  double distanceTraveled;
  final DateTime createdAt;
  final DateTime? endedAt;
  bool isActive;
  double remainingFuel;
  double estimatedRange;
  List<GpsPoint> gpsPoints;

  TripModel({
    this.id,
    required this.litersAdded,
    required this.consumptionPerKm,
    required this.initialOdometer,
    this.currentOdometer = 0,
    this.distanceTraveled = 0,
    required this.createdAt,
    this.endedAt,
    this.isActive = true,
    this.remainingFuel = 0,
    this.estimatedRange = 0,
    List<GpsPoint>? gpsPoints,
  }) : gpsPoints = gpsPoints ?? [];

  double get totalRange {
    if (consumptionPerKm <= 0) return 0;
    return litersAdded * consumptionPerKm;
  }

  void _recalculateFuel() {
    if (consumptionPerKm <= 0) {
      remainingFuel = 0;
      estimatedRange = 0;
      return;
    }

    final fuelConsumed = distanceTraveled / consumptionPerKm;

    remainingFuel = litersAdded - fuelConsumed;

    if (remainingFuel < 0) {
      remainingFuel = 0;
    }

    estimatedRange = remainingFuel * consumptionPerKm;

    if (estimatedRange < 0) {
      estimatedRange = 0;
    }
  }

  void updateFromGps(double newOdometer, double lat, double lng) {
    if (newOdometer > currentOdometer) {
      final delta = newOdometer - currentOdometer;

      distanceTraveled += delta;
      currentOdometer = newOdometer;

      _recalculateFuel();
    }

    gpsPoints.add(
      GpsPoint(
        latitude: lat,
        longitude: lng,
        odometer: newOdometer,
        timestamp: DateTime.now(),
      ),
    );
  }

  void updateFromManualOdometer(double newOdometer) {
    if (newOdometer > currentOdometer) {
      final delta = newOdometer - currentOdometer;

      distanceTraveled += delta;
      currentOdometer = newOdometer;

      _recalculateFuel();
    }
  }

  TripModel copyWith({
    int? id,
    double? litersAdded,
    double? consumptionPerKm,
    double? initialOdometer,
    double? currentOdometer,
    double? distanceTraveled,
    DateTime? createdAt,
    DateTime? endedAt,
    bool? isActive,
    double? remainingFuel,
    double? estimatedRange,
    List<GpsPoint>? gpsPoints,
  }) {
    return TripModel(
      id: id ?? this.id,
      litersAdded: litersAdded ?? this.litersAdded,
      consumptionPerKm: consumptionPerKm ?? this.consumptionPerKm,
      initialOdometer: initialOdometer ?? this.initialOdometer,
      currentOdometer: currentOdometer ?? this.currentOdometer,
      distanceTraveled: distanceTraveled ?? this.distanceTraveled,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      isActive: isActive ?? this.isActive,
      remainingFuel: remainingFuel ?? this.remainingFuel,
      estimatedRange: estimatedRange ?? this.estimatedRange,
      gpsPoints: gpsPoints ?? this.gpsPoints,
    );
  }

  TripModel withConsumption(double newConsumption) {
    final updated = copyWith(consumptionPerKm: newConsumption);
    updated._recalculateFuel();
    return updated;
  }

  TripModel withRemainingFuel(double liters) {
    final safeLiters = liters < 0 ? 0.0 : liters;
    return copyWith(
      remainingFuel: safeLiters,
      estimatedRange: safeLiters * consumptionPerKm,
    );
  }

  TripModel withEstimatedRange(double rangeKm) {
    final safeRange = rangeKm < 0 ? 0.0 : rangeKm;
    final liters = consumptionPerKm > 0 ? safeRange / consumptionPerKm : 0.0;
    return copyWith(
      remainingFuel: liters,
      estimatedRange: safeRange,
    );
  }

  TripModel withCurrentOdometer(double odometer) {
    final safeDistance = odometer - initialOdometer;
    final updated = copyWith(
      currentOdometer: odometer,
      distanceTraveled: safeDistance < 0 ? 0 : safeDistance,
    );
    updated._recalculateFuel();
    return updated;
  }

  TripModel withDistanceTraveled(double distanceKm) {
    final safeDistance = distanceKm < 0 ? 0.0 : distanceKm;
    final updated = copyWith(
      distanceTraveled: safeDistance,
      currentOdometer: initialOdometer + safeDistance,
    );
    updated._recalculateFuel();
    return updated;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'litersAdded': litersAdded,
      'consumptionPerKm': consumptionPerKm,
      'initialOdometer': initialOdometer,
      'currentOdometer': currentOdometer,
      'distanceTraveled': distanceTraveled,
      'createdAt': createdAt.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'isActive': isActive ? 1 : 0,
      'remainingFuel': remainingFuel,
      'estimatedRange': estimatedRange,
    };
  }

  factory TripModel.fromMap(Map<String, dynamic> map) {
    return TripModel(
      id: map['id'] as int?,
      litersAdded: (map['litersAdded'] as num).toDouble(),
      consumptionPerKm: (map['consumptionPerKm'] as num).toDouble(),
      initialOdometer: (map['initialOdometer'] as num).toDouble(),
      currentOdometer: (map['currentOdometer'] as num).toDouble(),
      distanceTraveled: (map['distanceTraveled'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      endedAt: map['endedAt'] != null
          ? DateTime.parse(map['endedAt'] as String)
          : null,
      isActive: map['isActive'] == 1,
      remainingFuel: (map['remainingFuel'] as num).toDouble(),
      estimatedRange: (map['estimatedRange'] as num).toDouble(),
    );
  }
}

class GpsPoint {
  final double latitude;
  final double longitude;
  final double odometer;
  final DateTime timestamp;

  GpsPoint({
    required this.latitude,
    required this.longitude,
    required this.odometer,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'odometer': odometer,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GpsPoint.fromMap(Map<String, dynamic> map) {
    return GpsPoint(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      odometer: (map['odometer'] as num).toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
