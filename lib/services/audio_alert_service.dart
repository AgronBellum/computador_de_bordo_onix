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
      while (_enabled && _pending.isNotEmpty) {
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
