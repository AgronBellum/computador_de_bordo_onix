import 'dart:ui';

class OfflineMapData {
  const OfflineMapData({
    required this.name,
    required this.source,
    required this.bounds,
    required this.center,
    required this.roads,
    required this.fuelStations,
    this.pointsOfInterest = const [],
  });

  final String name;
  final String source;
  final List<double> bounds;
  final Offset center;
  final List<OfflineRoad> roads;
  final List<FuelStation> fuelStations;
  final List<MapPoi> pointsOfInterest;

  factory OfflineMapData.fromJson(Map<String, dynamic> json) {
    final center = (json['center'] as List).map((v) => v as num).toList();
    final bounds = (json['bounds'] as List).map((v) => v as num).toList();
    final roads = (json['roads'] as List? ?? [])
        .map((road) => OfflineRoad.fromJson(road as Map<String, dynamic>))
        .toList();
    final stations = (json['fuel_stations'] as List? ?? [])
        .map((station) => FuelStation.fromJson(station as Map<String, dynamic>))
        .toList();
    final pois = (json['pois'] as List? ?? [])
        .map((poi) => MapPoi.fromJson(poi as Map<String, dynamic>))
        .toList();

    return OfflineMapData(
      name: (json['name'] as String?) ?? 'Mapa offline',
      source: (json['source'] as String?) ?? 'OpenStreetMap',
      bounds: bounds.map((v) => v.toDouble()).toList(),
      center: Offset(center[1].toDouble(), center[0].toDouble()),
      roads: roads,
      fuelStations: stations,
      pointsOfInterest: [
        ...pois,
        if (pois.where((poi) => poi.kind == 'posto').isEmpty)
          ...stations.map(MapPoi.fromFuelStation),
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'source': source,
      'bounds': bounds,
      'center': [center.dy, center.dx],
      'roads': roads.map((road) => road.toJson()).toList(),
      'fuel_stations': fuelStations.map((station) => station.toJson()).toList(),
      'pois': pointsOfInterest.map((poi) => poi.toJson()).toList(),
    };
  }
}

class MapPoi {
  const MapPoi({
    required this.name,
    required this.kind,
    required this.position,
    this.brand,
  });

  final String name;
  final String kind;
  final String? brand;
  final Offset position;

  factory MapPoi.fromFuelStation(FuelStation station) {
    return MapPoi(
      name: station.name,
      kind: 'posto',
      brand: station.brand,
      position: station.position,
    );
  }

  factory MapPoi.fromJson(Map<String, dynamic> json) {
    final values = json['p'] as List;
    final lat = (values[0] as num).toDouble();
    final lon = (values[1] as num).toDouble();

    return MapPoi(
      name: (json['n'] as String?) ?? 'Local',
      kind: (json['k'] as String?) ?? 'local',
      brand: json['b'] as String?,
      position: Offset(lon, lat),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'n': name,
      'k': kind,
      if (brand != null && brand!.trim().isNotEmpty) 'b': brand,
      'p': [position.dy, position.dx],
    };
  }
}

class OfflineRoad {
  const OfflineRoad({
    required this.rank,
    required this.points,
    this.name,
  });

  final int rank;
  final String? name;
  final List<Offset> points;

  factory OfflineRoad.fromJson(Map<String, dynamic> json) {
    final points = (json['p'] as List).map((point) {
      final values = point as List;
      final lat = (values[0] as num).toDouble();
      final lon = (values[1] as num).toDouble();
      return Offset(lon, lat);
    }).toList();

    return OfflineRoad(
      rank: (json['r'] as num?)?.toInt() ?? 1,
      name: json['n'] as String?,
      points: points,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'r': rank,
      if (name != null && name!.trim().isNotEmpty) 'n': name,
      'p': points.map((point) => [point.dy, point.dx]).toList(),
    };
  }
}

class FuelStation {
  const FuelStation({
    required this.name,
    required this.position,
    this.brand,
  });

  final String name;
  final String? brand;
  final Offset position;

  factory FuelStation.fromJson(Map<String, dynamic> json) {
    final values = json['p'] as List;
    final lat = (values[0] as num).toDouble();
    final lon = (values[1] as num).toDouble();

    return FuelStation(
      name: (json['n'] as String?) ?? 'Posto',
      brand: json['b'] as String?,
      position: Offset(lon, lat),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'n': name,
      if (brand != null && brand!.trim().isNotEmpty) 'b': brand,
      'p': [position.dy, position.dx],
    };
  }
}

class SavedMapPlace {
  const SavedMapPlace({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
  });

  final String id;
  final String name;
  final String type;
  final Offset position;

  factory SavedMapPlace.fromJson(Map<String, dynamic> json) {
    return SavedMapPlace(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      position: Offset(
        (json['lon'] as num).toDouble(),
        (json['lat'] as num).toDouble(),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'lat': position.dy,
      'lon': position.dx,
    };
  }
}

class MapDestination {
  const MapDestination({
    required this.name,
    required this.position,
    required this.kind,
  });

  final String name;
  final Offset position;
  final String kind;
}

class OfflineRoute {
  const OfflineRoute({
    required this.points,
    required this.distanceKm,
  });

  final List<Offset> points;
  final double distanceKm;
}

class DownloadedOfflineMap {
  const DownloadedOfflineMap({
    required this.name,
    required this.path,
    required this.active,
  });

  final String name;
  final String path;
  final bool active;
}

class MapSearchOption {
  const MapSearchOption({
    required this.name,
    required this.displayName,
    this.countryCode,
  });

  final String name;
  final String displayName;
  final String? countryCode;
}
