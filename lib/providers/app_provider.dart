import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_map.dart';
import '../models/trip_model.dart';
import '../services/audio_alert_service.dart';
import '../services/database_service.dart';
import '../services/gps_service.dart';
import '../services/offline_map_service.dart';
import '../services/offline_voice_service.dart';

class _VoiceNavigationDestination {
  const _VoiceNavigationDestination({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.aliases,
    required this.audioFiles,
    this.alternateAudioFiles = const [],
    this.arrivalAudioFile,
  });

  final String id;
  final String name;
  final String kind;
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final List<String> audioFiles;
  final List<String> alternateAudioFiles;
  final String? arrivalAudioFile;

  Offset get position => Offset(longitude, latitude);

  List<String> responseFiles() {
    if (alternateAudioFiles.isEmpty) return audioFiles;
    final evenTick = DateTime.now().millisecondsSinceEpoch.isEven;
    return evenTick ? audioFiles : alternateAudioFiles;
  }
}

class VoiceAssistantDestinationSetting {
  const VoiceAssistantDestinationSetting({
    required this.id,
    required this.name,
    required this.phrases,
  });

  final String id;
  final String name;
  final String phrases;
}

class AppProvider extends ChangeNotifier {
  final DatabaseService _db = DatabaseService.instance;
  final GpsService _gps = GpsService();
  final OfflineMapService _mapService = OfflineMapService();
  final AudioAlertService _audio = AudioAlertService();
  bool _disposed = false;

  TripModel? _activeTrip;
  List<TripModel> _trips = [];
  bool _isGpsTracking = false;
  String _statusMessage = '';
  bool _isLoading = true;
  bool _isDarkMode = true;
  bool _soundsEnabled = true;
  bool _wakeWordEnabled = false;
  bool _floatingAssistantBubbleEnabled = false;
  bool _quickVoiceCommandsEnabled = false;
  bool _voiceVolumeControlEnabled = true;
  bool _voiceMediaControlEnabled = true;
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
  DateTime? _lastGpsUiNotifyAt;
  DateTime? _lastGpsPersistAt;
  DateTime? _lastGpsPointPersistAt;
  double _cityConsumption = 9.0;
  double _tripConsumption = 12.0;
  double _fuelPrice = 5.79;
  double _tankCapacityLiters = 0;
  String _drivingMode = 'city';
  String _vehicleName = 'ONIX';
  String _mapVehicleIcon = 'arrow';
  double? _oilLastChangeKm;
  double? _oilNextChangeKm;
  bool _oilFilterChanged = false;
  String _oilType = '';
  Map<String, List<String>> _voiceDestinationAliases = {};
  OfflineRoute? _activeNavigationRoute;
  MapDestination? _activeNavigationDestination;
  OfflineMapData? _activeNavigationMap;
  OfflineRouteCalculator? _activeNavigationCalculator;
  bool _navigationRerouting = false;
  DateTime? _lastNavigationRerouteAt;

  double? _lastRemainingFuel;
  double? _lastOdometer;
  double? _lastConsumption;

  static const List<_VoiceNavigationDestination> _voiceDestinations = [
    _VoiceNavigationDestination(
      id: 'casa',
      name: 'Casa',
      kind: 'casa',
      latitude: -31.74030165726514,
      longitude: -52.31198595910366,
      aliases: ['casa', 'minha casa', 'vamos para casa', 'ir para casa'],
      audioFiles: ['assistente/caminho_pra_casa_ativo.mp3'],
      alternateAudioFiles: ['assistente/indo_pra_casa.mp3'],
      arrivalAudioFile: 'assistente/chegamos_em_casa.mp3',
    ),
    _VoiceNavigationDestination(
      id: 'krolow',
      name: 'Krolow',
      kind: 'mercado',
      latitude: -31.735146863157635,
      longitude: -52.32586841707766,
      aliases: [
        'krolow',
        'krolo',
        'crolo',
        'crolofe',
        'krolof',
        'crolof',
        'vamos para krolow',
        'vamos para crolo',
        'vamos para crolofe',
      ],
      audioFiles: ['assistente/krolow.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'posto_preferido',
      name: 'Posto Preferido',
      kind: 'posto',
      latitude: -31.760179070721417,
      longitude: -52.33998126419468,
      aliases: ['posto preferido', 'posto favorito', 'meu posto'],
      audioFiles: ['assistente/posto_preferido.mp3'],
      arrivalAudioFile: 'assistente/chegamos_posto.mp3',
    ),
    _VoiceNavigationDestination(
      id: 'central_pet',
      name: 'Central Pet',
      kind: 'pet',
      latitude: -31.759185786220783,
      longitude: -52.33921818422855,
      aliases: ['central pet', 'pet shop', 'petshop'],
      audioFiles: ['assistente/central_pet.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'mercado_publico',
      name: 'Mercado Publico',
      kind: 'mercado',
      latitude: -31.77062106540603,
      longitude: -52.342570632694844,
      aliases: ['mercado publico'],
      audioFiles: ['assistente/mercado_publico.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'guanabara',
      name: 'Supermercado Guanabara',
      kind: 'mercado',
      latitude: -31.77134523894226,
      longitude: -52.35027508043322,
      aliases: ['guanabara', 'supermercado guanabara', 'mercado guanabara'],
      audioFiles: ['assistente/guanabara.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'shopping',
      name: 'Shopping',
      kind: 'shopping',
      latitude: -31.760354329658902,
      longitude: -52.31855242299705,
      aliases: ['shopping', 'para o shopping'],
      audioFiles: ['assistente/shopping.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'baronesa',
      name: 'Museu da Baronesa',
      kind: 'museu',
      latitude: -31.75536399209294,
      longitude: -52.32033865524371,
      aliases: ['baronesa', 'museu da baronesa', 'museu baronesa'],
      audioFiles: ['assistente/baronesa.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'camboata',
      name: 'Camboata',
      kind: 'campo',
      latitude: -31.41209878419524,
      longitude: -52.414614076753644,
      aliases: ['camboata', 'seu gilson', 'gilson', 'mato'],
      audioFiles: ['assistente/rota_camboata.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'sao_lourenco',
      name: 'Sao Lourenco do Sul',
      kind: 'cidade',
      latitude: -31.368975743665874,
      longitude: -51.98216421884769,
      aliases: [
        'sao lourenco do sul',
        'sao lourenco',
        'sao lorenço',
        'santa lorenzo',
        'santa lorenco',
        'sao lorenco',
        'sao lourenço',
        'sao lourenso',
        'sao lourenço do sul',
        'vamos para sao lourenco',
        'vamos para sao lourenco do sul',
      ],
      audioFiles: ['assistente/sao_lourenco.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'santa_vitoria',
      name: 'Santa Vitoria do Palmar',
      kind: 'cidade',
      latitude: -33.523557630090096,
      longitude: -53.37638548894094,
      aliases: ['santa vitoria do palmar', 'santa vitoria'],
      audioFiles: ['assistente/santa_vitoria.mp3'],
    ),
    _VoiceNavigationDestination(
      id: 'pet_vida',
      name: 'PetVida',
      kind: 'veterinario',
      latitude: -31.75588508816931,
      longitude: -52.33289401883183,
      aliases: ['veterinario do chico', 'pet vida', 'petvida', 'veterinario'],
      audioFiles: ['assistente/pet_vida.mp3'],
    ),
  ];

  TripModel? get activeTrip => _activeTrip;
  List<TripModel> get trips => _trips;
  bool get isGpsTracking => _isGpsTracking;
  String get statusMessage => _statusMessage;
  bool get isLoading => _isLoading;
  bool get isDarkMode => _isDarkMode;
  bool get soundsEnabled => _soundsEnabled;
  bool get wakeWordEnabled => _wakeWordEnabled;
  bool get floatingAssistantBubbleEnabled => _floatingAssistantBubbleEnabled;
  bool get quickVoiceCommandsEnabled => _quickVoiceCommandsEnabled;
  bool get voiceVolumeControlEnabled => _voiceVolumeControlEnabled;
  bool get voiceMediaControlEnabled => _voiceMediaControlEnabled;
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
  double? get oilLastChangeKm => _oilLastChangeKm;
  double? get oilNextChangeKm => _oilNextChangeKm;
  bool get oilFilterChanged => _oilFilterChanged;
  String get oilType => _oilType;
  List<VoiceAssistantDestinationSetting> get voiceDestinationSettings =>
      _voiceDestinations
          .map(
            (destination) => VoiceAssistantDestinationSetting(
              id: destination.id,
              name: destination.name,
              phrases: _phrasesToText(_voiceAliasesFor(destination)),
            ),
          )
          .toList(growable: false);
  OfflineRoute? get activeNavigationRoute => _activeNavigationRoute;
  MapDestination? get activeNavigationDestination =>
      _activeNavigationDestination;
  bool get isCityMode => _drivingMode == 'city';
  double get selectedConsumption =>
      isCityMode ? _cityConsumption : _tripConsumption;
  double? get lastRemainingFuel => _lastRemainingFuel;
  double? get lastOdometer => _lastOdometer;
  double? get lastConsumption => _lastConsumption;
  double? get oilKmRemaining {
    if (_oilNextChangeKm == null || _activeTrip == null) return null;
    return _oilNextChangeKm! - _activeTrip!.currentOdometer;
  }

  bool get hasOilChangeInfo =>
      _oilLastChangeKm != null && _oilNextChangeKm != null;

  bool get isOilChangeDue {
    final remaining = oilKmRemaining;
    return remaining != null && remaining <= 0;
  }

  bool get isOilChangeNear {
    final remaining = oilKmRemaining;
    if (remaining == null) return false;
    return remaining > 0 && remaining <= 500;
  }

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
    _wakeWordEnabled = prefs.getBool('wake_word_enabled') ?? false;
    _floatingAssistantBubbleEnabled =
        prefs.getBool('floating_assistant_bubble_enabled') ?? false;
    _quickVoiceCommandsEnabled =
        prefs.getBool('quick_voice_commands_enabled') ?? false;
    _voiceVolumeControlEnabled =
        prefs.getBool('voice_volume_control_enabled') ?? true;
    _voiceMediaControlEnabled =
        prefs.getBool('voice_media_control_enabled') ?? true;
    _audio.setEnabled(_soundsEnabled);
    _drivingMode = prefs.getString('driving_mode') ?? 'city';
    _vehicleName = prefs.getString('vehicle_name') ?? 'ONIX';
    _mapVehicleIcon = prefs.getString('map_vehicle_icon') ?? 'arrow';
    _oilLastChangeKm = prefs.getDouble('oil_last_change_km');
    _oilNextChangeKm = prefs.getDouble('oil_next_change_km');
    _oilFilterChanged = prefs.getBool('oil_filter_changed') ?? false;
    _oilType = prefs.getString('oil_type') ?? '';
    _voiceDestinationAliases = _decodeVoiceAliases(
      prefs.getString('voice_destination_aliases'),
    );
  }

  Future<void> saveOilChange({
    required double lastChangeKm,
    required double nextChangeKm,
    required bool filterChanged,
    required String oilType,
  }) async {
    if (_disposed) return;
    _oilLastChangeKm = lastChangeKm;
    _oilNextChangeKm = nextChangeKm;
    _oilFilterChanged = filterChanged;
    _oilType = oilType.trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('oil_last_change_km', _oilLastChangeKm!);
    await prefs.setDouble('oil_next_change_km', _oilNextChangeKm!);
    await prefs.setBool('oil_filter_changed', _oilFilterChanged);
    await prefs.setString('oil_type', _oilType);

    _statusMessage = 'Troca de óleo salva';
    notifyListeners();
  }

  Map<String, List<String>> _decodeVoiceAliases(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      final result = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          final phrases = value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false);
          if (phrases.isNotEmpty) result[entry.key] = phrases;
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  List<String> _textToPhrases(String text) {
    return text
        .split(RegExp(r'[,;\n]'))
        .map((phrase) => phrase.trim())
        .where((phrase) => phrase.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _phrasesToText(List<String> phrases) => phrases.join(', ');

  List<String> _voiceAliasesFor(_VoiceNavigationDestination destination) {
    final custom = _voiceDestinationAliases[destination.id] ?? const <String>[];
    return {...destination.aliases, ...custom}.toList(growable: false);
  }

  Future<void> saveVoiceDestinationAliases(
    Map<String, String> destinationPhrases,
  ) async {
    if (_disposed) return;
    final next = <String, List<String>>{};
    for (final destination in _voiceDestinations) {
      final phrases = _textToPhrases(destinationPhrases[destination.id] ?? '');
      final defaults = destination.aliases.map(_normalizeVoiceCommand).toSet();
      final custom = phrases
          .where((phrase) => !defaults.contains(_normalizeVoiceCommand(phrase)))
          .toList(growable: false);
      if (custom.isNotEmpty) next[destination.id] = custom;
    }

    _voiceDestinationAliases = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_destination_aliases', jsonEncode(next));
    await OfflineVoiceService.instance.reloadGrammar();
    _statusMessage = 'Frases do assistente salvas';
    notifyListeners();
  }

  Future<void> saveAssistantAmbientSettings({
    required bool wakeWordEnabled,
    required bool floatingBubbleEnabled,
    bool quickVoiceCommandsEnabled = false,
    bool voiceVolumeControlEnabled = true,
    bool voiceMediaControlEnabled = true,
  }) async {
    if (_disposed) return;
    _wakeWordEnabled = wakeWordEnabled;
    _floatingAssistantBubbleEnabled = floatingBubbleEnabled;
    _quickVoiceCommandsEnabled = quickVoiceCommandsEnabled;
    _voiceVolumeControlEnabled = voiceVolumeControlEnabled;
    _voiceMediaControlEnabled = voiceMediaControlEnabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_word_enabled', _wakeWordEnabled);
    await prefs.setBool(
      'floating_assistant_bubble_enabled',
      _floatingAssistantBubbleEnabled,
    );
    await prefs.setBool(
      'quick_voice_commands_enabled',
      _quickVoiceCommandsEnabled,
    );
    await prefs.setBool(
      'voice_volume_control_enabled',
      _voiceVolumeControlEnabled,
    );
    await prefs.setBool(
      'voice_media_control_enabled',
      _voiceMediaControlEnabled,
    );

    _statusMessage = 'Assistente atualizado';
    notifyListeners();
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
    if (_disposed) return;
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

  Future<void> answerVoiceAssistantCommand(String command) async {
    if (_disposed) return;
    final normalized = _normalizeVoiceCommand(command);

    final routed = await _tryActivateVoiceNavigation(normalized);
    if (routed) return;

    final trip = _activeTrip;
    if (trip == null) {
      await _audio.playAssistantFallback();
      return;
    }

    final fuelPercent = (fuelPercentage * 100).round().clamp(0, 100);
    final autonomyKm = trip.estimatedRange.round().clamp(0, 999999);
    final remainingLiters = trip.remainingFuel.clamp(0.0, 999999.0);
    final intent = _detectVoiceIntent(normalized);
    debugPrint('[VoiceAssistant] provider intent="$intent" trip=true');

    switch (intent) {
      case 'liters':
        await _audio.playAssistantLitersRemaining(remainingLiters);
        return;
      case 'fuel':
        await _audio.playAssistantFuelOnly(fuelPercent);
        return;
      case 'autonomy':
        await _audio.playAssistantAutonomy(autonomyKm);
        return;
      case 'oil':
        await _audio.playAssistantOilStatus(
          remainingKm: oilKmRemaining?.round(),
          due: isOilChangeDue,
        );
        return;
      case 'summary':
      default:
        await _audio.playAssistantFuelSummary(
          fuelPercent: fuelPercent,
          autonomyKm: autonomyKm,
        );
        return;
    }
  }

  Future<bool> _tryActivateVoiceNavigation(String normalized) async {
    if (_disposed) return false;
    final destination = _detectVoiceDestination(normalized);
    if (destination == null) return false;

    _statusMessage = 'Calculando rota para ${destination.name}...';
    notifyListeners();

    final origin = await _currentNavigationOrigin();
    if (origin == null) {
      _statusMessage = 'Aguardando GPS para calcular rota';
      notifyListeners();
      return true;
    }

    try {
      final map = await _mapService.loadCurrentMap();
      final calculator = OfflineRouteCalculator(map);
      final route = calculator.calculate(
        origin,
        destination.position,
      );

      if (route == null) {
        _statusMessage = 'Rota indisponivel para ${destination.name}';
        notifyListeners();
        return true;
      }

      _activeNavigationRoute = route;
      _activeNavigationMap = map;
      _activeNavigationCalculator = calculator;
      _lastNavigationRerouteAt = DateTime.now();
      _activeNavigationDestination = MapDestination(
        name: destination.name,
        position: destination.position,
        kind: destination.kind,
      );
      _statusMessage = 'Rota para ${destination.name} ativa';
      notifyListeners();
      await _audio.playAssistantFiles(destination.responseFiles());
      return true;
    } catch (error) {
      debugPrint('[VoiceAssistant] route error for ${destination.id}: $error');
      _statusMessage =
          'Nao foi possivel calcular rota para ${destination.name}';
      notifyListeners();
      return true;
    }
  }

  Future<Offset?> _currentNavigationOrigin() async {
    final lat = _lastGpsLatitude;
    final lon = _lastGpsLongitude;
    if (lat != null && lon != null) return Offset(lon, lat);

    final allowed = await _gps.requestPermission();
    if (!allowed) return null;

    final position = await _gps.getCurrentPosition();
    if (position == null) return null;

    _lastGpsLatitude = position.latitude;
    _lastGpsLongitude = position.longitude;
    _lastGpsHeading = _headingForPosition(position);
    _lastGpsPositionAt = DateTime.now();
    return Offset(position.longitude, position.latitude);
  }

  _VoiceNavigationDestination? _detectVoiceDestination(String normalized) {
    if (normalized.isEmpty) return null;

    _VoiceNavigationDestination? best;
    var bestScore = 0;

    for (final destination in _voiceDestinations) {
      var score = 0;
      for (final alias in _voiceAliasesFor(destination)) {
        final normalizedAlias = _normalizeVoiceCommand(alias);
        if (normalized == normalizedAlias) {
          score += 100;
        } else if (normalized.contains(normalizedAlias)) {
          score += 60 + normalizedAlias.length;
        } else {
          final aliasWords = normalizedAlias.split(' ');
          for (final word in aliasWords) {
            if (word.length >= 3 && normalized.contains(word)) score += 6;
          }
        }
      }

      if (score > bestScore) {
        bestScore = score;
        best = destination;
      }
    }

    return bestScore >= 12 ? best : null;
  }

  String _normalizeVoiceCommand(String command) {
    final normalized = command
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return normalized
        .replaceAll('conbustivel', 'combustivel')
        .replaceAll('com bustivel', 'combustivel')
        .replaceAll('gazo lina', 'gasolina')
        .replaceAll('auto nomia', 'autonomia')
        .replaceAll('quilometros', 'quilometros')
        .replaceAll('quilometro', 'quilometro')
        .replaceAll('olio', 'oleo')
        .replaceAll('crolofe', 'crolofe')
        .replaceAll('crolo fi', 'crolofe')
        .replaceAll('crolo f', 'crolofe')
        .replaceAll('camboata', 'camboata')
        .replaceAll('santa lorenzo', 'sao lourenco')
        .replaceAll('santa lorenco', 'sao lourenco')
        .replaceAll('sao lorenco', 'sao lourenco')
        .replaceAll('sao lourenso', 'sao lourenco')
        .replaceAll('sao lorenzo', 'sao lourenco')
        .replaceAll('sao lourenco do sul', 'sao lourenco do sul');
  }

  String _detectVoiceIntent(String normalized) {
    if (normalized.isEmpty) return 'summary';

    final scores = <String, int>{
      'summary': _voiceIntentScore(
        normalized,
        phrases: const [
          'como estamos',
          'como esta',
          'status',
          'resumo',
          'situacao',
          'informacoes',
          'painel',
          'me fala',
        ],
        words: const ['status', 'resumo', 'situacao', 'painel'],
      ),
      'fuel': _voiceIntentScore(
        normalized,
        phrases: const [
          'como estamos de combustivel',
          'nivel de combustivel',
          'quanto combustivel',
          'quanto tem no tanque',
          'como esta o tanque',
          'estou com quanto',
          'tem gasolina',
        ],
        words: const [
          'combustivel',
          'gasolina',
          'tanque',
          'litros',
          'reserva',
          'abastecimento',
          'abastecer',
        ],
      ),
      'autonomy': _voiceIntentScore(
        normalized,
        phrases: const [
          'qual autonomia',
          'quanto posso rodar',
          'quantos quilometros',
          'quanto falta de autonomia',
          'qual alcance',
          'ate onde da para ir',
        ],
        words: const [
          'autonomia',
          'alcance',
          'rodar',
          'andar',
          'quilometro',
          'quilometros',
          'km',
          'distancia',
        ],
      ),
      'oil': _voiceIntentScore(
        normalized,
        phrases: const [
          'troca de oleo',
          'quando trocar oleo',
          'como esta o oleo',
          'falta quanto para troca',
          'proxima troca',
          'filtro de oleo',
        ],
        words: const ['oleo', 'troca', 'filtro', 'lubrificante'],
      ),
    };

    var bestIntent = 'summary';
    var bestScore = scores[bestIntent] ?? 0;
    for (final entry in scores.entries) {
      if (entry.value > bestScore) {
        bestIntent = entry.key;
        bestScore = entry.value;
      }
    }

    return bestScore <= 0 ? 'summary' : bestIntent;
  }

  int _voiceIntentScore(
    String normalized, {
    required List<String> phrases,
    required List<String> words,
  }) {
    var score = 0;
    final tokens = normalized.split(' ');

    for (final phrase in phrases) {
      if (normalized.contains(phrase)) score += 8;
    }

    for (final word in words) {
      if (normalized.contains(word)) score += 4;
      for (final token in tokens) {
        if (_voiceTokenLooksLike(token, word)) score += 2;
      }
    }

    return score;
  }

  bool _voiceTokenLooksLike(String token, String target) {
    if (token.length < 3 || target.length < 3) return false;
    if (token == target) return true;
    if (target.length >= 5 &&
        (token.startsWith(target.substring(0, 4)) ||
            target.startsWith(token))) {
      return true;
    }
    final limit = target.length >= 7 ? 2 : 1;
    return _levenshteinDistance(token, target, limit) <= limit;
  }

  int _levenshteinDistance(String a, String b, int maxDistance) {
    if ((a.length - b.length).abs() > maxDistance) return maxDistance + 1;
    var previous = List<int>.generate(b.length + 1, (index) => index);

    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0);
      current[0] = i + 1;
      var rowMin = current[0];

      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + cost,
        ].reduce((value, element) => value < element ? value : element);
        if (current[j + 1] < rowMin) rowMin = current[j + 1];
      }

      if (rowMin > maxDistance) return maxDistance + 1;
      previous = current;
    }

    return previous[b.length];
  }

  Future<void> setDrivingMode(String mode) async {
    if (_disposed) return;
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
    OfflineMapData? map,
    OfflineRouteCalculator? calculator,
  }) {
    _activeNavigationRoute = route;
    _activeNavigationDestination = destination;
    if (map != null) _activeNavigationMap = map;
    if (calculator != null) _activeNavigationCalculator = calculator;
    _lastNavigationRerouteAt = DateTime.now();
    notifyListeners();
  }

  void clearActiveNavigationRoute() {
    if (_activeNavigationRoute == null &&
        _activeNavigationDestination == null) {
      return;
    }

    _activeNavigationRoute = null;
    _activeNavigationDestination = null;
    _activeNavigationMap = null;
    _activeNavigationCalculator = null;
    _lastNavigationRerouteAt = null;
    _navigationRerouting = false;
    notifyListeners();
  }

  Future<void> applySelectedConsumption() async {
    if (_disposed || _activeTrip == null || selectedConsumption <= 0) return;

    _activeTrip = _activeTrip!.withConsumption(selectedConsumption);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();
  }

  Future<void> toggleThemeMode() async {
    if (_disposed) return;
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
    if (_disposed) return;
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
    if (_disposed) return;
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
      _lastGpsUiNotifyAt = null;
      _lastGpsPersistAt = null;
      _lastGpsPointPersistAt = null;

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

    if (_disposed || _activeTrip == null || _isGpsTracking || _gpsStoppedByUser)
      return;
    if (_smartGpsAutoAttempts >= 5) {
      _statusMessage = 'GPS automatico sem sinal - toque para iniciar';
      notifyListeners();
      return;
    }

    _statusMessage = 'GPS automatico preparando sinal...';
    notifyListeners();

    _smartGpsStartTimer = Timer(delay, () async {
      if (_disposed) return;
      await _trySmartGpsAutoStart();
    });
  }

  Future<void> _trySmartGpsAutoStart() async {
    if (_disposed || _activeTrip == null || _isGpsTracking || _gpsStoppedByUser)
      return;
    if (_autoGpsStarting) return;

    _autoGpsStarting = true;
    _smartGpsAutoAttempts++;

    try {
      await startGpsTracking(automatic: true);
    } finally {
      _autoGpsStarting = false;
    }

    if (_disposed) return;
    if (!_isGpsTracking && !_gpsStoppedByUser && _activeTrip != null) {
      _scheduleSmartGpsAutoStart(delay: const Duration(seconds: 12));
    }
  }

  Future<void> updateOdometer(double newOdometer) async {
    if (_activeTrip == null || _disposed) return;

    if (newOdometer < _activeTrip!.currentOdometer) {
      _statusMessage = 'KM não pode ser menor que o atual';
      notifyListeners();
      return;
    }

    _activeTrip!.updateFromManualOdometer(newOdometer);

    await _db.updateTrip(_activeTrip!);
    await _saveLastOdometer(newOdometer);
    await _saveRefuelData();

    if (_disposed) return;
    _statusMessage = 'KM atualizado: ${newOdometer.toStringAsFixed(0)}';

    notifyListeners();
    await _audio.playManualNumbers();
    if (_disposed) return;
    await _checkDashboardAudioAlerts();
    await _restartGpsTrackingFromCurrentTrip();
  }

  Future<void> setCurrentOdometer(double odometer) async {
    if (_disposed || _activeTrip == null) return;

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
    if (_disposed || _activeTrip == null) return;

    _activeTrip = _activeTrip!.withRemainingFuel(liters);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();

    _statusMessage = 'Combustível ajustado: ${liters.toStringAsFixed(1)}L';
    notifyListeners();
    await _checkFuelLevelAlerts();
  }

  Future<void> setEstimatedRange(double rangeKm) async {
    if (_disposed || _activeTrip == null) return;

    _activeTrip = _activeTrip!.withEstimatedRange(rangeKm);
    await _db.updateTrip(_activeTrip!);
    await _saveRefuelData();

    _statusMessage = 'Autonomia ajustada: ${rangeKm.toStringAsFixed(0)}km';
    notifyListeners();
  }

  Future<void> setDistanceTraveled(double distanceKm) async {
    if (_disposed || _activeTrip == null) return;

    _activeTrip = _activeTrip!.withDistanceTraveled(distanceKm);
    await _db.updateTrip(_activeTrip!);
    await _saveLastOdometer(_activeTrip!.currentOdometer);
    await _saveRefuelData();

    _statusMessage = 'Distância ajustada: ${distanceKm.toStringAsFixed(1)}km';
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
    if (_disposed) return;
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
          : 'GPS indisponível - aguardando sinal...';
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
        _lastGpsPositionAt = DateTime.now();
        if (_gpsRawPositionCount == 1) {
          _statusMessage = 'GPS recebendo posições: $_gpsRawPositionCount';
          _notifyGpsUi(force: true);
        } else {
          _notifyGpsUi();
        }
      },
      onMovementMeasured: (position, movementMeters) {
        _lastGpsMovementMeters = movementMeters;
        if (_gpsRawPositionCount % 5 == 0) {
          _statusMessage = 'GPS recebendo posições: $_gpsRawPositionCount';
          notifyListeners();
        }
      },
      onPositionIgnored: (position, reason) {
        _gpsIgnoredPositionCount++;
        _lastGpsAccuracy = position.accuracy;
        _lastGpsHeading = _headingForPosition(position);
        _statusMessage = 'GPS ignorou ponto: $reason';
        _notifyGpsUi(force: true);
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
        await _maybeRerouteActiveNavigation(lat, lng);

        final deltaKm = deltaMeters / 1000;
        final newOdometer = _activeTrip!.currentOdometer + deltaKm;
        _activeTrip!.updateFromGps(newOdometer, lat, lng);

        _statusMessage = 'GPS: +${deltaKm.toStringAsFixed(3)}km | '
            'Total: ${_activeTrip!.distanceTraveled.toStringAsFixed(1)}km | '
            'Atualizações: $_gpsUpdateCount';

        final now = DateTime.now();
        final shouldPersistTrip = _lastGpsPersistAt == null ||
            now.difference(_lastGpsPersistAt!) >= const Duration(seconds: 4) ||
            deltaMeters >= 80;
        if (shouldPersistTrip) {
          _lastGpsPersistAt = now;
          await _db.updateTrip(_activeTrip!);
          await _saveLastOdometer(newOdometer);
          await _saveRefuelData();
        }

        final shouldPersistPoint = _lastGpsPointPersistAt == null ||
            now.difference(_lastGpsPointPersistAt!) >=
                const Duration(seconds: 5) ||
            deltaMeters >= 25;
        if (shouldPersistPoint) {
          _lastGpsPointPersistAt = now;
          await _db.addGpsPoint(
            _activeTrip!.id!,
            GpsPoint(
              latitude: lat,
              longitude: lng,
              odometer: newOdometer,
              timestamp: now,
            ),
          );
        }

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
    _lastGpsPositionAt = null;
    _lastGpsUiNotifyAt = null;
    _lastGpsPersistAt = null;
    _lastGpsPointPersistAt = null;
    _suppressNextGpsConnectedAudio = true;

    await startGpsTracking();
  }

  Future<void> reconnectGpsTracking() async {
    if (_disposed || _activeTrip == null) return;

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
    _lastGpsUiNotifyAt = null;
    _lastGpsPersistAt = null;
    _lastGpsPointPersistAt = null;
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

  void _notifyGpsUi({bool force = false}) {
    final now = DateTime.now();
    final last = _lastGpsUiNotifyAt;
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 220)) {
      return;
    }
    _lastGpsUiNotifyAt = now;
    notifyListeners();
  }

  Future<void> _maybeRerouteActiveNavigation(double lat, double lon) async {
    if (_navigationRerouting ||
        _activeNavigationRoute == null ||
        _activeNavigationDestination == null) {
      return;
    }

    final now = DateTime.now();
    final last = _lastNavigationRerouteAt;
    if (last != null && now.difference(last) < const Duration(seconds: 12)) {
      return;
    }

    final origin = Offset(lon, lat);
    final distance =
        _distanceToRouteMeters(origin, _activeNavigationRoute!.points);
    if (distance < 75) return;

    _navigationRerouting = true;
    _lastNavigationRerouteAt = now;
    try {
      final map = _activeNavigationMap ?? await _mapService.loadCurrentMap();
      _activeNavigationMap = map;
      final calculator =
          _activeNavigationCalculator ?? OfflineRouteCalculator(map);
      _activeNavigationCalculator = calculator;
      final destination = _activeNavigationDestination!;
      final route = await Future<OfflineRoute?>(
        () => calculator.calculate(origin, destination.position),
      );
      if (route == null) return;

      _activeNavigationRoute = route;
      _statusMessage = 'Rota recalculada';
      notifyListeners();
    } catch (error) {
      debugPrint('[Navigation] reroute failed: $error');
    } finally {
      _navigationRerouting = false;
    }
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
      if (_disposed || _activeTrip == null) return;

      if (!_gps.isTracking) {
        _handleGpsStopped();
        return;
      }

      final lastPositionAt = _lastGpsPositionAt;
      if (lastPositionAt == null) return;

      final silence = DateTime.now().difference(lastPositionAt);
      if (silence.inSeconds >= 90) {
        _statusMessage = 'GPS ativo, mas sem novas posições ha '
            '${silence.inSeconds}s';
        notifyListeners();
      }
    });
  }

  void _handleGpsStopped() {
    if (_disposed || !_isGpsTracking) return;

    _isGpsTracking = false;
    _lastGpsUiNotifyAt = null;
    _lastGpsPersistAt = null;
    _lastGpsPointPersistAt = null;
    _statusMessage = _gpsStoppedByUser
        ? 'GPS pausado pelo usuário'
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
      if (_disposed) return;
      _audio.playStartupCare();
    });
  }

  void _scheduleThirtyMinuteTripAudio() {
    _thirtyMinuteTripTimer?.cancel();

    if (_disposed || _activeTrip == null || _thirtyMinuteAlertPlayed) return;

    final elapsed = DateTime.now().difference(_activeTrip!.createdAt);
    final remaining = const Duration(minutes: 30) - elapsed;

    if (remaining <= Duration.zero) {
      _thirtyMinuteAlertPlayed = true;
      _audio.playThirtyMinuteTrip();
      return;
    }

    _thirtyMinuteTripTimer = Timer(remaining, () {
      if (_disposed || _activeTrip == null || _thirtyMinuteAlertPlayed) return;

      _thirtyMinuteAlertPlayed = true;
      _audio.playThirtyMinuteTrip();
    });
  }

  Future<void> _checkDashboardAudioAlerts() async {
    if (_disposed) return;
    await _checkFuelLevelAlerts();
    if (_disposed) return;
    await _checkHundredKmAlert();
    if (_disposed) return;
    await _checkThirtyMinuteTripAlert();
  }

  Future<void> _checkFuelLevelAlerts() async {
    if (_disposed || _activeTrip == null) return;

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
    if (_disposed || _activeTrip == null || _hundredKmAlertPlayed) return;
    if (_activeTrip!.distanceTraveled < 100) return;

    _hundredKmAlertPlayed = true;
    await _audio.playHundredKmPosto();
  }

  Future<void> _checkThirtyMinuteTripAlert() async {
    if (_disposed || _activeTrip == null || _thirtyMinuteAlertPlayed) return;

    final elapsed = DateTime.now().difference(_activeTrip!.createdAt);
    if (elapsed.inMinutes < 30) return;

    _thirtyMinuteAlertPlayed = true;
    await _audio.playThirtyMinuteTrip();
  }

  Future<void> stopGpsTracking() async {
    if (_disposed) return;
    _gpsStoppedByUser = true;
    _smartGpsStartTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _gps.stopTracking();

    if (_activeTrip != null) {
      await _db.updateTrip(_activeTrip!);
      await _saveRefuelData();
    }

    _isGpsTracking = false;
    _lastGpsUiNotifyAt = null;
    _lastGpsPersistAt = null;
    _lastGpsPointPersistAt = null;
    _statusMessage =
        'GPS pausado - percorrido: ${_gpsDistance.toStringAsFixed(0)}m';

    notifyListeners();
  }

  Future<void> endCurrentTrip() async {
    if (_disposed || _activeTrip == null) return;

    _lastRemainingFuel = _activeTrip!.remainingFuel;
    _lastOdometer = _activeTrip!.currentOdometer;
    _lastConsumption = _activeTrip!.consumptionPerKm;

    await _saveRefuelData();

    _gps.stopTracking();
    _isGpsTracking = false;
    _lastGpsUiNotifyAt = null;
    _lastGpsPersistAt = null;
    _lastGpsPointPersistAt = null;
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
    if (_disposed) return;
    await _db.deleteTrip(id);
    if (_disposed) return;
    await _loadTrips();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _startupCareTimer?.cancel();
    _thirtyMinuteTripTimer?.cancel();
    _gpsWatchdogTimer?.cancel();
    _smartGpsStartTimer?.cancel();
    _gps.dispose();
    _audio.dispose();
    super.dispose();
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
  return 12742000 * math.asin(math.sqrt(hav));
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

  final abx = bx - ax;
  final aby = by - ay;
  final ab2 = abx * abx + aby * aby;
  if (ab2 <= 0) return _distanceMeters(point, a);

  final t = (((px - ax) * abx + (py - ay) * aby) / ab2).clamp(0.0, 1.0);
  final cx = ax + abx * t;
  final cy = ay + aby * t;
  final dx = px - cx;
  final dy = py - cy;
  return math.sqrt(dx * dx + dy * dy);
}
