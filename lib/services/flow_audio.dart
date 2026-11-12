import 'package:flutter/services.dart';

import '../presentation/haptics.dart';

/// Per-level bridge: no background service, account, network or audio package.
class FlowAudio {
  static const channel = MethodChannel('finora/flow_audio');
  bool _active = false, _sound = false, _haptics = false, _disposed = false;
  (bool, bool, bool, bool)? _configuration;

  Future<bool> configure({
    required bool active,
    required bool music,
    required bool sound,
    required bool haptics,
  }) async {
    if (_disposed) return false;
    _active = active;
    _sound = sound;
    _haptics = haptics;
    final next = (active, music, sound, haptics);
    if (_configuration == next) return true;
    _configuration = next;
    try {
      return await channel.invokeMethod<bool>('configure', {
            'active': active,
            'music': music,
            'sound': sound,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      _configuration = null;
      return false;
    }
  }

  Future<void> effect({bool success = false}) async {
    if (!_active || _disposed) return;
    if (_haptics) Haptics.light();
    if (!_sound) return;
    try {
      await channel.invokeMethod<void>('effect', {
        'name': success ? 'chime' : 'tap',
      });
    } on MissingPluginException {
      // Other platforms and widget tests do not own Android audio devices.
    } on PlatformException {
      // Sound failure never cancels a committed game move.
    }
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    try {
      await channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
