import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_provider.dart';
import '../services/obd_service.dart';
import '../services/obd_background_service.dart';

const Color _bg = Color(0xFF020914);
const Color _bar = Color(0xFF050D19);
const Color _card = Color(0xFF061426);
const Color _blue = Color(0xFF1677FF);
const Color _green = Color(0xFF69F01B);
const Color _line = Color(0xFF0B3C73);
const Color _amber = Color(0xFFFFC857);

class ComputerScreen extends StatefulWidget {
  const ComputerScreen({super.key});

  @override
  State<ComputerScreen> createState() => _ComputerScreenState();
}

class _ComputerScreenState extends State<ComputerScreen>
    with WidgetsBindingObserver {
  final ObdService _obd = ObdService();
  final ObdBackgroundService _background = ObdBackgroundService.instance;
  final ScrollController _logController = ScrollController();
  final TextEditingController _manualCommandController =
      TextEditingController();

  List<ObdBluetoothDevice> _devices = const [];
  ObdBluetoothDevice? _selectedDevice;
  Timer? _pollTimer;
  Timer? _keepAliveTimer;

  bool _loadingDevices = false;
  bool _scanningDevices = false;
  bool _connected = false;
  bool _communicating = false;
  bool _basicPidsUnlocked = false;
  bool _stopping = false;
  bool _gaugesOnly = true;
  int _intervalMs = 500;
  bool _autoStartupDone = false;
  bool _userStoppedObd = false;

  String _connectionStatus = 'Bluetooth aguardando ELM327';
  String _protocol = 'Não detectado';
  String _lastResponse = '--';
  String _activeCommand = '--';
  String _rpm = '--';
  String _speed = '--';
  String _temperature = '--';
  String _load = '--';
  String _throttle = '--';
  String _moduleVoltage = '--';
  String _fuelLevel = '--';

  final List<String> _log = [];
  final Set<String> _enabledPidCommands = {};
  final Set<String> _runningMomentaryCommands = {};
  final Map<String, bool> _detectedPidGroups = {};
  final Set<String> _supportedPids = {};
  String? _lastDeviceAddress;

  static const List<_ObdCommandSpec> _commands = [
    _ObdCommandSpec('ATZ', 'Resetar adaptador', momentary: true),
    _ObdCommandSpec('ATD', 'Restaurar padrões', momentary: true),
    _ObdCommandSpec('ATI', 'Mostrar versão', momentary: true),
    _ObdCommandSpec('ATRV', 'Tensão da bateria', momentary: true),
    _ObdCommandSpec('ATE0', 'Desligar eco', momentary: true),
    _ObdCommandSpec('ATL0', 'Desligar quebras de linha', momentary: true),
    _ObdCommandSpec('ATS0', 'Desligar espacos', momentary: true),
    _ObdCommandSpec('ATH0', 'Esconder headers', momentary: true),
    _ObdCommandSpec('ATSP0', 'Protocolo automatico', momentary: true),
    _ObdCommandSpec('ATSP6', 'Forcar CAN 11bit 500kbps', momentary: true),
    _ObdCommandSpec('ATDP', 'Mostrar protocolo atual', momentary: true),
    _ObdCommandSpec('ATDPN', 'Mostrar numero do protocolo', momentary: true),
    _ObdCommandSpec('0100', 'Verificar PIDs suportados', momentary: true),
    _ObdCommandSpec('010C', 'RPM'),
    _ObdCommandSpec('010D', 'Velocidade'),
    _ObdCommandSpec('0105', 'Temperatura do motor'),
    _ObdCommandSpec('0104', 'Carga do motor'),
    _ObdCommandSpec('0111', 'Posição do acelerador'),
    _ObdCommandSpec('0142', 'Tensão do módulo'),
    _ObdCommandSpec('012F', 'Nivel de combustivel'),
  ];

  static const List<String> _safeOnixSequence = [
    'ATSP6',
    '0100',
  ];

  static const List<String> _automaticPidSequence = [
    '010C',
    '010D',
    '0105',
    '0104',
    '0111',
    '0142',
    '012F',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBluetooth();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _keepAliveTimer?.cancel();
    _background.removeListener(_syncBackgroundObd);
    _logController.dispose();
    _manualCommandController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _connected) {
      _appendLog('SYS', 'App retomado: mantendo sessão OBD ativa');
    }
  }

  void _syncBackgroundObd() {
    if (!mounted) return;
    final background = _background;
    if (!background.connected && !background.communicating) return;
    setState(() {
      _connected = background.connected;
      _communicating = background.communicating;
      _connectionStatus = background.status;
      _lastResponse = background.lastResponse;
      _rpm = background.rpm;
      _speed = background.speed;
      _temperature = background.temperature;
      _load = background.load;
      _throttle = background.throttle;
      _moduleVoltage = background.moduleVoltage;
      _fuelLevel = background.fuelLevel;
      if (background.connected) {
        _basicPidsUnlocked = true;
      }
    });
  }

  Future<void> _loadDevices() async {
    setState(() {
      _loadingDevices = true;
      _connectionStatus = 'Solicitando permissão Bluetooth';
    });

    try {
      final granted = await _obd.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _loadingDevices = false;
          _connectionStatus = 'Permissão Bluetooth negada';
        });
        _appendLog('ERR', 'Permissão Bluetooth/Localização não concedida');
        return;
      }
      final devices = await _obd.listPairedDevices();
      final selected = _selectPreferredDevice(devices);
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selectedDevice = selected;
        _loadingDevices = false;
        _connectionStatus = devices.isEmpty
            ? 'Pareie o ELM327 no Android primeiro'
            : 'Selecione o ELM327 pareado';
      });
      _appendLog('SYS', 'Dispositivos pareados: ${devices.length}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _connectionStatus = 'Falha ao listar Bluetooth';
      });
      _appendLog('ERR', error.toString());
    }
  }

  Future<void> _initBluetooth() async {
    final prefs = await SharedPreferences.getInstance();
    _lastDeviceAddress = prefs.getString('last_elm327_address');
    await _loadDevices();
    if (await _restoreExistingNativeConnection()) return;
    await _autoConnectAndStart();
  }

  Future<bool> _restoreExistingNativeConnection() async {
    try {
      final alreadyConnected = await _obd.isConnected();
      if (!alreadyConnected || !mounted) return false;
      setState(() {
        _connected = true;
        _communicating = false;
        _userStoppedObd = false;
        _basicPidsUnlocked = true;
        _connectionStatus = 'ELM327 ja conectado - leitura retomada';
        _enabledPidCommands
          ..clear()
          ..addAll(_automaticPidSequence);
      });
      _startKeepAlive();
      _startPollingIfNeeded();
      _appendLog('SYS', 'Sessão Bluetooth nativa mantida; sem reconectar');
      return true;
    } catch (error) {
      _appendLog('ERR', 'Falha ao checar conexão nativa: $error');
      return false;
    }
  }

  ObdBluetoothDevice? _selectPreferredDevice(List<ObdBluetoothDevice> devices) {
    if (devices.isEmpty) return null;
    final last = _lastDeviceAddress;
    if (last != null) {
      for (final device in devices) {
        if (device.address == last) return device;
      }
    }
    return devices.first;
  }

  Future<void> _scanDevices() async {
    if (_connected || _scanningDevices) return;
    setState(() {
      _scanningDevices = true;
      _connectionStatus = 'Busca oficial Android em andamento...';
    });

    try {
      final granted = await _obd.requestPermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() {
          _scanningDevices = false;
          _connectionStatus = 'Permissão Bluetooth negada';
        });
        _appendLog('ERR', 'Permissão Bluetooth/Localização não concedida');
        return;
      }
      final devices =
          await _obd.scanDevices(timeout: const Duration(seconds: 20));
      final selected = _selectPreferredDevice(devices);
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _selectedDevice = selected ??
            (_lastDeviceAddress == null
                ? null
                : ObdBluetoothDevice(
                    name: 'ELM327 salvo',
                    address: _lastDeviceAddress!,
                    elmCandidate: true,
                  ));
        _scanningDevices = false;
        _connectionStatus = devices.isEmpty
            ? 'Nenhum aparelho encontrado'
            : 'Selecione um aparelho encontrado';
      });
      _appendLog(
        'SYS',
        'Busca Bluetooth encontrou ${devices.length} aparelhos. Se o ELM não aparecer, deixe ele ligado e perto da multimídia.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _scanningDevices = false;
        _connectionStatus = 'Falha na busca Bluetooth';
      });
      _appendLog('ERR', error.toString());
    }
  }

  Future<void> _pairSelectedDevice() async {
    final device = _selectedDevice;
    if (device == null || _connected || _communicating) return;

    setState(() {
      _communicating = true;
      _connectionStatus = 'Pareando ${device.name} pelo Android';
    });
    _appendLog(
      'SYS',
      'Pareamento oficial iniciado. Se pedir PIN/senha, tente 1234 ou 0000.',
    );

    try {
      final paired = await _obd.pairDevice(device);
      if (!mounted) return;
      setState(() {
        _devices = _mergeDevice(_devices, paired);
        _selectedDevice = paired;
        _communicating = false;
        _connectionStatus = 'Pareado: ${paired.name}';
      });
      _appendLog('SYS', 'Pareamento confirmado: ${paired.name}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _communicating = false;
        _connectionStatus = 'Falha ao parear';
      });
      _appendLog('ERR', 'Pareamento falhou: $error');
    }
  }

  List<ObdBluetoothDevice> _mergeDevice(
    List<ObdBluetoothDevice> devices,
    ObdBluetoothDevice updated,
  ) {
    final next = <ObdBluetoothDevice>[];
    var found = false;
    for (final device in devices) {
      if (device.address == updated.address) {
        next.add(updated);
        found = true;
      } else {
        next.add(device);
      }
    }
    if (!found) next.add(updated);
    return next;
  }

  Future<void> _connect() async {
    await _connectSelectedDevice(runStartup: true);
  }

  Future<void> _connectSelectedDevice({required bool runStartup}) async {
    final device = _selectedDevice;
    if (device == null || _communicating) return;
    _userStoppedObd = false;

    setState(() {
      _communicating = true;
      _connectionStatus = device.paired
          ? 'Conectando em ${device.name}'
          : 'Pareando ${device.name}: informe PIN se solicitado';
    });
    if (!device.paired) {
      _appendLog(
        'SYS',
        'Se o Android pedir senha/PIN, tente 1234 ou 0000 e confirme.',
      );
    }

    try {
      final name = await _obd.connect(device);
      if (!mounted) return;
      setState(() {
        _connected = true;
        _communicating = false;
        _connectionStatus = 'Conectado: $name';
      });
      _startKeepAlive();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_elm327_address', device.address);
      _lastDeviceAddress = device.address;
      _appendLog('SYS', 'Conectado em ${device.name} (${device.address})');
      if (runStartup) {
        await _runAutomaticObdStartup();
      }
      await _background.ensureStarted(force: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connected = false;
        _communicating = false;
        _connectionStatus = 'Falha ao conectar';
      });
      _stopKeepAlive();
      _appendLog('ERR', error.toString());
    }
  }

  Future<void> _autoConnectAndStart({bool force = false}) async {
    if (_userStoppedObd) return;
    if ((!force && _autoStartupDone) || _connected || _communicating) return;
    final address = _lastDeviceAddress;
    if (address == null || address.trim().isEmpty) return;

    _autoStartupDone = true;
    final device = _selectedDevice?.address == address
        ? _selectedDevice!
        : ObdBluetoothDevice(
            name: 'ELM327 salvo',
            address: address,
            elmCandidate: true,
          );

    if (!mounted) return;
    setState(() {
      _selectedDevice = device;
      _connectionStatus = 'Conectando ELM327 automáticamente';
    });
    _appendLog('SYS', 'Conexão unica no ultimo ELM salvo: $address');

    await _connectSelectedDevice(runStartup: true);
    if (!_connected || !mounted) return;
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 18), (_) async {
      if (!_connected || _communicating || _stopping) return;
      if (_enabledPidCommands.isNotEmpty) return;

      final result = await _obd.sendCommand(
        'AT',
        timeout: const Duration(seconds: 3),
      );
      if (!mounted) return;
      if (result.success && result.response.trim().isNotEmpty) {
        _appendLog('RX', 'keep-alive OK');
        return;
      }

      setState(() {
        _connected = false;
        _connectionStatus = 'ELM327 caiu no keep-alive';
      });
      _stopKeepAlive();
      _appendLog('ERR', result.error ?? 'Falha no keep-alive');
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<void> _stopCommunication() async {
    if (_stopping) return;
    setState(() {
      _userStoppedObd = true;
      _stopping = true;
      _communicating = false;
      _connected = false;
      _enabledPidCommands.clear();
      _runningMomentaryCommands.clear();
      _activeCommand = '--';
      _connectionStatus = 'Comunicação parada';
    });
    _pollTimer?.cancel();
    _pollTimer = null;
    _stopKeepAlive();
    await _background.stop();
    _appendLog('SYS', 'PARAR: timer, fila e leitura contínua cancelados');
    if (mounted) {
      setState(() => _stopping = false);
    }
  }

  Future<void> _forgetSelectedDevice() async {
    final device = _selectedDevice;
    if (device == null || _communicating) return;
    await _stopCommunication();
    try {
      await _obd.forgetDevice(device);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_elm327_address');
      _lastDeviceAddress = null;
      _appendLog('SYS', 'Dispositivo esquecido: ${device.name}');
      await _loadDevices();
    } catch (error) {
      _appendLog('ERR', 'Falha ao esquecer ${device.name}: $error');
    }
  }

  Future<void> _runSafeOnixSequence() async {
    if (!_connected || _communicating) return;

    setState(() {
      _communicating = true;
      _basicPidsUnlocked = false;
      _protocol = 'Detectando...';
    });
    _appendLog('SYS', 'Sequência Segura Onix LS 1.0 2015 iniciada');

    var pidCheckOk = false;
    for (final command in _safeOnixSequence) {
      if (!_connected) break;
      final result = await _sendOnce(command);
      if (result == null || result.shouldStopLoop) {
        _appendLog('SYS', 'Sequência interrompida em $command');
        break;
      }
      if (command == '0100' && _hasPositivePidResponse(result.response)) {
        pidCheckOk = true;
      }
      await Future<void>.delayed(Duration(milliseconds: _intervalMs));
    }

    if (!mounted) return;
    setState(() {
      _communicating = false;
      _basicPidsUnlocked = pidCheckOk;
      _connectionStatus =
          pidCheckOk ? 'Sequência segura concluida' : '0100 não confirmou PIDs';
    });

    if (pidCheckOk) {
      _appendLog('SYS', 'Liberado leitura dos PIDs suportados');
    }
  }

  Future<void> _runAutomaticObdStartup() async {
    if (!_connected || _communicating || _stopping) return;

    setState(() {
      _communicating = true;
      _basicPidsUnlocked = false;
      _enabledPidCommands.clear();
      _connectionStatus = 'Inicializando protocolo CAN 11bit 500kbps';
      _protocol = 'CAN 11bit 500kbps';
    });
    _pollTimer?.cancel();
    _pollTimer = null;
    _appendLog('SYS', 'Inicialização OBD automática iniciada');

    var pidCheckOk = false;
    for (final command in _safeOnixSequence) {
      if (!_connected || _stopping) break;
      final result = await _sendOnce(command);
      if (result == null) break;
      if (command == '0100') {
        pidCheckOk = result.success && _hasPositivePidResponse(result.response);
        if (!pidCheckOk) {
          _appendLog('SYS',
              '0100 não confirmou PIDs; leitura automática não sera ativada');
        }
      } else if (result.shouldStopLoop) {
        _appendLog('SYS', 'Inicialização parou em $command');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return;
    if (!pidCheckOk || !_connected || _stopping) {
      setState(() {
        _communicating = false;
        _basicPidsUnlocked = pidCheckOk;
        _connectionStatus = pidCheckOk
            ? 'Inicialização interrompida'
            : '0100 não confirmou PIDs';
      });
      return;
    }

    setState(() {
      _basicPidsUnlocked = true;
      _connectionStatus = 'Ativando PIDs um por um';
    });

    final enabled = <String>[];
    for (final command in _automaticPidSequence) {
      if (!_connected || _stopping) break;
      final result = await _sendOnce(command);
      if (result != null && result.success && !result.shouldStopLoop) {
        enabled.add(command);
      } else {
        _appendLog('SYS', '$command não entrou na leitura contínua');
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!mounted) return;
    setState(() {
      _enabledPidCommands
        ..clear()
        ..addAll(enabled);
      _communicating = false;
      _connectionStatus = enabled.isEmpty
          ? 'Sem PIDs para leitura contínua'
          : 'Leitura OBDII ativa e persistente';
    });
    _startPollingIfNeeded();
    _appendLog('SYS', 'PIDs ativos: ${enabled.join(', ')}');
  }

  Future<ObdCommandResult?> _sendOnce(String command) async {
    if (!_connected) {
      _appendLog('ERR', 'ELM327 não conectado');
      return null;
    }

    setState(() => _activeCommand = command);
    _appendLog('TX', command);
    final result = await _obd.sendCommand(command);
    if (!mounted) return result;

    final response = result.success ? result.response : (result.error ?? '');
    setState(() {
      _lastResponse = response.isEmpty ? 'Sem resposta' : response;
      _applyResponse(command, response);
    });
    _appendLog(result.success ? 'RX' : 'ERR', response);
    if (!result.success &&
        response.toUpperCase().contains('ELM327 NAO CONECTADO')) {
      setState(() {
        _connected = false;
        _communicating = false;
        _connectionStatus = 'ELM327 desconectado';
      });
    }

    if (result.shouldStopLoop) {
      setState(() => _enabledPidCommands.remove(command));
      _appendLog('SYS', '$command desativado para evitar loop em erro');
    }

    return result;
  }

  Future<void> _sendManualCommand() async {
    final command = _manualCommandController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (command.isEmpty) return;
    if (!_connected || _communicating) {
      _appendLog('ERR', 'Conecte ao ELM327 antes do comando manual');
      return;
    }

    setState(() => _communicating = true);
    await _sendOnce(command);
    if (mounted) {
      setState(() => _communicating = false);
    }
  }

  Future<void> _detectAllPidGroups() async {
    if (!_connected || _communicating) {
      _appendLog('ERR', 'Conecte ao ELM327 antes de detectar PIDs');
      return;
    }

    const groups = ['0100', '0120', '0140', '0160', '0180', '01A0'];
    setState(() {
      _communicating = true;
      _detectedPidGroups.clear();
      _supportedPids.clear();
    });
    _appendLog('SYS', 'Detectando grupos PID: ${groups.join(', ')}');

    for (final command in groups) {
      final result = await _sendOnce(command);
      final exists = result != null &&
          result.success &&
          _hasPositivePidResponse(result.response, command: command);
      if (!mounted) return;
      setState(() {
        _detectedPidGroups[command] = exists;
        if (exists) {
          _supportedPids.addAll(
            _decodeSupportedPids(command, result.response),
          );
        }
      });
      if (result == null || result.shouldStopLoop) {
        _appendLog(
          'SYS',
          '$command não disponível; seguindo para o próximo grupo',
        );
      }
      await Future<void>.delayed(Duration(milliseconds: _intervalMs));
    }

    if (mounted) {
      setState(() => _communicating = false);
    }
  }

  void _startPollingIfNeeded() {
    _pollTimer?.cancel();
    if (_enabledPidCommands.isEmpty || !_connected) return;

    var index = 0;
    _pollTimer = Timer.periodic(Duration(milliseconds: _intervalMs), (_) async {
      if (_communicating || _enabledPidCommands.isEmpty || !_connected) return;
      final commands = _enabledPidCommands.toList(growable: false);
      final command = commands[index % commands.length];
      index++;
      setState(() => _communicating = true);
      await _sendOnce(command);
      if (mounted) {
        setState(() => _communicating = false);
      }
    });
  }

  Future<void> _toggleCommand(_ObdCommandSpec spec, bool value) async {
    if (!_connected) {
      _appendLog('ERR', 'Conecte ao ELM327 antes de enviar ${spec.command}');
      return;
    }

    if (spec.isProtected && !_basicPidsUnlocked) {
      _appendLog('SYS', '${spec.command} bloqueado ate 0100 responder');
      return;
    }

    if (spec.momentary) {
      if (!value || _communicating) return;
      setState(() {
        _runningMomentaryCommands.add(spec.command);
        _communicating = true;
      });
      final result = await _sendOnce(spec.command);
      if (spec.command == '0100' &&
          result != null &&
          _hasPositivePidResponse(result.response)) {
        setState(() => _basicPidsUnlocked = true);
      }
      if (mounted) {
        setState(() {
          _runningMomentaryCommands.remove(spec.command);
          _communicating = false;
        });
      }
      return;
    }

    setState(() {
      if (value) {
        _enabledPidCommands.add(spec.command);
      } else {
        _enabledPidCommands.remove(spec.command);
      }
    });
    _startPollingIfNeeded();
  }

  void _applyResponse(String command, String response) {
    final clean = response.toUpperCase();
    if (command == 'ATDP') {
      _protocol = response.replaceAll('\n', ' ');
      return;
    }
    if (command == 'ATDPN') {
      _protocol = 'Numero ${response.replaceAll('\n', ' ')}';
      return;
    }

    final bytes = _hexBytes(clean);
    double? value;
    switch (command) {
      case '010C':
        value = _pidValue(bytes, 0x0C, 2);
        if (value != null) {
          final a = bytes[2];
          final b = bytes[3];
          _rpm = (((a * 256) + b) / 4).toStringAsFixed(0);
        }
        break;
      case '010D':
        value = _pidValue(bytes, 0x0D, 1);
        if (value != null) _speed = '${bytes[2]}';
        break;
      case '0105':
        value = _pidValue(bytes, 0x05, 1);
        if (value != null) _temperature = '${bytes[2] - 40}';
        break;
      case '0104':
        value = _pidValue(bytes, 0x04, 1);
        if (value != null) _load = _percent(bytes[2]);
        break;
      case '0111':
        value = _pidValue(bytes, 0x11, 1);
        if (value != null) _throttle = _percent(bytes[2]);
        break;
      case '0142':
        value = _pidValue(bytes, 0x42, 2);
        if (value != null) {
          _moduleVoltage =
              (((bytes[2] * 256) + bytes[3]) / 1000).toStringAsFixed(2);
        }
        break;
      case '012F':
        value = _pidValue(bytes, 0x2F, 1);
        if (value != null) _fuelLevel = _percent(bytes[2]);
        break;
    }
  }

  List<int> _hexBytes(String response) {
    final matches = RegExp(r'\b[0-9A-F]{2}\b').allMatches(response);
    final bytes =
        matches.map((match) => int.parse(match.group(0)!, radix: 16)).toList();
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 0x41) {
        return bytes.sublist(i);
      }
    }
    return bytes;
  }

  double? _pidValue(List<int> bytes, int pid, int dataLength) {
    if (bytes.length < 2 + dataLength) return null;
    if (bytes[0] != 0x41 || bytes[1] != pid) return null;
    return bytes[2].toDouble();
  }

  String _percent(int value) {
    return (value * 100 / 255).toStringAsFixed(1);
  }

  bool _hasPositivePidResponse(String response, {String command = '0100'}) {
    final upper = response.toUpperCase();
    if (upper.contains('NO DATA') ||
        upper.contains('ERROR') ||
        upper.contains('STOPPED') ||
        upper.contains('?')) {
      return false;
    }
    final pid = command.length >= 4 ? command.substring(2, 4) : '00';
    return upper.contains('41 $pid') ||
        upper.replaceAll(' ', '').contains('41$pid');
  }

  List<String> _decodeSupportedPids(String command, String response) {
    final bytes = _hexBytes(response.toUpperCase());
    if (bytes.length < 6 || bytes[0] != 0x41) return const [];
    final basePid = int.tryParse(command.substring(2, 4), radix: 16) ?? 0;
    if (bytes[1] != basePid) return const [];

    final bitBytes = bytes.sublist(2, 6);
    final result = <String>[];
    for (var byteIndex = 0; byteIndex < bitBytes.length; byteIndex++) {
      final value = bitBytes[byteIndex];
      for (var bit = 0; bit < 8; bit++) {
        if ((value & (0x80 >> bit)) == 0) continue;
        final pid = basePid + (byteIndex * 8) + bit + 1;
        result.add('01${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return result;
  }

  void _appendLog(String prefix, String message) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    final clean = message.trim().isEmpty ? '--' : message.trim();
    setState(() {
      _log.add('[$hh:$mm:$ss] $prefix  $clean');
      if (_log.length > 240) _log.removeRange(0, _log.length - 240);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logController.hasClients) return;
      _logController.animateTo(
        _logController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    _appendLog('SYS', 'Log copiado');
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ComputerColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (_gaugesOnly) {
                    return _buildGaugesOnly(colors, constraints);
                  }

                  final compact =
                      constraints.maxWidth < 980 || constraints.maxHeight < 460;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 8 : 18,
                      compact ? 8 : 14,
                      compact ? 8 : 18,
                      compact ? 8 : 14,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: compact ? 240 : 285,
                          child: _buildControlColumn(colors, compact),
                        ),
                        SizedBox(width: compact ? 8 : 14),
                        Expanded(
                          flex: 15,
                          child: _buildCommandPanel(colors),
                        ),
                        SizedBox(width: compact ? 8 : 14),
                        Expanded(
                          flex: 8,
                          child: _buildLogPanel(colors, compact),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildHeader(_ComputerColors colors) {
    final provider = context.watch<AppProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 980;
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      height: compact ? 62 : 74,
      padding: EdgeInsets.fromLTRB(
          compact ? 10 : 18, compact ? 7 : 10, compact ? 10 : 18, 0),
      color: colors.background,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
        decoration: ShapeDecoration(
          color: colors.panel.withValues(alpha: 0.94),
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
            Icon(Icons.circle, color: _connected ? _green : _amber, size: 12),
            SizedBox(width: compact ? 7 : 9),
            Text(
              _connected ? 'CONECTADO' : 'DESCONECTADO',
              style: TextStyle(
                color: _connected ? _green : _amber,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 13 : 14,
              ),
            ),
            SizedBox(width: compact ? 16 : 28),
            Icon(Icons.bluetooth,
                color: colors.secondaryText, size: compact ? 20 : 22),
            SizedBox(width: compact ? 6 : 8),
            Text(
              'ELM327',
              style: TextStyle(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 13 : 14,
              ),
            ),
            const Spacer(),
            Container(
              width: compact ? 46 : 54,
              height: compact ? 24 : 30,
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
            SizedBox(width: compact ? 10 : 14),
            Flexible(
              flex: 2,
              child: Text(
                provider.vehicleName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 15 : 16,
                ),
              ),
            ),
            const Spacer(),
            Icon(Icons.schedule,
                color: colors.secondaryText, size: compact ? 18 : 19),
            SizedBox(width: compact ? 6 : 8),
            Text(
              time,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(width: compact ? 8 : 16),
            IconButton(
              tooltip: _gaugesOnly ? 'Comandos' : 'Mostradores',
              onPressed: () => setState(() => _gaugesOnly = !_gaugesOnly),
              icon: Icon(_gaugesOnly ? Icons.tune : Icons.speed,
                  color: colors.secondaryText),
            ),
            if (!compact)
              ElevatedButton.icon(
                onPressed: _connected || _communicating || _stopping
                    ? _stopCommunication
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop_circle),
                label: const Text('PARAR'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlColumn(_ComputerColors colors, bool compact) {
    return _LabPanel(
      padding: EdgeInsets.all(compact ? 10 : 14),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(
                label: 'Conexão Bluetooth', color: colors.secondaryText),
            const SizedBox(height: 8),
            DropdownButtonFormField<ObdBluetoothDevice>(
              initialValue: _selectedDevice,
              decoration: const InputDecoration(
                labelText: 'ELM327 / Bluetooth',
                prefixIcon: Icon(Icons.bluetooth),
              ),
              items: _devices
                  .map(
                    (device) => DropdownMenuItem(
                      value: device,
                      child: Text(
                        '${device.elmCandidate ? "ELM/OBD - " : ""}${device.name} (${device.bondLabel}, ${device.transport})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _connected || _communicating
                  ? null
                  : (device) => setState(() => _selectedDevice = device),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _loadingDevices || _connected ? null : _loadDevices,
                    icon: _loadingDevices
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('PAREADOS'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _scanningDevices || _connected ? null : _scanDevices,
                    icon: _scanningDevices
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label: const Text('BUSCAR NOVOS'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectedDevice == null ||
                            _selectedDevice!.paired ||
                            _connected ||
                            _communicating
                        ? null
                        : _pairSelectedDevice,
                    icon: const Icon(Icons.bluetooth_connected),
                    label: const Text('PAREAR'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _selectedDevice == null || _connected || _communicating
                            ? null
                            : _connect,
                    icon: const Icon(Icons.link),
                    label: const Text('CONECTAR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _selectedDevice == null || _communicating
                  ? null
                  : _forgetSelectedDevice,
              icon: const Icon(Icons.link_off),
              label: const Text('ESQUECER DISPOSITIVO'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/bluetoothLab'),
              icon: const Icon(Icons.science),
              label: const Text('BLUETOOTH LAB ADAK'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: compact ? 46 : 58,
              child: ElevatedButton.icon(
                onPressed: _connected || _communicating || _stopping
                    ? _stopCommunication
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.stop_circle),
                label: const Text('PARAR COMUNICACAO'),
              ),
            ),
            const SizedBox(height: 12),
            _StatusLine(
              icon: Icons.sensors,
              label: 'Status',
              value: _connectionStatus,
              colors: colors,
            ),
            _StatusLine(
              icon: Icons.settings_input_component,
              label: 'Protocolo',
              value: _protocol,
              colors: colors,
            ),
            _StatusLine(
              icon: Icons.keyboard_return,
              label: 'Ultima resposta',
              value: _lastResponse,
              colors: colors,
            ),
            _StatusLine(
              icon: Icons.outbox,
              label: 'Comando ativo',
              value: _activeCommand,
              colors: colors,
            ),
            const SizedBox(height: 8),
            _SectionLabel(
                label: 'Intervalo seguro', color: colors.secondaryText),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1000, label: Text('1000ms')),
                ButtonSegment(value: 500, label: Text('500ms')),
                ButtonSegment(value: 250, label: Text('250ms')),
              ],
              selected: {_intervalMs},
              onSelectionChanged: (value) {
                setState(() => _intervalMs = value.first);
                _startPollingIfNeeded();
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed:
                  _connected && !_communicating ? _runSafeOnixSequence : null,
              icon: const Icon(Icons.verified_user),
              label: const Text('SEQUENCIA SEGURA ONIX'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _manualCommandController,
              textCapitalization: TextCapitalization.characters,
              style: TextStyle(color: colors.primaryText),
              decoration: const InputDecoration(
                labelText: 'Comando Manual',
                hintText: '0120',
                prefixIcon: Icon(Icons.terminal),
              ),
              onSubmitted: (_) => _sendManualCommand(),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed:
                  _connected && !_communicating ? _sendManualCommand : null,
              icon: const Icon(Icons.send),
              label: const Text('ENVIAR'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed:
                  _connected && !_communicating ? _detectAllPidGroups : null,
              icon: const Icon(Icons.manage_search),
              label: const Text('DETECTAR TODOS OS PIDS'),
            ),
            if (_detectedPidGroups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _detectedPidGroups.entries.map((entry) {
                  return Chip(
                    label: Text('${entry.key}: ${entry.value ? "OK" : "--"}'),
                    avatar: Icon(
                      entry.value ? Icons.check_circle : Icons.cancel,
                      color: entry.value ? _green : const Color(0xFFFF9A2E),
                      size: 18,
                    ),
                  );
                }).toList(),
              ),
              if (_supportedPids.isNotEmpty) ...[
                const SizedBox(height: 8),
                _SectionLabel(
                  label: 'PIDs suportados',
                  color: colors.secondaryText,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: (_supportedPids.toList()..sort()).map((pid) {
                    return Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(pid),
                    );
                  }).toList(),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommandPanel(_ComputerColors colors) {
    return _LabPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionLabel(
            label: 'Comandos / Interruptores',
            color: colors.secondaryText,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: _commands.length,
              itemBuilder: (context, index) {
                final spec = _commands[index];
                final enabled = spec.momentary
                    ? _runningMomentaryCommands.contains(spec.command)
                    : _enabledPidCommands.contains(spec.command);
                final locked = spec.isProtected && !_basicPidsUnlocked;
                return SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: locked || _stopping
                      ? null
                      : (value) => _toggleCommand(spec, value),
                  secondary: Icon(
                    spec.momentary ? Icons.terminal : Icons.monitor_heart,
                    color: locked ? colors.secondaryText : _blue,
                  ),
                  title: Text(
                    spec.command,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    locked ? '${spec.label} - execute 0100' : spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.secondaryText),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGaugesOnly(_ComputerColors colors, BoxConstraints constraints) {
    final compact = constraints.maxWidth < 1100 || constraints.maxHeight < 560;
    final temperatureAccent = _temperatureAccentColor();
    final fuelAccent = _fuelAccentColor();
    final trip = context.watch<AppProvider>().activeTrip;
    final fuelLiters = trip == null
        ? '-- litros'
        : '${trip.remainingFuel.toStringAsFixed(0)} litros';

    return Container(
      color: colors.background,
      padding: EdgeInsets.fromLTRB(compact ? 10 : 18, compact ? 8 : 16,
          compact ? 10 : 18, compact ? 6 : 10),
      child: LayoutBuilder(
        builder: (context, inner) {
          return Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                bottom: 0,
                child: _ProfessionalGaugePanel(
                  speed: _speed,
                  rpm: _rpm,
                  odometer: _odometerLabel(),
                  temperature: _temperature,
                  load: _load,
                  fuel: _fuelLevel,
                  fuelLiters: fuelLiters,
                  throttle: _throttle,
                  voltage: _moduleVoltage,
                  temperatureAccent: temperatureAccent,
                  fuelAccent: fuelAccent,
                  colors: colors,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _gaugePercent(String value, double min, double max) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || max <= min) return 0;
    return ((parsed - min) / (max - min)).clamp(0.0, 1.0);
  }

  double _numericValue(String value) {
    return double.tryParse(value.replaceAll(',', '.')) ?? double.nan;
  }

  Color _temperatureAccentColor() {
    final temp = _numericValue(_temperature);
    if (temp.isNaN) return _blue;
    if (temp >= 112) return const Color(0xFFFF9A2E);
    if (temp >= 100) return _amber;
    return _green;
  }

  Color _fuelAccentColor() {
    final fuel = _numericValue(_fuelLevel);
    if (fuel.isNaN) return _blue;
    if (fuel <= 12) return const Color(0xFFFF9A2E);
    if (fuel <= 25) return _amber;
    return _blue;
  }

  String _odometerLabel() {
    final trip = context.watch<AppProvider>().activeTrip;
    if (trip == null) return '-- km';
    return '${trip.currentOdometer.toStringAsFixed(0)} km';
  }

  Widget _buildLogPanel(_ComputerColors colors, bool compact) {
    return _LabPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _SectionLabel(label: 'Log TX/RX', color: colors.secondaryText),
              const Spacer(),
              IconButton(
                tooltip: 'Copiar log',
                onPressed: _log.isEmpty ? null : _copyLog,
                icon: const Icon(Icons.copy, color: _blue),
              ),
              IconButton(
                tooltip: 'Limpar log',
                onPressed: () => setState(_log.clear),
                icon: const Icon(Icons.delete_sweep, color: _blue),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _line.withValues(alpha: 0.7)),
              ),
              child: Scrollbar(
                controller: _logController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _logController,
                  itemCount: _log.length,
                  itemBuilder: (context, index) {
                    final line = _log[index];
                    final color = line.contains('TX')
                        ? _blue
                        : line.contains('ERR')
                            ? Colors.redAccent
                            : line.contains('RX')
                                ? _green
                                : colors.secondaryText;
                    return Text(
                      line,
                      style: TextStyle(
                        color: color,
                        fontFamily: 'monospace',
                        fontSize: compact ? 10 : 12,
                        height: 1.25,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final colors = _ComputerColors.of(context);
    final compact = _gaugesOnly;

    return Container(
      height: compact ? 58 : 78,
      padding: EdgeInsets.fromLTRB(18, compact ? 6 : 10, 18, compact ? 7 : 12),
      decoration: BoxDecoration(
        color: colors.bar,
        border: Border(top: BorderSide(color: _line.withValues(alpha: 0.75))),
      ),
      child: _LabPanel(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            _ComputerNavItem(
              icon: Icons.speed,
              label: 'PAINEL',
              onTap: () => Navigator.pushReplacementNamed(context, '/'),
            ),
            _ComputerNavItem(
              icon: Icons.memory,
              label: 'COMPUTADOR',
              active: true,
              onTap: () {},
            ),
            _ComputerNavItem(
              icon: Icons.location_city,
              label: 'CIDADE',
              active: provider.isCityMode,
              onTap: () => provider.setDrivingMode('city'),
            ),
            _ComputerNavItem(
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
}

class _ObdCommandSpec {
  const _ObdCommandSpec(
    this.command,
    this.label, {
    this.momentary = false,
  });

  final String command;
  final String label;
  final bool momentary;

  bool get isProtected =>
      command == '010C' || command == '010D' || command == '0105';
}

class _ProfessionalGaugePanel extends StatelessWidget {
  const _ProfessionalGaugePanel({
    required this.speed,
    required this.rpm,
    required this.odometer,
    required this.temperature,
    required this.load,
    required this.fuel,
    required this.fuelLiters,
    required this.throttle,
    required this.voltage,
    required this.temperatureAccent,
    required this.fuelAccent,
    required this.colors,
  });

  final String speed;
  final String rpm;
  final String odometer;
  final String temperature;
  final String load;
  final String fuel;
  final String fuelLiters;
  final String throttle;
  final String voltage;
  final Color temperatureAccent;
  final Color fuelAccent;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth >= 1500;
        final compact =
            constraints.maxWidth < 1200 || constraints.maxHeight < 520;
        final gap = compact ? 8.0 : (phone ? 20.0 : 12.0);
        final rpmHeight = (constraints.maxHeight *
                (phone
                    ? 0.145
                    : compact
                        ? 0.15
                        : 0.16))
            .clamp(compact ? 64.0 : 76.0, phone ? 112.0 : 102.0);
        final rpmWidth = (constraints.maxWidth *
                (phone
                    ? 0.42
                    : compact
                        ? 0.48
                        : 0.5))
            .clamp(compact ? 430.0 : 520.0, phone ? 980.0 : 680.0);
        final sideFlex = phone ? 30 : (compact ? 27 : 28);
        final centerFlex = phone ? 42 : (compact ? 38 : 40);

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _PanelBackgroundPainter(colors)),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: sideFlex,
                          child: Column(
                            children: [
                              Expanded(
                                child: _ProDataCard(
                                  icon: Icons.device_thermostat,
                                  title: 'Temperatura',
                                  value: temperature,
                                  unit: 'C',
                                  minLabel: '40',
                                  midLabel: '80',
                                  maxLabel: '120',
                                  percent:
                                      _ProGaugeMath.ratio(temperature, 40, 120),
                                  accent: temperatureAccent,
                                  colors: colors,
                                  phone: phone,
                                ),
                              ),
                              SizedBox(height: gap),
                              Expanded(
                                child: _ProDataCard(
                                  icon: Icons.settings_input_component,
                                  title: 'Carga do motor',
                                  value: load,
                                  unit: '%',
                                  minLabel: '0',
                                  midLabel: '50',
                                  maxLabel: '100',
                                  percent: _ProGaugeMath.ratio(load, 0, 100),
                                  accent: _green,
                                  colors: colors,
                                  phone: phone,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: centerFlex,
                          child: Transform.translate(
                            offset: Offset(0, phone ? -10 : -6),
                            child: _ProSpeedCluster(
                              odometer: odometer,
                              voltage: voltage,
                              percent: _ProGaugeMath.ratio(speed, 0, 240),
                              colors: colors,
                              phone: phone,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: sideFlex,
                          child: Column(
                            children: [
                              Expanded(
                                child: _ProFuelCard(
                                  value: fuel,
                                  litersLabel: fuelLiters,
                                  percent: _ProGaugeMath.ratio(fuel, 0, 100),
                                  accent: fuelAccent,
                                  colors: colors,
                                  phone: phone,
                                ),
                              ),
                              SizedBox(height: gap),
                              Expanded(
                                child: _ProDataCard(
                                  icon: Icons.speed,
                                  title: 'Posição do acelerador',
                                  value: throttle,
                                  unit: '%',
                                  minLabel: '0',
                                  midLabel: '50',
                                  maxLabel: '100',
                                  percent:
                                      _ProGaugeMath.ratio(throttle, 0, 100),
                                  accent: const Color(0xFF22D7F2),
                                  colors: colors,
                                  phone: phone,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: gap * 0.65),
                  Center(
                    child: SizedBox(
                      width: rpmWidth,
                      height: rpmHeight,
                      child: _ProRpmPanel(
                        percent: _ProGaugeMath.ratio(rpm, 0, 8000),
                        colors: colors,
                        phone: phone,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProGaugeMath {
  static double ratio(String value, double min, double max) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || max <= min) return 0;
    return ((parsed - min) / (max - min)).clamp(0.0, 1.0);
  }
}

class _ProDataCard extends StatelessWidget {
  const _ProDataCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.minLabel,
    required this.midLabel,
    required this.maxLabel,
    required this.percent,
    required this.accent,
    required this.colors,
    required this.phone,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String minLabel;
  final String midLabel;
  final String maxLabel;
  final double percent;
  final Color accent;
  final _ComputerColors colors;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return _ProGlassCard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            phone ? 28 : 18, phone ? 22 : 15, phone ? 28 : 18, phone ? 18 : 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: phone ? 31 : 24),
                SizedBox(width: phone ? 18 : 12),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: phone ? 20 : 15,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize:
                          value == '--' ? (phone ? 46 : 34) : (phone ? 66 : 49),
                      height: 0.86,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(width: phone ? 10 : 7),
                  Padding(
                    padding: EdgeInsets.only(bottom: phone ? 9 : 6),
                    child: Text(
                      unit,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: phone ? 27 : 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: phone ? 22 : 14),
            _DotGauge(percent: percent, accent: accent, phone: phone),
            SizedBox(height: phone ? 9 : 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [minLabel, midLabel, maxLabel].map((label) {
                return Text(
                  label,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: phone ? 15 : 12,
                    fontWeight: FontWeight.w800,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProFuelCard extends StatelessWidget {
  const _ProFuelCard({
    required this.value,
    required this.litersLabel,
    required this.percent,
    required this.accent,
    required this.colors,
    required this.phone,
  });

  final String value;
  final String litersLabel;
  final double percent;
  final Color accent;
  final _ComputerColors colors;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return _ProGlassCard(
      child: Stack(
        children: [
          Positioned(
            right: phone ? 28 : 16,
            top: phone ? 68 : 48,
            bottom: phone ? 40 : 25,
            width: phone ? 94 : 64,
            child: CustomPaint(painter: _FuelArcPainter(percent: percent)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 28 : 18, phone ? 22 : 15,
                phone ? 104 : 74, phone ? 18 : 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_gas_station,
                        color: accent, size: phone ? 31 : 24),
                    SizedBox(width: phone ? 18 : 12),
                    Expanded(
                      child: Text(
                        'NIVEL DE COMBUSTIVEL',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: phone ? 20 : 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: value == '--'
                              ? (phone ? 46 : 34)
                              : (phone ? 66 : 49),
                          height: 0.86,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: phone ? 10 : 7),
                      Padding(
                        padding: EdgeInsets.only(bottom: phone ? 9 : 6),
                        child: Text('%',
                            style: TextStyle(
                                color: colors.secondaryText,
                                fontSize: phone ? 27 : 21,
                                fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: phone ? 17 : 11),
                Text(
                  litersLabel.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: phone ? 16 : 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProSpeedCluster extends StatelessWidget {
  const _ProSpeedCluster({
    required this.odometer,
    required this.voltage,
    required this.percent,
    required this.colors,
    required this.phone,
  });

  final String odometer;
  final String voltage;
  final double percent;
  final _ComputerColors colors;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ProSpeedPainter(percent: percent),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: phone ? 22 : 11,
            child: Column(
              children: [
                Text(odometer,
                    style: TextStyle(
                        color: colors.primaryText,
                        fontSize: phone ? 24 : 18,
                        fontWeight: FontWeight.w900)),
                Text(
                  voltage == '--' ? 'ODOMETRO' : 'ODOMETRO  |  $voltage V',
                  style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: phone ? 13 : 10,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProRpmPanel extends StatelessWidget {
  const _ProRpmPanel({
    required this.percent,
    required this.colors,
    required this.phone,
  });

  final double percent;
  final _ComputerColors colors;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _RpmPanelClipper(),
      child: CustomPaint(
        painter: _RpmPanelChromePainter(),
        child: Padding(
          padding: EdgeInsets.fromLTRB(phone ? 42 : 26, phone ? 16 : 10,
              phone ? 42 : 26, phone ? 12 : 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _RpmDotGauge(percent: percent, phone: phone),
              ),
              SizedBox(height: phone ? 1 : 0),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(9, (i) {
                  return Text('$i',
                      style: TextStyle(
                          color: i / 8 <= percent
                              ? colors.primaryText
                              : colors.secondaryText,
                          fontSize: phone ? 22 : 14,
                          fontWeight: FontWeight.w900));
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProGlassCard extends StatelessWidget {
  const _ProGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _MetricPanelClipper(),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF04111F).withValues(alpha: 0.82),
          border: Border.all(color: _line.withValues(alpha: 0.72), width: 1.1),
        ),
        child: child,
      ),
    );
  }
}

class _RpmPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final corner = math.min(size.height * 0.42, 46.0);
    return Path()
      ..moveTo(corner, size.height)
      ..lineTo(size.width - corner, size.height)
      ..quadraticBezierTo(
          size.width, size.height, size.width, size.height - corner)
      ..lineTo(size.width, size.height * 0.43)
      ..cubicTo(size.width * 0.78, -size.height * 0.2, size.width * 0.22,
          -size.height * 0.2, 0, size.height * 0.43)
      ..lineTo(0, size.height - corner)
      ..quadraticBezierTo(0, size.height, corner, size.height)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _RpmPanelChromePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = _RpmPanelClipper().getClip(size);
    canvas.drawPath(path, Paint()..color = const Color(0xFF04111F));
    canvas.drawPath(
      path,
      Paint()
        ..color = _line.withValues(alpha: 0.88)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final topArc = Path()
      ..moveTo(size.width * 0.12, size.height * 0.47)
      ..cubicTo(size.width * 0.28, size.height * 0.12, size.width * 0.72,
          size.height * 0.12, size.width * 0.88, size.height * 0.47);
    canvas.drawPath(
      topArc,
      Paint()
        ..color = _blue.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DotGauge extends StatelessWidget {
  const _DotGauge(
      {required this.percent, required this.accent, required this.phone});

  final double percent;
  final Color accent;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGaugePainter(
          percent: percent, accent: accent, count: phone ? 36 : 30),
      child: SizedBox(height: phone ? 17 : 11, width: double.infinity),
    );
  }
}

class _RpmDotGauge extends StatelessWidget {
  const _RpmDotGauge({required this.percent, required this.phone});

  final double percent;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RpmDotGaugePainter(percent: percent, count: phone ? 72 : 54),
      child: const SizedBox.expand(),
    );
  }
}

class _PanelBackgroundPainter extends CustomPainter {
  const _PanelBackgroundPainter(this.colors);

  final _ComputerColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colors.background,
            colors.panel.withValues(alpha: 0.32),
            colors.background,
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _PanelBackgroundPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}

class _ProSpeedPainter extends CustomPainter {
  const _ProSpeedPainter({required this.percent});

  final double percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.57);
    final radius = math.min(size.width * 0.48, size.height * 0.57);
    const start = math.pi * 0.78;
    const sweep = math.pi * 1.44;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius * 0.66,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF103A58).withValues(alpha: 0.62),
            const Color(0xFF061426).withValues(alpha: 0.22),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    for (var i = 0; i <= 72; i++) {
      final t = i / 72;
      final angle = start + sweep * t;
      final major = i % 12 == 0;
      final p1 = Offset(center.dx + math.cos(angle) * radius * 0.88,
          center.dy + math.sin(angle) * radius * 0.88);
      final p2 = Offset(
          center.dx + math.cos(angle) * radius * (major ? 0.76 : 0.82),
          center.dy + math.sin(angle) * radius * (major ? 0.76 : 0.82));
      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = major
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.42)
          ..strokeWidth = major ? radius * 0.014 : radius * 0.008
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = _line.withValues(alpha: 0.62)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.045
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      start,
      sweep * percent.clamp(0.0, 1.0),
      false,
      Paint()
        ..shader = const SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [Color(0xFF1677FF), Color(0xFF22D7F2), Color(0xFF1677FF)],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.052
        ..strokeCap = StrokeCap.round,
    );

    final pointerAngle = start + sweep * percent.clamp(0.0, 1.0);
    final pointerEnd = Offset(
        center.dx + math.cos(pointerAngle) * radius * 0.78,
        center.dy + math.sin(pointerAngle) * radius * 0.78);
    final pointerStart = Offset(
        center.dx + math.cos(pointerAngle) * radius * 0.18,
        center.dy + math.sin(pointerAngle) * radius * 0.18);
    canvas.drawLine(
      pointerStart,
      pointerEnd,
      Paint()
        ..color = const Color(0xFFFF9A2E)
        ..strokeWidth = radius * 0.02
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, radius * 0.28,
        Paint()..color = const Color(0xFF061426).withValues(alpha: 0.74));
    canvas.drawCircle(
        center,
        radius * 0.28,
        Paint()
          ..color = _blue.withValues(alpha: 0.26)
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.01);
  }

  @override
  bool shouldRepaint(covariant _ProSpeedPainter oldDelegate) {
    return oldDelegate.percent != percent;
  }
}

class _DotGaugePainter extends CustomPainter {
  const _DotGaugePainter(
      {required this.percent, required this.accent, required this.count});

  final double percent;
  final Color accent;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final active = (count * percent.clamp(0.0, 1.0)).round();
    final gap = size.width / count;
    final dotW = math.max(2.0, gap * 0.45);
    final y1 = size.height * 0.18;
    final y2 = size.height * 0.82;
    for (var i = 0; i < count; i++) {
      final x = gap * (i + 0.5);
      canvas.drawLine(
        Offset(x, y1),
        Offset(x, y2),
        Paint()
          ..color = i < active
              ? accent
              : const Color(0xFF163149).withValues(alpha: 0.78)
          ..strokeWidth = dotW
          ..strokeCap = StrokeCap.butt,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotGaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.accent != accent;
  }
}

class _RpmDotGaugePainter extends CustomPainter {
  const _RpmDotGaugePainter({required this.percent, required this.count});

  final double percent;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final active = (count * percent.clamp(0.0, 1.0)).round();
    final gap = size.width / count;
    final dotW = math.max(2.4, gap * 0.48);
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final curve = math.sin(math.pi * t);
      final x = gap * (i + 0.5);
      final y = size.height * (0.72 - curve * 0.42);
      final nextT = ((i + 1).clamp(0, count - 1)) / (count - 1);
      final prevT = ((i - 1).clamp(0, count - 1)) / (count - 1);
      final nextY = size.height * (0.72 - math.sin(math.pi * nextT) * 0.42);
      final prevY = size.height * (0.72 - math.sin(math.pi * prevT) * 0.42);
      final tangent = math.atan2(nextY - prevY, gap * 2);
      final dotH = size.height * (0.32 + curve * 0.44);
      final color = t > 0.78
          ? const Color(0xFFFF9A2E)
          : t > 0.58
              ? _amber
              : _green;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(tangent + math.pi / 2);
      canvas.drawLine(
        Offset(0, -math.max(8, dotH) / 2),
        Offset(0, math.max(8, dotH) / 2),
        Paint()
          ..color = i < active
              ? color
              : const Color(0xFF21384E).withValues(alpha: 0.62)
          ..strokeWidth = dotW
          ..strokeCap = StrokeCap.butt,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RpmDotGaugePainter oldDelegate) {
    return oldDelegate.percent != percent;
  }
}

class _FigmaGaugePanel extends StatelessWidget {
  const _FigmaGaugePanel({
    required this.speed,
    required this.rpmLabel,
    required this.odometer,
    required this.temperature,
    required this.load,
    required this.fuel,
    required this.fuelLiters,
    required this.throttle,
    required this.temperatureAccent,
    required this.fuelAccent,
    required this.colors,
  });

  final String speed;
  final String rpmLabel;
  final String odometer;
  final String temperature;
  final String load;
  final String fuel;
  final String fuelLiters;
  final String throttle;
  final Color temperatureAccent;
  final Color fuelAccent;
  final _ComputerColors colors;

  static const double _baseW = 1024;
  static const double _baseH = 602;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final phoneBase = _isPhoneBase(constraints);
        final baseW = phoneBase ? 1920.0 : _baseW;
        final baseH = phoneBase ? 1080.0 : _baseH;
        double sx(double value) => constraints.maxWidth * value / baseW;
        double sy(double value) => constraints.maxHeight * value / baseH;
        final compact =
            constraints.maxHeight < 500 || constraints.maxWidth < 1050;

        Widget at({
          required double x,
          required double y,
          required double w,
          required double h,
          required Widget child,
        }) {
          return Positioned(
            left: sx(x),
            top: sy(y),
            width: sx(w),
            height: sy(h),
            child: child,
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              _isPhoneBase(constraints)
                  ? 'assets/images/painel_base_celular.png'
                  : 'assets/images/painel_base.png',
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _FigmaSpeedNeedlePainter(
                  percent: _ratio(speed, 0, 240),
                  phoneBase: phoneBase,
                ),
              ),
            ),
            at(
              x: _x(constraints, 72, 72),
              y: _y(constraints, 86, 126),
              w: _d(constraints, 230, 420),
              h: _d(constraints, 142, 245),
              child: _FigmaMetricText(
                icon: Icons.device_thermostat,
                title: 'Temperatura',
                value: temperature,
                unit: 'C',
                accent: temperatureAccent,
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 92, 92),
              y: _y(constraints, 250, 420),
              w: _d(constraints, 238, 425),
              h: _d(constraints, 28, 34),
              child: _FigmaLinearGauge(
                value: _ratio(temperature, 40, 120),
                accent: temperatureAccent,
              ),
            ),
            at(
              x: _x(constraints, 98, 98),
              y: _y(constraints, 286, 470),
              w: _d(constraints, 230, 420),
              h: _d(constraints, 24, 36),
              child: _FigmaScaleLabels(
                labels: const ['40', '80', '120'],
                colors: colors,
              ),
            ),
            at(
              x: _x(constraints, 72, 72),
              y: _y(constraints, 306, 505),
              w: _d(constraints, 230, 420),
              h: _d(constraints, 122, 230),
              child: _FigmaMetricText(
                icon: Icons.settings_input_component,
                title: 'Carga do motor',
                value: load,
                unit: '%',
                accent: _green,
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 92, 92),
              y: _y(constraints, 452, 770),
              w: _d(constraints, 238, 425),
              h: _d(constraints, 24, 34),
              child: _FigmaLinearGauge(
                value: _ratio(load, 0, 100),
                accent: _green,
              ),
            ),
            at(
              x: _x(constraints, 430, 828),
              y: _y(constraints, 202, 425),
              w: _d(constraints, 168, 265),
              h: _d(constraints, 112, 165),
              child: _FigmaSpeedText(
                value: speed,
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 402, 800),
              y: _y(constraints, 380, 650),
              w: _d(constraints, 220, 320),
              h: _d(constraints, 58, 82),
              child: _FigmaOdometerText(
                odometer: odometer,
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 720, 1470),
              y: _y(constraints, 86, 135),
              w: _d(constraints, 220, 420),
              h: _d(constraints, 134, 235),
              child: _FigmaMetricText(
                icon: Icons.local_gas_station,
                title: 'Nivel de combustivel',
                value: fuel,
                unit: '%',
                accent: fuelAccent,
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 875, 1700),
              y: _y(constraints, 162, 300),
              w: _d(constraints, 72, 125),
              h: _d(constraints, 110, 190),
              child: CustomPaint(
                painter: _FuelArcPainter(percent: _ratio(fuel, 0, 100)),
              ),
            ),
            at(
              x: _x(constraints, 720, 1470),
              y: _y(constraints, 250, 445),
              w: _d(constraints, 180, 320),
              h: _d(constraints, 28, 40),
              child: Text(
                fuelLiters.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            at(
              x: _x(constraints, 720, 1470),
              y: _y(constraints, 306, 515),
              w: _d(constraints, 230, 420),
              h: _d(constraints, 122, 230),
              child: _FigmaMetricText(
                icon: Icons.speed,
                title: 'Posição do acelerador',
                value: throttle,
                unit: '%',
                accent: const Color(0xFF22D7F2),
                colors: colors,
                compact: compact,
              ),
            ),
            at(
              x: _x(constraints, 732, 1485),
              y: _y(constraints, 452, 795),
              w: _d(constraints, 220, 390),
              h: _d(constraints, 24, 34),
              child: _FigmaLinearGauge(
                value: _ratio(throttle, 0, 100),
                accent: const Color(0xFF22D7F2),
              ),
            ),
            at(
              x: _x(constraints, 108, 225),
              y: _y(constraints, 488, 878),
              w: _d(constraints, 128, 210),
              h: _d(constraints, 58, 90),
              child: Text(
                'RPM\nx1000',
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: compact ? 17 : 20,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            at(
              x: _x(constraints, 342, 650),
              y: _y(constraints, 498, 885),
              w: _d(constraints, 340, 620),
              h: _d(constraints, 42, 70),
              child: _FigmaRpmTicks(
                value: _ratio(rpmLabel, 0, 8),
                colors: colors,
              ),
            ),
            at(
              x: _x(constraints, 432, 840),
              y: _y(constraints, 535, 945),
              w: _d(constraints, 160, 250),
              h: _d(constraints, 52, 86),
              child: Column(
                children: [
                  Text(
                    rpmLabel,
                    style: TextStyle(
                      color: colors.primaryText,
                      fontSize: compact ? 26 : 34,
                      height: 0.85,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'x1000 rpm',
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  static bool _isPhoneBase(BoxConstraints constraints) {
    return constraints.maxWidth >= 1300;
  }

  static double _x(BoxConstraints constraints, double media, double phone) {
    return _isPhoneBase(constraints) ? phone : media;
  }

  static double _y(BoxConstraints constraints, double media, double phone) {
    return _isPhoneBase(constraints) ? phone : media;
  }

  static double _d(BoxConstraints constraints, double media, double phone) {
    return _isPhoneBase(constraints) ? phone : media;
  }

  static double _ratio(String value, double min, double max) {
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed == null || max <= min) return 0;
    return ((parsed - min) / (max - min)).clamp(0.0, 1.0);
  }
}

class _FigmaMetricText extends StatelessWidget {
  const _FigmaMetricText({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.accent,
    required this.colors,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final Color accent;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueSize =
        value == '--' ? (compact ? 32.0 : 40.0) : (compact ? 46.0 : 58.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: compact ? 24 : 30),
            SizedBox(width: compact ? 12 : 16),
            Expanded(
              child: Text(
                title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.secondaryText,
                  fontSize: compact ? 16 : 19,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: colors.primaryText,
                  fontSize: valueSize,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: compact ? 24 : 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FigmaSpeedText extends StatelessWidget {
  const _FigmaSpeedText({
    required this.value,
    required this.colors,
    required this.compact,
  });

  final String value;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: colors.primaryText,
            fontSize: value == '--' ? (compact ? 38 : 46) : (compact ? 58 : 72),
            height: 0.82,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          'km/h',
          style: TextStyle(
            color: colors.secondaryText,
            fontSize: compact ? 16 : 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FigmaOdometerText extends StatelessWidget {
  const _FigmaOdometerText({
    required this.odometer,
    required this.colors,
    required this.compact,
  });

  final String odometer;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          odometer,
          style: TextStyle(
            color: colors.primaryText,
            fontSize: compact ? 20 : 26,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ODOMETRO',
          style: TextStyle(
            color: colors.secondaryText,
            fontSize: compact ? 10 : 12,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FigmaLinearGauge extends StatelessWidget {
  const _FigmaLinearGauge({required this.value, required this.accent});

  final double value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SegmentGaugePainter(
        percent: value,
        accent: accent,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _FigmaScaleLabels extends StatelessWidget {
  const _FigmaScaleLabels({required this.labels, required this.colors});

  final List<String> labels;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map(
            (label) => Text(
              label,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          )
          .toList(),
    );
  }
}

class _FigmaRpmTicks extends StatelessWidget {
  const _FigmaRpmTicks({required this.value, required this.colors});

  final double value;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(9, (index) {
        final active = index / 8 <= value;
        return Text(
          '$index',
          style: TextStyle(
            color: active ? colors.primaryText : colors.secondaryText,
            fontSize: index == 5 ? 23 : 20,
            fontWeight: FontWeight.w900,
          ),
        );
      }),
    );
  }
}

class _FigmaSpeedNeedlePainter extends CustomPainter {
  const _FigmaSpeedNeedlePainter({
    required this.percent,
    required this.phoneBase,
  });

  final double percent;
  final bool phoneBase;

  @override
  void paint(Canvas canvas, Size size) {
    final baseW = phoneBase ? 1920.0 : 1024.0;
    final baseH = phoneBase ? 1080.0 : 602.0;
    Offset p(double x, double y) =>
        Offset(size.width * x / baseW, size.height * y / baseH);
    double s(double value) =>
        value * size.shortestSide / (phoneBase ? 1080.0 : 602.0);

    final center = phoneBase ? p(976, 448) : p(518, 278);
    final startAngle = phoneBase ? math.pi * 0.83 : math.pi * 0.87;
    final endAngle = phoneBase ? math.pi * 0.18 : math.pi * 0.13;
    final angle =
        startAngle + (endAngle - startAngle) * percent.clamp(0.0, 1.0);
    final inner = s(phoneBase ? 64 : 38);
    final outer = s(phoneBase ? 390 : 214);
    final start = Offset(
      center.dx + math.cos(angle) * inner,
      center.dy + math.sin(angle) * inner,
    );
    final end = Offset(
      center.dx + math.cos(angle) * outer,
      center.dy + math.sin(angle) * outer,
    );

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFFFF9A2E).withValues(alpha: 0.34)
        ..strokeWidth = s(phoneBase ? 15 : 9)
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = const Color(0xFFFF9A2E)
        ..strokeWidth = s(phoneBase ? 7 : 4.4)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      center,
      s(phoneBase ? 10 : 6),
      Paint()..color = const Color(0xFFFFC857),
    );
  }

  @override
  bool shouldRepaint(covariant _FigmaSpeedNeedlePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.phoneBase != phoneBase;
  }
}

class _ObdCockpitTopBar extends StatelessWidget {
  const _ObdCockpitTopBar({
    required this.connected,
    required this.compact,
    required this.onCommands,
  });

  final bool connected;
  final bool compact;
  final VoidCallback onCommands;

  @override
  Widget build(BuildContext context) {
    final colors = _ComputerColors.of(context);
    final vehicleName = context.watch<AppProvider>().vehicleName;
    final now = TimeOfDay.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return Container(
      height: compact ? 46 : 54,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
      decoration: ShapeDecoration(
        color: const Color(0xFF03101E).withValues(alpha: 0.9),
        shape: StadiumBorder(
          side: BorderSide(color: _line.withValues(alpha: 0.72), width: 1.2),
        ),
        shadows: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.12),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: connected ? _green : _amber, size: 12),
          SizedBox(width: compact ? 7 : 9),
          Text(
            connected ? 'CONECTADO' : 'DESCONECTADO',
            style: TextStyle(
              color: connected ? _green : _amber,
              fontWeight: FontWeight.w900,
              fontSize: compact ? 13 : 14,
            ),
          ),
          SizedBox(width: compact ? 20 : 30),
          Icon(Icons.bluetooth,
              color: colors.secondaryText, size: compact ? 20 : 22),
          SizedBox(width: compact ? 6 : 8),
          Text(
            'ELM327',
            style: TextStyle(
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              fontSize: compact ? 13 : 14,
            ),
          ),
          const Spacer(),
          Container(
            width: compact ? 46 : 54,
            height: compact ? 24 : 30,
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
          SizedBox(width: compact ? 10 : 14),
          Text(
            vehicleName.toUpperCase(),
            style: TextStyle(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 15 : 16,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          Icon(Icons.schedule,
              color: colors.secondaryText, size: compact ? 18 : 19),
          SizedBox(width: compact ? 6 : 8),
          Text(
            time,
            style: TextStyle(
              color: colors.secondaryText,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(width: compact ? 10 : 20),
          IconButton(
            tooltip: 'Comandos',
            onPressed: onCommands,
            icon: Icon(Icons.more_horiz, color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _ObdSideMetric extends StatelessWidget {
  const _ObdSideMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.minLabel,
    required this.midLabel,
    required this.maxLabel,
    required this.percent,
    required this.accent,
    required this.colors,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String minLabel;
  final String midLabel;
  final String maxLabel;
  final double percent;
  final Color accent;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _MetricPanelClipper(),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          compact ? 14 : 20,
          compact ? 16 : 24,
          compact ? 12 : 18,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF04111F).withValues(alpha: 0.88),
          border: Border.all(color: _line.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 26,
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueSize = value == '--'
                ? (constraints.maxHeight * 0.24).clamp(28.0, 42.0)
                : (constraints.maxHeight * 0.32)
                    .clamp(compact ? 38.0 : 42.0, compact ? 58.0 : 72.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: compact ? 22 : 24),
                    SizedBox(width: compact ? 12 : 18),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: compact ? 13 : 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: valueSize,
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        unit,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 12 : 24),
                _SegmentBar(
                  percent: percent,
                  accent: accent,
                  height: compact ? 8 : 11,
                ),
                SizedBox(height: compact ? 6 : 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(minLabel, style: _scaleStyle(colors)),
                    Text(midLabel, style: _scaleStyle(colors)),
                    Text(maxLabel, style: _scaleStyle(colors)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  TextStyle _scaleStyle(_ComputerColors colors) {
    return TextStyle(
      color: colors.secondaryText,
      fontSize: compact ? 12 : 14,
      fontWeight: FontWeight.w800,
    );
  }
}

class _MetricPanelClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(18, 0)
      ..lineTo(size.width - 34, 0)
      ..quadraticBezierTo(size.width, 0, size.width, 28)
      ..lineTo(size.width, size.height - 36)
      ..quadraticBezierTo(
        size.width - 8,
        size.height - 4,
        size.width - 44,
        size.height,
      )
      ..lineTo(18, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 18)
      ..lineTo(0, 18)
      ..quadraticBezierTo(0, 0, 18, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _SegmentBar extends StatelessWidget {
  const _SegmentBar({
    required this.percent,
    required this.accent,
    required this.height,
  });

  final double percent;
  final Color accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SegmentGaugePainter(percent: percent, accent: accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _FuelArcCard extends StatelessWidget {
  const _FuelArcCard({
    required this.value,
    required this.litersLabel,
    required this.percent,
    required this.accent,
    required this.colors,
    required this.compact,
  });

  final String value;
  final String litersLabel;
  final double percent;
  final Color accent;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _MetricPanelClipper(),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 24,
          compact ? 14 : 20,
          compact ? 12 : 20,
          compact ? 12 : 18,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF04111F).withValues(alpha: 0.88),
          border: Border.all(color: _line.withValues(alpha: 0.7)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: compact ? 30 : 34,
              bottom: 8,
              width: compact ? 56 : 76,
              child: CustomPaint(
                painter: _FuelArcPainter(percent: percent),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_gas_station,
                        color: _amber, size: compact ? 22 : 24),
                    SizedBox(width: compact ? 12 : 18),
                    Expanded(
                      child: Text(
                        'NIVEL DE COMBUSTIVEL',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: compact ? 13 : 15,
                          height: 1.05,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        color: colors.primaryText,
                        fontSize: value == '--'
                            ? (compact ? 34 : 42)
                            : (compact ? 48 : 62),
                        height: 0.9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '%',
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 18),
                Text(
                  litersLabel.toUpperCase(),
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: compact ? 12 : 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterVehicleCluster extends StatelessWidget {
  const _CenterVehicleCluster({
    required this.speed,
    required this.odometer,
    required this.compact,
    required this.colors,
  });

  final String speed;
  final String odometer;
  final bool compact;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _VehicleHaloPainter(),
                  ),
                ),
                Positioned(
                  top: size * 0.02,
                  child: Column(
                    children: [
                      Text(
                        speed,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: speed == '--' ? size * 0.13 : size * 0.18,
                          height: 0.88,
                          fontWeight: FontWeight.w900,
                          shadows: [
                            Shadow(
                              color: Colors.white.withValues(alpha: 0.24),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'km/h',
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: size * 0.046,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: compact ? 0.43 : 0.42,
                  heightFactor: compact ? 0.52 : 0.54,
                  child: Image.asset(
                    'assets/images/aereo_onix.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                Positioned(
                  bottom: size * 0.105,
                  child: Column(
                    children: [
                      Text(
                        odometer,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: size * 0.072,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ODOMETRO',
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: size * 0.034,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
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
}

class _RpmSweepPanel extends StatelessWidget {
  const _RpmSweepPanel({
    required this.rpmLabel,
    required this.percent,
    required this.colors,
    required this.compact,
  });

  final String rpmLabel;
  final double percent;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RpmSweepPainter(percent: percent, compact: compact),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 42,
          compact ? 8 : 26,
          compact ? 18 : 42,
          compact ? 8 : 16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'RPM\nx1000',
              style: TextStyle(
                color: colors.primaryText,
                fontSize: compact ? 12 : 15,
                height: 1.28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  rpmLabel,
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: compact ? 28 : 46,
                    height: 0.88,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'x1000 rpm',
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: compact ? 12 : 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(width: compact ? 34 : 58),
          ],
        ),
      ),
    );
  }
}

class _SegmentGaugePainter extends CustomPainter {
  const _SegmentGaugePainter({required this.percent, required this.accent});

  final double percent;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 2.0;
    const count = 34;
    final width = (size.width - gap * (count - 1)) / count;
    final active = (count * percent.clamp(0.0, 1.0)).round();
    for (var i = 0; i < count; i++) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (width + gap), 0, width, size.height),
        const Radius.circular(999),
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i < active
              ? accent
              : const Color(0xFF12304A).withValues(alpha: 0.74),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentGaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.accent != accent;
  }
}

class _FuelArcPainter extends CustomPainter {
  const _FuelArcPainter({required this.percent});

  final double percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.08, size.height * 0.5);
    final radius = math.min(size.width * 1.05, size.height * 0.43);
    const start = -math.pi * 0.42;
    const sweep = math.pi * 0.84;
    const segments = 15;
    final active = (segments * percent.clamp(0.0, 1.0)).round();
    for (var i = 0; i < segments; i++) {
      final t = i / (segments - 1);
      final color = t < 0.18
          ? const Color(0xFFFF9A2E)
          : t < 0.42
              ? _amber
              : _green;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start + sweep * (1 - i / segments),
        -sweep / segments * 0.62,
        false,
        Paint()
          ..color = i < active
              ? color
              : const Color(0xFF163149).withValues(alpha: 0.62)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.butt,
      );
    }
    final textStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.9),
      fontSize: 13,
      fontWeight: FontWeight.w900,
    );
    for (final item in [
      (label: 'F', offset: Offset(size.width - 12, size.height * 0.1)),
      (label: 'E', offset: Offset(size.width - 12, size.height * 0.86)),
    ]) {
      final tp = TextPainter(
        text: TextSpan(text: item.label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, item.offset - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant _FuelArcPainter oldDelegate) {
    return oldDelegate.percent != percent;
  }
}

class _VehicleHaloPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.56);
    final radius = size.shortestSide * 0.43;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF0A2A44).withValues(alpha: 0.64),
            const Color(0xFF061426).withValues(alpha: 0.26),
            Colors.transparent,
          ],
        ).createShader(rect),
    );

    for (var i = 0; i < 80; i++) {
      final angle = math.pi * 2 * i / 80;
      final inner = radius * 0.26;
      final outer = radius * (0.78 + (i % 5) * 0.018);
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * inner,
            center.dy + math.sin(angle) * inner),
        Offset(center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer),
        Paint()
          ..color = _blue.withValues(alpha: i % 2 == 0 ? 0.08 : 0.035)
          ..strokeWidth = 0.8,
      );
    }

    for (final scale in const [0.42, 0.68, 0.9]) {
      canvas.drawCircle(
        center,
        radius * scale,
        Paint()
          ..color = _blue.withValues(alpha: 0.24 / scale)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }

    for (final side in const [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 1.04),
        side < 0 ? math.pi * 0.72 : -math.pi * 0.22,
        side < 0 ? math.pi * 0.55 : math.pi * 0.55,
        false,
        Paint()
          ..color = _blue.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.butt,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 1.17),
        side < 0 ? math.pi * 0.72 : -math.pi * 0.22,
        side < 0 ? math.pi * 0.55 : math.pi * 0.55,
        false,
        Paint()
          ..color = _blue.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RpmSweepPainter extends CustomPainter {
  const _RpmSweepPainter({required this.percent, required this.compact});

  final double percent;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final panel = Path()
      ..moveTo(size.width * 0.09, size.height)
      ..quadraticBezierTo(size.width * 0.12, compact ? 18 : 8,
          size.width * 0.25, compact ? 16 : 6)
      ..quadraticBezierTo(size.width * 0.5, compact ? 8 : -6, size.width * 0.75,
          compact ? 16 : 6)
      ..quadraticBezierTo(
          size.width * 0.88, compact ? 18 : 8, size.width * 0.91, size.height)
      ..close();
    canvas.drawPath(
      panel,
      Paint()
        ..color = const Color(0xFF04111F).withValues(alpha: 0.88)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      panel,
      Paint()
        ..color = _line.withValues(alpha: 0.86)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );

    final segments = compact ? 44 : 58;
    final active = (segments * percent.clamp(0.0, 1.0)).round();
    for (var i = 0; i < segments; i++) {
      final t = i / (segments - 1);
      final x = size.width * (0.22 + 0.56 * t);
      final y =
          (compact ? 23 : 32) - math.sin(t * math.pi) * (compact ? 6 : 14);
      final h =
          (compact ? 7 : 10) + math.sin(t * math.pi) * (compact ? 1.5 : 3);
      final color = t > 0.72
          ? const Color(0xFFFF1E2D)
          : t > 0.62
              ? _amber
              : _blue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(x, y), width: compact ? 5.4 : 7.5, height: h),
          const Radius.circular(2),
        ),
        Paint()
          ..color = i < active
              ? color
              : const Color(0xFF243B54).withValues(alpha: 0.8),
      );
    }

    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      final x = size.width * (0.22 + 0.56 * t);
      final y =
          (compact ? 37 : 58) - math.sin(t * math.pi) * (compact ? 5 : 12);
      final tp = TextPainter(
        text: TextSpan(
          text: '$i',
          style: TextStyle(
            color: i >= 5 ? Colors.white : Colors.white.withValues(alpha: 0.78),
            fontSize: compact ? (i == 5 ? 14 : 12) : (i == 5 ? 18 : 15),
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y));
    }
  }

  @override
  bool shouldRepaint(covariant _RpmSweepPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.compact != compact;
  }
}

class _DigitalMetricCard extends StatelessWidget {
  const _DigitalMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color accent;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return _LabPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final valueSize = (constraints.maxHeight * 0.35)
                .clamp(28.0, constraints.maxWidth < 190 ? 42.0 : 58.0);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.primaryText,
                          fontSize: valueSize,
                          height: 0.9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          unit,
                          style: TextStyle(
                            color: accent,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThinFuelBar extends StatelessWidget {
  const _ThinFuelBar({
    required this.value,
    required this.accent,
    required this.colors,
    this.compact = false,
  });

  final String value;
  final Color accent;
  final _ComputerColors colors;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    final percent = (parsed / 100).clamp(0.0, 1.0);
    return _LabPanel(
      padding: EdgeInsets.fromLTRB(14, compact ? 8 : 12, 14, compact ? 8 : 12),
      child: SizedBox(
        height: compact ? 54 : 72,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.local_gas_station, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NIVEL DE COMBUSTIVEL',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  value == '--' ? '--' : '$value%',
                  style: TextStyle(
                    color: colors.primaryText,
                    fontSize: compact ? 18 : 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: compact ? 9 : 12,
                value: percent,
                backgroundColor: _line.withValues(alpha: 0.38),
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenterSpeedometerCard extends StatelessWidget {
  const _CenterSpeedometerCard({
    required this.speed,
    required this.rpm,
    required this.odometer,
    required this.percent,
    required this.colors,
  });

  final String speed;
  final String rpm;
  final String odometer;
  final double percent;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return _LabPanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = math.min(constraints.maxWidth, constraints.maxHeight);
          return Center(
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CenterSpeedometerPainter(
                        percent: percent,
                        colors: colors,
                      ),
                    ),
                  ),
                  Positioned(
                    top: size * 0.39,
                    child: Column(
                      children: [
                        Text(
                          speed,
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: size * 0.16,
                            height: 0.86,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'km/h',
                          style: TextStyle(
                            color: colors.primaryText,
                            fontSize: size * 0.052,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: size * 0.14,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: size * 0.055,
                        vertical: size * 0.018,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _blue.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            odometer,
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: size * 0.052,
                              height: 1.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            rpm == '--' ? '-- rpm' : '$rpm rpm',
                            style: TextStyle(
                              color: colors.secondaryText,
                              fontSize: size * 0.026,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ignore: unused_element
class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.minLabel,
    required this.maxLabel,
    required this.percent,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String minLabel;
  final String maxLabel;
  final double percent;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return _LabPanel(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gaugeSize = math.min(
            constraints.maxWidth,
            constraints.maxHeight * 0.9,
          );
          return Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: _blue, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: gaugeSize,
                    height: gaugeSize * 0.72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GaugePainter(percent: percent),
                          ),
                        ),
                        Positioned(
                          bottom: 13,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.primaryText,
                                  fontSize: 30,
                                  height: 0.95,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Text(
                                  unit,
                                  style: TextStyle(
                                    color: colors.primaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 5,
                          bottom: 0,
                          child: Text(
                            minLabel,
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 5,
                          bottom: 0,
                          child: Text(
                            maxLabel,
                            style: TextStyle(
                              color: colors.primaryText,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ignore: unused_element
class _FuelLevelCard extends StatelessWidget {
  const _FuelLevelCard({
    required this.value,
    required this.colors,
  });

  final String value;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
    final percent = (parsed / 100).clamp(0.0, 1.0);
    return _LabPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.local_gas_station, color: _blue, size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  'NIVEL DE COMBUSTIVEL',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.secondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value == '--' ? '--' : '$value%',
            style: TextStyle(
              color: colors.primaryText,
              fontSize: 38,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              minHeight: 22,
              value: percent,
              backgroundColor: _line.withValues(alpha: 0.35),
              color: _blue,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('E', style: TextStyle(color: colors.primaryText)),
              Text('F', style: TextStyle(color: colors.primaryText)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CenterSpeedometerPainter extends CustomPainter {
  const _CenterSpeedometerPainter({
    required this.percent,
    required this.colors,
  });

  final double percent;
  final _ComputerColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.455;
    final safePercent = percent.clamp(0.0, 1.0);
    final outerRect = Rect.fromCircle(center: center, radius: radius);
    final innerRect = Rect.fromCircle(center: center, radius: radius * 0.8);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0.92),
            const Color(0xFF061426),
            _blue.withValues(alpha: 0.34),
            Colors.black.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.58, 0.82, 1.0],
        ).createShader(outerRect),
    );

    canvas.drawCircle(
      center,
      radius * 0.99,
      Paint()
        ..color = _blue.withValues(alpha: 0.46)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.055
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawCircle(
      center,
      radius * 0.97,
      Paint()
        ..color = _blue.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.018,
    );
    canvas.drawCircle(
      center,
      radius * 0.79,
      Paint()
        ..color = _blue.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.01
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      center,
      radius * 0.43,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF071321),
            const Color(0xFF050A12),
            _blue.withValues(alpha: 0.3),
          ],
        ).createShader(innerRect),
    );
    canvas.drawCircle(
      center,
      radius * 0.43,
      Paint()
        ..color = _blue.withValues(alpha: 0.54)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.012
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    final minorTickPaint = Paint()
      ..color = colors.primaryText.withValues(alpha: 0.78)
      ..strokeWidth = radius * 0.007
      ..strokeCap = StrokeCap.square;
    final majorTickPaint = Paint()
      ..color = colors.primaryText.withValues(alpha: 0.94)
      ..strokeWidth = radius * 0.015
      ..strokeCap = StrokeCap.square;
    final cardinalTickPaint = Paint()
      ..color = colors.primaryText
      ..strokeWidth = radius * 0.024
      ..strokeCap = StrokeCap.square;

    const startAngle = math.pi * 0.76;
    const sweepAngle = math.pi * 1.48;
    for (var i = 0; i <= 72; i++) {
      final t = i / 72;
      final angle = startAngle + sweepAngle * t;
      final major = i % 6 == 0;
      final cardinal = i % 18 == 0;
      final outer = radius * 0.75;
      final inner = radius *
          (cardinal
              ? 0.61
              : major
                  ? 0.64
                  : 0.68);
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer),
        Offset(center.dx + math.cos(angle) * inner,
            center.dy + math.sin(angle) * inner),
        cardinal
            ? cardinalTickPaint
            : major
                ? majorTickPaint
                : minorTickPaint,
      );
    }

    for (var speed = 0; speed <= 240; speed += 20) {
      final t = speed / 240;
      final angle = startAngle + sweepAngle * t;
      final textOffset = Offset(
        center.dx + math.cos(angle) * radius * 0.88,
        center.dy + math.sin(angle) * radius * 0.88,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '$speed',
          style: TextStyle(
            color: colors.primaryText.withValues(alpha: 0.9),
            fontSize: radius * 0.085,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        textOffset - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final pointerAngle = startAngle + sweepAngle * safePercent;
    final pointerInner = radius * 0.17;
    final pointerOuter = radius * 0.73;
    final pointerGlow = Paint()
      ..color = _amber.withValues(alpha: 0.42)
      ..strokeWidth = radius * 0.09
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final pointerPaint = Paint()
      ..color = _amber
      ..strokeWidth = radius * 0.045
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(center.dx + math.cos(pointerAngle) * pointerInner,
          center.dy + math.sin(pointerAngle) * pointerInner),
      Offset(center.dx + math.cos(pointerAngle) * pointerOuter,
          center.dy + math.sin(pointerAngle) * pointerOuter),
      pointerGlow,
    );
    canvas.drawLine(
      Offset(center.dx + math.cos(pointerAngle) * pointerInner,
          center.dy + math.sin(pointerAngle) * pointerInner),
      Offset(center.dx + math.cos(pointerAngle) * pointerOuter,
          center.dy + math.sin(pointerAngle) * pointerOuter),
      pointerPaint,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.985),
      startAngle,
      sweepAngle * safePercent,
      false,
      Paint()
        ..color = _blue.withValues(alpha: 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.018
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CenterSpeedometerPainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.colors != colors;
  }
}

// ignore: unused_element
class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.percent});

  final double percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.98);
    final radius = math.min(size.width * 0.46, size.height * 0.88);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = math.pi;
    const sweep = math.pi;
    final stroke = math.max(9.0, radius * 0.12);

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = _line.withValues(alpha: 0.58)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );
    canvas.drawArc(
      rect,
      start,
      sweep * 0.18,
      false,
      Paint()
        ..color = _blue
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );
    canvas.drawArc(
      rect,
      start + sweep * 0.18,
      sweep * 0.56,
      false,
      Paint()
        ..color = _green.withValues(alpha: 0.86)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );
    canvas.drawArc(
      rect,
      start + sweep * 0.74,
      sweep * 0.16,
      false,
      Paint()
        ..color = _amber
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );
    canvas.drawArc(
      rect,
      start + sweep * 0.9,
      sweep * 0.1,
      false,
      Paint()
        ..color = const Color(0xFFFF9A2E)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt,
    );

    final tickPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.88)
      ..strokeWidth = math.max(1.2, radius * 0.015)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 18; i++) {
      final angle = start + sweep * (i / 18);
      final outer = radius + stroke * 0.08;
      final inner = radius - stroke * (i % 3 == 0 ? 0.86 : 0.52);
      canvas.drawLine(
        Offset(center.dx + math.cos(angle) * outer,
            center.dy + math.sin(angle) * outer),
        Offset(center.dx + math.cos(angle) * inner,
            center.dy + math.sin(angle) * inner),
        tickPaint,
      );
    }

    final pointerAngle = start + sweep * percent.clamp(0.0, 1.0);
    final pointerLength = radius - stroke * 0.3;
    final pointerEnd = Offset(
      center.dx + math.cos(pointerAngle) * pointerLength,
      center.dy + math.sin(pointerAngle) * pointerLength,
    );
    canvas.drawLine(
      center,
      pointerEnd,
      Paint()
        ..color = _amber
        ..strokeWidth = math.max(3.0, radius * 0.035)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
        center, math.max(5, radius * 0.06), Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.percent != percent;
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final String value;
  final _ComputerColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: _blue, size: 17),
          const SizedBox(width: 7),
          SizedBox(
            width: 92,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.primaryText,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _LabPanel extends StatelessWidget {
  const _LabPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _ComputerColors.of(context).panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ComputerNavItem extends StatelessWidget {
  const _ComputerNavItem({
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
    final colors = _ComputerColors.of(context);
    final color = active ? _blue : colors.secondaryText;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: active ? _blue.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active ? Border.all(color: _blue) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 25),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComputerColors {
  const _ComputerColors({
    required this.background,
    required this.bar,
    required this.panel,
    required this.primaryText,
    required this.secondaryText,
  });

  final Color background;
  final Color bar;
  final Color panel;
  final Color primaryText;
  final Color secondaryText;

  static _ComputerColors of(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (dark) {
      return const _ComputerColors(
        background: _bg,
        bar: _bar,
        panel: _card,
        primaryText: Colors.white,
        secondaryText: Color(0xFF8EA4C3),
      );
    }
    return const _ComputerColors(
      background: Color(0xFFEAF2FF),
      bar: Colors.white,
      panel: Colors.white,
      primaryText: Color(0xFF071527),
      secondaryText: Color(0xFF5A6B83),
    );
  }
}
