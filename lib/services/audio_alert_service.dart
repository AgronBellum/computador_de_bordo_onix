import 'package:audioplayers/audioplayers.dart';

class AudioAlertService {
  final AudioPlayer _player = AudioPlayer();
  Future<void> _queue = Future.value();
  bool _enabled = true;

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _player.stop();
    }
  }

  Future<void> playRefuelRecalculated() => _play('renovado.mp3');
  Future<void> playSettingsSaved() => _play('sucesso.mp3');
  Future<void> playManualNumbers() => _play('numeros.mp3');
  Future<void> playLowFuel() => _play('baixo.mp3');
  Future<void> playReserveFuel() => _play('reserva.mp3');
  Future<void> playFullFuel() => _play('agora_sim.mp3');
  Future<void> playStartupCare() => _play('eu_cuido.mp3');
  Future<void> playHundredKmPosto() => _play('100_km_posto.mp3');
  Future<void> playThirtyMinuteTrip() => _play('normalmente.mp3');
  Future<void> playGpsConnected() => _play('conectado.mp3');

  Future<void> _play(String fileName) {
    if (!_enabled) return Future.value();

    _queue = _queue.then((_) => _playNow(fileName)).catchError((_) {
      return null;
    });
    return Future.value();
  }

  Future<void> _playNow(String fileName) async {
    await _player.stop();
    await _player.play(AssetSource('audio/$fileName'));
    await _player.onPlayerComplete.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
