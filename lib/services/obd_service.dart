import 'dart:async';

import 'package:flutter/services.dart';

class ObdBluetoothDevice {
  const ObdBluetoothDevice({
    required this.name,
    required this.address,
    this.paired = false,
    this.bondState = 10,
    this.type = 0,
    this.elmCandidate = false,
    this.transport = 'CLASSIC',
    this.rssi,
  });

  final String name;
  final String address;
  final bool paired;
  final int bondState;
  final int type;
  final bool elmCandidate;
  final String transport;
  final int? rssi;

  String get bondLabel {
    switch (bondState) {
      case 12:
        return 'pareado';
      case 11:
        return 'pareando';
      default:
        return 'novo';
    }
  }

  factory ObdBluetoothDevice.fromMap(Map<dynamic, dynamic> map) {
    return ObdBluetoothDevice(
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? map['name'] as String
          : 'ELM327',
      address: map['address'] as String,
      paired: map['paired'] == true || map['paired'] == 'true',
      bondState: (map['bondState'] as num?)?.toInt() ?? 10,
      type: (map['type'] as num?)?.toInt() ?? 0,
      transport: (map['transport'] as String?) ?? 'CLASSIC',
      rssi: (map['rssi'] as num?)?.toInt(),
      elmCandidate: map['elmCandidate'] == true ||
          map['elmCandidate'] == 'true' ||
          ((map['name'] as String?) ?? '').toUpperCase().contains('ELM') ||
          ((map['name'] as String?) ?? '').toUpperCase().contains('OBD'),
    );
  }
}

class ObdCommandResult {
  const ObdCommandResult({
    required this.command,
    required this.response,
    required this.success,
    this.error,
  });

  final String command;
  final String response;
  final bool success;
  final String? error;

  bool get shouldStopLoop {
    final text = '${response.toUpperCase()} ${error?.toUpperCase() ?? ''}';
    return text.contains('ERROR') ||
        text.contains('NO DATA') ||
        text.contains('STOPPED') ||
        text.contains('?') ||
        text.contains('TIMEOUT');
  }
}

class ObdService {
  static const MethodChannel _channel = MethodChannel('onyx_gps/obd_bluetooth');

  static bool _busy = false;
  bool _stopped = false;

  Future<bool> requestPermissions() async {
    final granted = await _channel.invokeMethod<bool>('requestPermissions');
    return granted ?? false;
  }

  Future<Map<String, dynamic>> bluetoothStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'bluetoothStatus',
    );
    return Map<String, dynamic>.from(raw ?? const {});
  }

  Future<bool> requestEnableBluetooth() async {
    final enabled = await _channel.invokeMethod<bool>('requestEnableBluetooth');
    return enabled ?? false;
  }

  Future<List<ObdBluetoothDevice>> listPairedDevices() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listPairedDevices');
    return (raw ?? const [])
        .map(
            (item) => ObdBluetoothDevice.fromMap(item as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  Future<List<ObdBluetoothDevice>> scanDevices({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      'scanDevices',
      {'timeoutMs': timeout.inMilliseconds},
    );
    return (raw ?? const [])
        .map(
            (item) => ObdBluetoothDevice.fromMap(item as Map<dynamic, dynamic>))
        .toList(growable: false);
  }

  Future<String> connect(ObdBluetoothDevice device) async {
    _stopped = false;
    final name = await _channel.invokeMethod<String>(
      'connect',
      {'address': device.address},
    );
    return name ?? device.name;
  }

  Future<String> connectByAddress(String address) async {
    _stopped = false;
    final name = await _channel.invokeMethod<String>(
      'connect',
      {'address': address.trim().toUpperCase()},
    );
    return name ?? address;
  }

  Future<ObdBluetoothDevice> pairDevice(
    ObdBluetoothDevice device, {
    String? pin,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pairDevice',
      {
        'address': device.address,
        if (pin != null && pin.trim().isNotEmpty) 'pin': pin.trim(),
      },
    );
    return raw == null ? device : ObdBluetoothDevice.fromMap(raw);
  }

  Future<ObdBluetoothDevice> pairDeviceByAddress(
    String address, {
    String? pin,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'pairDevice',
      {
        'address': address.trim().toUpperCase(),
        if (pin != null && pin.trim().isNotEmpty) 'pin': pin.trim(),
      },
    );
    return raw == null
        ? ObdBluetoothDevice(
            name: 'ELM327', address: address.trim().toUpperCase())
        : ObdBluetoothDevice.fromMap(raw);
  }

  Future<void> cancelScan() async {
    await _channel.invokeMethod<bool>('cancelScan');
  }

  Future<void> disconnect() async {
    _stopped = true;
    await _channel.invokeMethod<bool>('disconnect');
  }

  Future<bool> isConnected() async {
    final connected = await _channel.invokeMethod<bool>('isConnected');
    final value = connected ?? false;
    if (value) _stopped = false;
    return value;
  }

  Future<void> forgetDevice(ObdBluetoothDevice device) async {
    await _channel.invokeMethod<bool>(
      'forgetDevice',
      {'address': device.address},
    );
  }

  Future<ObdCommandResult> sendCommand(
    String command, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_stopped) {
      return ObdCommandResult(
        command: command,
        response: '',
        success: false,
        error: 'Comunicação parada',
      );
    }
    if (_busy) {
      return ObdCommandResult(
        command: command,
        response: '',
        success: false,
        error: 'Comando em andamento',
      );
    }

    _busy = true;
    try {
      final response = await _channel.invokeMethod<String>(
        'sendCommand',
        {
          'command': command,
          'timeoutMs': timeout.inMilliseconds,
        },
      );
      return ObdCommandResult(
        command: command,
        response: _cleanResponse(response ?? ''),
        success: true,
      );
    } on PlatformException catch (error) {
      return ObdCommandResult(
        command: command,
        response: '',
        success: false,
        error: error.message ?? error.code,
      );
    } finally {
      _busy = false;
    }
  }

  String _cleanResponse(String value) {
    return value
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }
}
