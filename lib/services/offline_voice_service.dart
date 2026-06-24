import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

class OfflineVoiceRecognitionResult {
  const OfflineVoiceRecognitionResult({
    required this.text,
    required this.engine,
    this.partial = '',
    this.error,
  });

  final String text;
  final String partial;
  final String engine;
  final String? error;

  bool get hasText => text.trim().isNotEmpty;
}

class OfflineVoiceService {
  OfflineVoiceService._();

  static final OfflineVoiceService instance = OfflineVoiceService._();

  static const String _modelAsset = 'assets/vosk/vosk-model-small-pt-0.3.zip';
  static const int _sampleRate = 16000;

  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();

  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  Future<void>? _initializing;
  String? _activeGrammar;

  static const String _commandGrammarMode = 'command';
  static const String _wakeGrammarMode = 'wake';

  static const List<String> wakeWordGrammar = [
    'ei pin',
    'e pin',
    'hey pin',
    'oi pin',
    'ai pin',
    'ei pim',
    'e pim',
    'hey pim',
    'oi pim',
    'ai pim',
    'ei pino',
    'e pino',
    'oi pino',
    'pin',
    'pim',
    '[unk]',
  ];

  static const List<String> commandGrammar = [
    'ei pin',
    'e pin',
    'hey pin',
    'oi pin',
    'pin',
    'combustivel',
    'gasolina',
    'tanque',
    'nivel de combustivel',
    'quanto combustivel',
    'como estamos de combustivel',
    'quantos litros restantes',
    'litros restantes',
    'quantos litros ainda temos',
    'temos quantos litros',
    'autonomia',
    'alcance',
    'quantos quilometros',
    'quanto posso rodar',
    'status',
    'resumo',
    'como estamos',
    'oleo',
    'troca de oleo',
    'proxima troca',
    'filtro de oleo',
    'vamos para casa',
    'ir para casa',
    'casa',
    'vamos para posto preferido',
    'posto preferido',
    'posto favorito',
    'vamos para krolow',
    'vamos para crolo',
    'vamos para crolofe',
    'krolow',
    'krolo',
    'crolo',
    'crolofe',
    'crolof',
    'krolof',
    'vamos para guanabara',
    'guanabara',
    'supermercado guanabara',
    'vamos para central pet',
    'central pet',
    'pet shop',
    'vamos para shopping',
    'shopping',
    'vamos para baronesa',
    'museu da baronesa',
    'baronesa',
    'vamos para mercado publico',
    'mercado publico',
    'vamos para camboata',
    'camboata',
    'vamos para seu gilson',
    'seu gilson',
    'gilson',
    'vamos para sao lourenco do sul',
    'vamos para sao lourenco',
    'sao lourenco do sul',
    'sao lourenco',
    'sao lorenco',
    'sao lourenso',
    'sao lorenzo',
    'santa lorenzo',
    'santa lorenco',
    'vamos para santa vitoria do palmar',
    'santa vitoria do palmar',
    'santa vitoria',
    'vamos para veterinario do chico',
    'veterinario do chico',
    'pet vida',
    'petvida',
    '[unk]',
  ];

  Future<void> warmUp() async {
    if (_recognizer != null && _speechService != null) return;
    final active = _initializing;
    if (active != null) return active;

    final future = _initialize();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<OfflineVoiceRecognitionResult> listenForCommand({
    Duration listenFor = const Duration(seconds: 6),
    void Function(String status)? onStatus,
    void Function(String partial)? onPartial,
    bool useCommandGrammar = true,
  }) async {
    try {
      onStatus?.call('Carregando voz offline...');
      await warmUp();
      if (useCommandGrammar) await _useCommandGrammar();
      final service = _speechService;
      if (service == null) {
        return const OfflineVoiceRecognitionResult(
          text: '',
          engine: 'vosk',
          error: 'Serviço offline não iniciado',
        );
      }

      await _recognizer?.reset();

      var bestPartial = '';
      var bestResult = '';
      final done = Completer<void>();
      late final StreamSubscription<String> partialSub;
      late final StreamSubscription<String> resultSub;

      partialSub = service.onPartial().listen((raw) {
        final text = _extractText(raw, partial: true);
        if (text.isNotEmpty) {
          bestPartial = _pickBest(bestPartial, text);
          onPartial?.call(bestPartial);
        }
      });
      resultSub = service.onResult().listen((raw) {
        final text = _extractText(raw);
        if (text.isNotEmpty) {
          bestResult = _pickBest(bestResult, text);
          onPartial?.call(bestResult);
          if (!done.isCompleted) done.complete();
        }
      });

      onStatus?.call('Ouvindo offline...');
      await service.start(onRecognitionError: (error) {
        if (!done.isCompleted) done.complete();
      });

      await done.future.timeout(listenFor, onTimeout: () {});
      await service.stop().timeout(
            const Duration(milliseconds: 900),
            onTimeout: () => null,
          );
      final finalText = _extractText(
        await _recognizer?.getFinalResult().timeout(
                  const Duration(milliseconds: 700),
                  onTimeout: () => '{}',
                ) ??
            '{}',
      );
      if (finalText.isNotEmpty) {
        bestResult = _pickBest(bestResult, finalText);
        onPartial?.call(bestResult);
      }
      await _recognizer?.reset();
      await partialSub.cancel();
      await resultSub.cancel();

      final text = _pickBest(bestResult, bestPartial);
      return OfflineVoiceRecognitionResult(
        text: text,
        partial: bestPartial,
        engine: 'vosk',
      );
    } catch (error) {
      try {
        await _speechService?.stop();
      } catch (_) {}
      try {
        await _recognizer?.reset();
      } catch (_) {}
      return OfflineVoiceRecognitionResult(
        text: '',
        engine: 'vosk',
        error: error.toString(),
      );
    }
  }

  Future<bool> listenForWakeWord({
    Duration listenFor = const Duration(seconds: 4),
    void Function(String status)? onStatus,
  }) async {
    await warmUp();
    await _useWakeWordGrammar();
    final result = await listenForCommand(
      listenFor: listenFor,
      onStatus: onStatus,
      useCommandGrammar: false,
    );
    return _looksLikeWakeWord(result.text) ||
        _looksLikeWakeWord(result.partial);
  }

  bool _looksLikeWakeWord(String text) {
    final normalized = _normalizeWakeText(text);
    if (normalized.isEmpty || normalized == 'unk') return false;
    final tokens = normalized.split(' ');
    if (tokens.length == 1) return _looksLikePin(tokens.first);
    for (var i = 0; i < tokens.length - 1; i++) {
      if (_looksLikeWakePrefix(tokens[i]) && _looksLikePin(tokens[i + 1])) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeWakePrefix(String token) {
    return token == 'ei' ||
        token == 'e' ||
        token == 'hey' ||
        token == 'oi' ||
        token == 'ai';
  }

  bool _looksLikePin(String token) {
    return token == 'pin' ||
        token == 'pim' ||
        token == 'pino' ||
        token == 'bin' ||
        token == 'bim';
  }

  String _normalizeWakeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâãä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòôõö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<String>> _grammarWithSavedPhrases() async {
    final phrases = <String>{...commandGrammar};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('voice_destination_aliases');
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final value in decoded.values) {
            if (value is List) {
              for (final phrase in value) {
                final text = phrase.toString().trim().toLowerCase();
                if (text.isNotEmpty) phrases.add(text);
              }
            }
          }
        }
      }
    } catch (_) {}
    return phrases.toList(growable: false);
  }

  Future<void> reloadGrammar() async {
    await dispose();
  }

  Future<void> _initialize() async {
    final model = _model ??
        await _vosk.createModel(
          await ModelLoader().loadFromAssets(_modelAsset),
        );
    _model = model;

    final recognizer = _recognizer ??
        await _vosk.createRecognizer(
          model: model,
          sampleRate: _sampleRate,
          grammar: await _grammarWithSavedPhrases(),
        );
    _recognizer = recognizer;

    _speechService ??= await _vosk.initSpeechService(recognizer);
    await _useCommandGrammar();
  }

  Future<void> _useCommandGrammar() async {
    if (_activeGrammar == _commandGrammarMode) return;
    final recognizer = _recognizer;
    if (recognizer == null) return;
    await recognizer.setGrammar(await _grammarWithSavedPhrases());
    await recognizer.reset();
    _activeGrammar = _commandGrammarMode;
  }

  Future<void> _useWakeWordGrammar() async {
    if (_activeGrammar == _wakeGrammarMode) return;
    final recognizer = _recognizer;
    if (recognizer == null) return;
    await recognizer.setGrammar(wakeWordGrammar);
    await recognizer.reset();
    _activeGrammar = _wakeGrammarMode;
  }

  String _extractText(String raw, {bool partial = false}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final value = decoded[partial ? 'partial' : 'text'] ?? decoded['text'];
        return value?.toString().trim() ?? '';
      }
    } catch (_) {}
    return raw.trim();
  }

  String _pickBest(String current, String candidate) {
    final safeCurrent = current.trim();
    final safeCandidate = candidate.trim();
    if (safeCurrent.isEmpty) return safeCandidate;
    if (safeCandidate.isEmpty) return safeCurrent;
    if (safeCandidate.split(' ').length > safeCurrent.split(' ').length) {
      return safeCandidate;
    }
    if (safeCandidate.length > safeCurrent.length + 3) return safeCandidate;
    return safeCurrent;
  }

  Future<void> dispose() async {
    try {
      await _speechService?.stop();
    } catch (_) {}
    try {
      await _speechService?.cancel();
    } catch (_) {}
    try {
      await _recognizer?.reset();
    } catch (_) {}
    try {
      await _recognizer?.dispose();
    } catch (_) {}
    try {
      _model?.dispose();
    } catch (_) {}
    _speechService = null;
    _recognizer = null;
    _model = null;
    _activeGrammar = null;
  }
}
