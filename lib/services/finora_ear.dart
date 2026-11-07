import 'dart:async';

import 'package:flutter/services.dart';

/// Finora's own silent ear (1.31, see FinoraEar.kt): offline Russian speech
/// recognition. [listen] hears one phrase; [wakeStart] waits for «Финора»
/// while the app is on screen. Each result is a list of hypotheses: the text
/// heard with the app's vocabulary first, then the free text.
abstract final class FinoraEar {
  static const _channel = MethodChannel('finora/ear');
  static final _partials = StreamController<String>.broadcast();
  static final _wakes = StreamController<List<String>>.broadcast();
  static bool _ready = false;
  static bool? _available;

  static void _init() {
    if (_ready) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'partial':
          _partials.add(call.arguments as String? ?? '');
        case 'wake':
          _wakes.add(
            (call.arguments as List?)?.whereType<String>().toList() ?? const [],
          );
      }
      return null;
    });
  }

  /// What is being heard right now, while [listen] runs.
  static Stream<String> get partials {
    _init();
    return _partials.stream;
  }

  /// «Финора, …» heard while waiting.
  static Stream<List<String>> get wakes {
    _init();
    return _wakes.stream;
  }

  static Future<T?> _call<T>(String method, [Object? args]) async {
    if (_available == false) return null;
    _init();
    try {
      final r = await _channel.invokeMethod<T>(method, args);
      _available = true;
      return r;
    } on MissingPluginException {
      _available = false;
      return null;
    }
  }

  /// Unpacks the speech model once (a few seconds on the first launch).
  static Future<bool> prepare() async => await _call<bool>('prepare') ?? false;

  static Future<bool> micAllowed() async =>
      await _call<bool>('micAllowed') ?? false;

  static Future<bool> requestMic() async =>
      await _call<bool>('requestMic') ?? false;

  /// False in tests and where the native part is missing.
  static Future<bool> get available async {
    if (_available == null) await _call<bool>('micAllowed');
    return _available ?? false;
  }

  /// One phrase; empty when nothing was said. Throws PlatformException when
  /// the microphone or the model is unavailable.
  static Future<List<String>> listen(List<String> vocabulary) async {
    _init();
    final r = await _channel.invokeListMethod<String>('listen', {
      'vocabulary': vocabulary,
    });
    return r ?? const [];
  }

  static Future<void> wakeStart(List<String> vocabulary) =>
      _call<bool>('wakeStart', {'vocabulary': vocabulary});

  static Future<void> stop() => _call<bool>('stop');
}
