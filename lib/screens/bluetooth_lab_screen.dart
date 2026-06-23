import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/obd_service.dart';

class BluetoothLabScreen extends StatefulWidget {
  const BluetoothLabScreen({super.key});

  @override
  State<BluetoothLabScreen> createState() => _BluetoothLabScreenState();
}

class _BluetoothLabScreenState extends State<BluetoothLabScreen> {
  static const Color _bg = Color(0xFF020914);
  static const Color _panel = Color(0xFF061426);
  static const Color _line = Color(0xFF0B3C73);
  static const Color _blue = Color(0xFF1677FF);
  static const Color _green = Color(0xFF69F01B);
  static const Color _amber = Color(0xFFFFC857);

  final ObdService _obd = ObdService();
  final TextEditingController _macController = TextEditingController();
  final TextEditingController _pinController =
      TextEditingController(text: '1234');
  final ScrollController _logController = ScrollController();

  Map<String, dynamic> _status = const {};
  List<ObdBluetoothDevice> _paired = const [];
  List<ObdBluetoothDevice> _found = const [];
  List<String> _log = const [];
  bool _loadingStatus = false;
  bool _requestingPermissions = false;
  bool _loadingPaired = false;
  bool _scanning = false;
  bool _connecting = false;
  bool _pairing = false;
  bool _autoReconnect = false;
  String? _lastMac;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    _macController.dispose();
    _pinController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMac = prefs.getString('last_elm327_address');
    final autoReconnect =
        prefs.getBool('bluetooth_lab_auto_reconnect') ?? false;
    if (!mounted) return;
    setState(() {
      _lastMac = lastMac;
      _autoReconnect = autoReconnect;
      if (lastMac != null && _macController.text.trim().isEmpty) {
        _macController.text = lastMac;
      }
    });
    _addLog('Prefs carregadas. Ultimo MAC: ${lastMac ?? "--"}');
    if (autoReconnect && lastMac != null) {
      _addLog(
          'Auto reconectar estÃ¡ ativado, mas nÃ£o dispara durante diagnÃ³stico para evitar loop de pareamento. Use RECONECTAR ULTIMO.');
    }
  }

  Future<void> _saveAutoReconnect(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bluetooth_lab_auto_reconnect', value);
    if (!mounted) return;
    setState(() => _autoReconnect = value);
    _addLog('Auto reconectar ultimo ELM: ${value ? "ativado" : "desativado"}');
  }

  Future<void> _refreshStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final status = await _obd.bluetoothStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
      _addLog(
        'Status: disponÃ­vel=${_yes(status["available"])} ligado=${_yes(status["enabled"])} permissÃµes=${_yes(status["permissionsGranted"])} sdk=${status["sdk"] ?? "--"}',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingStatus = false);
      _addLog('ERRO status: $error');
    }
  }

  Future<void> _requestPermissions() async {
    setState(() => _requestingPermissions = true);
    _addLog('Solicitando permissÃµes Bluetooth/LocalizaÃ§Ã£o...');
    try {
      final granted = await _obd.requestPermissions();
      _addLog(granted ? 'Permissoes concedidas' : 'Permissoes negadas');
      await _refreshStatus();
    } catch (error) {
      _addLog('ERRO permissões: $error');
    } finally {
      if (mounted) setState(() => _requestingPermissions = false);
    }
  }

  Future<void> _requestEnableBluetooth() async {
    _addLog('Abrindo solicitacao nativa para ligar Bluetooth...');
    try {
      final alreadyEnabled = await _obd.requestEnableBluetooth();
      _addLog(
        alreadyEnabled
            ? 'Bluetooth ja estava ligado'
            : 'Solicitacao de ligar Bluetooth enviada ao Android',
      );
      await Future<void>.delayed(const Duration(seconds: 1));
      await _refreshStatus();
    } catch (error) {
      _addLog('ERRO ligar Bluetooth: $error');
    }
  }

  Future<void> _loadPaired() async {
    setState(() => _loadingPaired = true);
    _addLog('Buscando dispositivos pareados...');
    try {
      final devices = await _obd.listPairedDevices();
      if (!mounted) return;
      setState(() {
        _paired = devices;
        _loadingPaired = false;
      });
      _addLog('Pareados encontrados: ${devices.length}');
      for (final device in devices) {
        _addLog('Pareado: ${_deviceLine(device)}');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingPaired = false);
      _addLog('ERRO pareados: $error');
    }
  }

  Future<void> _scanDevices() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _found = const [];
    });
    _addLog('Scan iniciado: Bluetooth classico/SPP + BLE por 20s');
    try {
      final devices =
          await _obd.scanDevices(timeout: const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {
        _found = devices;
        _scanning = false;
      });
      _addLog('Scan finalizado: ${devices.length} dispositivos');
      for (final device in devices) {
        _addLog('Encontrado: ${_deviceLine(device)}');
      }
      await _refreshStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _addLog('ERRO scan: $error');
      await _refreshStatus();
    }
  }

  Future<void> _stopScan() async {
    _addLog('Parando busca Bluetooth...');
    try {
      await _obd.cancelScan();
      _addLog('Busca parada');
    } catch (error) {
      _addLog('ERRO parar busca: $error');
    } finally {
      if (mounted) setState(() => _scanning = false);
      await _refreshStatus();
    }
  }

  Future<void> _connectManual() async {
    await _connectByMac(_macController.text);
  }

  Future<void> _pairManual() async {
    final mac = _normalizeMac(_macController.text);
    if (!_isValidMac(mac)) {
      _addLog('ERRO MAC invalido para parear: ${_macController.text}');
      return;
    }

    final pin = _pinController.text.trim().isEmpty
        ? '1234'
        : _pinController.text.trim();
    setState(() => _pairing = true);
    _addLog('Pareamento solicitado: $mac usando PIN $pin');
    _addLog(
      'Se o Android abrir janela de PIN, confirme com $pin. Se nÃ£o abrir, o app tenta informar o PIN automaticamente.',
    );
    try {
      final device = await _obd.pairDeviceByAddress(mac, pin: pin);
      if (!mounted) return;
      setState(() => _pairing = false);
      _addLog('Pareado confirmado: ${_deviceLine(device)}');
      await _loadPaired();
      await _refreshStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _pairing = false);
      _addLog('ERRO parear $mac: $error');
      await _refreshStatus();
    }
  }

  Future<void> _connectByMac(String rawMac, {bool auto = false}) async {
    final mac = _normalizeMac(rawMac);
    if (!_isValidMac(mac)) {
      _addLog('ERRO MAC invalido: $rawMac');
      return;
    }

    setState(() => _connecting = true);
    _addLog('${auto ? "Auto reconexÃ£o" : "ConexÃ£o manual"} por MAC: $mac');
    _addLog(
        'Tentando parear se necessario e conectar SPP UUID 00001101-0000-1000-8000-00805F9B34FB');
    try {
      final name = await _obd.connectByAddress(mac);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_elm327_address', mac);
      if (!mounted) return;
      setState(() {
        _lastMac = mac;
        _macController.text = mac;
        _connecting = false;
      });
      _addLog('Conectado: $name ($mac)');
      await _refreshStatus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _connecting = false);
      _addLog('ERRO conectar $mac: $error');
      await _refreshStatus();
    }
  }

  Future<void> _disconnect() async {
    _addLog('Desconectando...');
    try {
      await _obd.disconnect();
      _addLog('Desconectado');
      await _refreshStatus();
    } catch (error) {
      _addLog('ERRO desconectar: $error');
    }
  }

  void _useDeviceMac(ObdBluetoothDevice device) {
    _macController.text = device.address;
    _addLog('MAC selecionado: ${device.address} (${device.name})');
  }

  void _addLog(String message) {
    final time = TimeOfDay.now();
    final stamp =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    setState(() {
      _log = [..._log.take(240), '$stamp  $message'];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logController.hasClients) return;
      _logController.animateTo(
        _logController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  String _normalizeMac(String value) => value.trim().toUpperCase();

  bool _isValidMac(String value) {
    return RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$').hasMatch(value);
  }

  String _yes(dynamic value) => value == true ? 'sim' : 'nÃ£o';

  String _deviceLine(ObdBluetoothDevice device) {
    return '${device.name} | ${device.address} | ${device.transport} | ${device.bondLabel} | RSSI: ${device.rssi?.toString() ?? "n/d"}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Bluetooth Lab ADAK'),
        actions: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              flex: 30,
              child: Column(
                children: [
                  Expanded(child: _buildStatusPanel()),
                  const SizedBox(height: 10),
                  Expanded(child: _buildManualPanel()),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 40,
              child: Column(
                children: [
                  Expanded(child: _buildDevicesPanel('Pareados', _paired)),
                  const SizedBox(height: 10),
                  Expanded(
                      child: _buildDevicesPanel('Encontrados no scan', _found)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(flex: 30, child: _buildLogPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    return _LabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Diagnostico'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _actionButton('Verificar permissões', Icons.fact_check,
                  _loadingStatus ? null : _refreshStatus),
              _actionButton('Pedir permissões', Icons.security,
                  _requestingPermissions ? null : _requestPermissions),
              _actionButton(
                  'Ligar Bluetooth', Icons.bluetooth, _requestEnableBluetooth),
              _actionButton('Buscar pareados', Icons.devices,
                  _loadingPaired ? null : _loadPaired),
              _actionButton('Buscar novos dispositivos',
                  Icons.bluetooth_searching, _scanning ? null : _scanDevices),
              _actionButton('Parar busca', Icons.stop_circle,
                  _scanning ? _stopScan : null),
              _actionButton('Desconectar', Icons.link_off, _disconnect),
            ],
          ),
          const SizedBox(height: 12),
          _statusLine('Bluetooth disponÃ­vel', _yes(_status['available'])),
          _statusLine('Bluetooth ligado', _yes(_status['enabled'])),
          _statusLine(
              'Permissoes concedidas', _yes(_status['permissionsGranted'])),
          _statusLine('PermissÃ£o CONNECT', _yes(_status['connectPermission'])),
          _statusLine('PermissÃ£o SCAN', _yes(_status['scanPermission'])),
          _statusLine('PermissÃ£o de localizaÃ§Ã£o',
              _yes(_status['locationPermission'])),
          _statusLine('LocalizaÃ§Ã£o ligada', _yes(_status['locationEnabled'])),
          _statusLine('Android SDK', '${_status['sdk'] ?? '--'}'),
          _statusLine('Pareados Android', '${_status['bondedCount'] ?? '--'}'),
          _statusLine('Conectado SPP', _yes(_status['connected'])),
        ],
      ),
    );
  }

  Widget _buildManualPanel() {
    return _LabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('ConexÃ£o por MAC'),
          TextField(
            controller: _macController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'MAC do ELM327',
              hintText: '00:1D:A5:XX:XX:XX',
              prefixIcon: Icon(Icons.numbers),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'PIN de pareamento',
              hintText: '1234',
              prefixIcon: Icon(Icons.pin),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pairing || _connecting ? null : _pairManual,
            icon: const Icon(Icons.bluetooth_connected),
            label: const Text('PAREAR COM PIN'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _connecting || _pairing ? null : _connectManual,
            icon: const Icon(Icons.link),
            label: const Text('CONECTAR PELO MAC'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _lastMac == null || _connecting
                ? null
                : () => _connectByMac(_lastMac!),
            icon: const Icon(Icons.replay),
            label: Text('RECONECTAR ULTIMO ${_lastMac ?? ""}'),
          ),
          SwitchListTile(
            value: _autoReconnect,
            onChanged: _saveAutoReconnect,
            title: const Text('Auto reconectar ultimo ELM'),
            subtitle: Text(_lastMac ?? 'Nenhum MAC salvo'),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesPanel(String title, List<ObdBluetoothDevice> devices) {
    return _LabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('$title (${devices.length})'),
          Expanded(
            child: devices.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhum dispositivo',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final device = devices[index];
                      return ListTile(
                        dense: true,
                        onTap: () => _useDeviceMac(device),
                        title: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          '${device.address}\nTipo: ${device.transport} | ${device.bondLabel} | RSSI: ${device.rssi?.toString() ?? "n/d"}',
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: Icon(
                          device.elmCandidate
                              ? Icons.car_repair
                              : Icons.bluetooth,
                          color: device.elmCandidate ? _green : _blue,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogPanel() {
    return _LabPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _sectionTitle('Log completo')),
              IconButton(
                tooltip: 'Copiar log',
                onPressed: _log.isEmpty
                    ? null
                    : () =>
                        Clipboard.setData(ClipboardData(text: _log.join('\n'))),
                icon: const Icon(Icons.copy, color: _blue),
              ),
              IconButton(
                tooltip: 'Limpar log',
                onPressed: () => setState(() => _log = const []),
                icon: const Icon(Icons.delete_sweep, color: _blue),
              ),
            ],
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line),
              ),
              child: ListView.builder(
                controller: _logController,
                itemCount: _log.length,
                itemBuilder: (context, index) {
                  final line = _log[index];
                  final isError =
                      line.contains('ERRO') || line.contains('negad');
                  return Text(
                    line,
                    style: TextStyle(
                      color: isError ? _amber : Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.25,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: 190,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _statusLine(String label, String value) {
    final ok = value == 'sim';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.info,
            color: ok ? _green : _blue,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _blue,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LabPanel extends StatelessWidget {
  const _LabPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _BluetoothLabScreenState._panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _BluetoothLabScreenState._line),
      ),
      child: child,
    );
  }
}
