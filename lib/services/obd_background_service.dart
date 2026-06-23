import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'obd_service.dart';

class ObdBackgroundService extends ChangeNotifier {
  ObdBackgroundService._();

  static final ObdBackgroundService instance = ObdBackgroundService._();

  final ObdService _obd = ObdService();
  final Set<String> _enabledPidCommands = {};

  Timer? _pollTimer;
  Timer? _keepAliveTimer;
  bool _started = false;
  bool _connected = false;
  bool _communicating = false;
  bool _userStopped = false;
  int _pollIndex = 0;

  String _status = 'OBD aguardando';
  String _rpm = '--';
  String _speed = '--';
  String _temperature = '--';
  String _load = '--';
  String _throttle = '--';
  String _moduleVoltage = '--';
  String _fuelLevel = '--';
  String _lastResponse = '--';

  static const List<String> _startupSequence = ['ATSP6', '0100'];
  static const List<String> _automaticPidSequence = [
    '010C',
    '010D',
    '0105',
    '0104',
    '0111',
    '0142',
    '012F',
  ];

  bool get connected => _connected;
  bool get communicating => _communicating;
  String get status => _status;
  String get rpm => _rpm;
  String get speed => _speed;
  String get temperature => _temperature;
  String get load => _load;
  String get throttle => _throttle;
  String get moduleVoltage => _moduleVoltage;
  String get fuelLevel => _fuelLevel;
  String get lastResponse => _lastResponse;

  Future<void> ensureStarted({bool force = false}) async {
    if (_userStopped && !force) return;
    if (_started && !force) return;
    if (_communicating) return;
    _started = true;
    if (force) _userStopped = false;

    final prefs = await SharedPreferences.getInstance();
    final address = prefs.getString('last_elm327_address');
    if (address == null || address.trim().isEmpty) {
      _status = 'Nenhum ELM salvo para conexão automática';
      notifyListeners();
      return;
    }

    final nativeConnected = await _obd.isConnected();
    if (nativeConnected) {
      _connected = true;
      _status = 'Sessao OBD mantida em segundo plano';
      _startKeepAlive();
      if (_enabledPidCommands.isEmpty) {
        _enabledPidCommands.addAll(_automaticPidSequence);
      }
      _startPolling();
      notifyListeners();
      return;
    }

    await _connectAndStart(address.trim());
  }

  Future<void> resumeExistingSession() async {
    if (_userStopped || _communicating) return;
    final nativeConnected = await _obd.isConnected();
    if (!nativeConnected) return;
    _started = true;
    _connected = true;
    _status = 'Sessao OBD ativa';
    if (_enabledPidCommands.isEmpty) {
      _enabledPidCommands.addAll(_automaticPidSequence);
    }
    _startKeepAlive();
    _startPolling();
    notifyListeners();
  }

  Future<void> stop() async {
    _userStopped = true;
    _started = false;
    _connected = false;
    _communicating = false;
    _enabledPidCommands.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    await _obd.disconnect();
    _status = 'OBD parado pelo usuário';
    notifyListeners();
  }

  Future<void> _connectAndStart(String address) async {
    if (_userStopped || _communicating) return;
    _communicating = true;
    _status = 'Conectando ELM327 em segundo plano';
    notifyListeners();

    try {
      await _obd.requestPermissions();
      await _obd.connectByAddress(address);
      _connected = true;
      _status = 'ELM327 conectado em segundo plano';
      _startKeepAlive();
      notifyListeners();
      await _runStartup();
    } catch (error) {
      _connected = false;
      _status = 'Falha ao manter ELM327: $error';
      _stopTimers();
      notifyListeners();
    } finally {
      _communicating = false;
      notifyListeners();
    }
  }

  Future<void> _runStartup() async {
    if (!_connected || _userStopped) return;
    _communicating = true;
    _enabledPidCommands.clear();
    _pollTimer?.cancel();
    _pollTimer = null;
    notifyListeners();

    var pidCheckOk = false;
    for (final command in _startupSequence) {
      if (!_connected || _userStopped) break;
      final result = await _sendOnce(command);
      if (command == '0100') {
        pidCheckOk = result != null &&
            result.success &&
            _hasPositivePidResponse(result.response);
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    if (!pidCheckOk || !_connected || _userStopped) {
      _communicating = false;
      _status = pidCheckOk
          ? 'Inicializacao OBD interrompida'
          : '0100 não confirmou PIDs';
      notifyListeners();
      return;
    }

    _status = 'Ativando PIDs em segundo plano';
    notifyListeners();
    for (final command in _automaticPidSequence) {
      if (!_connected || _userStopped) break;
      final result = await _sendOnce(command);
      if (result != null && result.success && !result.shouldStopLoop) {
        _enabledPidCommands.add(command);
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    _communicating = false;
    _status = _enabledPidCommands.isEmpty
        ? 'Sem PIDs para leitura continua'
        : 'Leitura OBD em segundo plano';
    _startPolling();
    notifyListeners();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (!_connected || _enabledPidCommands.isEmpty || _userStopped) return;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_connected || _communicating || _enabledPidCommands.isEmpty) return;
      final commands = _enabledPidCommands.toList(growable: false);
      final command = commands[_pollIndex % commands.length];
      _pollIndex++;
      await _sendOnce(command);
    });
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 18), (_) async {
      if (!_connected || _communicating || _enabledPidCommands.isNotEmpty) {
        return;
      }
      final result = await _obd.sendCommand('AT');
      if (result.success) return;
      _connected = false;
      _status = 'ELM327 caiu no keep-alive';
      _stopTimers();
      notifyListeners();
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  Future<ObdCommandResult?> _sendOnce(String command) async {
    if (!_connected) return null;
    final result = await _obd.sendCommand(command);
    final response = result.success ? result.response : (result.error ?? '');
    _lastResponse = response.isEmpty ? 'Sem resposta' : response;
    _applyResponse(command, response);
    if (!result.success &&
        response.toUpperCase().contains('ELM327 NAO CONECTADO')) {
      _connected = false;
      _status = 'ELM327 desconectado';
      _stopTimers();
    }
    if (result.shouldStopLoop) {
      _enabledPidCommands.remove(command);
    }
    notifyListeners();
    return result;
  }

  void _applyResponse(String command, String response) {
    final bytes = _hexBytes(response.toUpperCase());
    if (bytes.length < 2) return;
    switch (command) {
      case '010C':
        if (bytes.length >= 4 && bytes[0] == 0x41 && bytes[1] == 0x0C) {
          final a = bytes[2];
          final b = bytes[3];
          _rpm = (((a * 256) + b) / 4).toStringAsFixed(0);
        }
        break;
      case '010D':
        if (bytes.length >= 3 && bytes[0] == 0x41 && bytes[1] == 0x0D) {
          _speed = '${bytes[2]}';
        }
        break;
      case '0105':
        if (bytes.length >= 3 && bytes[0] == 0x41 && bytes[1] == 0x05) {
          _temperature = '${bytes[2] - 40}';
        }
        break;
      case '0104':
        if (bytes.length >= 3 && bytes[0] == 0x41 && bytes[1] == 0x04) {
          _load = (bytes[2] * 100 / 255).toStringAsFixed(1);
        }
        break;
      case '0111':
        if (bytes.length >= 3 && bytes[0] == 0x41 && bytes[1] == 0x11) {
          _throttle = (bytes[2] * 100 / 255).toStringAsFixed(1);
        }
        break;
      case '0142':
        if (bytes.length >= 4 && bytes[0] == 0x41 && bytes[1] == 0x42) {
          _moduleVoltage =
              (((bytes[2] * 256) + bytes[3]) / 1000).toStringAsFixed(1);
        }
        break;
      case '012F':
        if (bytes.length >= 3 && bytes[0] == 0x41 && bytes[1] == 0x2F) {
          _fuelLevel = (bytes[2] * 100 / 255).toStringAsFixed(1);
        }
        break;
    }
  }

  List<int> _hexBytes(String response) {
    final matches = RegExp(r'\b[0-9A-F]{2}\b').allMatches(response);
    final bytes =
        matches.map((match) => int.parse(match.group(0)!, radix: 16)).toList();
    for (var i = 0; i < bytes.length - 1; i++) {
      if (bytes[i] == 0x41) return bytes.sublist(i);
    }
    return bytes;
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
}
