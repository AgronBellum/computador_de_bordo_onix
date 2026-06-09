import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/trip_model.dart';
import '../providers/app_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _odometerController = TextEditingController();
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  static const Color _bg = Color(0xFF020914);
  static const Color _bar = Color(0xFF050D19);
  static const Color _card = Color(0xFF061426);
  static const Color _card2 = Color(0xFF020B17);
  static const Color _blue = Color(0xFF1677FF);
  static const Color _green = Color(0xFF69F01B);
  static const Color _purple = Color(0xFFB7A2E8);
  static const Color _line = Color(0xFF0B3C73);

  @override
  void initState() {
    super.initState();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
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
    final topHeight = compact
        ? availableHeight * 0.52
        : (availableHeight * 0.52).clamp(240.0, 430.0);
    final metricHeight = compact
        ? availableHeight * 0.21
        : (availableHeight * 0.18).clamp(104.0, 150.0);
    final actionHeight = math.max(
      compact ? 56.0 : 122.0,
      availableHeight - topHeight - metricHeight - (gap * 2),
    );

    return SingleChildScrollView(
      padding: padding,
      child: Column(
        children: [
          SizedBox(
            height: topHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 26,
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
                  flex: 34,
                  child: _FuelGaugeCard(
                    percentage: provider.fuelPercentage,
                    fuelName: 'GASOLINA',
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 19,
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
                SizedBox(width: gap),
                Expanded(
                  flex: 18,
                  child: _TripPanel(
                    distance: _decimal(trip.distanceTraveled, 1),
                    duration: _formatDuration(
                      DateTime.now().difference(trip.createdAt),
                    ),
                    consumption: _decimal(trip.consumptionPerKm, 1),
                    cost: _estimatedCostValue(provider, trip),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: metricHeight,
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
                    title: 'CONSUMO MEDIO GERAL',
                    value: _decimal(trip.consumptionPerKm, 1),
                    unit: 'km/L',
                    onTap: () => _showNumberEditDialog(
                      context: context,
                      title: 'Alterar consumo medio',
                      currentValue: trip.consumptionPerKm,
                      suffix: 'km/L',
                      onSave: provider.setConsumption,
                    ),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  child: _MetricCard(
                    icon: Icons.attach_money,
                    title: 'CUSTO ESTIMADO',
                    value: _estimatedCostValue(provider, trip),
                    unit: '',
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: gap),
          SizedBox(
            height: actionHeight,
            child: Row(
              children: [
                Expanded(
                  flex: 27,
                  child: _ActionCard(
                    icon: Icons.local_gas_station,
                    title: 'ABASTECER',
                    subtitle: 'Registrar abastecimento',
                    color: _green,
                    onTap: () => Navigator.pushNamed(context, '/addFuel'),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 29,
                  child: _ActionCard(
                    icon: Icons.route,
                    title: 'KM MANUAL',
                    subtitle: 'Registrar km manualmente',
                    color: _blue,
                    onTap: () => _showManualKmDialog(context, provider),
                  ),
                ),
                SizedBox(width: gap),
                Expanded(
                  flex: 39,
                  child: _GpsStatusCard(
                    active: provider.isGpsTracking,
                    statusMessage: provider.statusMessage,
                    distanceMeters: provider.gpsDistance,
                    updates: provider.gpsUpdateCount,
                    rawPositions: provider.gpsRawPositionCount,
                    ignoredPositions: provider.gpsIgnoredPositionCount,
                    lastAccuracy: provider.lastGpsAccuracy,
                    lastMovementMeters: provider.lastGpsMovementMeters,
                    onTap: provider.isGpsTracking
                        ? provider.stopGpsTracking
                        : provider.startGpsTracking,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppProvider provider) {
    final colors = _DashboardColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compactHeader = width < 900;

    return Container(
      height: compactHeader ? 62 : 74,
      padding: EdgeInsets.symmetric(horizontal: compactHeader ? 12 : 22),
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(
          bottom: BorderSide(color: _line.withValues(alpha: 0.75)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.directions_car_filled,
            color: _blue,
            size: compactHeader ? 32 : 42,
          ),
          SizedBox(width: compactHeader ? 10 : 16),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                provider.vehicleName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: compactHeader ? 18 : 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (!compactHeader) ...[
                const SizedBox(height: 2),
                Text(
                  'COMPUTADOR DE BORDO',
                  style: TextStyle(color: colors.secondaryText, fontSize: 14),
                ),
              ],
            ],
          ),
          SizedBox(width: compactHeader ? 12 : 0),
          if (!compactHeader) const Spacer(),
          Icon(
            Icons.circle,
            color: provider.isGpsTracking ? _green : Colors.orangeAccent,
            size: compactHeader ? 10 : 14,
          ),
          SizedBox(width: compactHeader ? 6 : 14),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.isGpsTracking ? 'GPS ATIVO' : 'GPS OFFLINE',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        provider.isGpsTracking ? _green : Colors.orangeAccent,
                    fontSize: compactHeader ? 13 : 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (!compactHeader)
                  Text(
                    provider.isGpsTracking
                        ? 'Rastreamento automatico em segundo plano'
                        : 'GPS automatico aguardando permissao/sinal',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.primaryText, fontSize: 13),
                  ),
              ],
            ),
          ),
          if (!compactHeader) const Spacer(),
          InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: provider.toggleThemeMode,
            child: _RoundStatusIcon(
              icon: provider.isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: colors.primaryText,
              size: compactHeader ? 38 : 48,
            ),
          ),
          if (!compactHeader) ...[
            const SizedBox(width: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: provider.toggleThemeMode,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.isDarkMode ? 'MODO ESCURO' : 'MODO CLARO',
                    style: TextStyle(color: colors.primaryText, fontSize: 14),
                  ),
                  Text(
                    'Toque para mudar',
                    style: TextStyle(color: colors.primaryText, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 34),
            Container(width: 1, height: 38, color: _line),
            const SizedBox(width: 26),
            IconButton(
              onPressed: () => _showSettingsDialog(context, provider),
              icon: Icon(Icons.settings, color: colors.secondaryIcon, size: 34),
            ),
            const SizedBox(width: 26),
          ] else ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _showSettingsDialog(context, provider),
              icon: Icon(Icons.settings, color: colors.secondaryIcon, size: 28),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(
            _formatTime(_now),
            style: TextStyle(
              color: colors.primaryText,
              fontSize: compactHeader ? 22 : 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, BoxConstraints constraints) {
    final colors = _DashboardColors.of(context);
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
                    width: compact ? 220 : 260,
                    height: compact ? 54 : 86,
                    child: _ActionCard(
                      icon: Icons.add,
                      title: 'ABASTECER',
                      subtitle: 'Iniciar computador de bordo',
                      color: _green,
                      onTap: () => Navigator.pushNamed(context, '/addFuel'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
              icon: Icons.calendar_month,
              label: 'HISTORICO',
              onTap: () => Navigator.pushReplacementNamed(context, '/history'),
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
                      'Configuracoes',
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
                                  labelText: 'Nome do veiculo',
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
                                  labelText: 'Preco medio gasolina',
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

  String _formatTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDuration(Duration duration) {
    final h = duration.inHours.toString().padLeft(2, '0');
    final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$h:$m h';
  }

  String _decimal(double value, int digits) {
    return value.toStringAsFixed(digits).replaceAll('.', ',');
  }

  String _estimatedCostValue(AppProvider provider, TripModel trip) {
    return _formatCurrency(_estimatedCostAmount(provider.fuelPrice, trip));
  }

  double _estimatedCostAmount(double fuelPrice, TripModel trip) {
    final consumed = math.max<double>(
      0.0,
      trip.litersAdded - trip.remainingFuel,
    );
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
                      'Nivel de combustivel',
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
                      'Distancia',
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
                      'Consumo medio',
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
