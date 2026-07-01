import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/offline_map.dart';

class OfflineRouteCalculator {
  OfflineRouteCalculator(this.map);

  final OfflineMapData map;
  _RouteGraph? _graph;

  void invalidateGraph() {
    _graph = null;
  }

  OfflineRoute? calculate(Offset origin, Offset destination) {
    final graph = _graph ??= _RouteGraph.fromRoads(map.roads);
    if (graph.points.length < 2) return null;

    final start = graph.nearest(origin);
    final end = graph.nearest(destination);
    if (start == null || end == null) return null;

    final pathIndexes = graph.shortestPathAStar(start, end);
    if (pathIndexes.isEmpty) return null;

    final points = pathIndexes.map((index) => graph.points[index]).toList();
    var meters = 0.0;
    for (var i = 1; i < points.length; i++) {
      meters += _distanceMeters(points[i - 1], points[i]);
    }

    return OfflineRoute(points: points, distanceKm: meters / 1000);
  }
}

class OfflineMapService {
  static const _placesKey = 'offline_map_places';
  static const _currentMapKey = 'offline_map_current_file';
  static const bundledPelotasPath = 'asset:pelotas';
  static const bundledRegionalPath = 'asset:rs_sul';

  Future<OfflineMapData> loadCurrentMap() async {
    final prefs = await SharedPreferences.getInstance();
    final filePath = prefs.getString(_currentMapKey) ?? bundledRegionalPath;

    if (filePath != bundledPelotasPath &&
        filePath != bundledRegionalPath &&
        await File(filePath).exists()) {
      final text = await File(filePath).readAsString();
      return OfflineMapData.fromJson(jsonDecode(text) as Map<String, dynamic>);
    }

    return loadBundledRegional();
  }

  Future<OfflineMapData> loadBundledPelotas() async {
    final text = await rootBundle.loadString('assets/maps/pelotas_roads.json');
    return OfflineMapData.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<OfflineMapData> loadBundledRegional() async {
    final text = await rootBundle.loadString('assets/maps/rs_sul_region.json');
    return OfflineMapData.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<List<SavedMapPlace>> loadPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_placesKey);
    if (raw == null || raw.isEmpty) return [];

    final list = jsonDecode(raw) as List;
    return list
        .map((item) => SavedMapPlace.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> savePlace(SavedMapPlace place) async {
    final places = await loadPlaces();
    final filtered = places.where((item) => item.id != place.id).toList()
      ..add(place);
    await _savePlaces(filtered);
  }

  Future<void> deletePlace(String id) async {
    final places = await loadPlaces();
    await _savePlaces(places.where((item) => item.id != id).toList());
  }

  Future<void> _savePlaces(List<SavedMapPlace> places) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _placesKey,
      jsonEncode(places.map((place) => place.toJson()).toList()),
    );
  }

  Future<List<DownloadedOfflineMap>> downloadedMaps() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString(_currentMapKey) ?? bundledRegionalPath;
    final maps = <DownloadedOfflineMap>[
      DownloadedOfflineMap(
        name: 'Sul do RS',
        path: bundledRegionalPath,
        active: current == bundledRegionalPath,
      ),
      DownloadedOfflineMap(
        name: 'Pelotas',
        path: bundledPelotasPath,
        active: current == bundledPelotasPath,
      ),
    ];
    final dir = await _mapDirectory();
    if (!await dir.exists()) return maps;

    final files = await dir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

    final downloaded = await Future.wait(files.map((file) async {
      try {
        final data =
            OfflineMapData.fromJson(jsonDecode(await file.readAsString()));
        return DownloadedOfflineMap(
          name: data.name,
          path: file.path,
          active: current == file.path,
        );
      } catch (_) {
        return DownloadedOfflineMap(
          name: p.basenameWithoutExtension(file.path),
          path: file.path,
          active: current == file.path,
        );
      }
    }));
    maps.addAll(downloaded);
    return maps;
  }

  Future<void> setCurrentMap(String path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == bundledPelotasPath || path == bundledRegionalPath) {
      await prefs.setString(_currentMapKey, path);
      return;
    }
    if (!await File(path).exists()) {
      throw const FileSystemException('Mapa offline nao encontrado');
    }
    await prefs.setString(_currentMapKey, path);
  }

  Future<OfflineMapData> downloadCityMap(String cityQuery) async {
    final trimmed = cityQuery.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Informe o nome da cidade');
    }

    final place = await _searchPlace(trimmed);
    final bbox = _expandBounds(place.boundingBox, factor: 2.8);
    final overpass = await _fetchOverpass(bbox);
    final map = _buildMapFromOverpass(
      name: place.displayName.split(',').first.trim(),
      bounds: bbox,
      overpass: overpass,
    );

    final dir = await _mapDirectory();
    await dir.create(recursive: true);
    final fileName = _safeFileName(map.name);
    final tempFile = File(p.join(dir.path, '.$fileName.tmp'));
    final file = File(p.join(dir.path, '$fileName.json'));

    await tempFile.writeAsString(jsonEncode(map.toJson()));
    await tempFile.rename(file.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentMapKey, file.path);

    return map;
  }

  Future<List<MapSearchOption>> searchCountries(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'json',
      'addressdetails': '1',
      'limit': '8',
      'featuretype': 'country',
      'q': trimmed,
    });
    final results = await _getJson(uri) as List;
    return results
        .map((raw) => _optionFromSearch(raw as Map<String, dynamic>))
        .toList();
  }

  Future<List<MapSearchOption>> searchStates(MapSearchOption country) async {
    if ((country.countryCode ?? '').toLowerCase() == 'br' ||
        country.name.toLowerCase() == 'brasil' ||
        country.name.toLowerCase() == 'brazil') {
      return _brazilStates();
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'json',
      'addressdetails': '1',
      'limit': '20',
      'featuretype': 'state',
      'countrycodes': country.countryCode ?? '',
      'q': country.name,
    });
    final results = await _getJson(uri) as List;
    return results
        .map((raw) => _optionFromSearch(raw as Map<String, dynamic>))
        .where((option) => option.name != country.name)
        .toList();
  }

  Future<List<MapSearchOption>> searchCities({
    required MapSearchOption country,
    required MapSearchOption state,
  }) async {
    final uf = _brazilStateCode(state.name);
    if (((country.countryCode ?? '').toLowerCase() == 'br' ||
            country.name.toLowerCase() == 'brasil' ||
            country.name.toLowerCase() == 'brazil') &&
        uf != null) {
      final uri = Uri.https(
        'servicodados.ibge.gov.br',
        '/api/v1/localidades/estados/$uf/municipios',
      );
      final results = await _getJson(uri) as List;
      return results.map((raw) {
        final json = raw as Map<String, dynamic>;
        final name = json['nome'] as String;
        return MapSearchOption(
          name: name,
          displayName: '$name, ${state.name}, Brasil',
          countryCode: 'br',
        );
      }).toList();
    }

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'json',
      'addressdetails': '1',
      'limit': '30',
      'featuretype': 'city',
      'countrycodes': country.countryCode ?? '',
      'state': state.name,
      'q': '${state.name}, ${country.name}',
    });
    final results = await _getJson(uri) as List;
    return results
        .map((raw) => _optionFromSearch(raw as Map<String, dynamic>))
        .where((option) => option.name != state.name)
        .toList();
  }

  MapSearchOption _optionFromSearch(Map<String, dynamic> json) {
    final address = json['address'] as Map<String, dynamic>?;
    final name = (address?['city'] ??
            address?['town'] ??
            address?['municipality'] ??
            address?['state'] ??
            address?['country'] ??
            json['name'] ??
            (json['display_name'] as String).split(',').first)
        .toString();

    return MapSearchOption(
      name: name,
      displayName: json['display_name'] as String,
      countryCode: address?['country_code'] as String?,
    );
  }

  Future<Directory> _mapDirectory() async {
    final dbPath = await getDatabasesPath();
    return Directory(p.join(dbPath, 'offline_maps'));
  }

  Future<_SearchPlace> _searchPlace(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'json',
      'limit': '1',
      'q': query,
    });
    final response = await _getJson(uri);
    final results = response as List;

    if (results.isEmpty) {
      throw const FormatException('Cidade nao encontrada');
    }

    return _SearchPlace.fromJson(results.first as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _fetchOverpass(List<double> bbox) async {
    final south = bbox[0];
    final west = bbox[1];
    final north = bbox[2];
    final east = bbox[3];
    final query = '''
[out:json][timeout:90];
(
  way["highway"]["highway"!~"footway|cycleway|path|steps|pedestrian|track|bridleway|service"]($south,$west,$north,$east);
  node["amenity"="fuel"]($south,$west,$north,$east);
  node["amenity"="pharmacy"]($south,$west,$north,$east);
  node["shop"="supermarket"]($south,$west,$north,$east);
  way["amenity"="fuel"]($south,$west,$north,$east);
  way["amenity"="pharmacy"]($south,$west,$north,$east);
  way["shop"="supermarket"]($south,$west,$north,$east);
  relation["amenity"="fuel"]($south,$west,$north,$east);
  relation["amenity"="pharmacy"]($south,$west,$north,$east);
  relation["shop"="supermarket"]($south,$west,$north,$east);
);
out center body;
>;
out skel qt;
''';
    final uri = Uri.https('overpass-api.de', '/api/interpreter');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      request.headers.set(HttpHeaders.userAgentHeader, 'OnyxFuelApp/1.0');
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close().timeout(
        const Duration(seconds: 120),
        onTimeout: () {
          throw HttpException('Timeout ao baixar mapa');
        },
      );
      final text = await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw HttpException('Timeout lendo resposta do mapa');
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Falha ao baixar mapa: ${response.statusCode}');
      }

      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<dynamic> _getJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'OnyxFuelApp/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw HttpException('Timeout na consulta');
        },
      );
      final text = await response.transform(utf8.decoder).join().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw HttpException('Timeout lendo resposta');
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Falha na consulta: ${response.statusCode}');
      }

      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  OfflineMapData _buildMapFromOverpass({
    required String name,
    required List<double> bounds,
    required Map<String, dynamic> overpass,
  }) {
    final elements = overpass['elements'] as List? ?? [];
    final nodes = <int, Offset>{};
    final stations = <FuelStation>[];
    final pois = <MapPoi>[];

    for (final raw in elements) {
      final element = raw as Map<String, dynamic>;
      final type = element['type'] as String?;
      final center = element['center'] as Map<String, dynamic>?;
      final lat = ((element['lat'] ?? center?['lat']) as num?)?.toDouble();
      final lon = ((element['lon'] ?? center?['lon']) as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final position = Offset(lon, lat);
      if (type == 'node') {
        final id = element['id'] as int;
        nodes[id] = position;
      }

      final tags = element['tags'] as Map<String, dynamic>?;
      if (tags?['amenity'] == 'fuel') {
        final station = FuelStation(
          name: (tags?['name'] as String?) ?? 'Posto',
          brand: tags?['brand'] as String?,
          position: position,
        );
        stations.add(station);
        pois.add(MapPoi.fromFuelStation(station));
      } else if (tags?['amenity'] == 'pharmacy') {
        pois.add(
          MapPoi(
            name: (tags?['name'] as String?) ?? 'Farmacia',
            brand: tags?['brand'] as String?,
            kind: 'farmacia',
            position: position,
          ),
        );
      } else if (tags?['shop'] == 'supermarket') {
        pois.add(
          MapPoi(
            name: (tags?['name'] as String?) ?? 'Supermercado',
            brand: tags?['brand'] as String?,
            kind: 'supermercado',
            position: position,
          ),
        );
      }
    }

    final roads = <OfflineRoad>[];
    for (final raw in elements) {
      final element = raw as Map<String, dynamic>;
      if (element['type'] != 'way') continue;

      final nodeIds = (element['nodes'] as List? ?? []).cast<int>();
      final points = nodeIds
          .map((id) => nodes[id])
          .whereType<Offset>()
          .toList(growable: false);
      if (points.length < 2) continue;

      final tags = element['tags'] as Map<String, dynamic>?;
      roads.add(
        OfflineRoad(
          rank: _roadRank(tags?['highway'] as String?),
          name: tags?['name'] as String?,
          oneway: _onewayDirection(tags),
          points: points,
        ),
      );
    }

    final center = Offset(
      (bounds[1] + bounds[3]) / 2,
      (bounds[0] + bounds[2]) / 2,
    );

    return OfflineMapData(
      name: name,
      source: 'OpenStreetMap/Overpass',
      bounds: bounds,
      center: center,
      roads: roads,
      fuelStations: stations,
      pointsOfInterest: pois,
    );
  }

  int _onewayDirection(Map<String, dynamic>? tags) {
    if (tags == null) return 0;

    final oneway = (tags['oneway'] as String?)?.toLowerCase().trim();
    final junction = (tags['junction'] as String?)?.toLowerCase().trim();
    final highway = (tags['highway'] as String?)?.toLowerCase().trim();

    if (oneway == '-1' || oneway == 'reverse') return -1;
    if (oneway == 'yes' ||
        oneway == 'true' ||
        oneway == '1' ||
        oneway == 'designated') {
      return 1;
    }
    if (oneway == 'no' || oneway == 'false' || oneway == '0') return 0;

    if (junction == 'roundabout' || junction == 'circular') return 1;
    if (highway == 'motorway' || highway == 'motorway_link') return 1;

    return 0;
  }

  int _roadRank(String? highway) {
    switch (highway) {
      case 'motorway':
      case 'motorway_link':
      case 'trunk':
      case 'trunk_link':
        return 5;
      case 'primary':
      case 'primary_link':
        return 4;
      case 'secondary':
      case 'secondary_link':
        return 3;
      case 'tertiary':
      case 'tertiary_link':
        return 2;
      case 'residential':
      case 'unclassified':
      case 'living_street':
        return 1;
      default:
        return 0;
    }
  }

  List<double> _expandBounds(List<double> bounds, {required double factor}) {
    final south = bounds[0];
    final west = bounds[1];
    final north = bounds[2];
    final east = bounds[3];
    final latPadding = ((north - south) * (factor - 1) / 2).clamp(0.05, 0.45);
    final lonPadding = ((east - west) * (factor - 1) / 2).clamp(0.05, 0.45);

    return [
      (south - latPadding).clamp(-85.0, 85.0),
      (west - lonPadding).clamp(-180.0, 180.0),
      (north + latPadding).clamp(-85.0, 85.0),
      (east + lonPadding).clamp(-180.0, 180.0),
    ];
  }

  String _safeFileName(String value) {
    final result = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return result.isEmpty ? 'mapa' : result;
  }

  List<MapSearchOption> _brazilStates() {
    const states = <String, String>{
      'AC': 'Acre',
      'AL': 'Alagoas',
      'AP': 'Amapa',
      'AM': 'Amazonas',
      'BA': 'Bahia',
      'CE': 'Ceara',
      'DF': 'Distrito Federal',
      'ES': 'Espirito Santo',
      'GO': 'Goias',
      'MA': 'Maranhao',
      'MT': 'Mato Grosso',
      'MS': 'Mato Grosso do Sul',
      'MG': 'Minas Gerais',
      'PA': 'Para',
      'PB': 'Paraiba',
      'PR': 'Parana',
      'PE': 'Pernambuco',
      'PI': 'Piaui',
      'RJ': 'Rio de Janeiro',
      'RN': 'Rio Grande do Norte',
      'RS': 'Rio Grande do Sul',
      'RO': 'Rondonia',
      'RR': 'Roraima',
      'SC': 'Santa Catarina',
      'SP': 'Sao Paulo',
      'SE': 'Sergipe',
      'TO': 'Tocantins',
    };

    return states.entries
        .map(
          (entry) => MapSearchOption(
            name: entry.value,
            displayName: '${entry.value}, Brasil',
            countryCode: 'br',
          ),
        )
        .toList();
  }

  String? _brazilStateCode(String stateName) {
    final normalized = _normalize(stateName);
    const states = <String, String>{
      'acre': 'AC',
      'alagoas': 'AL',
      'amapa': 'AP',
      'amazonas': 'AM',
      'bahia': 'BA',
      'ceara': 'CE',
      'distrito federal': 'DF',
      'espirito santo': 'ES',
      'goias': 'GO',
      'maranhao': 'MA',
      'mato grosso': 'MT',
      'mato grosso do sul': 'MS',
      'minas gerais': 'MG',
      'para': 'PA',
      'paraiba': 'PB',
      'parana': 'PR',
      'pernambuco': 'PE',
      'piaui': 'PI',
      'rio de janeiro': 'RJ',
      'rio grande do norte': 'RN',
      'rio grande do sul': 'RS',
      'rondonia': 'RO',
      'roraima': 'RR',
      'santa catarina': 'SC',
      'sao paulo': 'SP',
      'sergipe': 'SE',
      'tocantins': 'TO',
    };
    return states[normalized];
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[\u00E1\u00E0\u00E2\u00E3\u00E4]'), 'a')
        .replaceAll(RegExp(r'[\u00E9\u00E8\u00EA\u00EB]'), 'e')
        .replaceAll(RegExp(r'[\u00ED\u00EC\u00EE\u00EF]'), 'i')
        .replaceAll(RegExp(r'[\u00F3\u00F2\u00F4\u00F5\u00F6]'), 'o')
        .replaceAll(RegExp(r'[\u00FA\u00F9\u00FB\u00FC]'), 'u')
        .replaceAll('\u00E7', 'c');
  }
}

class _SearchPlace {
  const _SearchPlace({
    required this.displayName,
    required this.boundingBox,
  });

  final String displayName;
  final List<double> boundingBox;

  factory _SearchPlace.fromJson(Map<String, dynamic> json) {
    final bbox = (json['boundingbox'] as List)
        .map((value) => double.parse(value as String))
        .toList();

    return _SearchPlace(
      displayName: json['display_name'] as String,
      boundingBox: [bbox[0], bbox[2], bbox[1], bbox[3]],
    );
  }
}

// ============================================================
// OPTIMIZED ROUTE GRAPH WITH SPATIAL GRID + A* + DISTANCE CACHE
// ============================================================

class _RouteGraph {
  _RouteGraph({
    required this.points,
    required this.edges,
    required this.edgeDistances,
    required this.spatialGrid,
  });

  final List<Offset> points;
  final List<List<_RouteEdge>> edges;
  final List<List<double>> edgeDistances; // Pre-computed haversine distances
  final _SpatialGrid spatialGrid;

  static _RouteGraph fromRoads(List<OfflineRoad> roads) {
    // Phase 1: Collect unique points with fast hash-based dedup
    final indexes = <int, int>{};
    final points = <Offset>[];
    final edges = <List<_RouteEdge>>[];
    final edgeDistances = <List<double>>[];

    int indexFor(Offset point) {
      final key = _pointHash(point);
      final existing = indexes[key];
      if (existing != null) {
        // Collision check with tolerance
        final existingPoint = points[existing];
        if ((existingPoint.dx - point.dx).abs() < 1e-6 &&
            (existingPoint.dy - point.dy).abs() < 1e-6) {
          return existing;
        }
        // Handle collision with linear probing
        var probe = key + 1;
        while (true) {
          final probeExisting = indexes[probe];
          if (probeExisting == null) break;
          final probePoint = points[probeExisting];
          if ((probePoint.dx - point.dx).abs() < 1e-6 &&
              (probePoint.dy - point.dy).abs() < 1e-6) {
            return probeExisting;
          }
          probe++;
        }
        final index = points.length;
        indexes[probe] = index;
        points.add(point);
        edges.add([]);
        edgeDistances.add([]);
        return index;
      }

      final index = points.length;
      indexes[key] = index;
      points.add(point);
      edges.add([]);
      edgeDistances.add([]);
      return index;
    }

    // Phase 2: Build graph
    for (final road in roads) {
      for (var i = 1; i < road.points.length; i++) {
        final a = indexFor(road.points[i - 1]);
        final b = indexFor(road.points[i]);
        if (a == b) continue;

        final meters = _distanceMeters(points[a], points[b]);
        if (meters <= 0) continue;

        final cost = meters * _roadCostFactor(road.rank);
        if (road.oneway >= 0) {
          edges[a].add(_RouteEdge(b, cost));
          edgeDistances[a].add(meters);
        }
        if (road.oneway <= 0) {
          edges[b].add(_RouteEdge(a, cost));
          edgeDistances[b].add(meters);
        }
      }
    }

    // Phase 3: Build spatial grid for O(1) nearest lookup
    final spatialGrid = _SpatialGrid.fromPoints(points);

    return _RouteGraph(
      points: points,
      edges: edges,
      edgeDistances: edgeDistances,
      spatialGrid: spatialGrid,
    );
  }

  int? nearest(Offset target) {
    return spatialGrid.nearest(target, points);
  }

  List<int> shortestPathAStar(int start, int end) {
    if (start == end) return [start];

    final n = points.length;
    final dist = List<double>.filled(n, double.infinity);
    final previous = List<int?>.filled(n, null);
    final openSet = _FastHeap(n);
    final inOpenSet = List<bool>.filled(n, false);
    final closedSet = List<bool>.filled(n, false);

    final endPoint = points[end];
    dist[start] = 0;
    openSet.push(start, _heuristic(points[start], endPoint));
    inOpenSet[start] = true;

    while (openSet.isNotEmpty) {
      final current = openSet.pop();
      if (current == null) break;
      inOpenSet[current] = false;
      closedSet[current] = true;

      if (current == end) break;

      final currentEdges = edges[current];
      for (var i = 0; i < currentEdges.length; i++) {
        final edge = currentEdges[i];
        if (closedSet[edge.to]) continue;

        final nextDist = dist[current] + edge.cost;
        if (nextDist >= dist[edge.to]) continue;

        dist[edge.to] = nextDist;
        previous[edge.to] = current;

        final priority = nextDist + _heuristic(points[edge.to], endPoint);
        if (inOpenSet[edge.to]) {
          openSet.decreaseKey(edge.to, priority);
        } else {
          openSet.push(edge.to, priority);
          inOpenSet[edge.to] = true;
        }
      }
    }

    if (dist[end].isInfinite) return [];

    // Reconstruct path
    final path = <int>[];
    int? cursor = end;
    while (cursor != null) {
      path.add(cursor);
      if (cursor == start) break;
      cursor = previous[cursor];
    }
    return path.reversed.toList();
  }

  static double _heuristic(Offset from, Offset to) {
    // Euclidean distance in meters (approximate, fast)
    final dx = (to.dx - from.dx) * 111320.0;
    final dy = (to.dy - from.dy) * 111320.0;
    return math.sqrt(dx * dx + dy * dy) * 0.8; // 0.8 = admissible underestimate
  }
}

// Fast hash for point deduplication (no string allocation)
int _pointHash(Offset point) {
  final lonBits = (point.dx * 1e6).toInt();
  final latBits = (point.dy * 1e6).toInt();
  return lonBits * 73856093 ^ latBits * 19349663;
}

class _RouteEdge {
  const _RouteEdge(this.to, this.cost);

  final int to;
  final double cost;
}

// ============================================================
// SPATIAL GRID FOR O(1) NEAREST NEIGHBOR LOOKUP
// ============================================================

class _SpatialGrid {
  _SpatialGrid({
    required this.cells,
    required this.minLon,
    required this.minLat,
    required this.cellSizeLon,
    required this.cellSizeLat,
    required this.gridWidth,
    required this.gridHeight,
  });

  final List<List<int>> cells;
  final double minLon;
  final double minLat;
  final double cellSizeLon;
  final double cellSizeLat;
  final int gridWidth;
  final int gridHeight;

  static const int _targetCellsPerPoint = 8;
  static const int _maxGridSize = 200;

  factory _SpatialGrid.fromPoints(List<Offset> points) {
    if (points.isEmpty) {
      return _SpatialGrid(
        cells: [],
        minLon: 0,
        minLat: 0,
        cellSizeLon: 1,
        cellSizeLat: 1,
        gridWidth: 1,
        gridHeight: 1,
      );
    }

    // Compute bounds
    var minLon = points[0].dx;
    var maxLon = points[0].dx;
    var minLat = points[0].dy;
    var maxLat = points[0].dy;

    for (final point in points) {
      if (point.dx < minLon) minLon = point.dx;
      if (point.dx > maxLon) maxLon = point.dx;
      if (point.dy < minLat) minLat = point.dy;
      if (point.dy > maxLat) maxLat = point.dy;
    }

    // Add small padding
    final lonRange = (maxLon - minLon) * 1.01 + 1e-9;
    final latRange = (maxLat - minLat) * 1.01 + 1e-9;

    // Calculate grid size: aim for ~8 points per cell
    final totalCells = (points.length / _targetCellsPerPoint).ceil();
    final aspectRatio = lonRange / latRange;
    final gridHeight = math.min(
      _maxGridSize,
      math.max(1, math.sqrt(totalCells / aspectRatio).round()),
    );
    final gridWidth = math.min(
      _maxGridSize,
      math.max(1, (totalCells / gridHeight).round()),
    );

    final cellSizeLon = lonRange / gridWidth;
    final cellSizeLat = latRange / gridHeight;

    // Build cells
    final cells = List.generate(gridWidth * gridHeight, (_) => <int>[]);

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final gx =
          ((point.dx - minLon) / cellSizeLon).floor().clamp(0, gridWidth - 1);
      final gy =
          ((point.dy - minLat) / cellSizeLat).floor().clamp(0, gridHeight - 1);
      cells[gy * gridWidth + gx].add(i);
    }

    return _SpatialGrid(
      cells: cells,
      minLon: minLon,
      minLat: minLat,
      cellSizeLon: cellSizeLon,
      cellSizeLat: cellSizeLat,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
    );
  }

  int? nearest(Offset target, List<Offset> points) {
    if (points.isEmpty) return null;

    final tx = ((target.dx - minLon) / cellSizeLon).floor();
    final ty = ((target.dy - minLat) / cellSizeLat).floor();

    var bestIndex = 0;
    var bestDist = double.infinity;

    // Search in expanding rings around target cell
    final maxRadius = math.max(gridWidth, gridHeight);
    for (var radius = 0; radius <= maxRadius; radius++) {
      var foundInRing = false;

      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (radius > 0 && dy.abs() < radius && dx.abs() < radius) continue;

          final gx = (tx + dx).clamp(0, gridWidth - 1);
          final gy = (ty + dy).clamp(0, gridHeight - 1);
          final cell = cells[gy * gridWidth + gx];

          for (final index in cell) {
            foundInRing = true;
            final dist = _quickDistanceSquared(target, points[index]);
            if (dist < bestDist) {
              bestDist = dist;
              bestIndex = index;
            }
          }
        }
      }

      // If we found points and the closest is closer than the cell diagonal,
      // we can stop (no point in a farther cell can be closer)
      if (foundInRing && radius > 0) {
        final cellDiag = cellSizeLon * cellSizeLon + cellSizeLat * cellSizeLat;
        if (bestDist < cellDiag * radius * radius) {
          break;
        }
      }
    }

    return bestIndex;
  }

  static double _quickDistanceSquared(Offset a, Offset b) {
    final dx = (b.dx - a.dx) * 111320.0;
    final dy = (b.dy - a.dy) * 111320.0;
    return dx * dx + dy * dy;
  }
}

// ============================================================
// FAST BINARY HEAP WITH FIXED CAPACITY (NO GROWING)
// ============================================================

class _FastHeap {
  _FastHeap(int capacity)
      : _items = List<int>.filled(capacity, 0),
        _priorities = List<double>.filled(capacity, 0),
        _positions = List<int>.filled(capacity, -1);

  final List<int> _items;
  final List<double> _priorities;
  final List<int> _positions;
  int _size = 0;

  bool get isNotEmpty => _size > 0;
  bool get isEmpty => _size == 0;

  void push(int index, double priority) {
    if (_positions[index] >= 0) {
      // Already in heap, update if better
      if (priority < _priorities[_positions[index]]) {
        _priorities[_positions[index]] = priority;
        _bubbleUp(_positions[index]);
      }
      return;
    }

    _items[_size] = index;
    _priorities[_size] = priority;
    _positions[index] = _size;
    _bubbleUp(_size);
    _size++;
  }

  int? pop() {
    if (_size == 0) return null;
    final result = _items[0];
    _positions[result] = -1;
    _size--;

    if (_size > 0) {
      _items[0] = _items[_size];
      _priorities[0] = _priorities[_size];
      _positions[_items[0]] = 0;
      _bubbleDown(0);
    }

    return result;
  }

  void decreaseKey(int index, double newPriority) {
    final pos = _positions[index];
    if (pos < 0) return;
    if (newPriority >= _priorities[pos]) return;
    _priorities[pos] = newPriority;
    _bubbleUp(pos);
  }

  void _bubbleUp(int index) {
    final item = _items[index];
    final priority = _priorities[index];

    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_priorities[parent] <= priority) break;

      _items[index] = _items[parent];
      _priorities[index] = _priorities[parent];
      _positions[_items[parent]] = index;

      index = parent;
    }

    _items[index] = item;
    _priorities[index] = priority;
    _positions[item] = index;
  }

  void _bubbleDown(int index) {
    final item = _items[index];
    final priority = _priorities[index];
    final halfSize = _size >> 1;

    while (index < halfSize) {
      var child = (index << 1) + 1;
      var childPriority = _priorities[child];

      final right = child + 1;
      if (right < _size && _priorities[right] < childPriority) {
        child = right;
        childPriority = _priorities[right];
      }

      if (childPriority >= priority) break;

      _items[index] = _items[child];
      _priorities[index] = _priorities[child];
      _positions[_items[child]] = index;

      index = child;
    }

    _items[index] = item;
    _priorities[index] = priority;
    _positions[item] = index;
  }
}

// ============================================================
// UTILITY FUNCTIONS
// ============================================================

double _distanceMeters(Offset a, Offset b) {
  const p = 0.017453292519943295;
  final hav = 0.5 -
      math.cos((b.dy - a.dy) * p) / 2 +
      math.cos(a.dy * p) *
          math.cos(b.dy * p) *
          (1 - math.cos((b.dx - a.dx) * p)) /
          2;
  return 12742 * math.asin(math.sqrt(hav)) * 1000;
}

double _roadCostFactor(int rank) {
  switch (rank) {
    case 5:
      return 0.62;
    case 4:
      return 0.72;
    case 3:
      return 0.84;
    case 2:
      return 0.95;
    case 1:
      return 1.08;
    default:
      return 1.22;
  }
}
