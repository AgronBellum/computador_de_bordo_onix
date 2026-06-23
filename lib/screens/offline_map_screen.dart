import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/offline_map.dart';
import '../providers/app_provider.dart';
import '../services/offline_map_service.dart';

class OfflineMapScreen extends StatefulWidget {
  const OfflineMapScreen({super.key});

  @override
  State<OfflineMapScreen> createState() => _OfflineMapScreenState();
}

class _OfflineMapScreenState extends State<OfflineMapScreen> {
  final OfflineMapService _service = OfflineMapService();
  final TextEditingController _searchController = TextEditingController();
  OfflineMapData? _map;
  OfflineRouteCalculator? _calculator;
  List<SavedMapPlace> _places = [];
  MapDestination? _destination;
  OfflineRoute? _route;
  Offset? _viewCenter;
  double _viewLatSpan = 0.025;
  double _gestureStartLatSpan = 0.025;
  bool _followCar = true;
  bool _routePanelCollapsed = false;
  bool _showFuelPois = true;
  bool _showPharmacyPois = true;
  bool _showSupermarketPois = true;
  bool _loading = true;
  bool _routing = false;
  bool _autoRerouting = false;
  DateTime? _lastRerouteAt;
  String? _message;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final map = await _service.loadCurrentMap();
      final places = await _service.loadPlaces();
      final provider = mounted ? context.read<AppProvider>() : null;
      if (!mounted) return;
      setState(() {
        _map = map;
        _calculator = OfflineRouteCalculator(map);
        _places = places;
        _route = provider?.activeNavigationRoute;
        _destination = provider?.activeNavigationDestination;
        _viewCenter = map.center;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Não foi possível carregar o mapa offline';
        _loading = false;
      });
    }
  }

  Future<void> _selectDestination(
    AppProvider provider,
    MapDestination destination,
  ) async {
    if (_isSameDestination(_destination, destination)) {
      provider.clearActiveNavigationRoute();
      setState(() {
        _destination = null;
        _route = null;
        _message = 'Rota removida';
      });
      return;
    }

    final map = _map;
    final origin = _origin(provider);
    if (map == null || origin == null) {
      setState(() {
        _message = 'Aguardando posicao GPS para calcular a rota';
      });
      return;
    }

    setState(() {
      _routing = true;
      _destination = destination;
      _message = null;
    });

    final calculator = _calculator ?? OfflineRouteCalculator(map);
    _calculator = calculator;
    final route = await Future<OfflineRoute?>(
      () => calculator.calculate(origin, destination.position),
    );

    if (!mounted) return;
    setState(() {
      _route = route;
      _routing = false;
      _message = route == null ? 'Rota indisponível neste mapa offline' : null;
    });
    if (route != null) {
      provider.setActiveNavigationRoute(
        route: route,
        destination: destination,
      );
    } else {
      provider.clearActiveNavigationRoute();
    }
  }

  Future<void> _maybeReroute(AppProvider provider, Offset origin) async {
    if (_autoRerouting || _routing || _route == null || _destination == null) {
      return;
    }

    final last = _lastRerouteAt;
    if (last != null && DateTime.now().difference(last).inSeconds < 12) {
      return;
    }

    final distance = _distanceToRouteMeters(origin, _route!.points);
    if (distance < 75) return;

    final map = _map;
    if (map == null) return;

    setState(() {
      _autoRerouting = true;
      _message = 'Recalculando rota...';
    });

    final calculator = _calculator ?? OfflineRouteCalculator(map);
    _calculator = calculator;
    final route = await Future<OfflineRoute?>(
      () => calculator.calculate(
        origin,
        _destination!.position,
      ),
    );

    if (!mounted) return;
    _lastRerouteAt = DateTime.now();

    setState(() {
      _autoRerouting = false;
      if (route != null) {
        _route = route;
        _message = 'Rota recalculada';
      } else {
        _message = 'Não consegui recalcular neste mapa offline';
      }
    });

    if (route != null) {
      provider.setActiveNavigationRoute(
        route: route,
        destination: _destination!,
      );
    }
  }

  Future<void> _routeToNearestFuel(AppProvider provider) async {
    final map = _map;
    final origin = _origin(provider);
    if (map == null || origin == null) {
      setState(() => _message = 'Aguardando GPS para buscar posto');
      return;
    }

    FuelStation? best;
    OfflineRoute? bestRoute;
    var bestDistance = double.infinity;
    final calculator = _calculator ?? OfflineRouteCalculator(map);
    _calculator = calculator;

    setState(() {
      _routing = true;
      _message = 'Buscando posto mais proximo...';
    });

    final stations = [...map.fuelStations]..sort((a, b) {
        return _distanceMeters(origin, a.position)
            .compareTo(_distanceMeters(origin, b.position));
      });

    for (final station in stations.take(18)) {
      final route = await Future<OfflineRoute?>(
        () => calculator.calculate(origin, station.position),
      );
      if (route == null) continue;

      final fuelNeeded = provider.selectedConsumption > 0
          ? route.distanceKm / provider.selectedConsumption
          : double.infinity;
      final viable = provider.activeTrip == null ||
          provider.activeTrip!.remainingFuel >= fuelNeeded;

      if (viable && route.distanceKm < bestDistance) {
        best = station;
        bestRoute = route;
        bestDistance = route.distanceKm;
      }
    }

    if (!mounted) return;

    if (best == null || bestRoute == null) {
      setState(() {
        _routing = false;
        _message = 'Nenhum posto viavel encontrado neste mapa';
      });
      return;
    }

    final destination = MapDestination(
      name: best.name,
      position: best.position,
      kind: 'posto',
    );

    setState(() {
      _routing = false;
      _destination = destination;
      _route = bestRoute;
      _message = 'Rota para posto mais proximo';
    });
    provider.setActiveNavigationRoute(
      route: bestRoute,
      destination: destination,
    );
  }

  _RouteInstruction? _routeInstruction(Offset? origin) {
    final route = _route;
    if (origin == null || route == null || route.points.length < 3) return null;

    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < route.points.length; i++) {
      final meters = _distanceMeters(origin, route.points[i]);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }

    final lookAheadIndex = math.min(nearestIndex + 3, route.points.length - 1);
    final maneuverIndex = math.min(nearestIndex + 8, route.points.length - 1);
    if (lookAheadIndex <= nearestIndex) return null;

    final bearingNow = _bearingDegrees(origin, route.points[lookAheadIndex]);
    var instruction = 'Siga em frente';
    var icon = Icons.straight;

    if (maneuverIndex > lookAheadIndex) {
      final bearingNext = _bearingDegrees(
          route.points[lookAheadIndex], route.points[maneuverIndex]);
      final delta = _angleDelta(bearingNow, bearingNext);
      if (delta > 35) {
        instruction = 'Vire a direita';
        icon = Icons.turn_right;
      } else if (delta < -35) {
        instruction = 'Vire a esquerda';
        icon = Icons.turn_left;
      }
    }

    var metersAhead = 0.0;
    var previous = origin;
    for (var i = nearestIndex; i <= maneuverIndex; i++) {
      metersAhead += _distanceMeters(previous, route.points[i]);
      previous = route.points[i];
    }

    return _RouteInstruction(
      text: '$instruction em ${metersAhead.clamp(0, 999).toStringAsFixed(0)} m',
      icon: icon,
    );
  }

  bool _isSameDestination(MapDestination? a, MapDestination b) {
    if (a == null) return false;
    return a.name == b.name &&
        a.kind == b.kind &&
        (a.position - b.position).distance < 0.000001;
  }

  Future<void> _addCurrentPlace(AppProvider provider) async {
    final origin = _origin(provider);
    if (origin == null) {
      setState(() {
        _message = 'GPS ainda não informou a posição atual';
      });
      return;
    }

    final nameController = TextEditingController();
    var type = 'favorito';

    final place = await showDialog<SavedMapPlace>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Salvar local atual'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nome',
                      hintText: 'Casa, Trabalho, Cliente...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: const [
                      DropdownMenuItem(value: 'casa', child: Text('Casa')),
                      DropdownMenuItem(
                        value: 'trabalho',
                        child: Text('Trabalho'),
                      ),
                      DropdownMenuItem(value: 'posto', child: Text('Posto')),
                      DropdownMenuItem(
                        value: 'mercado',
                        child: Text('Super Mercado'),
                      ),
                      DropdownMenuItem(
                        value: 'favorito',
                        child: Text('Favorito'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => type = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    Navigator.pop(
                      context,
                      SavedMapPlace(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        name: name,
                        type: type,
                        position: origin,
                      ),
                    );
                  },
                  child: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    if (place == null) return;

    await _service.savePlace(place);
    final places = await _service.loadPlaces();
    if (!mounted) return;
    setState(() {
      _places = places;
      _message = 'Local salvo';
    });
  }

  Offset? _origin(AppProvider provider) {
    final lat = provider.lastGpsLatitude;
    final lon = provider.lastGpsLongitude;
    if (lat == null || lon == null) return null;
    return Offset(lon, lat);
  }

  Offset _effectiveCenter(Offset? origin) {
    if (_followCar && origin != null) return origin;
    return _viewCenter ?? origin ?? _map?.center ?? Offset.zero;
  }

  void _handleScaleStart(ScaleStartDetails details, Offset? origin) {
    _gestureStartLatSpan = _viewLatSpan;
  }

  void _handleScaleUpdate(
    ScaleUpdateDetails details,
    Size size,
    Offset? origin,
  ) {
    final currentCenter = _followCar
        ? _effectiveCenter(origin)
        : (_viewCenter ?? _effectiveCenter(origin));
    final newSpan = (_gestureStartLatSpan / details.scale).clamp(0.003, 0.08);
    final lonSpan = _lonSpan(currentCenter, newSpan, size);
    final moved = details.focalPointDelta.distance > 0.2 || details.scale != 1;

    if (!moved) return;

    setState(() {
      _followCar = false;
      _viewLatSpan = newSpan;
      _viewCenter = Offset(
        currentCenter.dx - details.focalPointDelta.dx * lonSpan / size.width,
        currentCenter.dy + details.focalPointDelta.dy * newSpan / size.height,
      );
    });
  }

  void _centerOnCar(Offset? origin) {
    if (origin == null) {
      setState(() => _message = 'Aguardando GPS para centralizar');
      return;
    }
    setState(() {
      _followCar = true;
      _viewLatSpan = 0.025;
      _viewCenter = origin;
      _message = null;
    });
  }

  void _handleMapTap(
    TapUpDetails details,
    Size size,
    AppProvider provider,
    OfflineMapData map,
    Offset? origin,
  ) {
    final poi = _nearestPoi(details.localPosition, size, map, origin);
    if (poi == null) return;
    _showPoiSheet(provider, poi);
  }

  MapPoi? _nearestPoi(
    Offset tap,
    Size size,
    OfflineMapData map,
    Offset? origin,
  ) {
    MapPoi? best;
    var bestDistance = double.infinity;

    for (final poi in _visiblePois(map)) {
      final point = _project(poi.position, size, origin);
      final distance = (point - tap).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = poi;
      }
    }

    return bestDistance <= 26 ? best : null;
  }

  List<MapPoi> _visiblePois(OfflineMapData map) {
    return map.pointsOfInterest.where((poi) {
      switch (poi.kind) {
        case 'posto':
          return _showFuelPois;
        case 'farmacia':
          return _showPharmacyPois;
        case 'supermercado':
          return _showSupermarketPois;
        default:
          return true;
      }
    }).toList(growable: false);
  }

  List<_MapSearchResult> _searchResults(OfflineMapData map) {
    final query = _normalizeSearch(_searchQuery);
    if (query.length < 2) return const [];

    final results = <_MapSearchResult>[];
    final seen = <String>{};

    void add(_MapSearchResult result) {
      final key =
          '${_normalizeSearch(result.name)}:${result.position.dx.toStringAsFixed(4)}:${result.position.dy.toStringAsFixed(4)}';
      if (seen.add(key)) results.add(result);
    }

    for (final place in _places) {
      final haystack = _normalizeSearch('${place.name} ${place.type}');
      if (!haystack.contains(query)) continue;
      add(
        _MapSearchResult(
          name: place.name,
          subtitle: _labelForKind(place.type),
          kind: place.type,
          icon: _poiIcon(place.type),
          position: place.position,
        ),
      );
    }

    for (final poi in _visiblePois(map)) {
      final haystack = _normalizeSearch('${poi.name} ${poi.brand ?? ''}');
      if (!haystack.contains(query)) continue;
      add(
        _MapSearchResult(
          name: poi.name,
          subtitle: _labelForKind(poi.kind),
          kind: poi.kind,
          icon: _poiIcon(poi.kind),
          position: poi.position,
        ),
      );
    }

    for (final city in _regionalCities) {
      final haystack = _normalizeSearch(city.name);
      if (!haystack.contains(query)) continue;
      add(
        _MapSearchResult(
          name: city.name,
          subtitle: 'Cidade',
          kind: 'cidade',
          icon: Icons.location_city,
          position: city.position,
        ),
      );
    }

    for (final road in map.roads) {
      final name = road.name?.trim();
      if (name == null || name.length < 2 || road.points.isEmpty) continue;
      if (!_normalizeSearch(name).contains(query)) continue;
      add(
        _MapSearchResult(
          name: name,
          subtitle: 'Rua',
          kind: 'rua',
          icon: Icons.alt_route,
          position: road.points[road.points.length ~/ 2],
        ),
      );
      if (results.length >= 24) break;
    }

    return results.take(24).toList(growable: false);
  }

  void _selectSearchResult(
    AppProvider provider,
    _MapSearchResult result,
  ) {
    _searchController.text = result.name;
    FocusScope.of(context).unfocus();
    setState(() {
      _searchQuery = '';
      _followCar = false;
      _viewCenter = result.position;
      _viewLatSpan = result.kind == 'cidade' ? 0.045 : 0.012;
    });
    _selectDestination(
      provider,
      MapDestination(
        name: result.name,
        position: result.position,
        kind: result.kind,
      ),
    );
  }

  String _labelForKind(String kind) {
    switch (kind) {
      case 'casa':
        return 'Casa';
      case 'trabalho':
        return 'Trabalho';
      case 'posto':
        return 'Posto';
      case 'farmacia':
        return 'Farmacia';
      case 'supermercado':
      case 'mercado':
        return 'Supermercado';
      case 'cidade':
        return 'Cidade';
      case 'rua':
        return 'Rua';
      default:
        return 'Favorito';
    }
  }

  Offset _project(Offset lonLat, Size size, Offset? origin) {
    final center = _effectiveCenter(origin);
    final latSpan = _viewLatSpan;
    final lonSpan = _lonSpan(center, latSpan, size);
    final minLat = center.dy - latSpan / 2;
    final minLon = center.dx - lonSpan / 2;
    final normalizedX = (lonLat.dx - minLon) / lonSpan;
    final normalizedY = 1 - ((lonLat.dy - minLat) / latSpan);

    return Offset(normalizedX * size.width, normalizedY * size.height);
  }

  double _lonSpan(Offset center, double latSpan, Size size) {
    final centerLat = center.dy * math.pi / 180;
    final cosLat = math.cos(centerLat).abs().clamp(0.25, 1.0);
    return latSpan * (size.width / size.height) / cosLat;
  }

  Future<void> _showPoiSheet(
    AppProvider provider,
    MapPoi poi,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = _MapColors.of(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_poiIcon(poi.kind), color: colors.warning, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          poi.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (poi.brand != null)
                          Text(
                            poi.brand!,
                            style: TextStyle(color: colors.secondaryText),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _savePlaceFromDestination(
                        MapDestination(
                          name: poi.name,
                          position: poi.position,
                          kind: poi.kind,
                        ),
                        type: 'favorito',
                      );
                    },
                    icon: const Icon(Icons.star),
                    label: const Text('FAVORITO'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _selectDestination(
                        provider,
                        MapDestination(
                          name: poi.name,
                          position: poi.position,
                          kind: poi.kind,
                        ),
                      );
                    },
                    icon: const Icon(Icons.navigation),
                    label: const Text('ROTA'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _poiIcon(String kind) {
    switch (kind) {
      case 'casa':
        return Icons.home;
      case 'trabalho':
        return Icons.work;
      case 'farmacia':
        return Icons.local_pharmacy;
      case 'supermercado':
      case 'mercado':
        return Icons.shopping_cart;
      case 'cidade':
        return Icons.location_city;
      case 'rua':
        return Icons.alt_route;
      case 'posto':
      default:
        return Icons.local_gas_station;
    }
  }

  Future<void> _savePlaceFromDestination(
    MapDestination destination, {
    required String type,
  }) async {
    final place = SavedMapPlace(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: destination.name,
      type: type,
      position: destination.position,
    );
    await _service.savePlace(place);
    final places = await _service.loadPlaces();
    if (!mounted) return;
    setState(() {
      _places = places;
      _message = 'Favorito salvo';
    });
  }

  Future<void> _showMapManager() async {
    final maps = await _service.downloadedMaps();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = _MapColors.of(context);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mapas baixados',
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: maps.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = maps[index];
                        return ListTile(
                          leading: Icon(
                            item.active
                                ? Icons.radio_button_checked
                                : Icons.map,
                            color: item.active ? colors.green : colors.blue,
                          ),
                          title: Text(
                            item.name,
                            style: TextStyle(color: colors.primaryText),
                          ),
                          trailing: item.active
                              ? const Text('ATIVO')
                              : const Text('USAR'),
                          onTap: item.active
                              ? null
                              : () async {
                                  await _service.setCurrentMap(item.path);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  _calculator = null;
                                  await _load();
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final map = _map;
    final origin = _origin(provider);
    final colors = _MapColors.of(context);
    final visiblePois = map == null ? const <MapPoi>[] : _visiblePois(map);
    if (map != null &&
        origin != null &&
        _route != null &&
        _destination != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _maybeReroute(provider, origin);
      });
    }

    return Scaffold(
      body: _loading || map == null
          ? Center(
              child: _message == null
                  ? const CircularProgressIndicator()
                  : Text(_message!),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (details) =>
                            _handleScaleStart(details, origin),
                        onScaleUpdate: (details) =>
                            _handleScaleUpdate(details, size, origin),
                        onTapUp: (details) =>
                            _handleMapTap(details, size, provider, map, origin),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _FullscreenMapPainter(
                                  map: map,
                                  pointsOfInterest: visiblePois,
                                  origin: origin,
                                  viewCenter: _effectiveCenter(origin),
                                  viewLatSpan: _viewLatSpan,
                                  followCar: _followCar,
                                  heading: provider.lastGpsHeading,
                                  vehicleIcon: provider.mapVehicleIcon,
                                  destination: _destination?.position,
                                  route: _route,
                                  darkMode: Theme.of(context).brightness ==
                                      Brightness.dark,
                                  showVehicle: false,
                                ),
                              ),
                            ),
                            if (origin != null)
                              _OfflineVehicleMarkerOverlay(
                                size: size,
                                origin: origin,
                                viewCenter: _effectiveCenter(origin),
                                viewLatSpan: _viewLatSpan,
                                followCar: _followCar,
                                heading: provider.lastGpsHeading,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 82,
                  child: Column(
                    children: [
                      _MapFab(
                        icon: _followCar ? Icons.explore : Icons.my_location,
                        tooltip: _followCar
                            ? 'Explorar mapa'
                            : 'Centralizar no carro',
                        onTap: () {
                          if (_followCar) {
                            setState(() {
                              _followCar = false;
                              _viewCenter = null;
                            });
                          } else {
                            _centerOnCar(origin);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      _MapFab(
                        icon: Icons.tune,
                        tooltip: 'Filtros do mapa',
                        onTap: _showPoiFilters,
                      ),
                      const SizedBox(height: 8),
                      _MapFab(
                        icon: Icons.map,
                        tooltip: 'Mapas baixados',
                        onTap: _showMapManager,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 12,
                  right: 14,
                  child: _TopMapBar(
                    fuelPercent: provider.fuelPercentage * 100,
                    rangeKm: provider.activeTrip?.estimatedRange ?? 0,
                    mapName: map.name,
                    onClose: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 74,
                  right: 76,
                  child: _MapSearchOverlay(
                    colors: colors,
                    controller: _searchController,
                    query: _searchQuery,
                    results: _searchResults(map),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    onClear: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    onSelect: (result) => _selectSearchResult(provider, result),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 12,
                  child: _routePanelCollapsed
                      ? _CollapsedRoutePanel(
                          colors: colors,
                          title: _destination?.name ?? 'Rotas e favoritos',
                          instruction: _routeInstruction(origin),
                          onExpand: () {
                            setState(() => _routePanelCollapsed = false);
                          },
                        )
                      : _BottomRoutePanel(
                          colors: colors,
                          favorites: _places,
                          destinations: _destinations(map),
                          selected: _destination,
                          route: _route,
                          routing: _routing,
                          autoRerouting: _autoRerouting,
                          remainingFuel:
                              provider.activeTrip?.remainingFuel ?? 0,
                          consumption: provider.selectedConsumption,
                          fuelPrice: provider.fuelPrice,
                          instruction: _routeInstruction(origin),
                          message: _message,
                          onMinimize: () {
                            setState(() => _routePanelCollapsed = true);
                          },
                          onAddPlace: () => _addCurrentPlace(provider),
                          onNearestFuel: () => _routeToNearestFuel(provider),
                          onSelect: (destination) =>
                              _selectDestination(provider, destination),
                        ),
                ),
              ],
            ),
    );
  }

  List<MapDestination> _destinations(OfflineMapData map) {
    final saved = _places.map(
      (place) => MapDestination(
        name: place.name,
        position: place.position,
        kind: place.type,
      ),
    );
    final pois = _visiblePois(map).map(
      (poi) => MapDestination(
        name: poi.name,
        position: poi.position,
        kind: poi.kind,
      ),
    );
    return [...saved, ...pois];
  }

  Future<void> _showPoiFilters() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        var showFuel = _showFuelPois;
        var showPharmacy = _showPharmacyPois;
        var showSupermarket = _showSupermarketPois;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pontos no mapa'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    value: showFuel,
                    onChanged: (value) =>
                        setDialogState(() => showFuel = value ?? true),
                    secondary: const Icon(Icons.local_gas_station),
                    title: const Text('Postos'),
                  ),
                  CheckboxListTile(
                    value: showPharmacy,
                    onChanged: (value) =>
                        setDialogState(() => showPharmacy = value ?? true),
                    secondary: const Icon(Icons.local_pharmacy),
                    title: const Text('Farmacias'),
                  ),
                  CheckboxListTile(
                    value: showSupermarket,
                    onChanged: (value) =>
                        setDialogState(() => showSupermarket = value ?? true),
                    secondary: const Icon(Icons.shopping_cart),
                    title: const Text('Supermercados'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _showFuelPois = showFuel;
                      _showPharmacyPois = showPharmacy;
                      _showSupermarketPois = showSupermarket;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('APLICAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _MapSearchOverlay extends StatelessWidget {
  const _MapSearchOverlay({
    required this.colors,
    required this.controller,
    required this.query,
    required this.results,
    required this.onChanged,
    required this.onClear,
    required this.onSelect,
  });

  final _MapColors colors;
  final TextEditingController controller;
  final String query;
  final List<_MapSearchResult> results;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<_MapSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final showResults = query.trim().length >= 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: colors.panel.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(8),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pesquisar rua ou cidade',
              hintStyle: TextStyle(color: colors.secondaryText),
              prefixIcon: Icon(Icons.search, color: colors.blue),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      onPressed: onClear,
                      icon: const Icon(Icons.close),
                      color: colors.secondaryText,
                    ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.blue),
              ),
              filled: true,
              fillColor: colors.panel.withValues(alpha: 0.94),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
            ),
          ),
        ),
        if (showResults)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: colors.panel.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 236),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.search_off,
                                color: colors.secondaryText, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Nenhum resultado no mapa offline',
                              style: TextStyle(color: colors.secondaryText),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: colors.border.withValues(alpha: 0.65),
                        ),
                        itemBuilder: (context, index) {
                          final result = results[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(result.icon, color: colors.blue),
                            title: Text(
                              result.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.primaryText,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            subtitle: Text(
                              result.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.secondaryText),
                            ),
                            onTap: () => onSelect(result),
                          );
                        },
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

class _TopMapBar extends StatelessWidget {
  const _TopMapBar({
    required this.fuelPercent,
    required this.rangeKm,
    required this.mapName,
    required this.onClose,
  });

  final double fuelPercent;
  final double rangeKm;
  final String mapName;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = _MapColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Voltar',
              onPressed: onClose,
              icon: const Icon(Icons.arrow_back),
              color: colors.primaryText,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                mapName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
            _MetricPill(
              icon: Icons.local_gas_station,
              value: '${fuelPercent.toStringAsFixed(0)}%',
            ),
            const SizedBox(width: 8),
            _MetricPill(
              icon: Icons.route,
              value: '${rangeKm.toStringAsFixed(0)} km',
            ),
          ],
        ),
      ),
    );
  }
}

class _MapFab extends StatelessWidget {
  const _MapFab({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _MapColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Icon(icon, color: colors.blue),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = _MapColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colors.blue.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.blue.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: colors.blue, size: 17),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomRoutePanel extends StatelessWidget {
  const _BottomRoutePanel({
    required this.colors,
    required this.favorites,
    required this.destinations,
    required this.selected,
    required this.route,
    required this.routing,
    required this.autoRerouting,
    required this.remainingFuel,
    required this.consumption,
    required this.fuelPrice,
    required this.instruction,
    required this.message,
    required this.onMinimize,
    required this.onAddPlace,
    required this.onNearestFuel,
    required this.onSelect,
  });

  final _MapColors colors;
  final List<SavedMapPlace> favorites;
  final List<MapDestination> destinations;
  final MapDestination? selected;
  final OfflineRoute? route;
  final bool routing;
  final bool autoRerouting;
  final double remainingFuel;
  final double consumption;
  final double fuelPrice;
  final _RouteInstruction? instruction;
  final String? message;
  final VoidCallback onMinimize;
  final VoidCallback onAddPlace;
  final VoidCallback onNearestFuel;
  final ValueChanged<MapDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final fuelNeeded = route == null || consumption <= 0
        ? 0.0
        : route!.distanceKm / consumption;
    final enoughFuel = route == null || remainingFuel >= fuelNeeded;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Minimizar',
                        onPressed: onMinimize,
                        icon: const Icon(Icons.keyboard_arrow_down),
                        color: colors.secondaryText,
                      ),
                      Expanded(
                        child: Text(
                          selected == null
                              ? 'Escolha um destino'
                              : selected!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onAddPlace,
                        icon: const Icon(Icons.add_location_alt, size: 18),
                        label: const Text('SALVAR LOCAL'),
                      ),
                      TextButton.icon(
                        onPressed: onNearestFuel,
                        icon: const Icon(Icons.local_gas_station, size: 18),
                        label: const Text('POSTO'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (favorites.isNotEmpty) ...[
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemBuilder: (context, index) {
                          final place = favorites[index];
                          final destination = MapDestination(
                            name: place.name,
                            position: place.position,
                            kind: place.type,
                          );
                          return ActionChip(
                            avatar: Icon(
                              _iconFor(place.type),
                              size: 16,
                              color: colors.green,
                            ),
                            label: Text(place.name),
                            onPressed: () => onSelect(destination),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: favorites.length,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final destination = destinations[index];
                        return ChoiceChip(
                          selected: selected?.name == destination.name &&
                              selected?.kind == destination.kind,
                          label: Text(destination.name),
                          avatar: Icon(
                            _iconFor(destination.kind),
                            size: 17,
                            color: colors.blue,
                          ),
                          onSelected: (_) => onSelect(destination),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: destinations.length,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: _RouteSummary(
                colors: colors,
                routing: routing,
                autoRerouting: autoRerouting,
                route: route,
                fuelNeeded: fuelNeeded,
                cost: fuelNeeded * fuelPrice,
                enoughFuel: enoughFuel,
                instruction: instruction,
                message: message,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String kind) {
    switch (kind) {
      case 'casa':
        return Icons.home;
      case 'trabalho':
        return Icons.work;
      case 'posto':
        return Icons.local_gas_station;
      case 'mercado':
        return Icons.storefront;
      default:
        return Icons.star;
    }
  }
}

class _CollapsedRoutePanel extends StatelessWidget {
  const _CollapsedRoutePanel({
    required this.colors,
    required this.title,
    required this.instruction,
    required this.onExpand,
  });

  final _MapColors colors;
  final String title;
  final _RouteInstruction? instruction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.panel.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              Icon(
                instruction?.icon ?? Icons.route,
                color: colors.blue,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  instruction?.text ?? title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.keyboard_arrow_up, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({
    required this.colors,
    required this.routing,
    required this.autoRerouting,
    required this.route,
    required this.fuelNeeded,
    required this.cost,
    required this.enoughFuel,
    required this.instruction,
    required this.message,
  });

  final _MapColors colors;
  final bool routing;
  final bool autoRerouting;
  final OfflineRoute? route;
  final double fuelNeeded;
  final double cost;
  final bool enoughFuel;
  final _RouteInstruction? instruction;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (routing || autoRerouting) {
      return const Center(child: LinearProgressIndicator());
    }

    final text = message ??
        (route == null
            ? 'Toque em um local ou posto para calcular.'
            : '${route!.distanceKm.toStringAsFixed(1)} km  |  ${fuelNeeded.toStringAsFixed(1)} L');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (instruction != null) ...[
          Row(
            children: [
              Icon(instruction!.icon, color: colors.blue, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  instruction!.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (route != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  enoughFuel ? 'Gasolina suficiente' : 'Gasolina insuficiente',
                  style: TextStyle(
                    color: enoughFuel ? colors.green : colors.warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'R\$ ${cost.toStringAsFixed(2).replaceAll('.', ',')}',
                style: TextStyle(
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _RouteInstruction {
  const _RouteInstruction({
    required this.text,
    required this.icon,
  });

  final String text;
  final IconData icon;
}

class _OfflineVehicleMarkerOverlay extends StatelessWidget {
  const _OfflineVehicleMarkerOverlay({
    required this.size,
    required this.origin,
    required this.viewCenter,
    required this.viewLatSpan,
    required this.followCar,
    required this.heading,
  });

  final Size size;
  final Offset origin;
  final Offset viewCenter;
  final double viewLatSpan;
  final bool followCar;
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final point = _project(origin);
    final markerSize = _markerSize;
    final visibleRect = (Offset.zero & size).inflate(markerSize);
    if (!visibleRect.contains(point)) return const SizedBox.shrink();

    return Positioned(
      left: point.dx - markerSize / 2,
      top: point.dy - markerSize / 2,
      width: markerSize,
      height: markerSize,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: followCar ? 0 : (heading ?? 0) * math.pi / 180,
          child: Image.asset(
            'assets/images/aereo_onix.png',
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }

  double get _markerSize {
    if (viewLatSpan <= 0.004) return 84;
    if (viewLatSpan <= 0.012) return 72;
    if (viewLatSpan <= 0.03) return 60;
    return 50;
  }

  Offset _project(Offset lonLat) {
    final centerLat = viewCenter.dy * math.pi / 180;
    final cosLat = math.cos(centerLat).abs().clamp(0.25, 1.0);
    final lonSpan = viewLatSpan * (size.width / size.height) / cosLat;
    final minLat = viewCenter.dy - viewLatSpan / 2;
    final minLon = viewCenter.dx - lonSpan / 2;
    final normalizedX = (lonLat.dx - minLon) / lonSpan;
    final normalizedY = 1 - ((lonLat.dy - minLat) / viewLatSpan);
    return _rotateForCompass(
      Offset(normalizedX * size.width, normalizedY * size.height),
    );
  }

  Offset _rotateForCompass(Offset point) {
    if (!followCar || heading == null) return point;

    final angle = -(heading! * math.pi / 180);
    final center = Offset(size.width / 2, size.height / 2);
    final translated = point - center;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
          translated.dx * cosA - translated.dy * sinA,
          translated.dx * sinA + translated.dy * cosA,
        ) +
        center;
  }
}

class _FullscreenMapPainter extends CustomPainter {
  const _FullscreenMapPainter({
    required this.map,
    required this.pointsOfInterest,
    required this.origin,
    required this.viewCenter,
    required this.viewLatSpan,
    required this.followCar,
    required this.heading,
    required this.vehicleIcon,
    required this.destination,
    required this.route,
    required this.darkMode,
    required this.showVehicle,
  });

  final OfflineMapData map;
  final List<MapPoi> pointsOfInterest;
  final Offset? origin;
  final Offset viewCenter;
  final double viewLatSpan;
  final bool followCar;
  final double? heading;
  final String vehicleIcon;
  final Offset? destination;
  final OfflineRoute? route;
  final bool darkMode;
  final bool showVehicle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = darkMode ? const Color(0xFF05080C) : const Color(0xFFF4F7FA),
    );

    _drawRoads(canvas, size);
    _drawPois(canvas, size);
    _drawRoute(canvas, size);
    _drawMarker(canvas, size, destination, const Color(0xFF39D8B6), 9);
    if (showVehicle) {
      _drawVehicle(
        canvas,
        size,
        origin ?? map.center,
        const Color(0xFF31E981),
        13,
      );
    }
  }

  void _drawRoads(Canvas canvas, Size size) {
    final paints = <int, Paint>{
      0: Paint()
        ..color = const Color(0xFF3A4148).withValues(alpha: 0.44)
        ..strokeWidth = 0.7
        ..style = PaintingStyle.stroke,
      1: Paint()
        ..color = const Color(0xFF58616A).withValues(alpha: 0.62)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
      2: Paint()
        ..color = const Color(0xFF737D86).withValues(alpha: 0.72)
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke,
      3: Paint()
        ..color = const Color(0xFF8A949C).withValues(alpha: 0.78)
        ..strokeWidth = 1.7
        ..style = PaintingStyle.stroke,
      4: Paint()
        ..color = const Color(0xFFA4ADB4).withValues(alpha: 0.82)
        ..strokeWidth = 2.1
        ..style = PaintingStyle.stroke,
      5: Paint()
        ..color = const Color(0xFFC0C7CC).withValues(alpha: 0.9)
        ..strokeWidth = 2.35
        ..style = PaintingStyle.stroke,
    };
    final visibleRect = (Offset.zero & size).inflate(80);

    for (final road in map.roads) {
      if (road.points.length < 2) continue;

      final points = road.points.map((point) => _project(point, size)).toList();
      if (!_projectedPathTouches(points, visibleRect)) continue;

      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paints[road.rank] ?? paints[1]!);
    }
  }

  bool _projectedPathTouches(List<Offset> points, Rect visibleRect) {
    if (points.any(visibleRect.contains)) return true;

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final segmentBounds = Rect.fromLTRB(
        math.min(a.dx, b.dx),
        math.min(a.dy, b.dy),
        math.max(a.dx, b.dx),
        math.max(a.dy, b.dy),
      );
      if (segmentBounds.overlaps(visibleRect)) return true;
    }

    return false;
  }

  void _drawPois(Canvas canvas, Size size) {
    final visibleRect = (Offset.zero & size).inflate(24);

    for (final poi in pointsOfInterest) {
      final point = _project(poi.position, size);
      if (!visibleRect.contains(point)) continue;
      _drawPoiIcon(canvas, point, poi.kind);
    }
  }

  void _drawPoiIcon(Canvas canvas, Offset center, String kind) {
    final color = _poiColor(kind);
    canvas.drawCircle(
      center,
      12,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = const Color(0xFF03101E).withValues(alpha: 0.92)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      8,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(_poiIcon(kind).codePoint),
        style: TextStyle(
          fontFamily: _poiIcon(kind).fontFamily,
          package: _poiIcon(kind).fontPackage,
          color: color,
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  IconData _poiIcon(String kind) {
    switch (kind) {
      case 'farmacia':
        return Icons.local_pharmacy;
      case 'supermercado':
        return Icons.shopping_cart;
      case 'posto':
      default:
        return Icons.local_gas_station;
    }
  }

  Color _poiColor(String kind) {
    switch (kind) {
      case 'farmacia':
        return const Color(0xFFF0C56A);
      case 'supermercado':
        return const Color(0xFFC6A9FF);
      case 'posto':
      default:
        return const Color(0xFF31E981);
    }
  }

  void _drawRoute(Canvas canvas, Size size) {
    final rawRoutePoints = route?.points;
    final routePoints = rawRoutePoints == null
        ? null
        : origin == null
            ? rawRoutePoints
            : _routePointsFromCar(rawRoutePoints);
    if (routePoints == null || routePoints.length < 2) return;

    final path = Path();
    final first = _project(routePoints.first, size);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < routePoints.length; i++) {
      final point = _project(routePoints[i], size);
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF9AF2D8).withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 8,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF39D8B6).withValues(alpha: 0.86)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 4,
    );
  }

  void _drawMarker(
    Canvas canvas,
    Size size,
    Offset? lonLat,
    Color color,
    double radius,
  ) {
    if (lonLat == null) return;
    final point = _project(lonLat, size);
    canvas.drawCircle(
        point, radius * 1.9, Paint()..color = color.withValues(alpha: 0.18));
    canvas.drawCircle(point, radius, Paint()..color = color);
    canvas.drawCircle(point, radius * 0.42, Paint()..color = Colors.white);
  }

  void _drawVehicle(
    Canvas canvas,
    Size size,
    Offset lonLat,
    Color color,
    double radius,
  ) {
    final point = _project(lonLat, size);
    canvas.drawCircle(
      point,
      radius * 1.9,
      Paint()..color = color.withValues(alpha: 0.18),
    );

    canvas.save();
    canvas.translate(point.dx, point.dy);
    canvas
        .rotate(_mapRotationRadians == 0 ? (heading ?? 0) * math.pi / 180 : 0);

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: darkMode ? 0.45 : 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = _vehicleIconPath(radius);

    canvas.drawPath(path.shift(const Offset(1.4, 1.6)), shadow);
    canvas.drawPath(path, fill);
    canvas.drawCircle(
      Offset(0, vehicleIcon == 'bolt' ? radius * 0.18 : radius * 0.14),
      radius * 0.18,
      accent,
    );
    canvas.restore();
  }

  Path _vehicleIconPath(double radius) {
    switch (vehicleIcon) {
      case 'shuttle':
        return Path()
          ..moveTo(0, -radius * 1.35)
          ..cubicTo(
            radius * 0.8,
            -radius * 0.35,
            radius * 0.55,
            radius * 0.85,
            0,
            radius * 1.05,
          )
          ..cubicTo(
            -radius * 0.55,
            radius * 0.85,
            -radius * 0.8,
            -radius * 0.35,
            0,
            -radius * 1.35,
          )
          ..close();
      case 'bolt':
        return Path()
          ..moveTo(radius * 0.12, -radius * 1.35)
          ..lineTo(radius * 0.72, -radius * 0.12)
          ..lineTo(radius * 0.26, -radius * 0.12)
          ..lineTo(radius * 0.56, radius * 1.2)
          ..lineTo(-radius * 0.72, -radius * 0.32)
          ..lineTo(-radius * 0.18, -radius * 0.32)
          ..close();
      case 'diamond':
        return Path()
          ..moveTo(0, -radius * 1.3)
          ..lineTo(radius * 0.75, 0)
          ..lineTo(0, radius * 1.05)
          ..lineTo(-radius * 0.75, 0)
          ..close();
      case 'arrow':
      default:
        return Path()
          ..moveTo(0, -radius * 1.35)
          ..lineTo(radius * 0.78, radius * 1.05)
          ..lineTo(0, radius * 0.52)
          ..lineTo(-radius * 0.78, radius * 1.05)
          ..close();
    }
  }

  Offset _project(Offset lonLat, Size size) {
    final center = viewCenter;
    final latSpan = viewLatSpan;
    final centerLat = center.dy * math.pi / 180;
    final cosLat = math.cos(centerLat).abs().clamp(0.25, 1.0);
    final lonSpan = latSpan * (size.width / size.height) / cosLat;
    final minLat = center.dy - latSpan / 2;
    final minLon = center.dx - lonSpan / 2;
    final normalizedX = (lonLat.dx - minLon) / lonSpan;
    final normalizedY = 1 - ((lonLat.dy - minLat) / latSpan);

    return _rotateForCompass(
      Offset(normalizedX * size.width, normalizedY * size.height),
      size,
    );
  }

  List<Offset> _routePointsFromCar(List<Offset> points) {
    final car = origin;
    if (car == null) return points;

    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final meters = _distanceMeters(car, points[i]);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }

    return [car, ...points.skip(nearestIndex)];
  }

  double get _mapRotationRadians {
    if (!followCar || origin == null || heading == null) return 0;
    return -(heading! * math.pi / 180);
  }

  Offset _rotateForCompass(Offset point, Size size) {
    final angle = _mapRotationRadians;
    if (angle == 0) return point;

    final center = Offset(size.width / 2, size.height / 2);
    final translated = point - center;
    final cosA = math.cos(angle);
    final sinA = math.sin(angle);
    return Offset(
          translated.dx * cosA - translated.dy * sinA,
          translated.dx * sinA + translated.dy * cosA,
        ) +
        center;
  }

  @override
  bool shouldRepaint(covariant _FullscreenMapPainter oldDelegate) {
    return oldDelegate.map != map ||
        oldDelegate.pointsOfInterest != pointsOfInterest ||
        oldDelegate.origin != origin ||
        oldDelegate.viewCenter != viewCenter ||
        oldDelegate.viewLatSpan != viewLatSpan ||
        oldDelegate.followCar != followCar ||
        oldDelegate.heading != heading ||
        oldDelegate.vehicleIcon != vehicleIcon ||
        oldDelegate.destination != destination ||
        oldDelegate.route != route ||
        oldDelegate.darkMode != darkMode ||
        oldDelegate.showVehicle != showVehicle;
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

double _bearingDegrees(Offset from, Offset to) {
  final lat1 = from.dy * math.pi / 180;
  final lat2 = to.dy * math.pi / 180;
  final deltaLon = (to.dx - from.dx) * math.pi / 180;
  final y = math.sin(deltaLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLon);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _angleDelta(double from, double to) {
  var delta = (to - from + 540) % 360 - 180;
  if (delta < -180) delta += 360;
  return delta;
}

double _distanceToRouteMeters(Offset point, List<Offset> route) {
  if (route.isEmpty) return double.infinity;
  if (route.length == 1) return _distanceMeters(point, route.first);

  var best = double.infinity;
  for (var i = 1; i < route.length; i++) {
    final distance = _distanceToSegmentMeters(point, route[i - 1], route[i]);
    if (distance < best) best = distance;
  }
  return best;
}

double _distanceToSegmentMeters(Offset point, Offset a, Offset b) {
  const latScale = 111320.0;
  final lonScale = latScale * math.cos(point.dy * math.pi / 180).abs();
  final px = point.dx * lonScale;
  final py = point.dy * latScale;
  final ax = a.dx * lonScale;
  final ay = a.dy * latScale;
  final bx = b.dx * lonScale;
  final by = b.dy * latScale;
  final dx = bx - ax;
  final dy = by - ay;

  if (dx == 0 && dy == 0) {
    return math.sqrt(math.pow(px - ax, 2) + math.pow(py - ay, 2));
  }

  final t =
      (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
  final closestX = ax + t * dx;
  final closestY = ay + t * dy;
  return math.sqrt(
    math.pow(px - closestX, 2) + math.pow(py - closestY, 2),
  );
}

class _MapSearchResult {
  const _MapSearchResult({
    required this.name,
    required this.subtitle,
    required this.kind,
    required this.icon,
    required this.position,
  });

  final String name;
  final String subtitle;
  final String kind;
  final IconData icon;
  final Offset position;
}

class _RegionalCity {
  const _RegionalCity(this.name, this.position);

  final String name;
  final Offset position;
}

const _regionalCities = <_RegionalCity>[
  _RegionalCity('Pelotas', Offset(-52.3376, -31.7654)),
  _RegionalCity('Rio Grande', Offset(-52.0986, -32.0350)),
  _RegionalCity('Sao Lourenco do Sul', Offset(-51.9784, -31.3653)),
  _RegionalCity('Cangucu', Offset(-52.6756, -31.3950)),
  _RegionalCity('Capao do Leao', Offset(-52.4836, -31.7645)),
  _RegionalCity('Turucu', Offset(-52.1756, -31.4387)),
  _RegionalCity('Morro Redondo', Offset(-52.6260, -31.5881)),
  _RegionalCity('Arroio do Padre', Offset(-52.4245, -31.4380)),
  _RegionalCity('Cerrito', Offset(-52.8122, -31.8567)),
  _RegionalCity('Pedro Osorio', Offset(-52.8180, -31.8640)),
  _RegionalCity('Arroio Grande', Offset(-53.0868, -32.2370)),
  _RegionalCity('Jaguarao', Offset(-53.3756, -32.5667)),
  _RegionalCity('Santa Vitoria do Palmar', Offset(-53.3681, -33.5189)),
  _RegionalCity('Chui', Offset(-53.4594, -33.6906)),
  _RegionalCity('Herval', Offset(-53.3940, -32.0236)),
  _RegionalCity('Pinheiro Machado', Offset(-53.3818, -31.5796)),
  _RegionalCity('Piratini', Offset(-53.1043, -31.4473)),
];

String _normalizeSearch(String value) {
  const replacements = {
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
    'Ã': 'a',
    'Ã€': 'a',
    'Ãƒ': 'a',
    'Ã‚': 'a',
    'Ã„': 'a',
    'Ã‰': 'e',
    'ÃŠ': 'e',
    'Ã‹': 'e',
    'Ã': 'i',
    'Ã': 'i',
    'Ã“': 'o',
    'Ã•': 'o',
    'Ã”': 'o',
    'Ã–': 'o',
    'Ãš': 'u',
    'Ãœ': 'u',
    'Ã‡': 'c',
  };
  var normalized = value.toLowerCase().trim();
  replacements.forEach((from, to) {
    normalized = normalized.replaceAll(from, to);
  });
  return normalized;
}

class _MapColors {
  const _MapColors({
    required this.panel,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.blue,
    required this.green,
    required this.warning,
  });

  final Color panel;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color blue;
  final Color green;
  final Color warning;

  static _MapColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _MapColors(
      panel: dark ? const Color(0xFF071527) : Colors.white,
      border: const Color(0xFF39D8B6).withValues(alpha: 0.28),
      primaryText: dark ? Colors.white : const Color(0xFF071527),
      secondaryText: dark ? Colors.white70 : const Color(0xFF45566B),
      blue: const Color(0xFF39D8B6),
      green: const Color(0xFF31E981),
      warning: const Color(0xFFFFC247),
    );
  }
}
