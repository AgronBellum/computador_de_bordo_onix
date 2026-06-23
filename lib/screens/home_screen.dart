import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';

import '../models/offline_map.dart';
import '../models/trip_model.dart';
import '../providers/app_provider.dart';
import '../services/offline_map_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _odometerController = TextEditingController();
  final OfflineMapService _offlineMapService = OfflineMapService();
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  Future<List<SavedMapPlace>>? _placesCacheFuture;
  OfflineMapData? _cachedNavigationMap;
  OfflineRouteCalculator? _cachedRouteCalculator;
  List<SavedMapPlace> _cachedPlaces = const [];
  bool _showLocalMapPreview = false;
  bool _voiceAssistantBusy = false;
  VideoPlayerController? _voiceVideoController;

  static const MethodChannel _nativeChannel =
      MethodChannel('onyx_gps/obd_bluetooth');

  static const Color _bg = Color(0xFF020914);
  static const Color _bar = Color(0xFF050D19);
  static const Color _card = Color(0xFF061426);
  static const Color _card2 = Color(0xFF020B17);
  static const Color _blue = Color(0xFF1677FF);
  static const Color _green = Color(0xFF69F01B);
  static const Color _amber = Color(0xFFFFC857);
  static const Color _oilDue = Color(0xFFFF5A1F);
  static const Color _purple = Color(0xFFB7A2E8);
  static const Color _line = Color(0xFF0B3C73);

  @override
  void initState() {
    super.initState();
    _placesCacheFuture = _warmPlacesCache();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  Future<List<SavedMapPlace>> _warmPlacesCache() async {
    final places = await _offlineMapService.loadPlaces();
    _cachedPlaces = places;
    return places;
  }

  Future<OfflineMapData> _loadNavigationMap() async {
    final cached = _cachedNavigationMap;
    if (cached != null) return cached;

    final map = await _offlineMapService.loadCurrentMap();
    _cachedNavigationMap = map;
    _cachedRouteCalculator = OfflineRouteCalculator(map);
    return map;
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _odometerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Consumer<AppProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const Center(
                child: CircularProgressIndicator(color: _blue),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    _buildHeader(provider),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, dashboardConstraints) {
                          return provider.activeTrip == null
                              ? _buildEmptyState(
                                  context,
                                  dashboardConstraints,
                                )
                              : _buildLandscapeDashboard(
                                  context,
                                  provider,
                                  dashboardConstraints,
                                );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildLandscapeDashboard(
    BuildContext context,
    AppProvider provider,
    BoxConstraints constraints,
  ) {
    final trip = provider.activeTrip!;
    final compact = constraints.maxWidth < 900 || constraints.maxHeight < 430;
    final gap = compact ? 6.0 : 14.0;
    final padding = compact
        ? const EdgeInsets.fromLTRB(6, 6, 6, 6)
        : const EdgeInsets.fromLTRB(18, 14, 18, 14);
    final availableHeight =
        math.max(180.0, constraints.maxHeight - padding.top - padding.bottom);
    final cockpitWidth = compact ? 180.0 : 260.0;
    final leftTopHeight = compact
        ? availableHeight * 0.49
        : (availableHeight * 0.5).clamp(230.0, 410.0);
    final leftMetricHeight = compact
        ? availableHeight * 0.2
        : (availableHeight * 0.17).clamp(92.0, 132.0);
    final leftActionHeight = math.max(
      compact ? 56.0 : 106.0,
      availableHeight - leftTopHeight - leftMetricHeight - (gap * 2),
    );

    return SingleChildScrollView(
      padding: padding,
      child: SizedBox(
        height: availableHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: leftTopHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 27,
                          child: _BigNumberCard(
                            title: 'LITROS RESTANTES',
                            value: _decimal(trip.remainingFuel, 1),
                            unit: 'L',
                            icon: Icons.local_gas_station,
                            color: _blue,
                            onTap: () => _showNumberEditDialog(
                              context: context,
                              title: 'Alterar litros restantes',
                              currentValue: trip.remainingFuel,
                              suffix: 'L',
                              onSave: provider.setRemainingFuel,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 38,
                          child: _FuelGaugeCard(
                            percentage: provider.fuelPercentage,
                            fuelName: 'GASOLINA',
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 21,
                          child: _BigNumberCard(
                            title: 'AUTONOMIA',
                            value: trip.estimatedRange.toStringAsFixed(0),
                            unit: 'km',
                            footer: 'Autonomia estimada',
                            icon: Icons.local_gas_station,
                            color: _blue,
                            onTap: () => _showNumberEditDialog(
                              context: context,
                              title: 'Alterar autonomia',
                              currentValue: trip.estimatedRange,
                              suffix: 'km',
                              digits: 0,
                              onSave: provider.setEstimatedRange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  SizedBox(
                    height: leftMetricHeight,
                    child: Row(
                      children: [
                        Expanded(
                          child: _MetricCard(
                            icon: Icons.route,
                            title: 'KM ATUAL',
                            value: trip.currentOdometer.floor().toString(),
                            unit: 'km',
                            onTap: () => _showNumberEditDialog(
                              context: context,
                              title: 'Alterar KM atual',
                              currentValue: trip.currentOdometer,
                              suffix: 'km',
                              digits: 0,
                              onSave: provider.setCurrentOdometer,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: _MetricCard(
                            icon: Icons.route,
                            title: 'KM PERCORRIDO',
                            value: _decimal(trip.distanceTraveled, 1),
                            unit: 'km',
                            onTap: () => _showNumberEditDialog(
                              context: context,
                              title: 'Alterar KM percorrido',
                              currentValue: trip.distanceTraveled,
                              suffix: 'km',
                              onSave: provider.setDistanceTraveled,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          child: _MetricCard(
                            icon: Icons.bar_chart,
                            title: 'CONSUMO MÉDIO GERAL',
                            value: _decimal(trip.consumptionPerKm, 1),
                            unit: 'km/L',
                            onTap: () => _showNumberEditDialog(
                              context: context,
                              title: 'Alterar consumo médio',
                              currentValue: trip.consumptionPerKm,
                              suffix: 'km/L',
                              onSave: provider.setConsumption,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap),
                  SizedBox(
                    height: leftActionHeight,
                    child: Row(
                      children: [
                        Expanded(
                          flex: 27,
                          child: _buildFuelOilActions(provider),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 34,
                          child: _NavigationRouteCard(
                            instruction: _dashboardRouteInstruction(provider),
                            destination:
                                provider.activeNavigationDestination?.name,
                            hasRoute: provider.activeNavigationRoute != null,
                            onTap: () =>
                                _showNavigationRouteDialog(context, provider),
                            onFavoritesTap: () =>
                                _showNavigationRouteDialog(context, provider),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: 19,
                          child: _CompactCostCard(
                            value: _estimatedCostValue(provider, trip),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: cockpitWidth,
              child: _PelotasOfflineMapCard(
                latitude: provider.lastGpsLatitude,
                longitude: provider.lastGpsLongitude,
                heading: provider.lastGpsHeading,
                active: provider.isGpsTracking,
                vehicleIcon: provider.mapVehicleIcon,
                route: provider.activeNavigationRoute,
                localMapPreview: _showLocalMapPreview,
                onTap: () {
                  if (_showLocalMapPreview) {
                    Navigator.pushNamed(context, '/offlineMap');
                  } else {
                    setState(() => _showLocalMapPreview = true);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppProvider provider) {
    final colors = _DashboardColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compactHeader = width < 900;

    return Container(
      height: compactHeader ? 62 : 74,
      padding: EdgeInsets.fromLTRB(compactHeader ? 10 : 18,
          compactHeader ? 7 : 10, compactHeader ? 10 : 18, 0),
      color: colors.background,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compactHeader ? 14 : 20),
        decoration: ShapeDecoration(
          color: colors.card.withValues(alpha: 0.94),
          shape: StadiumBorder(
            side: BorderSide(color: _line.withValues(alpha: 0.82), width: 1.2),
          ),
          shadows: [
            BoxShadow(
              color: _blue.withValues(alpha: 0.13),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.circle,
                color: provider.isGpsTracking ? _green : Colors.orangeAccent,
                size: 12),
            SizedBox(width: compactHeader ? 7 : 9),
            Text(
              provider.isGpsTracking ? 'GPS ATIVO' : 'GPS OFFLINE',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: provider.isGpsTracking ? _green : Colors.orangeAccent,
                fontSize: compactHeader ? 13 : 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(width: compactHeader ? 8 : 12),
            _HeaderGpsButton(
              active: provider.isGpsTracking,
              onTap: provider.isGpsTracking
                  ? provider.stopGpsTracking
                  : provider.startGpsTracking,
              compact: compactHeader,
            ),
            const Spacer(),
            Container(
              width: compactHeader ? 46 : 54,
              height: compactHeader ? 24 : 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFC99A28).withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/chevrolet_logo_transparent.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            SizedBox(width: compactHeader ? 10 : 14),
            Flexible(
              flex: 2,
              child: Text(
                provider.vehicleName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: compactHeader ? 15 : 16,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Assistente de voz',
              onPressed: _voiceAssistantBusy
                  ? null
                  : () => _startVoiceAssistant(provider),
              icon: Icon(
                _voiceAssistantBusy ? Icons.mic : Icons.mic_none,
                color: _voiceAssistantBusy ? _green : colors.secondaryIcon,
                size: compactHeader ? 23 : 25,
              ),
            ),
            IconButton(
              tooltip: provider.isDarkMode ? 'Modo claro' : 'Modo escuro',
              onPressed: provider.toggleThemeMode,
              icon: Icon(
                provider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
                color: colors.secondaryIcon,
                size: compactHeader ? 23 : 25,
              ),
            ),
            IconButton(
              tooltip: 'Configurações',
              onPressed: () => _showSettingsDialog(context, provider),
              icon: Icon(Icons.settings,
                  color: colors.secondaryIcon, size: compactHeader ? 23 : 25),
            ),
            Icon(Icons.schedule,
                color: colors.secondaryText, size: compactHeader ? 18 : 19),
            SizedBox(width: compactHeader ? 6 : 8),
            Text(
              _formatTime(_now),
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, BoxConstraints constraints) {
    final colors = _DashboardColors.of(context);
    final provider = context.watch<AppProvider>();
    final compact = constraints.maxWidth < 760 || constraints.maxHeight < 360;
    final panelWidth = math
        .min(
          math.max(0, constraints.maxWidth - 16),
          compact ? 480.0 : 620.0,
        )
        .toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: math.max(0.0, constraints.maxHeight - 16),
        ),
        child: Center(
          child: SizedBox(
            width: math.max(280.0, panelWidth),
            child: _Panel(
              padding: EdgeInsets.all(compact ? 10 : 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    const _GlowIcon(
                      icon: Icons.local_gas_station,
                      color: _blue,
                      size: 76,
                    ),
                    const SizedBox(height: 18),
                  ] else ...[
                    const _GlowIcon(
                      icon: Icons.local_gas_station,
                      color: _blue,
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    'Nenhum abastecimento ativo',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: compact ? 16 : 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Registre o abastecimento para calcular autonomia e consumo.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: colors.secondaryText, fontSize: 14),
                    ),
                  ],
                  SizedBox(height: compact ? 10 : 20),
                  SizedBox(
                    width: compact ? 300 : 380,
                    height: compact ? 54 : 86,
                    child: _buildFuelOilActions(provider),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFuelOilActions(AppProvider provider) {
    return Row(
      children: [
        Expanded(
          child: _ActionCard(
            icon: Icons.local_gas_station,
            title: 'ABASTECER',
            subtitle: 'Registrar abastecimento',
            color: _green,
            onTap: () => Navigator.pushNamed(context, '/addFuel'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ActionCard(
            icon: Icons.oil_barrel,
            title: 'ÓLEO',
            subtitle: _oilActionSubtitle(provider),
            color: _oilActionColor(provider),
            onTap: () => _showOilChangeDialog(context, provider),
          ),
        ),
      ],
    );
  }

  Color _oilActionColor(AppProvider provider) {
    if (provider.isOilChangeDue) return _oilDue;
    if (provider.isOilChangeNear) return _amber;
    return provider.hasOilChangeInfo ? _green : _blue;
  }

  String _oilActionSubtitle(AppProvider provider) {
    if (!provider.hasOilChangeInfo) return 'Registrar troca';
    final remaining = provider.oilKmRemaining;
    if (remaining == null) {
      return 'Prox. ${provider.oilNextChangeKm!.toStringAsFixed(0)} km';
    }
    if (remaining <= 0) return 'Troca vencida';
    if (remaining <= 500) return 'Faltam ${remaining.toStringAsFixed(0)} km';
    return 'Prox. ${provider.oilNextChangeKm!.toStringAsFixed(0)} km';
  }

  Future<void> _startVoiceAssistant(AppProvider provider) async {
    if (_voiceAssistantBusy) return;

    setState(() => _voiceAssistantBusy = true);
    final speech = stt.SpeechToText();
    final voiceStatus = ValueNotifier<String>('Preparando microfone...');
    final recognizedPreview = ValueNotifier<String>('');
    VideoPlayerController? controller;
    var dialogOpen = false;

    Future<void> closeDialog() async {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogOpen = false;
      }
      await controller?.pause();
      await controller?.dispose();
      if (_voiceVideoController == controller) {
        _voiceVideoController = null;
      }
    }

    Future<void> answer(String command) async {
      await closeDialog();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await provider.answerVoiceAssistantCommand(command);
    }

    try {
      try {
        controller = VideoPlayerController.asset('assets/videos/ouvindo.mp4');
        _voiceVideoController = controller;
        await controller.initialize();
        await controller.setVolume(0);
        await controller.setLooping(true);
        await controller.play();
      } catch (_) {
        await controller?.dispose();
        controller = null;
        _voiceVideoController = null;
      }

      if (!mounted) return;
      final activeController = controller;
      dialogOpen = true;
      unawaited(
        showGeneralDialog<void>(
          context: context,
          barrierDismissible: false,
          barrierLabel: 'Assistente ouvindo',
          barrierColor: Colors.black,
          transitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => Material(
            color: Colors.black,
            child: SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (activeController != null &&
                      activeController.value.isInitialized)
                    FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: activeController.value.size.width,
                        height: activeController.value.size.height,
                        child: VideoPlayer(activeController),
                      ),
                    )
                  else
                    const _VoiceListeningFallback(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _blue.withValues(alpha: 0.7),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ValueListenableBuilder<String>(
                              valueListenable: voiceStatus,
                              builder: (_, status, __) => Text(
                                status,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            ValueListenableBuilder<String>(
                              valueListenable: recognizedPreview,
                              builder: (_, preview, __) => preview.isEmpty
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        preview,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.78),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 180));
      final voicePermission = await _requestVoicePermission();
      if (!voicePermission) {
        voiceStatus.value = 'Permissão de microfone negada';
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await answer('status');
        return;
      }

      voiceStatus.value = 'Ativando reconhecimento...';
      final available = await speech.initialize(
        onError: (error) {
          voiceStatus.value = 'Erro no microfone: ${error.errorMsg}';
        },
        onStatus: (status) {
          if (status == 'listening') {
            voiceStatus.value = 'Ouvindo...';
          } else if (status == 'notListening' &&
              recognizedPreview.value.isEmpty) {
            voiceStatus.value = 'Não ouvi nenhum comando';
          }
        },
      );
      if (!available) {
        voiceStatus.value = 'Reconhecimento indisponível';
        await Future<void>.delayed(const Duration(milliseconds: 900));
        await answer('status');
        return;
      }

      voiceStatus.value = 'Ouvindo...';
      var recognized = '';
      final done = Completer<void>();
      try {
        await speech.listen(
          localeId: 'pt_BR',
          listenFor: const Duration(seconds: 6),
          pauseFor: const Duration(milliseconds: 900),
          onResult: (result) {
            recognized = result.recognizedWords;
            recognizedPreview.value =
                recognized.isEmpty ? '' : 'Entendi: $recognized';
            if (recognized.isNotEmpty) {
              voiceStatus.value =
                  result.finalResult ? 'Comando entendido' : 'Ouvindo...';
            }
            if (result.finalResult && !done.isCompleted) {
              done.complete();
            }
          },
        );

        await done.future.timeout(
          const Duration(seconds: 7),
          onTimeout: () {},
        );
      } catch (_) {
        voiceStatus.value = 'Falha ao ouvir comando';
        recognized = '';
      } finally {
        await speech.stop();
      }

      if (recognized.trim().isEmpty) {
        voiceStatus.value = 'Não entendi, respondendo status';
        await Future<void>.delayed(const Duration(milliseconds: 650));
      }
      await answer(recognized.trim().isEmpty ? 'status' : recognized);
    } finally {
      await closeDialog();
      voiceStatus.dispose();
      recognizedPreview.dispose();
      if (mounted) {
        setState(() => _voiceAssistantBusy = false);
      }
    }
  }

  Future<bool> _requestVoicePermission() async {
    try {
      return await _nativeChannel
              .invokeMethod<bool>('requestVoicePermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Widget _buildBottomNav(BuildContext context) {
    final colors = _DashboardColors.of(context);
    final provider = context.watch<AppProvider>();

    return Container(
      height: 78,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(top: BorderSide(color: _line.withValues(alpha: 0.75))),
      ),
      child: _Panel(
        padding: const EdgeInsets.symmetric(horizontal: 0),
        child: Row(
          children: [
            _NavItem(
              icon: Icons.speed,
              label: 'PAINEL',
              active: true,
              onTap: () {},
            ),
            _NavItem(
              icon: Icons.memory,
              label: 'COMPUTADOR',
              onTap: () => Navigator.pushReplacementNamed(context, '/computer'),
            ),
            _NavItem(
              icon: Icons.location_city,
              label: 'CIDADE',
              active: provider.isCityMode,
              onTap: () => provider.setDrivingMode('city'),
            ),
            _NavItem(
              icon: Icons.route,
              label: 'VIAGEM',
              active: !provider.isCityMode,
              onTap: () => provider.setDrivingMode('trip'),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showManualKmDialog(BuildContext context, AppProvider provider) {
    _odometerController.text = '';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Atualizar KM manual'),
        content: TextField(
          controller: _odometerController,
          keyboardType: TextInputType.number,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            hintText:
                'KM atual: ${provider.activeTrip!.currentOdometer.toStringAsFixed(0)}',
            prefixIcon: const Icon(Icons.route),
            suffixText: 'KM',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(
                _odometerController.text.replaceAll(',', '.'),
              );

              if (value != null) {
                provider.updateOdometer(value);
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  Future<void> _showOilChangeDialog(
    BuildContext context,
    AppProvider provider,
  ) async {
    final currentKm = provider.activeTrip?.currentOdometer ??
        provider.oilLastChangeKm ??
        provider.lastOdometer ??
        0.0;
    final lastController = TextEditingController(
      text: (provider.oilLastChangeKm ?? currentKm)
          .toStringAsFixed(0)
          .replaceAll('.', ','),
    );
    final nextController = TextEditingController(
      text: (provider.oilNextChangeKm ?? currentKm + 10000)
          .toStringAsFixed(0)
          .replaceAll('.', ','),
    );
    final typeController = TextEditingController(
      text: provider.oilType.isEmpty ? '5W30' : provider.oilType,
    );
    var filterChanged = provider.oilFilterChanged;
    String? error;

    double? parseKm(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.'));

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Troca de óleo'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: lastController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'KM da troca',
                          prefixIcon: Icon(Icons.route),
                          suffixText: 'km',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nextController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'KM da próxima troca',
                          prefixIcon: Icon(Icons.flag),
                          suffixText: 'km',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: typeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de óleo',
                          hintText: 'Ex: 5W30, 5W40, 10W40',
                          prefixIcon: Icon(Icons.oil_barrel),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Filtro de óleo trocado'),
                        value: filterChanged,
                        onChanged: (value) =>
                            setDialogState(() => filterChanged = value),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          error!,
                          style: const TextStyle(
                            color: _oilDue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('CANCELAR'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final lastKm = parseKm(lastController);
                    final nextKm = parseKm(nextController);
                    if (lastKm == null || nextKm == null || lastKm < 0) {
                      setDialogState(
                          () => error = 'Informe os KM corretamente');
                      return;
                    }
                    if (nextKm < lastKm) {
                      setDialogState(
                        () => error = 'A próxima troca deve ser maior ou igual',
                      );
                      return;
                    }

                    await provider.saveOilChange(
                      lastChangeKm: lastKm,
                      nextChangeKm: nextKm,
                      filterChanged: filterChanged,
                      oilType: typeController.text,
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('SALVAR'),
                ),
              ],
            );
          },
        );
      },
    );

    lastController.dispose();
    nextController.dispose();
    typeController.dispose();
  }

  void _showNumberEditDialog({
    required BuildContext context,
    required String title,
    required double currentValue,
    required String suffix,
    required Future<void> Function(double value) onSave,
    int digits = 1,
  }) {
    final controller = TextEditingController(
      text: currentValue.toStringAsFixed(digits).replaceAll('.', ','),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.dispose();
              Navigator.pop(dialogContext);
            },
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = double.tryParse(
                controller.text.replaceAll(',', '.'),
              );

              if (value == null) return;

              await onSave(value);
              controller.dispose();

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: const Text('SALVAR'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, AppProvider provider) {
    final vehicleController = TextEditingController(
      text: provider.vehicleName,
    );
    final cityController = TextEditingController(
      text: provider.cityConsumption.toStringAsFixed(1).replaceAll('.', ','),
    );
    final tripController = TextEditingController(
      text: provider.tripConsumption.toStringAsFixed(1).replaceAll('.', ','),
    );
    final priceController = TextEditingController(
      text: provider.fuelPrice.toStringAsFixed(2).replaceAll('.', ','),
    );
    final tankController = TextEditingController(
      text: provider.tankCapacityLiters > 0
          ? provider.tankCapacityLiters.toStringAsFixed(1).replaceAll('.', ',')
          : '',
    );
    var soundsEnabled = provider.soundsEnabled;
    var mapVehicleIcon = provider.mapVehicleIcon;

    showDialog(
      context: context,
      useSafeArea: true,
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final availableHeight = media.size.height -
            media.viewInsets.bottom -
            media.padding.top -
            media.padding.bottom -
            24;
        final dialogHeight = math.max(180.0, availableHeight);

        void closeDialog() {
          vehicleController.dispose();
          cityController.dispose();
          tripController.dispose();
          priceController.dispose();
          tankController.dispose();
          Navigator.pop(dialogContext);
        }

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 460.0,
              maxHeight: dialogHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Configurações',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: StatefulBuilder(
                      builder: (context, setDialogState) {
                        return SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: vehicleController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Nome do veículo',
                                  prefixIcon: Icon(Icons.directions_car_filled),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: cityController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Consumo Cidade',
                                  suffixText: 'km/L',
                                  prefixIcon: Icon(Icons.location_city),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: tripController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Consumo Viagem',
                                  suffixText: 'km/L',
                                  prefixIcon: Icon(Icons.route),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: priceController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Preço médio gasolina',
                                  prefixText: 'R\$ ',
                                  suffixText: '/L',
                                  prefixIcon: Icon(Icons.local_gas_station),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: tankController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Tamanho do tanque',
                                  hintText: 'Opcional',
                                  suffixText: 'L',
                                  prefixIcon: Icon(Icons.local_gas_station),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: soundsEnabled,
                                onChanged: (value) {
                                  setDialogState(() {
                                    soundsEnabled = value;
                                  });
                                },
                                secondary: const Icon(Icons.volume_up),
                                title: const Text('Sons e alertas'),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: mapVehicleIcon,
                                decoration: const InputDecoration(
                                  labelText: 'Icone do mapa',
                                  prefixIcon: Icon(Icons.navigation),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'arrow',
                                    child: Text('Flecha eletrica'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'shuttle',
                                    child: Text('Nave urbana'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'bolt',
                                    child: Text('Raio'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'diamond',
                                    child: Text('Cristal'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setDialogState(() {
                                    mapVehicleIcon = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _showMapDownloadDialog(context),
                                  icon: const Icon(Icons.map),
                                  label: const Text('MAPAS OFFLINE'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    closeDialog();
                                    Navigator.pushNamed(context, '/history');
                                  },
                                  icon: const Icon(Icons.history),
                                  label: const Text('HISTORICO'),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: closeDialog,
                        child: const Text('CANCELAR'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          final city = double.tryParse(
                            cityController.text.replaceAll(',', '.'),
                          );
                          final trip = double.tryParse(
                            tripController.text.replaceAll(',', '.'),
                          );
                          final price = double.tryParse(
                            priceController.text.replaceAll(',', '.'),
                          );
                          final tankText = tankController.text.trim();
                          final tank = tankText.isEmpty
                              ? 0.0
                              : double.tryParse(
                                  tankText.replaceAll(',', '.'),
                                );

                          if (city == null ||
                              trip == null ||
                              price == null ||
                              tank == null ||
                              city <= 0 ||
                              trip <= 0 ||
                              price < 0 ||
                              tank < 0) {
                            return;
                          }

                          await provider.saveDashboardSettings(
                            cityConsumption: city,
                            tripConsumption: trip,
                            fuelPrice: price,
                            tankCapacityLiters: tank,
                            soundsEnabled: soundsEnabled,
                            vehicleName: vehicleController.text,
                            mapVehicleIcon: mapVehicleIcon,
                          );

                          if (dialogContext.mounted) {
                            closeDialog();
                          }
                        },
                        child: const Text('SALVAR'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMapDownloadDialog(BuildContext context) {
    final service = OfflineMapService();
    final countryController = TextEditingController(text: 'Brasil');
    List<DownloadedOfflineMap> downloadedMaps = [];
    List<MapSearchOption> countries = [];
    List<MapSearchOption> states = [];
    List<MapSearchOption> cities = [];
    MapSearchOption? selectedCountry;
    MapSearchOption? selectedState;
    MapSearchOption? selectedCity;
    var busy = false;
    String? message;

    showDialog(
      context: context,
      builder: (dialogContext) {
        Future<void> refreshMaps(StateSetter setDialogState) async {
          final maps = await service.downloadedMaps();
          if (!dialogContext.mounted) return;
          setDialogState(() => downloadedMaps = maps);
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (downloadedMaps.isEmpty && !busy) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) refreshMaps(setDialogState);
              });
            }

            return AlertDialog(
              title: const Text('Mapas offline'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Baixados',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (downloadedMaps.isEmpty)
                        const LinearProgressIndicator()
                      else
                        ...downloadedMaps.map(
                          (map) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              map.active
                                  ? Icons.radio_button_checked
                                  : Icons.map,
                              color: map.active
                                  ? _HomeScreenState._green
                                  : _HomeScreenState._blue,
                            ),
                            title: Text(map.name),
                            trailing: map.active
                                ? const Text('ATIVO')
                                : const Text('USAR'),
                            onTap: map.active || busy
                                ? null
                                : () async {
                                    await service.setCurrentMap(map.path);
                                    await refreshMaps(setDialogState);
                                    setDialogState(() {
                                      message =
                                          '${map.name} definido como mapa ativo.';
                                    });
                                  },
                          ),
                        ),
                      const Divider(height: 24),
                      TextField(
                        controller: countryController,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Pais',
                          hintText: 'Brasil, Argentina, Uruguai...',
                          prefixIcon: Icon(Icons.public),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setDialogState(() {
                                    busy = true;
                                    message = 'Buscando país...';
                                  });
                                  try {
                                    final result =
                                        await service.searchCountries(
                                            countryController.text);
                                    setDialogState(() {
                                      countries = result;
                                      selectedCountry = result.isNotEmpty
                                          ? result.first
                                          : null;
                                      states = [];
                                      cities = [];
                                      selectedState = null;
                                      selectedCity = null;
                                      busy = false;
                                      message = result.isEmpty
                                          ? 'Nenhum país encontrado.'
                                          : 'Escolha o país.';
                                    });
                                  } catch (_) {
                                    setDialogState(() {
                                      busy = false;
                                      message = 'Falha ao buscar país.';
                                    });
                                  }
                                },
                          icon: const Icon(Icons.search),
                          label: const Text('BUSCAR PAIS'),
                        ),
                      ),
                      if (countries.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<MapSearchOption>(
                          initialValue: selectedCountry,
                          decoration: const InputDecoration(labelText: 'Pais'),
                          items: countries
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(option.name),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedCountry = value;
                                    states = [];
                                    cities = [];
                                    selectedState = null;
                                    selectedCity = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: busy || selectedCountry == null
                                ? null
                                : () async {
                                    setDialogState(() {
                                      busy = true;
                                      message = 'Buscando estados...';
                                    });
                                    try {
                                      final result = await service
                                          .searchStates(selectedCountry!);
                                      setDialogState(() {
                                        states = result;
                                        selectedState = result.isNotEmpty
                                            ? result.first
                                            : null;
                                        cities = [];
                                        selectedCity = null;
                                        busy = false;
                                        message = result.isEmpty
                                            ? 'Nenhum estado encontrado.'
                                            : 'Escolha o estado.';
                                      });
                                    } catch (_) {
                                      setDialogState(() {
                                        busy = false;
                                        message = 'Falha ao buscar estados.';
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.account_balance),
                            label: const Text('BUSCAR ESTADOS'),
                          ),
                        ),
                      ],
                      if (states.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<MapSearchOption>(
                          initialValue: selectedState,
                          decoration:
                              const InputDecoration(labelText: 'Estado'),
                          items: states
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(option.name),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedState = value;
                                    cities = [];
                                    selectedCity = null;
                                  });
                                },
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: busy ||
                                    selectedCountry == null ||
                                    selectedState == null
                                ? null
                                : () async {
                                    setDialogState(() {
                                      busy = true;
                                      message = 'Buscando cidades...';
                                    });
                                    try {
                                      final result = await service.searchCities(
                                        country: selectedCountry!,
                                        state: selectedState!,
                                      );
                                      setDialogState(() {
                                        cities = result;
                                        selectedCity = result.isNotEmpty
                                            ? result.first
                                            : null;
                                        busy = false;
                                        message = result.isEmpty
                                            ? 'Nenhuma cidade encontrada.'
                                            : 'Escolha a cidade.';
                                      });
                                    } catch (_) {
                                      setDialogState(() {
                                        busy = false;
                                        message = 'Falha ao buscar cidades.';
                                      });
                                    }
                                  },
                            icon: const Icon(Icons.location_city),
                            label: const Text('BUSCAR CIDADES'),
                          ),
                        ),
                      ],
                      if (cities.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<MapSearchOption>(
                          initialValue: selectedCity,
                          decoration:
                              const InputDecoration(labelText: 'Cidade'),
                          items: cities
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option,
                                  child: Text(option.name),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) {
                                  setDialogState(() {
                                    selectedCity = value;
                                  });
                                },
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (busy) const LinearProgressIndicator(),
                      if (message != null) ...[
                        const SizedBox(height: 10),
                        Text(message!),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('FECHAR'),
                ),
                ElevatedButton(
                  onPressed: busy || selectedCity == null
                      ? null
                      : () async {
                          setDialogState(() {
                            busy = true;
                            message = 'Baixando ruas e postos...';
                          });

                          try {
                            final map = await service
                                .downloadCityMap(selectedCity!.displayName);
                            await refreshMaps(setDialogState);
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              busy = false;
                              message =
                                  '${map.name} salvo e definido como mapa ativo.';
                            });
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              busy = false;
                              message =
                                  'Não foi possível baixar. Verifique a internet e tente novamente.';
                            });
                          }
                        },
                  child: const Text('BAIXAR'),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => countryController.dispose());
  }

  _DashboardInstruction? _dashboardRouteInstruction(AppProvider provider) {
    final route = provider.activeNavigationRoute;
    final lat = provider.lastGpsLatitude;
    final lon = provider.lastGpsLongitude;
    final instruction = _RouteManeuverInstruction.fromRoute(
      route: route,
      latitude: lat,
      longitude: lon,
      heading: provider.lastGpsHeading,
    );
    if (instruction == null) {
      return null;
    }

    return _DashboardInstruction(
      icon: instruction.icon,
      title: instruction.title,
      detail: instruction.detail,
    );
  }

  Future<void> _showNavigationRouteDialog(
    BuildContext context,
    AppProvider provider,
  ) async {
    var loading = _cachedPlaces.isEmpty;
    var routing = false;
    String? message;
    List<SavedMapPlace> places = List<SavedMapPlace>.of(_cachedPlaces);
    OfflineRouteCalculator? calculator = _cachedRouteCalculator;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> load(StateSetter setDialogState) async {
          try {
            final loadedPlaces =
                await (_placesCacheFuture ??= _warmPlacesCache());
            if (!dialogContext.mounted) return;
            setDialogState(() {
              places = loadedPlaces;
              loading = false;
            });
          } catch (_) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              loading = false;
              message = 'Não foi possível carregar favoritos.';
            });
          }
        }

        Future<void> selectPlace(
          StateSetter setDialogState,
          SavedMapPlace place,
        ) async {
          final lat = provider.lastGpsLatitude;
          final lon = provider.lastGpsLongitude;
          if (lat == null || lon == null) {
            setDialogState(() {
              message = 'Aguardando GPS para calcular rota.';
            });
            return;
          }

          setDialogState(() {
            routing = true;
            message = 'Calculando rota...';
          });

          late final OfflineMapData currentMap;
          try {
            currentMap = await _loadNavigationMap();
          } catch (_) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              routing = false;
              message = 'Não foi possível carregar o mapa offline.';
            });
            return;
          }

          final destination = MapDestination(
            name: place.name,
            position: place.position,
            kind: place.type,
          );
          calculator ??= OfflineRouteCalculator(currentMap);
          _cachedRouteCalculator ??= calculator;
          final route = await Future<OfflineRoute?>(
            () => calculator!.calculate(
              Offset(lon, lat),
              place.position,
            ),
          );

          if (!dialogContext.mounted) return;
          setDialogState(() {
            routing = false;
            message = route == null
                ? 'Rota indisponível neste mapa offline.'
                : 'Rota para ${place.name} ativa.';
          });

          if (route != null) {
            provider.setActiveNavigationRoute(
              route: route,
              destination: destination,
            );
          }
        }

        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (loading && places.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (dialogContext.mounted) load(setDialogState);
              });
            }

            final instruction = _dashboardRouteInstruction(provider);
            return AlertDialog(
              title: const Text('Navegação'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (provider.activeNavigationRoute != null) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          instruction?.icon ?? Icons.route,
                          color: _blue,
                          size: 32,
                        ),
                        title: Text(
                          instruction?.title ?? 'Rota ativa',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          instruction?.detail ??
                              provider.activeNavigationDestination?.name ??
                              'Destino selecionado',
                        ),
                        trailing: IconButton(
                          tooltip: 'Limpar rota',
                          onPressed: provider.clearActiveNavigationRoute,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                      const Divider(),
                    ],
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Favoritos salvos',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/offlineMap'),
                          icon: const Icon(Icons.map),
                          label: const Text('MAPA'),
                        ),
                      ],
                    ),
                    if (loading || routing) const LinearProgressIndicator(),
                    if (!loading && places.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhum favorito salvo ainda.'),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: places.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final place = places[index];
                            return ListTile(
                              dense: true,
                              leading:
                                  Icon(_placeIcon(place.type), color: _blue),
                              title: Text(place.name),
                              subtitle: Text(_placeTypeLabel(place.type)),
                              onTap: routing
                                  ? null
                                  : () => selectPlace(setDialogState, place),
                            );
                          },
                        ),
                      ),
                    if (message != null) ...[
                      const SizedBox(height: 10),
                      Text(message!),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('FECHAR'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  IconData _placeIcon(String type) {
    switch (type) {
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

  String _placeTypeLabel(String type) {
    switch (type) {
      case 'casa':
        return 'Casa';
      case 'trabalho':
        return 'Trabalho';
      case 'posto':
        return 'Posto';
      case 'mercado':
        return 'Super Mercado';
      default:
        return 'Favorito';
    }
  }

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _decimal(double value, int digits) {
    return value.toStringAsFixed(digits).replaceAll('.', ',');
  }

  String _estimatedCostValue(AppProvider provider, TripModel trip) {
    return _formatCurrency(_estimatedCostAmount(provider.fuelPrice, trip));
  }

  double _estimatedCostAmount(double fuelPrice, TripModel trip) {
    final consumed = math.max<double>(0.0, trip.fuelConsumedLiters);
    return consumed * fuelPrice;
  }

  String _formatCurrency(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.card, colors.card2],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _HomeScreenState._line.withValues(alpha: 0.9),
        ),
        boxShadow: [
          BoxShadow(
            color: _HomeScreenState._blue.withValues(alpha: 0.08),
            blurRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DashboardColors {
  const _DashboardColors({
    required this.background,
    required this.bar,
    required this.card,
    required this.card2,
    required this.innerPanel,
    required this.primaryText,
    required this.secondaryText,
    required this.secondaryIcon,
  });

  final Color background;
  final Color bar;
  final Color card;
  final Color card2;
  final Color innerPanel;
  final Color primaryText;
  final Color secondaryText;
  final Color secondaryIcon;

  static _DashboardColors of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isDark) {
      return const _DashboardColors(
        background: _HomeScreenState._bg,
        bar: _HomeScreenState._bar,
        card: _HomeScreenState._card,
        card2: _HomeScreenState._card2,
        innerPanel: Color(0xFF041426),
        primaryText: Colors.white,
        secondaryText: Colors.white70,
        secondaryIcon: _HomeScreenState._purple,
      );
    }

    return const _DashboardColors(
      background: Color(0xFFEAF2FF),
      bar: Color(0xFFF7FAFF),
      card: Color(0xFFFFFFFF),
      card2: Color(0xFFE8F2FF),
      innerPanel: Color(0xFFF5F8FF),
      primaryText: Color(0xFF071527),
      secondaryText: Color(0xFF536172),
      secondaryIcon: Color(0xFF516481),
    );
  }
}

class _BigNumberCard extends StatelessWidget {
  const _BigNumberCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.footer,
    this.onTap,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final String? footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 190 || constraints.maxWidth < 150;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: _Panel(
              padding: EdgeInsets.all(dense ? 6 : 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: dense ? 10 : 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: dense ? 4 : 12),
                  _GlowIcon(icon: icon, color: color, size: dense ? 34 : 72),
                  SizedBox(height: dense ? 4 : 14),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: dense ? 36 : 72,
                            fontWeight: FontWeight.w900,
                            height: 0.98,
                          ),
                        ),
                        SizedBox(width: dense ? 4 : 8),
                        Padding(
                          padding: EdgeInsets.only(bottom: dense ? 3 : 8),
                          child: Text(
                            unit,
                            style: TextStyle(
                              color: color,
                              fontSize: dense ? 15 : 28,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (footer != null && !dense) ...[
                    const SizedBox(height: 16),
                    Text(
                      footer!,
                      style:
                          TextStyle(color: colors.secondaryText, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FuelGaugeCard extends StatelessWidget {
  const _FuelGaugeCard({
    required this.percentage,
    required this.fuelName,
  });

  final double percentage;
  final String fuelName;

  @override
  Widget build(BuildContext context) {
    final safePercentage = percentage.clamp(0.0, 1.0);
    final colors = _DashboardColors.of(context);

    return Center(
      child: AspectRatio(
        aspectRatio: 1.1,
        child: CustomPaint(
          painter: _FuelGaugePainter(percentage: safePercentage),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox(
                width: 250,
                height: 230,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.local_gas_station,
                      color: _HomeScreenState._blue,
                      size: 30,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      fuelName,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(safePercentage * 100).round()}',
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              height: 0.9,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '%',
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 36,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ]),
                    const SizedBox(height: 8),
                    Text(
                      'Nível de combustível',
                      style:
                          TextStyle(color: colors.secondaryText, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteManeuverInstruction {
  const _RouteManeuverInstruction({
    required this.title,
    required this.detail,
    required this.distanceLabel,
    required this.icon,
    required this.color,
  });

  final String title;
  final String detail;
  final String distanceLabel;
  final IconData icon;
  final Color color;

  static _RouteManeuverInstruction? fromRoute({
    required OfflineRoute? route,
    required double? latitude,
    required double? longitude,
    required double? heading,
  }) {
    final points = route?.points;
    if (points == null ||
        latitude == null ||
        longitude == null ||
        points.length < 2) {
      return null;
    }

    final origin = Offset(longitude, latitude);
    final match = _CockpitRouteMatcher.match(
      points: points,
      origin: origin,
      heading: heading,
    );
    final startIndex =
        match?.nearestIndex ?? _nearestRouteIndex(points, origin);
    final startPoint = match?.points.first ?? origin;
    final segmentStart = startIndex.clamp(0, points.length - 2).toInt();
    final maneuver = _findNextManeuver(
      points: points,
      startPoint: startPoint,
      segmentStart: segmentStart,
    );

    if (maneuver != null) return maneuver;

    final remainingMeters = _remainingRouteMeters(
      points: points,
      startPoint: startPoint,
      segmentStart: segmentStart,
    );

    return _RouteManeuverInstruction(
      title: 'Siga em frente',
      detail: 'por ${_formatRouteDistance(remainingMeters)}',
      distanceLabel: _formatRouteDistance(remainingMeters),
      icon: Icons.straight,
      color: _HomeScreenState._blue,
    );
  }

  static _RouteManeuverInstruction? _findNextManeuver({
    required List<Offset> points,
    required Offset startPoint,
    required int segmentStart,
  }) {
    var metersAhead = 0.0;
    var previous = startPoint;

    for (var i = segmentStart + 1; i < points.length - 1; i++) {
      final vertex = points[i];
      metersAhead += _distanceMeters(previous, vertex);

      final bearingIn = _bearingDegrees(
        i == segmentStart + 1 ? startPoint : points[i - 1],
        vertex,
      );
      final bearingOut = _bearingDegrees(vertex, points[i + 1]);
      final delta = _angleDelta(bearingIn, bearingOut);
      final absDelta = delta.abs();

      if (absDelta >= 30) {
        final right = delta > 0;
        return _RouteManeuverInstruction(
          title: right ? 'Vire a direita' : 'Vire a esquerda',
          detail: 'em ${_formatRouteDistance(metersAhead)}',
          distanceLabel: _formatRouteDistance(metersAhead),
          icon: right ? Icons.turn_right : Icons.turn_left,
          color: const Color(0xFF39D8B6),
        );
      }

      if (absDelta >= 17) {
        final right = delta > 0;
        return _RouteManeuverInstruction(
          title: right ? 'Curva a direita' : 'Curva a esquerda',
          detail: 'em ${_formatRouteDistance(metersAhead)}',
          distanceLabel: _formatRouteDistance(metersAhead),
          icon: right ? Icons.turn_slight_right : Icons.turn_slight_left,
          color: const Color(0xFF39D8B6),
        );
      }

      previous = vertex;
      if (metersAhead > 3200) break;
    }

    return null;
  }

  static int _nearestRouteIndex(List<Offset> points, Offset origin) {
    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final meters = _distanceMeters(origin, points[i]);
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }
    return nearestIndex.clamp(0, math.max(0, points.length - 2)).toInt();
  }

  static double _remainingRouteMeters({
    required List<Offset> points,
    required Offset startPoint,
    required int segmentStart,
  }) {
    var meters = 0.0;
    var previous = startPoint;
    for (var i = segmentStart + 1; i < points.length; i++) {
      meters += _distanceMeters(previous, points[i]);
      previous = points[i];
    }
    return meters;
  }
}

class _CockpitRouteInfo {
  const _CockpitRouteInfo({
    required this.localPath,
    required this.title,
    required this.subtitle,
    required this.distanceLabel,
    required this.icon,
    required this.turnColor,
    required this.hasRoute,
  });

  final List<Offset> localPath;
  final String title;
  final String subtitle;
  final String distanceLabel;
  final IconData icon;
  final Color turnColor;
  final bool hasRoute;

  factory _CockpitRouteInfo.fromRoute({
    required OfflineRoute? route,
    required double? latitude,
    required double? longitude,
    required double? heading,
    _PelotasMapData? mapData,
  }) {
    final origin = latitude == null || longitude == null
        ? null
        : Offset(longitude, latitude);
    final points = route?.points;
    if (origin == null || points == null || points.length < 2) {
      if (origin != null && mapData != null) {
        final matched = _CockpitRoadMatcher.match(
          mapData: mapData,
          origin: origin,
          heading: heading,
        );
        if (matched != null && matched.points.length >= 3) {
          final roadHeading = _responsiveHeading(
            mapHeading: matched.heading,
            gpsHeading: heading,
          );
          final localPath = _routeToLocalPath(
            origin: origin,
            heading: roadHeading,
            points: matched.points,
          );
          final instruction = _instructionFromLocalPath(localPath);
          return _CockpitRouteInfo(
            localPath: localPath,
            title: instruction.title,
            subtitle: matched.roadName,
            distanceLabel: 'VIA',
            icon: instruction.icon,
            turnColor: instruction.color,
            hasRoute: false,
          );
        }
      }

      final curve =
          heading == null ? 0.0 : math.sin(heading * math.pi / 135) * 18;
      return _CockpitRouteInfo(
        localPath: [
          const Offset(0, 0),
          Offset(curve * 0.12, 30),
          Offset(curve * 0.32, 66),
          Offset(curve * 0.62, 112),
          Offset(curve, 162),
        ],
        title: 'Siga em frente',
        subtitle: 'Aguardando rota ativa',
        distanceLabel: '-- m',
        icon: Icons.straight,
        turnColor: _HomeScreenState._blue,
        hasRoute: false,
      );
    }

    final routeMatch = _CockpitRouteMatcher.match(
      points: points,
      origin: origin,
      heading: heading,
    );
    final nearestIndex = routeMatch?.nearestIndex ?? 0;
    final firstAheadIndex = math.min(nearestIndex + 2, points.length - 1);
    final mapHeading = routeMatch?.heading ??
        _bearingDegrees(
          origin,
          points[firstAheadIndex],
        );
    final routeHeading = _responsiveHeading(
      mapHeading: mapHeading,
      gpsHeading: heading,
    );
    final localPath = _routeToLocalPath(
      origin: origin,
      heading: routeHeading,
      points: routeMatch?.points ?? points.skip(nearestIndex).take(22).toList(),
    );
    final cockpitPath = _shapeUpcomingTurn(
      localPath,
      cue: routeMatch == null
          ? null
          : _CockpitTurnCue.fromRoutePoints(routeMatch.points),
    );

    final fallback = _instructionFromLocalPath(cockpitPath);
    final instruction = _RouteManeuverInstruction.fromRoute(
          route: route,
          latitude: latitude,
          longitude: longitude,
          heading: heading,
        ) ??
        _RouteManeuverInstruction(
          title: fallback.title,
          detail: '-- m',
          distanceLabel: '-- m',
          icon: fallback.icon,
          color: fallback.color,
        );
    return _CockpitRouteInfo(
      localPath: cockpitPath,
      title: instruction.title,
      subtitle: route == null ? 'Sem rota ativa' : 'Rota ativa no painel',
      distanceLabel: instruction.distanceLabel,
      icon: instruction.icon,
      turnColor: instruction.color,
      hasRoute: true,
    );
  }

  static double _responsiveHeading({
    required double mapHeading,
    required double? gpsHeading,
  }) {
    if (gpsHeading == null) return mapHeading;
    final delta = _angleDelta(mapHeading, gpsHeading);
    if (delta.abs() > 95) return mapHeading;
    return (mapHeading + delta * 0.62 + 360) % 360;
  }

  static List<Offset> _routeToLocalPath({
    required Offset origin,
    required double heading,
    required List<Offset> points,
  }) {
    final result = <Offset>[const Offset(0, 0)];
    final latRad = origin.dy * math.pi / 180;
    final metersPerLon = 111320.0 * math.cos(latRad).abs().clamp(0.25, 1.0);
    const metersPerLat = 111320.0;
    final h = heading * math.pi / 180;
    final sinH = math.sin(h);
    final cosH = math.cos(h);

    for (final point in points) {
      final east = (point.dx - origin.dx) * metersPerLon;
      final north = (point.dy - origin.dy) * metersPerLat;
      final forward = east * sinH + north * cosH;
      final lateral = east * cosH - north * sinH;
      if (forward < -6) continue;
      if (forward > 170) break;
      if (result.isNotEmpty &&
          (result.last - Offset(lateral, forward)).distance < 8) {
        continue;
      }
      result.add(Offset(lateral.clamp(-44.0, 44.0), forward));
    }

    if (result.length < 3) {
      return const [
        Offset(0, 0),
        Offset(0, 28),
        Offset(0, 60),
        Offset(0, 105),
        Offset(0, 155),
      ];
    }
    return _smoothLocalPath(result);
  }

  static List<Offset> _shapeUpcomingTurn(
    List<Offset> points, {
    required _CockpitTurnCue? cue,
  }) {
    final sampled = _densifyLocalPath(points);
    if (cue == null ||
        cue.distanceMeters > 140 ||
        cue.deltaDegrees.abs() < 24) {
      return sampled;
    }

    final turnStart = cue.distanceMeters.clamp(48.0, 112.0);
    final turnLength = cue.distanceMeters < 55 ? 50.0 : 68.0;
    final strength = (cue.deltaDegrees.abs() / 82).clamp(0.55, 1.0);
    final targetLateral = cue.direction * (34.0 + 14.0 * strength);

    return sampled.map((point) {
      if (point.dy <= 58) return Offset(0, point.dy);
      if (point.dy < turnStart) return point;

      final progress = ((point.dy - turnStart) / turnLength).clamp(0.0, 1.0);
      final eased = progress * progress * (3 - 2 * progress);
      final lateral = point.dx * (1 - eased) + targetLateral * eased;
      return Offset(lateral.clamp(-48.0, 48.0), point.dy);
    }).toList();
  }

  static List<Offset> _densifyLocalPath(List<Offset> points) {
    if (points.length < 2) return points;

    const sampleYs = [0.0, 24.0, 48.0, 70.0, 92.0, 118.0, 146.0, 170.0];
    final result = <Offset>[];
    var segmentIndex = 0;
    for (final y in sampleYs) {
      while (
          segmentIndex < points.length - 2 && points[segmentIndex + 1].dy < y) {
        segmentIndex++;
      }

      final a = points[segmentIndex];
      final b = points[math.min(segmentIndex + 1, points.length - 1)];
      final span = b.dy - a.dy;
      final t = span.abs() < 0.001 ? 0.0 : ((y - a.dy) / span).clamp(0.0, 1.0);
      result.add(Offset(a.dx + (b.dx - a.dx) * t, y));
    }
    return _anchorVehicleLane(result);
  }

  static List<Offset> _smoothLocalPath(List<Offset> points) {
    final cleaned = <Offset>[points.first];
    for (final point in points.skip(1)) {
      final previous = cleaned.last;
      if (point.dy <= previous.dy + 2) continue;

      final forwardDelta = point.dy - previous.dy;
      final maxLateralStep = math.max(9.0, forwardDelta * 0.42);
      final nextLateral = point.dx.clamp(
        previous.dx - maxLateralStep,
        previous.dx + maxLateralStep,
      );
      cleaned.add(Offset(nextLateral, point.dy));
    }

    if (cleaned.length < 3) {
      return const [
        Offset(0, 0),
        Offset(0, 28),
        Offset(0, 60),
        Offset(0, 105),
        Offset(0, 155),
      ];
    }

    final smoothed = <Offset>[cleaned.first];
    for (var i = 1; i < cleaned.length - 1; i++) {
      final previous = cleaned[i - 1];
      final current = cleaned[i];
      final next = cleaned[i + 1];
      smoothed.add(
        Offset(
          previous.dx * 0.18 + current.dx * 0.64 + next.dx * 0.18,
          current.dy,
        ),
      );
    }
    smoothed.add(cleaned.last);
    return _anchorVehicleLane(smoothed);
  }

  static List<Offset> _anchorVehicleLane(List<Offset> points) {
    return points.map((point) {
      if (point.dy <= 58) {
        return Offset(0, point.dy);
      }

      final curveProgress = ((point.dy - 58) / 62).clamp(0.0, 1.0);
      final eased = curveProgress * curveProgress * (3 - 2 * curveProgress);
      return Offset(point.dx * eased, point.dy);
    }).toList();
  }

  static _CockpitInstruction _instructionFromLocalPath(List<Offset> localPath) {
    if (localPath.length < 3) {
      return const _CockpitInstruction(
        title: 'Siga em frente',
        icon: Icons.straight,
        color: _HomeScreenState._blue,
      );
    }

    final mid = localPath[(localPath.length / 2).floor()];
    final end = localPath.last;
    final lateral = (mid.dx * 0.45) + (end.dx * 0.55);
    if (lateral > 24) {
      return const _CockpitInstruction(
        title: 'Curva a direita',
        icon: Icons.turn_slight_right,
        color: Color(0xFF39D8B6),
      );
    }
    if (lateral < -24) {
      return const _CockpitInstruction(
        title: 'Curva a esquerda',
        icon: Icons.turn_slight_left,
        color: Color(0xFF39D8B6),
      );
    }
    return const _CockpitInstruction(
      title: 'Siga em frente',
      icon: Icons.straight,
      color: _HomeScreenState._blue,
    );
  }
}

class _CockpitInstruction {
  const _CockpitInstruction({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;
}

class _CockpitRoadMatch {
  const _CockpitRoadMatch({
    required this.points,
    required this.heading,
    required this.roadName,
  });

  final List<Offset> points;
  final double heading;
  final String roadName;
}

class _CockpitRouteMatch {
  const _CockpitRouteMatch({
    required this.points,
    required this.heading,
    required this.nearestIndex,
  });

  final List<Offset> points;
  final double heading;
  final int nearestIndex;
}

class _CockpitTurnCue {
  const _CockpitTurnCue({
    required this.direction,
    required this.distanceMeters,
    required this.deltaDegrees,
  });

  final double direction;
  final double distanceMeters;
  final double deltaDegrees;

  static _CockpitTurnCue? fromRoutePoints(List<Offset> points) {
    if (points.length < 4) return null;

    var traveled = 0.0;
    var previousBearing = _bearingDegrees(points[0], points[1]);
    for (var i = 1; i < points.length - 1; i++) {
      traveled += _distanceMeters(points[i - 1], points[i]);
      if (traveled > 145) break;

      final nextBearing = _bearingDegrees(points[i], points[i + 1]);
      final delta = _angleDelta(previousBearing, nextBearing);
      if (delta.abs() >= 24) {
        return _CockpitTurnCue(
          direction: delta > 0 ? 1 : -1,
          distanceMeters: traveled,
          deltaDegrees: delta,
        );
      }
      previousBearing = nextBearing;
    }
    return null;
  }
}

class _CockpitRouteMatcher {
  static _CockpitRouteMatch? match({
    required List<Offset> points,
    required Offset origin,
    required double? heading,
  }) {
    if (points.length < 2) return null;

    _CandidateRouteSegment? best;
    for (var i = 0; i < points.length - 1; i++) {
      final candidate = _CandidateRouteSegment.from(
        points: points,
        segmentIndex: i,
        origin: origin,
        heading: heading,
      );
      if (candidate == null) continue;
      if (best == null || candidate.score < best.score) {
        best = candidate;
      }
    }

    if (best == null) return null;
    final matchedPoints = <Offset>[best.projectedLonLat];
    var totalMeters = 0.0;
    var previous = best.projectedLonLat;
    for (var i = best.segmentIndex + 1; i < points.length; i++) {
      final point = points[i];
      totalMeters += _distanceMeters(previous, point);
      if ((matchedPoints.last - point).distance > 0.00001) {
        matchedPoints.add(point);
      }
      previous = point;
      if (totalMeters >= 190) break;
    }

    if (matchedPoints.length < 2) return null;
    final headingPoint = matchedPoints.length > 2
        ? matchedPoints[2]
        : matchedPoints[matchedPoints.length - 1];
    return _CockpitRouteMatch(
      points: matchedPoints,
      heading: _bearingDegrees(matchedPoints.first, headingPoint),
      nearestIndex: best.segmentIndex,
    );
  }
}

class _CandidateRouteSegment {
  const _CandidateRouteSegment({
    required this.segmentIndex,
    required this.projectedLonLat,
    required this.segmentHeading,
    required this.score,
  });

  final int segmentIndex;
  final Offset projectedLonLat;
  final double segmentHeading;
  final double score;

  static _CandidateRouteSegment? from({
    required List<Offset> points,
    required int segmentIndex,
    required Offset origin,
    required double? heading,
  }) {
    final a = points[segmentIndex];
    final b = points[segmentIndex + 1];
    final aMeters = _metersFromOrigin(origin, a);
    final bMeters = _metersFromOrigin(origin, b);
    final ab = bMeters - aMeters;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared < 4) return null;

    final ao = Offset(-aMeters.dx, -aMeters.dy);
    final t = ((ao.dx * ab.dx + ao.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final projectedMeters = Offset(
      aMeters.dx + ab.dx * t,
      aMeters.dy + ab.dy * t,
    );
    final distance = projectedMeters.distance;
    final projectedLonLat = Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
    final segmentHeading = _bearingDegrees(a, b);
    final headingPenalty = heading == null
        ? 0.0
        : _angleDelta(segmentHeading, heading).abs().clamp(0.0, 90.0);
    final score = distance + headingPenalty * 0.18;

    return _CandidateRouteSegment(
      segmentIndex: segmentIndex,
      projectedLonLat: projectedLonLat,
      segmentHeading: segmentHeading,
      score: score,
    );
  }
}

class _CockpitRoadMatcher {
  static _CockpitRoadMatch? match({
    required _PelotasMapData mapData,
    required Offset origin,
    required double? heading,
  }) {
    _CandidateRoadSegment? best;

    for (final road in mapData.roads) {
      final points = road.points;
      if (points.length < 2) continue;
      for (var i = 0; i < points.length - 1; i++) {
        final candidate = _CandidateRoadSegment.from(
          road: road,
          segmentIndex: i,
          origin: origin,
          heading: heading,
        );
        if (candidate == null) continue;
        if (best == null || candidate.score < best.score) {
          best = candidate;
        }
      }
    }

    if (best == null || best.distanceMeters > 75) return null;

    final roadPoints = best.road.points;
    final forward = heading == null ||
        _angleDelta(best.segmentHeading, heading).abs() <= 90;
    final matchedPoints = <Offset>[best.projectedLonLat];
    var totalMeters = 0.0;
    var previous = best.projectedLonLat;

    if (forward) {
      for (var i = best.segmentIndex + 1; i < roadPoints.length; i++) {
        final point = roadPoints[i];
        totalMeters += _distanceMeters(previous, point);
        if ((matchedPoints.last - point).distance > 0.00001) {
          matchedPoints.add(point);
        }
        previous = point;
        if (totalMeters >= 190) break;
      }
    } else {
      for (var i = best.segmentIndex; i >= 0; i--) {
        final point = roadPoints[i];
        totalMeters += _distanceMeters(previous, point);
        if ((matchedPoints.last - point).distance > 0.00001) {
          matchedPoints.add(point);
        }
        previous = point;
        if (totalMeters >= 190) break;
      }
    }

    if (matchedPoints.length < 3) return null;

    final roadHeading = _bearingDegrees(
      matchedPoints.first,
      matchedPoints[math.min(2, matchedPoints.length - 1)],
    );
    return _CockpitRoadMatch(
      points: matchedPoints,
      heading: roadHeading,
      roadName: 'Rua atual',
    );
  }
}

class _CandidateRoadSegment {
  const _CandidateRoadSegment({
    required this.road,
    required this.segmentIndex,
    required this.projectedLonLat,
    required this.distanceMeters,
    required this.segmentHeading,
    required this.score,
  });

  final _PelotasRoad road;
  final int segmentIndex;
  final Offset projectedLonLat;
  final double distanceMeters;
  final double segmentHeading;
  final double score;

  static _CandidateRoadSegment? from({
    required _PelotasRoad road,
    required int segmentIndex,
    required Offset origin,
    required double? heading,
  }) {
    final a = road.points[segmentIndex];
    final b = road.points[segmentIndex + 1];
    final aMeters = _metersFromOrigin(origin, a);
    final bMeters = _metersFromOrigin(origin, b);
    final ab = bMeters - aMeters;
    final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lengthSquared < 4) return null;

    final ao = Offset(-aMeters.dx, -aMeters.dy);
    final t = ((ao.dx * ab.dx + ao.dy * ab.dy) / lengthSquared).clamp(0.0, 1.0);
    final projectedMeters = Offset(
      aMeters.dx + ab.dx * t,
      aMeters.dy + ab.dy * t,
    );
    final distance = projectedMeters.distance;
    if (distance > 95) return null;

    final projectedLonLat = Offset(
      a.dx + (b.dx - a.dx) * t,
      a.dy + (b.dy - a.dy) * t,
    );
    final segmentHeading = _bearingDegrees(a, b);
    final headingPenalty = heading == null
        ? 0.0
        : math.min(
            _angleDelta(segmentHeading, heading).abs(),
            _angleDelta((segmentHeading + 180) % 360, heading).abs(),
          );
    final rankBonus = road.rank * 1.8;
    final score = distance + headingPenalty * 0.82 - rankBonus;

    return _CandidateRoadSegment(
      road: road,
      segmentIndex: segmentIndex,
      projectedLonLat: projectedLonLat,
      distanceMeters: distance,
      segmentHeading: segmentHeading,
      score: score,
    );
  }
}

class _CockpitDrivePainter extends CustomPainter {
  const _CockpitDrivePainter({
    required this.routeInfo,
    required this.active,
    required this.darkMode,
  });

  static const Color _renderSafeBlue = Color(0xFF39D8B6);
  static const Color _renderSafeCyan = Color(0xFF9AF2D8);

  final _CockpitRouteInfo routeInfo;
  final bool active;
  final bool darkMode;

  @override
  void paint(Canvas canvas, Size size) {
    _drawRoad(canvas, size);
    _drawMotionLines(canvas, size);
    _drawRoute(canvas, size);
  }

  void _drawRoad(Canvas canvas, Size size) {
    final centerPath = _roadCenterPath();
    _drawRoadCone(canvas, size, centerPath);

    final edgePaint = Paint()
      ..color = _renderSafeBlue.withValues(alpha: active ? 0.74 : 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawOffsetPath(canvas, size, centerPath, 24, edgePaint);
    _drawOffsetPath(canvas, size, centerPath, -24, edgePaint);

    final lanePaint = Paint()
      ..color = Colors.white.withValues(alpha: darkMode ? 0.1 : 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawOffsetPath(canvas, size, centerPath, 0, lanePaint);
  }

  void _drawMotionLines(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = _renderSafeCyan.withValues(alpha: active ? 0.18 : 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final dashPaint = Paint()
      ..color = Colors.white.withValues(alpha: darkMode ? 0.18 : 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (final side in const [-1.0, 1.0]) {
      for (var i = 0; i < 4; i++) {
        final startForward = 24.0 + i * 34;
        final lateral = side * (34.0 + i * 3.6);
        final start = _project(Offset(lateral, startForward), size);
        final end =
            _project(Offset(lateral + side * 6, startForward + 24), size);
        canvas.drawLine(start, end, glowPaint);
      }
    }

    for (var i = 0; i < 5; i++) {
      final forward = 18.0 + i * 28;
      final start = _project(Offset(0, forward), size);
      final end = _project(Offset(0, forward + 12), size);
      canvas.drawLine(start, end, dashPaint);
    }
  }

  void _drawRoadCone(Canvas canvas, Size size, List<Offset> centerPath) {
    if (centerPath.length < 2) return;

    final left = <Offset>[];
    final right = <Offset>[];
    for (final point in centerPath) {
      final depth = (point.dy / 180).clamp(0.0, 1.0);
      final width = 42.0 - depth * 17.0;
      left.add(_project(Offset(point.dx - width, point.dy), size));
      right.add(_project(Offset(point.dx + width, point.dy), size));
    }

    final cone = Path()..moveTo(left.first.dx, left.first.dy);
    for (var i = 1; i < left.length; i++) {
      final previous = left[i - 1];
      final current = left[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      cone.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    cone.lineTo(left.last.dx, left.last.dy);
    for (var i = right.length - 1; i > 0; i--) {
      final previous = right[i];
      final current = right[i - 1];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      cone.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    cone.lineTo(right.first.dx, right.first.dy);
    cone.close();

    canvas.drawPath(
      cone,
      Paint()
        ..color = (darkMode ? const Color(0xFF383C3D) : const Color(0xFF98A0A6))
            .withValues(alpha: darkMode ? 0.78 : 0.68)
        ..style = PaintingStyle.fill,
    );
  }

  List<Offset> _roadCenterPath() {
    final points = routeInfo.localPath;
    if (points.length >= 3) return points;
    return const [
      Offset(0, 0),
      Offset(0, 28),
      Offset(0, 60),
      Offset(0, 105),
      Offset(0, 155),
    ];
  }

  void _drawOffsetPath(
    Canvas canvas,
    Size size,
    List<Offset> centerPath,
    double lateralMeters,
    Paint paint,
  ) {
    final points = centerPath
        .map((point) => Offset(point.dx + lateralMeters, point.dy))
        .map((point) => _project(point, size))
        .toList();
    canvas.drawPath(_smoothScreenPath(points), paint);
  }

  void _drawRoute(Canvas canvas, Size size) {
    if (!routeInfo.hasRoute) return;
    final points = routeInfo.localPath;
    if (points.length < 2) return;

    final path = _smoothScreenPath(
      points.map((point) => _project(point, size)).toList(),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = _renderSafeCyan.withValues(alpha: 0.12)
        ..strokeWidth = 9
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _renderSafeBlue.withValues(alpha: active ? 0.9 : 0.58)
        ..strokeWidth = 4.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Offset _project(Offset local, Size size) {
    final forward = local.dy.clamp(0.0, 180.0);
    final depth = (forward / 180.0).clamp(0.0, 1.0);
    final eased = 1 - math.pow(1 - depth, 2.15).toDouble();
    final bottomY = size.height * 0.88;
    final horizonY = size.height * 0.2;
    final y = bottomY - eased * (bottomY - horizonY);
    final scale = 1.08 - eased * 0.86;
    final x = size.width / 2 + local.dx * scale * (size.width / 78);
    return Offset(x, y);
  }

  Path _smoothScreenPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final mid = Offset(
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
      path.quadraticBezierTo(previous.dx, previous.dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant _CockpitDrivePainter oldDelegate) {
    return oldDelegate.routeInfo != routeInfo ||
        oldDelegate.active != active ||
        oldDelegate.darkMode != darkMode;
  }
}

final Future<_PelotasMapData> _pelotasMapDataFuture = _PelotasMapData.load();

class _PelotasOfflineMapCard extends StatefulWidget {
  const _PelotasOfflineMapCard({
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.active,
    required this.vehicleIcon,
    required this.route,
    required this.localMapPreview,
    required this.onTap,
  });

  final double? latitude;
  final double? longitude;
  final double? heading;
  final bool active;
  final String vehicleIcon;
  final OfflineRoute? route;
  final bool localMapPreview;
  final VoidCallback onTap;

  @override
  State<_PelotasOfflineMapCard> createState() => _PelotasOfflineMapCardState();
}

class _PelotasOfflineMapCardState extends State<_PelotasOfflineMapCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double? _fromLatitude;
  double? _fromLongitude;
  double? _fromHeading;
  double? _toLatitude;
  double? _toLongitude;
  double? _toHeading;
  double? _displayLatitude;
  double? _displayLongitude;
  double? _displayHeading;

  @override
  void initState() {
    super.initState();
    _displayLatitude = widget.latitude;
    _displayLongitude = widget.longitude;
    _displayHeading = widget.heading;
    _toLatitude = widget.latitude;
    _toLongitude = widget.longitude;
    _toHeading = widget.heading;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_updateDisplayPosition);
  }

  @override
  void didUpdateWidget(covariant _PelotasOfflineMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_positionChanged(oldWidget)) return;

    _fromLatitude = _displayLatitude ?? oldWidget.latitude;
    _fromLongitude = _displayLongitude ?? oldWidget.longitude;
    _fromHeading = _displayHeading ?? oldWidget.heading;
    final filteredTarget = _filteredTarget(widget.latitude, widget.longitude);
    _toLatitude = filteredTarget?.dy;
    _toLongitude = filteredTarget?.dx;
    _toHeading = _filteredHeading(widget.heading);

    if (_fromLatitude == null ||
        _fromLongitude == null ||
        _toLatitude == null ||
        _toLongitude == null) {
      _displayLatitude = widget.latitude;
      _displayLongitude = widget.longitude;
      _displayHeading = widget.heading;
      return;
    }

    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _positionChanged(_PelotasOfflineMapCard oldWidget) {
    return oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude ||
        oldWidget.heading != widget.heading;
  }

  void _updateDisplayPosition() {
    final t = Curves.easeOutCubic.transform(_controller.value);
    final fromLat = _fromLatitude;
    final fromLon = _fromLongitude;
    final toLat = _toLatitude;
    final toLon = _toLongitude;
    if (fromLat == null || fromLon == null || toLat == null || toLon == null) {
      return;
    }

    setState(() {
      _displayLatitude = _lerpDouble(fromLat, toLat, t);
      _displayLongitude = _lerpDouble(fromLon, toLon, t);
      _displayHeading = _lerpHeading(_fromHeading, _toHeading, t);
    });
  }

  double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

  Offset? _filteredTarget(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return null;
    final raw = Offset(longitude, latitude);
    final previousLat = _displayLatitude;
    final previousLon = _displayLongitude;
    if (previousLat == null || previousLon == null) return raw;

    final previous = Offset(previousLon, previousLat);
    final meters = _distanceMeters(previous, raw);
    if (meters < 2.2) return previous;
    if (meters > 75) return raw;

    final blend = meters < 14 ? 0.58 : 0.78;
    return Offset(
      previous.dx + (raw.dx - previous.dx) * blend,
      previous.dy + (raw.dy - previous.dy) * blend,
    );
  }

  double? _filteredHeading(double? heading) {
    final previous = _displayHeading;
    if (heading == null || previous == null) return heading ?? previous;
    final delta = ((heading - previous + 540) % 360) - 180;
    if (delta.abs() < 2.5) return previous;
    return (previous + delta * 0.72 + 360) % 360;
  }

  double? _lerpHeading(double? from, double? to, double t) {
    if (from == null) return to;
    if (to == null) return from;
    final delta = ((to - from + 540) % 360) - 180;
    return (from + delta * t + 360) % 360;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);
    final latitude = _displayLatitude ?? widget.latitude;
    final longitude = _displayLongitude ?? widget.longitude;
    final heading = _displayHeading ?? widget.heading;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: ClipRect(
          child: FutureBuilder<_PelotasMapData>(
            future: _pelotasMapDataFuture,
            builder: (context, snapshot) {
              final routeInfo = _CockpitRouteInfo.fromRoute(
                route: widget.route,
                latitude: latitude,
                longitude: longitude,
                heading: heading,
                mapData: snapshot.data,
              );
              final mapData = snapshot.data;
              final showLocalMap = widget.localMapPreview && mapData != null;

              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: showLocalMap
                          ? _PelotasMapPainter(
                              data: mapData,
                              latitude: latitude,
                              longitude: longitude,
                              heading: heading,
                              active: widget.active,
                              vehicleIcon: widget.vehicleIcon,
                              route: widget.route,
                              darkMode: Theme.of(context).brightness ==
                                  Brightness.dark,
                              gpsLatitudeSpan: 0.00135,
                              showVehicle: false,
                            )
                          : _CockpitDrivePainter(
                              routeInfo: routeInfo,
                              active: widget.active,
                              darkMode: Theme.of(context).brightness ==
                                  Brightness.dark,
                            ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 7,
                    right: 8,
                    child: Row(
                      children: [
                        Icon(
                          routeInfo.icon,
                          color: routeInfo.turnColor,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            routeInfo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: (widget.active
                                    ? _HomeScreenState._green
                                    : _HomeScreenState._blue)
                                .withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: widget.active
                                  ? _HomeScreenState._green
                                  : _HomeScreenState._blue,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            showLocalMap
                                ? 'LOCAL'
                                : routeInfo.hasRoute
                                    ? routeInfo.distanceLabel
                                    : widget.active
                                        ? routeInfo.distanceLabel
                                        : 'GPS',
                            style: TextStyle(
                              color: widget.active
                                  ? _HomeScreenState._green
                                  : _HomeScreenState._blue,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!showLocalMap)
                    Align(
                      alignment: const Alignment(0, 0.68),
                      child: FractionallySizedBox(
                        widthFactor: 1.0,
                        heightFactor: 0.84,
                        child: Image.asset(
                          'assets/images/car_top.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  if (showLocalMap)
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.36,
                        heightFactor: 0.32,
                        child: Image.asset(
                          'assets/images/aereo_onix.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    bottom: 8,
                    right: 10,
                    child: Text(
                      showLocalMap
                          ? 'Toque para abrir o mapa'
                          : routeInfo.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PelotasMapData {
  const _PelotasMapData({
    required this.bounds,
    required this.center,
    required this.roads,
    required this.fuelStations,
  });

  final List<double> bounds;
  final Offset center;
  final List<_PelotasRoad> roads;
  final List<_FuelStation> fuelStations;

  static Future<_PelotasMapData> load() async {
    final text = await rootBundle.loadString('assets/maps/rs_sul_region.json');
    final json = jsonDecode(text) as Map<String, dynamic>;
    final bounds = (json['bounds'] as List).map((v) => v as num).toList();
    final center = (json['center'] as List).map((v) => v as num).toList();
    final roads = (json['roads'] as List)
        .map((road) => _PelotasRoad.fromJson(road as Map<String, dynamic>))
        .toList();
    final stations = ((json['fuel_stations'] as List?) ?? [])
        .map(
            (station) => _FuelStation.fromJson(station as Map<String, dynamic>))
        .toList();

    return _PelotasMapData(
      bounds: bounds.map((v) => v.toDouble()).toList(),
      center: Offset(center[1].toDouble(), center[0].toDouble()),
      roads: roads,
      fuelStations: stations,
    );
  }
}

class _PelotasRoad {
  const _PelotasRoad({
    required this.rank,
    required this.points,
  });

  final int rank;
  final List<Offset> points;

  factory _PelotasRoad.fromJson(Map<String, dynamic> json) {
    final points = (json['p'] as List).map((point) {
      final values = point as List;
      final lat = (values[0] as num).toDouble();
      final lon = (values[1] as num).toDouble();
      return Offset(lon, lat);
    }).toList();

    return _PelotasRoad(
      rank: (json['r'] as num).toInt(),
      points: points,
    );
  }
}

class _FuelStation {
  const _FuelStation({
    required this.name,
    required this.position,
  });

  final String name;
  final Offset position;

  factory _FuelStation.fromJson(Map<String, dynamic> json) {
    final values = json['p'] as List;
    final lat = (values[0] as num).toDouble();
    final lon = (values[1] as num).toDouble();

    return _FuelStation(
      name: (json['n'] as String?) ?? 'Posto',
      position: Offset(lon, lat),
    );
  }
}

// ignore: unused_element
class _PelotasMapPainter extends CustomPainter {
  const _PelotasMapPainter({
    required this.data,
    required this.latitude,
    required this.longitude,
    required this.heading,
    required this.active,
    required this.vehicleIcon,
    required this.route,
    required this.darkMode,
    this.gpsLatitudeSpan = 0.00028,
    this.showVehicle = true,
  });

  final _PelotasMapData data;
  final double? latitude;
  final double? longitude;
  final double? heading;
  final bool active;
  final String vehicleIcon;
  final OfflineRoute? route;
  final bool darkMode;
  final double gpsLatitudeSpan;
  final bool showVehicle;

  bool get _hasGps => latitude != null && longitude != null;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: darkMode
            ? const [Color(0xFF020814), Color(0xFF071527)]
            : const [Color(0xFFEAF2FF), Color(0xFFFFFFFF)],
      ).createShader(Offset.zero & size);

    canvas.drawRect(Offset.zero & size, background);
    _drawGrid(canvas, size);
    _drawRoads(canvas, size);
    _drawFuelStations(canvas, size);
    _drawRoute(canvas, size);
    if (showVehicle) _drawVehicle(canvas, size);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (darkMode ? Colors.white : Colors.black).withValues(alpha: 0.03)
      ..strokeWidth = 1;

    const spacing = 34.0;
    for (var x = 0.0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawRoads(Canvas canvas, Size size) {
    final minorRoad =
        darkMode ? const Color(0xFF294560) : const Color(0xFFB8CBE0);
    final localRoad =
        darkMode ? const Color(0xFF4F7393) : const Color(0xFF8EA9C4);
    final collectorRoad =
        darkMode ? const Color(0xFF6FA0C4) : const Color(0xFF678CAC);
    final mainRoad =
        darkMode ? const Color(0xFF39D8B6) : const Color(0xFF168C78);
    final glowRoad =
        darkMode ? const Color(0xFF39D8B6) : const Color(0xFF168C78);
    final gpsScale = _hasGps ? 5.8 : 1.0;
    final paints = <int, Paint>{
      0: Paint()
        ..color = minorRoad.withValues(alpha: darkMode ? 0.55 : 0.65)
        ..strokeWidth = 0.62 * gpsScale
        ..style = PaintingStyle.stroke,
      1: Paint()
        ..color = localRoad.withValues(alpha: darkMode ? 0.7 : 0.75)
        ..strokeWidth = 0.82 * gpsScale
        ..style = PaintingStyle.stroke,
      2: Paint()
        ..color = collectorRoad.withValues(alpha: 0.82)
        ..strokeWidth = 1.04 * gpsScale
        ..style = PaintingStyle.stroke,
      3: Paint()
        ..color = mainRoad.withValues(alpha: 0.85)
        ..strokeWidth = 1.28 * gpsScale
        ..style = PaintingStyle.stroke,
      4: Paint()
        ..color = glowRoad.withValues(alpha: 0.9)
        ..strokeWidth = 1.62 * gpsScale
        ..style = PaintingStyle.stroke,
      5: Paint()
        ..color = _HomeScreenState._green.withValues(alpha: 0.9)
        ..strokeWidth = 1.84 * gpsScale
        ..style = PaintingStyle.stroke,
    };

    final visibleRect = (Offset.zero & size).inflate(_hasGps ? 260 : 40);

    for (final road in data.roads) {
      if (road.points.length < 2) continue;

      final projectedPoints = road.points
          .map((point) => _project(point, size))
          .toList(growable: false);
      if (!_projectedPathTouches(projectedPoints, visibleRect)) continue;

      final path = Path()
        ..moveTo(projectedPoints.first.dx, projectedPoints.first.dy);

      for (var i = 1; i < projectedPoints.length; i++) {
        final point = projectedPoints[i];
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(path, paints[road.rank] ?? paints[1]!);
    }
  }

  void _drawFuelStations(Canvas canvas, Size size) {
    final visibleRect = (Offset.zero & size).inflate(18);
    final stationPaint = Paint()
      ..color = _HomeScreenState._green
      ..style = PaintingStyle.fill;
    final haloPaint = Paint()
      ..color = _HomeScreenState._green.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    final darkPaint = Paint()
      ..color = const Color(0xFF03101E)
      ..style = PaintingStyle.fill;
    final hosePaint = Paint()
      ..color = const Color(0xFF03101E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    for (final station in data.fuelStations) {
      final point = _project(station.position, size);
      if (!visibleRect.contains(point)) continue;

      canvas.drawCircle(point, 8, haloPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: point, width: 9, height: 10),
          const Radius.circular(2),
        ),
        stationPaint,
      );
      canvas.drawRect(
        Rect.fromLTWH(point.dx - 2.2, point.dy - 2.6, 3.4, 2.6),
        darkPaint,
      );
      canvas.drawPath(
        Path()
          ..moveTo(point.dx + 3.2, point.dy - 1.5)
          ..quadraticBezierTo(
            point.dx + 7,
            point.dy,
            point.dx + 4,
            point.dy + 5,
          ),
        hosePaint,
      );
    }
  }

  void _drawRoute(Canvas canvas, Size size) {
    final points = route?.points;
    if (points == null || points.length < 2) return;

    final routePoints = _hasGps ? _routePointsFromCar(points) : points;
    final projectedPoints = routePoints
        .map((point) => _project(point, size))
        .toList(growable: false);
    final visibleRect = (Offset.zero & size).inflate(280);
    if (!_projectedPathTouches(projectedPoints, visibleRect)) return;

    final path = Path()
      ..moveTo(projectedPoints.first.dx, projectedPoints.first.dy);
    for (var i = 1; i < projectedPoints.length; i++) {
      path.lineTo(projectedPoints[i].dx, projectedPoints[i].dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF9AF2D8).withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 12,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _HomeScreenState._blue
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 6.2,
    );
  }

  List<Offset> _routePointsFromCar(List<Offset> points) {
    final car = _viewCenter;
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

  void _drawVehicle(Canvas canvas, Size size) {
    final point = _project(_viewCenter, size);
    final color =
        active && _hasGps ? _HomeScreenState._green : _HomeScreenState._blue;
    final radius = active && _hasGps ? 13.0 : 10.0;

    canvas.drawCircle(
      point,
      radius * 1.4,
      Paint()..color = color.withValues(alpha: 0.18),
    );
    _drawVehicleIcon(canvas, point, color, radius, heading ?? 0);
  }

  void _drawVehicleIcon(
    Canvas canvas,
    Offset center,
    Color color,
    double radius,
    double headingDegrees,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas
        .rotate(_mapRotationRadians == 0 ? headingDegrees * math.pi / 180 : 0);

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: darkMode ? 0.45 : 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = _vehicleIconPath(radius);
    canvas.drawPath(path.shift(const Offset(1.2, 1.4)), shadow);
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
    final center = _viewCenter;
    final latSpan = _latitudeSpan;
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

  Offset get _viewCenter {
    if (_hasGps) return Offset(longitude!, latitude!);
    return data.center;
  }

  double get _latitudeSpan => _hasGps ? gpsLatitudeSpan : 0.045;

  double get _mapRotationRadians {
    if (!_hasGps || heading == null) return 0;
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
  bool shouldRepaint(covariant _PelotasMapPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.latitude != latitude ||
        oldDelegate.longitude != longitude ||
        oldDelegate.heading != heading ||
        oldDelegate.active != active ||
        oldDelegate.vehicleIcon != vehicleIcon ||
        oldDelegate.route != route ||
        oldDelegate.darkMode != darkMode ||
        oldDelegate.gpsLatitudeSpan != gpsLatitudeSpan ||
        oldDelegate.showVehicle != showVehicle;
  }
}

// ignore: unused_element
class _TripPanel extends StatelessWidget {
  const _TripPanel({
    required this.distance,
    required this.duration,
    required this.consumption,
    required this.cost,
  });

  final String distance;
  final String duration;
  final String consumption;
  final String cost;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 180 || constraints.maxWidth < 150;

        return _Panel(
          padding: EdgeInsets.fromLTRB(
            dense ? 6 : 14,
            dense ? 6 : 14,
            dense ? 6 : 14,
            dense ? 4 : 10,
          ),
          child: Column(
            children: [
              Text(
                'VIAGEM ATUAL',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: dense ? 10 : 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Divider(
                color: _HomeScreenState._line,
                height: dense ? 6 : 22,
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _TripLine(
                      Icons.route,
                      'Distância',
                      distance,
                      'km',
                      dense: dense,
                    ),
                    _TripLine(
                      Icons.timer_outlined,
                      'Tempo',
                      duration,
                      '',
                      dense: dense,
                    ),
                    _TripLine(
                      Icons.local_gas_station,
                      'Consumo médio',
                      consumption,
                      'km/L',
                      dense: dense,
                    ),
                    if (!dense)
                      _TripLine(
                        Icons.attach_money,
                        'Custo estimado',
                        cost,
                        '',
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TripLine extends StatelessWidget {
  const _TripLine(
    this.icon,
    this.label,
    this.value,
    this.unit, {
    this.dense = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return Row(
      children: [
        Icon(icon, color: _HomeScreenState._blue, size: dense ? 15 : 28),
        SizedBox(width: dense ? 4 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: dense ? 8 : 13,
                  height: 1,
                ),
              ),
              RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  text: value,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: dense ? 11 : 18,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                  children: [
                    if (unit.isNotEmpty)
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(color: _HomeScreenState._blue),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 90 || constraints.maxWidth < 160;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: _Panel(
              padding: EdgeInsets.all(dense ? 6 : 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: _HomeScreenState._blue,
                    size: dense ? 24 : 52,
                  ),
                  SizedBox(width: dense ? 6 : 18),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: dense ? 8 : 13,
                            height: 1,
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                value,
                                style: TextStyle(
                                  color: colors.primaryText,
                                  fontSize: dense ? 18 : 30,
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                ),
                              ),
                              SizedBox(width: dense ? 3 : 5),
                              Padding(
                                padding: EdgeInsets.only(bottom: dense ? 1 : 3),
                                child: Text(
                                  unit,
                                  style: TextStyle(
                                    color: _HomeScreenState._blue,
                                    fontSize: dense ? 10 : 18,
                                    fontWeight: FontWeight.w700,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 95 || constraints.maxWidth < 190;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: _Panel(
              padding: EdgeInsets.all(dense ? 6 : 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GlowIcon(icon: icon, color: color, size: dense ? 34 : 66),
                  SizedBox(width: dense ? 8 : 20),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: dense ? 12 : 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!dense) ...[
                          const SizedBox(height: 7),
                          Text(
                            subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
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
}

class _CompactCostCard extends StatelessWidget {
  const _CompactCostCard({
    required this.value,
  });

  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dense =
              constraints.maxWidth < 150 || constraints.maxHeight < 82;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.attach_money,
                color: colors.secondaryIcon,
                size: dense ? 18 : 25,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!dense)
                      Text(
                        'CUSTO',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: dense ? 12 : 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NavigationRouteCard extends StatelessWidget {
  const _NavigationRouteCard({
    required this.instruction,
    required this.destination,
    required this.hasRoute,
    required this.onTap,
    required this.onFavoritesTap,
  });

  final _DashboardInstruction? instruction;
  final String? destination;
  final bool hasRoute;
  final VoidCallback onTap;
  final VoidCallback onFavoritesTap;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 95 || constraints.maxWidth < 190;
        final title = instruction?.title ?? (hasRoute ? 'ROTA ATIVA' : 'ROTAS');
        final detail =
            instruction?.detail ?? destination ?? 'Favoritos e navegação';

        return Material(
          color: Colors.transparent,
          child: _Panel(
            padding: EdgeInsets.all(dense ? 6 : 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap,
                    child: Row(
                      children: [
                        _GlowIcon(
                          icon: instruction?.icon ?? Icons.navigation,
                          color: _HomeScreenState._blue,
                          size: dense ? 32 : 54,
                        ),
                        SizedBox(width: dense ? 8 : 14),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _HomeScreenState._blue,
                                  fontSize: dense ? 12 : 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: dense ? 2 : 5),
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.secondaryText,
                                  fontSize: dense ? 10 : 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onFavoritesTap,
                  child: Container(
                    width: dense ? 34 : 46,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: _HomeScreenState._blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _HomeScreenState._blue.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Icon(
                      Icons.star,
                      color: _HomeScreenState._blue,
                      size: dense ? 18 : 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashboardInstruction {
  const _DashboardInstruction({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;
}

// ignore: unused_element
class _GpsStatusCard extends StatelessWidget {
  const _GpsStatusCard({
    required this.active,
    required this.statusMessage,
    required this.distanceMeters,
    required this.updates,
    required this.rawPositions,
    required this.ignoredPositions,
    required this.lastAccuracy,
    required this.lastMovementMeters,
    required this.onTap,
  });

  final bool active;
  final String statusMessage;
  final double distanceMeters;
  final int updates;
  final int rawPositions;
  final int ignoredPositions;
  final double? lastAccuracy;
  final double? lastMovementMeters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dense = constraints.maxHeight < 105 || constraints.maxWidth < 250;
        final distanceKm = distanceMeters / 1000;
        final accuracyText = lastAccuracy == null
            ? 'sem sinal'
            : 'prec. ${lastAccuracy!.toStringAsFixed(0)}m';
        final movementText = lastMovementMeters == null
            ? 'aguardando movimento'
            : 'ult. ${lastMovementMeters!.toStringAsFixed(0)}m';

        return _Panel(
          padding: EdgeInsets.fromLTRB(
            dense ? 8 : 28,
            dense ? 6 : 14,
            dense ? 8 : 28,
            dense ? 6 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'CONTROLE GPS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: dense ? 10 : 17,
                      ),
                    ),
                  ),
                  Icon(
                    active ? Icons.stop_circle_outlined : Icons.gps_fixed,
                    color: active
                        ? _HomeScreenState._green
                        : _HomeScreenState._blue,
                    size: dense ? 14 : 20,
                  ),
                ],
              ),
              SizedBox(height: dense ? 4 : 10),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: onTap,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 22),
                      decoration: BoxDecoration(
                        color: colors.innerPanel,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _HomeScreenState._line),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GlowIcon(
                            icon: active ? Icons.location_on : Icons.gps_fixed,
                            color: active
                                ? _HomeScreenState._green
                                : _HomeScreenState._blue,
                            size: dense ? 34 : 66,
                          ),
                          SizedBox(width: dense ? 8 : 22),
                          Flexible(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  active ? 'PARAR GPS' : 'INICIAR GPS',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: active
                                        ? _HomeScreenState._green
                                        : _HomeScreenState._blue,
                                    fontSize: dense ? 12 : 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                if (!dense) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    active
                                        ? '${distanceKm.toStringAsFixed(2)} km GPS | $updates mov.'
                                        : statusMessage.isEmpty
                                            ? 'Toque para ativar quando estiver pronto'
                                            : statusMessage,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.primaryText,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (active) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      statusMessage.isEmpty
                                          ? '$rawPositions pos. | $ignoredPositions ign. | $accuracyText | $movementText'
                                          : statusMessage,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.secondaryText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ] else if (active) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${distanceKm.toStringAsFixed(2)}km',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.secondaryText,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = _DashboardColors.of(context);
    final color = active ? _HomeScreenState._blue : colors.secondaryIcon;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 150;

              return Container(
                height: 54,
                decoration: BoxDecoration(
                  color: active
                      ? _HomeScreenState._blue.withValues(alpha: 0.16)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      active ? Border.all(color: _HomeScreenState._blue) : null,
                ),
                child: stacked
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 24),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, color: color, size: 28),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GlowIcon extends StatelessWidget {
  const _GlowIcon({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.34),
            blurRadius: 18,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size * 0.54),
    );
  }
}

class _RoundStatusIcon extends StatelessWidget {
  const _RoundStatusIcon({
    required this.icon,
    required this.color,
    this.size = 48,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _HomeScreenState._line),
      ),
      child: Icon(icon, color: color, size: size * 0.58),
    );
  }
}

class _HeaderGpsButton extends StatelessWidget {
  const _HeaderGpsButton({
    required this.active,
    required this.onTap,
    required this.compact,
  });

  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = active ? _HomeScreenState._green : _HomeScreenState._blue;

    return Tooltip(
      message: active ? 'Parar GPS' : 'Iniciar GPS',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: compact ? 36 : 44,
          padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 13),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.location_on : Icons.gps_fixed,
                color: color,
                size: compact ? 18 : 22,
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                Text(
                  active ? 'PARAR' : 'INICIAR',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FuelGaugePainter extends CustomPainter {
  _FuelGaugePainter({required this.percentage});

  final double percentage;
  static const Color _lowFuelOrange = Color(0xFFFF4A00);

  @override
  void paint(Canvas canvas, Size size) {
    final pct = percentage.clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height / 2 + size.height * 0.08);
    final radius = math.min(size.width, size.height) * 0.43;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = math.pi * 0.80;
    const sweepAngle = math.pi * 1.40;
    final stroke = math.max(16.0, radius * 0.13);

    final glowPaint = Paint()
      ..color = _HomeScreenState._blue.withValues(alpha: 0.09)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);

    final bgPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    if (pct > 0.001) {
      final fuelPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [
            _lowFuelOrange,
            Colors.deepOrange,
            Colors.amber,
            Colors.lightGreenAccent,
            Colors.green,
          ],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweepAngle * pct, false, fuelPaint);
    }

    final tickPaint = Paint()
      ..color = _HomeScreenState._blue
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i <= 10; i++) {
      final angle = startAngle + (sweepAngle / 10) * i;
      final outer = radius - stroke * 0.65;
      final inner = radius - stroke * 1.25;
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer),
        Offset(center.dx + math.cos(angle) * inner,
            center.dy + math.sin(angle) * inner),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FuelGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage;
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

String _formatRouteDistance(double meters) {
  final safeMeters = meters.isFinite ? math.max(0, meters) : 0.0;
  if (safeMeters < 950) {
    return '${safeMeters.round()} m';
  }

  final km = safeMeters / 1000;
  final digits = km >= 10 ? 0 : 1;
  return '${km.toStringAsFixed(digits).replaceAll('.', ',')} km';
}

Offset _metersFromOrigin(Offset origin, Offset point) {
  final latRad = origin.dy * math.pi / 180;
  final metersPerLon = 111320.0 * math.cos(latRad).abs().clamp(0.25, 1.0);
  const metersPerLat = 111320.0;
  return Offset(
    (point.dx - origin.dx) * metersPerLon,
    (point.dy - origin.dy) * metersPerLat,
  );
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

class _VoiceListeningFallback extends StatelessWidget {
  const _VoiceListeningFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.88,
          colors: [Color(0xFF072A4A), Color(0xFF02060D), Colors.black],
          stops: [0, 0.58, 1],
        ),
      ),
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.72, end: 1),
          duration: const Duration(milliseconds: 760),
          curve: Curves.easeInOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF05223D),
                  border: Border.all(color: _HomeScreenState._blue, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _HomeScreenState._blue.withValues(alpha: 0.42),
                      blurRadius: 42,
                      spreadRadius: 12,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mic,
                  color: Colors.white,
                  size: 88,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
