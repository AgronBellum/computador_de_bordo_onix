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

  OfflineRoute? calculate(Offset origin, Offset destination) {
    final graph = _graph ??= _RouteGraph.fromRoads(map.roads);
    if (graph.points.length < 2) return null;

    final start = graph.nearest(origin);
    final end = graph.nearest(destination);
    if (start == null || end == null) return null;

    final pathIndexes = graph.shortestPath(start, end);
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
      throw const FileSystemException('Mapa offline não encontrado');
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
    final file = File(p.join(dir.path, '$fileName.json'));
    await file.writeAsString(jsonEncode(map.toJson()));

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
      throw const FormatException('Cidade não encontrada');
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
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded');
      request.headers.set(HttpHeaders.userAgentHeader, 'OnyxFuelApp/1.0');
      request.write('data=${Uri.encodeQueryComponent(query)}');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

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
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'OnyxFuelApp/1.0');
      final response = await request.close();
      final text = await response.transform(utf8.decoder).join();

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

  int _roadRank(String? highway) {
    switch (highway) {
      case 'motorway':
      case 'trunk':
        return 5;
      case 'primary':
        return 4;
      case 'secondary':
        return 3;
      case 'tertiary':
        return 2;
      case 'residential':
      case 'unclassified':
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
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
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
    const accents = {
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã£': 'a',
      'Ã¢': 'a',
      'Ã¤': 'a',
      'Ã©': 'e',
      'Ãª': 'e',
      'Ã«': 'e',
      'Ã­': 'i',
      'Ã¯': 'i',
      'Ã³': 'o',
      'Ãµ': 'o',
      'Ã´': 'o',
      'Ã¶': 'o',
      'Ãº': 'u',
      'Ã¼': 'u',
      'Ã§': 'c',
    };
    var result = value.toLowerCase();
    accents.forEach((from, to) {
      result = result.replaceAll(from, to);
    });
    return result;
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

class _RouteGraph {
  _RouteGraph({
    required this.points,
    required this.edges,
  });

  final List<Offset> points;
  final List<List<_RouteEdge>> edges;

  static _RouteGraph fromRoads(List<OfflineRoad> roads) {
    final indexes = <String, int>{};
    final points = <Offset>[];
    final edges = <List<_RouteEdge>>[];

    int indexFor(Offset point) {
      final key =
          '${point.dx.toStringAsFixed(6)},${point.dy.toStringAsFixed(6)}';
      final existing = indexes[key];
      if (existing != null) return existing;

      final index = points.length;
      indexes[key] = index;
      points.add(point);
      edges.add([]);
      return index;
    }

    for (final road in roads) {
      for (var i = 1; i < road.points.length; i++) {
        final a = indexFor(road.points[i - 1]);
        final b = indexFor(road.points[i]);
        final meters = _distanceMeters(points[a], points[b]);
        if (meters <= 0) continue;
        final cost = meters * _roadCostFactor(road.rank);
        edges[a].add(_RouteEdge(b, cost));
        edges[b].add(_RouteEdge(a, cost));
      }
    }

    return _RouteGraph(points: points, edges: edges);
  }

  int? nearest(Offset target) {
    if (points.isEmpty) return null;

    var bestIndex = 0;
    var bestMeters = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final meters = _distanceMeters(target, points[i]);
      if (meters < bestMeters) {
        bestMeters = meters;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  List<int> shortestPath(int start, int end) {
    final dist = List<double>.filled(points.length, double.infinity);
    final previous = List<int?>.filled(points.length, null);
    final queue = _MinQueue();

    dist[start] = 0;
    queue.push(start, 0);

    while (queue.isNotEmpty) {
      final current = queue.pop();
      if (current == null) break;
      if (current.priority > dist[current.index]) continue;
      if (current.index == end) break;

      for (final edge in edges[current.index]) {
        final nextDistance = dist[current.index] + edge.cost;
        if (nextDistance >= dist[edge.to]) continue;
        dist[edge.to] = nextDistance;
        previous[edge.to] = current.index;
        queue.push(edge.to, nextDistance);
      }
    }

    if (dist[end].isInfinite) return [];

    final path = <int>[];
    int? cursor = end;
    while (cursor != null) {
      path.add(cursor);
      if (cursor == start) break;
      cursor = previous[cursor];
    }
    return path.reversed.toList();
  }
}

class _RouteEdge {
  const _RouteEdge(this.to, this.cost);

  final int to;
  final double cost;
}

class _QueueItem {
  const _QueueItem(this.index, this.priority);

  final int index;
  final double priority;
}

class _MinQueue {
  final List<_QueueItem> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void push(int index, double priority) {
    _items.add(_QueueItem(index, priority));
    _bubbleUp(_items.length - 1);
  }

  _QueueItem? pop() {
    if (_items.isEmpty) return null;
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isNotEmpty) {
      _items[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      final parent = (index - 1) >> 1;
      if (_items[parent].priority <= _items[index].priority) break;
      final temp = _items[parent];
      _items[parent] = _items[index];
      _items[index] = temp;
      index = parent;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
      final left = index * 2 + 1;
      final right = left + 1;
      var smallest = index;

      if (left < _items.length &&
          _items[left].priority < _items[smallest].priority) {
        smallest = left;
      }
      if (right < _items.length &&
          _items[right].priority < _items[smallest].priority) {
        smallest = right;
      }
      if (smallest == index) break;

      final temp = _items[smallest];
      _items[smallest] = _items[index];
      _items[index] = temp;
      index = smallest;
    }
  }
}

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
