import 'dart:async';

import 'package:flutter/services.dart';

/// Finora outside the app screen (1.27, see FinoraBridge.kt): widgets, the
/// Quick Settings tile and shade controls send actions in; the app sends
/// widget data and the shade text out; «Финора» heard while the app is open
/// arrives as [wakes].
abstract final class FinoraSystem {
  static const _channel = MethodChannel('finora/system');
  static final _actions = StreamController<String>.broadcast();
  static final _wakes = StreamController<List<String>>.broadcast();
  static bool _ready = false;
  static bool? _available;

  /// voice, expense, income, scan, payments or open.
  static Stream<String> get actions {
    _init();
    return _actions.stream;
  }

  static Stream<List<String>> get wakes {
    _init();
    return _wakes.stream;
  }

  static void _init() {
    if (_ready) return;
    _ready = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'action':
          final action = call.arguments as String?;
          if (action == null || !_actions.hasListener) return false;
          _actions.add(action);
          return true;
        case 'wake':
          final heard = (call.arguments as List?)?.whereType<String>().toList();
          _wakes.add(heard ?? const []);
          return true;
      }
      return null;
    });
  }

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (_available == false) return null;
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      _available = true;
      return result;
    } on MissingPluginException {
      _available = false;
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// False in tests and on platforms without the bridge.
  static Future<bool> get available async {
    if (_available == null) await _call<bool>('micAllowed');
    return _available ?? false;
  }

  /// An action that opened the app (from a widget, the tile or the shade).
  static Future<String?> takeAction() {
    _init();
    return _call<String>('takeAction');
  }

  static Future<void> updateWidgets(Map<String, String> data) =>
      _call<bool>('updateWidgets', data);

  static Future<void> shade({
    required bool on,
    String title = 'Финора',
    String text = '',
  }) => _call<bool>('shade', {'on': on, 'title': title, 'text': text});

  static Future<bool> requestMic() async =>
      await _call<bool>('requestMic') ?? false;

  static Future<bool> wakeStart() async {
    _init();
    return await _call<bool>('wakeStart') ?? false;
  }

  static Future<void> wakeStop() => _call<bool>('wakeStop');
}
