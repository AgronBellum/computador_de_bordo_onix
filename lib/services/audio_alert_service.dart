import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

class AudioAlertService {
  final AudioPlayer _player = AudioPlayer();
  final ListQueue<String> _pending = ListQueue<String>();
  final Random _random = Random();

  Completer<void>? _currentPlaybackDone;
  bool _enabled = true;
  bool _isDraining = false;

  void setEnabled(bool enabled) {
    _enabled = enabled;

    if (!enabled) {
      _pending.clear();
      _finishCurrentPlayback();
      _player.stop();
    }
  }

  Future<void> playRefuelRecalculated() =>
      _playRandom(['renovado.mp3', 'recalculada.mp3']);
  Future<void> playSettingsSaved() => _play('sucesso.mp3');
  Future<void> playManualNumbers() => _play('numeros.mp3');
  Future<void> playLowFuel() => _play('baixo.mp3');
  Future<void> playReserveFuel() => _play('reserva.mp3');
  Future<void> playFullFuel() => _play('agora_sim.mp3');
  Future<void> playStartupCare() => _play('eu_cuido.mp3');
  Future<void> playHundredKmPosto() => _play('100_km_posto.mp3');
  Future<void> playThirtyMinuteTrip() => _play('normalmente.mp3');
  Future<void> playGpsConnected() => _play('conectado.mp3');
  Future<void> playCityMode() => _play('cidade.mp3');
  Future<void> playTripMode() => _play('viagem.mp3');

  Future<void> playAssistantFuelSummary({
    required int fuelPercent,
    required int autonomyKm,
  }) {
    return _playSequence([
      'assistente/estou_com.mp3',
      ..._numberFiles(fuelPercent),
      'assistente/porcento_de.mp3',
      'assistente/combustivel.mp3',
      'assistente/autonomia.mp3',
      ..._numberFiles(autonomyKm),
      'assistente/quilometros.mp3',
    ], force: true);
  }

  Future<void> playAssistantAutonomy(int autonomyKm) {
    return _playSequence([
      'assistente/autonomia.mp3',
      ..._numberFiles(autonomyKm),
      'assistente/quilometros.mp3',
    ], force: true);
  }

  Future<void> playAssistantFuelOnly(int fuelPercent) {
    return _playSequence([
      'assistente/estou_com.mp3',
      ..._numberFiles(fuelPercent),
      'assistente/porcento_de.mp3',
      'assistente/combustivel.mp3',
    ], force: true);
  }

  Future<void> playAssistantOilStatus({
    required int? remainingKm,
    required bool due,
  }) {
    if (remainingKm == null) {
      return _playSequence([
        'assistente/oleo.mp3',
        'assistente/proxima_troca.mp3',
      ], force: true);
    }

    if (due || remainingKm <= 0) {
      return _playSequence([
        'assistente/atencao.mp3',
        'assistente/troca_de_oleo.mp3',
      ], force: true);
    }

    return _playSequence([
      'assistente/faltam.mp3',
      ..._numberFiles(remainingKm),
      'assistente/quilometros.mp3',
      'assistente/proxima_troca.mp3',
      'assistente/oleo.mp3',
    ], force: true);
  }

  Future<void> playStartupGreeting() {
    final hour = DateTime.now().hour;

    if (hour >= 4 && hour <= 12) {
      return _playRandom(['bom_dia.mp3', 'bom_dia1.mp3']);
    }

    if (hour >= 13 && hour <= 17) {
      return _playRandom(['boa_tarde.mp3', 'boa_tarde1.mp3']);
    }

    return _playRandom(['boa_noite.mp3', 'boa_noite1.mp3', 'cuidado.mp3']);
  }

  Future<void> _playRandom(List<String> fileNames) {
    final index = _random.nextInt(fileNames.length);
    return _play(fileNames[index]);
  }

  Future<void> _playSequence(List<String> fileNames, {bool force = false}) {
    if (!_enabled && !force) return Future.value();

    for (final fileName in fileNames) {
      _pending.add(fileName);
    }
    unawaited(_drainQueue());
    return Future.value();
  }

  List<String> _numberFiles(int value) {
    final safe = value.clamp(0, 999999);
    if (safe <= 99) return ['separados/$safe.mp3'];
    if (safe == 100) return const ['separados/100.mp3'];
    if (safe < 200) {
      return ['separados/cento_e.mp3', ..._numberFiles(safe - 100)];
    }
    if (safe < 1000) {
      final hundred = (safe ~/ 100) * 100;
      final rest = safe % 100;
      if (rest == 0) return ['separados/$hundred.mp3'];
      return [
        'separados/$hundred.mp3',
        'assistente/e.mp3',
        ..._numberFiles(rest),
      ];
    }

    final thousands = safe ~/ 1000;
    final rest = safe % 1000;
    return [
      if (thousands > 1) ..._numberFiles(thousands),
      'separados/1000.mp3',
      if (rest > 0) ...['assistente/e.mp3', ..._numberFiles(rest)],
    ];
  }

  Future<void> _play(String fileName) {
    if (!_enabled) return Future.value();

    _pending.add(fileName);
    unawaited(_drainQueue());
    return Future.value();
  }

  Future<void> _drainQueue() async {
    if (_isDraining) return;

    _isDraining = true;

    try {
      while (_pending.isNotEmpty) {
        final fileName = _pending.removeFirst();
        await _playNow(fileName);
      }
    } finally {
      _isDraining = false;
    }
  }

  Future<void> _playNow(String fileName) async {
    final done = Completer<void>();
    _currentPlaybackDone = done;

    late final StreamSubscription<void> completeSub;
    completeSub = _player.onPlayerComplete.listen((_) {
      _finishCurrentPlayback();
    });

    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setVolume(1);
      await _player.play(AssetSource('audio/$fileName'));

      await done.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {},
      );
    } catch (_) {
      _finishCurrentPlayback();
    } finally {
      await completeSub.cancel();

      if (_currentPlaybackDone == done) {
        _currentPlaybackDone = null;
      }
    }
  }

  void _finishCurrentPlayback() {
    final done = _currentPlaybackDone;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  Future<void> dispose() async {
    _pending.clear();
    _finishCurrentPlayback();
    await _player.dispose();
  }
}
