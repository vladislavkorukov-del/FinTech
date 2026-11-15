import 'package:flutter/services.dart';

/// The sound of «Магистрали» (S21): music and effects played by the app's
/// own Android bridge; elsewhere (tests, other platforms) it stays silent.
class MagAudio {
  static const channel = MethodChannel('finora/mag_audio');
  bool _active = false, _sound = false, _closed = false;
  (bool, bool, bool)? _config;
  final _last = <String, int>{};

  Future<void> configure({
    required bool active,
    required bool music,
    required bool sound,
  }) async {
    if (_closed) return;
    _active = active;
    _sound = sound;
    final next = (active, music, sound);
    if (_config == next) return;
    _config = next;
    try {
      await channel.invokeMethod<bool>('configure', {
        'active': active,
        'music': music,
        'sound': sound,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      _config = null;
    }
  }

  /// An effect; the same one at most every [gapMs] milliseconds.
  Future<void> effect(String name, {double volume = 1, int gapMs = 90}) async {
    if (!_active || !_sound || _closed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_last[name] ?? 0) < gapMs) return;
    _last[name] = now;
    try {
      await channel.invokeMethod<void>('effect', {
        'name': name,
        'volume': volume,
      });
    } on MissingPluginException {
      return;
    } on PlatformException {
      return; // a sound never stops the game
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
