import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';

class AddFuelScreen extends StatefulWidget {
  const AddFuelScreen({super.key});

  @override
  State<AddFuelScreen> createState() => _AddFuelScreenState();
}

class _AddFuelScreenState extends State<AddFuelScreen> {
  final _formKey = GlobalKey<FormState>();
  final _litersController = TextEditingController();
  final _consumptionController = TextEditingController();
  final _odometerController = TextEditingController();

  bool _usePreviousOdometer = true;
  bool _usePreviousConsumption = true;
  bool _addRemainingFuel = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreviousData();
    });
  }

  void _loadPreviousData() {
    final provider = context.read<AppProvider>();

    final consumption =
        provider.activeTrip?.consumptionPerKm ?? provider.lastConsumption;

    final odometer =
        provider.activeTrip?.currentOdometer ?? provider.lastOdometer;

    if (consumption != null && _usePreviousConsumption) {
      _consumptionController.text = consumption.toStringAsFixed(2);
    }

    if (odometer != null && _usePreviousOdometer) {
      _odometerController.text = odometer.toStringAsFixed(0);
    }

    setState(() {});
  }

  @override
  void dispose() {
    _litersController.dispose();
    _consumptionController.dispose();
    _odometerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700 && size.height > 350;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ABASTECER',
          style: TextStyle(fontSize: 14),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 40,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Form(
          key: _formKey,
          child: isWide ? _buildWideLayout() : _buildCompactLayout(),
        ),
      ),
    );
  }

  Widget _buildWideLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              _buildPreviousDataCard(),
              const SizedBox(height: 10),
              _buildPreviewCard(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 6,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOptionsCard(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildInput(
                      controller: _litersController,
                      label: 'Litros novos',
                      hint: '15.0',
                      icon: Icons.local_gas_station,
                      suffix: 'L',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildInput(
                      controller: _consumptionController,
                      label: 'Consumo (km/L)',
                      hint: '10.0',
                      icon: Icons.speed,
                      suffix: 'km/L',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildOdometerInput(),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _save,
                  child: const Text(
                    'CONFIRMAR ABASTECIMENTO',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        const SizedBox(height: 8),
        _buildPreviousDataCard(),
        const SizedBox(height: 8),
        _buildOptionsCard(),
        const SizedBox(height: 8),
        _buildPreviewCard(),
        const SizedBox(height: 8),
        _buildInput(
          controller: _litersController,
          label: 'Litros abastecidos agora',
          hint: '15.0',
          icon: Icons.local_gas_station,
          suffix: 'L',
        ),
        const SizedBox(height: 8),
        _buildInput(
          controller: _consumptionController,
          label: 'Consumo (km por litro)',
          hint: '10.0',
          icon: Icons.speed,
          suffix: 'km/L',
        ),
        const SizedBox(height: 8),
        _buildOdometerInput(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: _save,
            child: const Text(
              'CONFIRMAR ABASTECIMENTO',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade700, Colors.orange.shade500],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.local_gas_station, size: 24, color: Colors.white),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Novo Abastecimento',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Soma com o combustível restante atual',
                  style: TextStyle(fontSize: 9, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviousDataCard() {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final remainingFuel =
            provider.activeTrip?.remainingFuel ?? provider.lastRemainingFuel;

        final odometer =
            provider.activeTrip?.currentOdometer ?? provider.lastOdometer;

        final consumption =
            provider.activeTrip?.consumptionPerKm ?? provider.lastConsumption;

        final hasData =
            remainingFuel != null || odometer != null || consumption != null;

        if (!hasData) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.white38, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Primeiro abastecimento. Nenhum dado anterior.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.shade700.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.history, color: Colors.orange.shade400, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'DADOS ATUAIS DO TANQUE',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade400,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (remainingFuel != null)
                    _buildPrevStat(
                      'Restante',
                      '${remainingFuel.toStringAsFixed(1)} L',
                      Colors.green,
                    ),
                  if (odometer != null)
                    _buildPrevStat(
                      'KM',
                      odometer.toStringAsFixed(0),
                      Colors.blue,
                    ),
                  if (consumption != null)
                    _buildPrevStat(
                      'Consumo',
                      '${consumption.toStringAsFixed(1)} km/L',
                      Colors.purple,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrevStat(String label, String value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 10, color: Colors.white38),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildOptionsCard() {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final remainingFuel =
            provider.activeTrip?.remainingFuel ?? provider.lastRemainingFuel;

        final odometer =
            provider.activeTrip?.currentOdometer ?? provider.lastOdometer;

        final consumption =
            provider.activeTrip?.consumptionPerKm ?? provider.lastConsumption;

        final hasData =
            remainingFuel != null || odometer != null || consumption != null;

        if (!hasData) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF252538),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'OPÇÕES',
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.white38,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              if (remainingFuel != null && remainingFuel > 0)
                _buildOptionSwitch(
                  'Somar combustível restante (${remainingFuel.toStringAsFixed(1)} L)',
                  _addRemainingFuel,
                  (v) => setState(() => _addRemainingFuel = v),
                ),
              if (odometer != null)
                _buildOptionSwitch(
                  'Usar KM atual (${odometer.toStringAsFixed(0)})',
                  _usePreviousOdometer,
                  (v) {
                    setState(() {
                      _usePreviousOdometer = v;
                      if (v) {
                        _odometerController.text = odometer.toStringAsFixed(0);
                      } else {
                        _odometerController.clear();
                      }
                    });
                  },
                ),
              if (consumption != null)
                _buildOptionSwitch(
                  'Usar consumo atual (${consumption.toStringAsFixed(1)} km/L)',
                  _usePreviousConsumption,
                  (v) {
                    setState(() {
                      _usePreviousConsumption = v;
                      if (v) {
                        _consumptionController.text =
                            consumption.toStringAsFixed(1);
                      } else {
                        _consumptionController.clear();
                      }
                    });
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionSwitch(
    String label,
    bool value,
    Function(bool) onChanged,
  ) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 20,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: Colors.orange.shade400,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 10, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _litersController,
      builder: (context, litersText, child) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: _consumptionController,
          builder: (context, consumptionText, child) {
            final provider = context.read<AppProvider>();

            final newLiters =
                double.tryParse(litersText.text.replaceAll(',', '.')) ?? 0;

            final consumption =
                double.tryParse(consumptionText.text.replaceAll(',', '.')) ?? 0;

            final previousRemaining = _addRemainingFuel
                ? (provider.activeTrip?.remainingFuel ??
                    provider.lastRemainingFuel ??
                    0)
                : 0;

            final totalFuel = newLiters + previousRemaining;
            final range = consumption > 0 ? totalFuel * consumption : 0;

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.shade700.withOpacity(0.3),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'PREVISÃO PÓS ABASTECIMENTO',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildPreviewStat(
                        'NOVO',
                        '${newLiters.toStringAsFixed(1)} L',
                        Colors.white70,
                      ),
                      if (previousRemaining > 0)
                        _buildPreviewStat(
                          'RESTANTE',
                          '+${previousRemaining.toStringAsFixed(1)} L',
                          Colors.green,
                        ),
                      _buildPreviewStat(
                        'TOTAL',
                        '${totalFuel.toStringAsFixed(1)} L',
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'AUTONOMIA: ${range.toStringAsFixed(0)} KM',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color:
                          range > 0 ? Colors.orange.shade400 : Colors.white24,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPreviewStat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 7, color: Colors.white38),
        ),
      ],
    );
  }

  Widget _buildOdometerInput() {
    return Consumer<AppProvider>(
      builder: (context, provider, child) {
        final odometer =
            provider.activeTrip?.currentOdometer ?? provider.lastOdometer;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Quilometragem',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(width: 6),
                if (_usePreviousOdometer && odometer != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade900.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ATUAL: ${odometer.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 8,
                        color: Colors.blue.shade400,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _odometerController,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14, color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ex: 45230',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.add_road, size: 18),
                suffixText: 'KM',
                suffixStyle: TextStyle(
                  color: Colors.orange.shade400,
                  fontWeight: FontWeight.bold,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 12,
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Obrigatório';

                final parsed = double.tryParse(value.replaceAll(',', '.'));

                if (parsed == null) return 'Inválido';

                return null;
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
            suffixText: suffix,
            suffixStyle: TextStyle(
              color: Colors.orange.shade400,
              fontWeight: FontWeight.bold,
            ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 12,
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Obrigatório';

            final parsed = double.tryParse(value.replaceAll(',', '.'));

            if (parsed == null) return 'Inválido';

            if (parsed <= 0) return 'Valor deve ser maior que zero';

            return null;
          },
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AppProvider>();

    final liters = double.parse(_litersController.text.replaceAll(',', '.'));

    final consumption =
        double.parse(_consumptionController.text.replaceAll(',', '.'));

    final odometer =
        double.parse(_odometerController.text.replaceAll(',', '.'));

    final lastKm =
        provider.activeTrip?.currentOdometer ?? provider.lastOdometer;

    if (lastKm != null && odometer < lastKm - 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KM não pode ser menor que a última registrada'),
        ),
      );
      return;
    }

    final previousRemaining =
        provider.activeTrip?.remainingFuel ?? provider.lastRemainingFuel;

    try {
      if (_addRemainingFuel && previousRemaining != null) {
        await provider.refuel(
          newLiters: liters,
          consumption: consumption,
          odometer: odometer,
          previousRemaining: previousRemaining,
        );
      } else {
        await provider.createTrip(
          liters: liters,
          consumption: consumption,
          odometer: odometer,
        );
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }
}
