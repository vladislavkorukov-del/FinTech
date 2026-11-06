import 'package:flutter/services.dart';

/// System speech dialog (Finance 1.19, see VoiceInputBridge.kt). Returns the
/// recognized phrases, best first; empty when the person cancelled.
class VoiceInputService {
  const VoiceInputService();
  static const _channel = MethodChannel('finora/voice');

  Future<List<String>> listen() async {
    try {
      final heard = await _channel.invokeListMethod<String>('listen', {
        'prompt': 'Скажите, например: «Пятёрочка 450 рублей»',
      });
      return heard ?? const [];
    } on MissingPluginException {
      throw const FormatException(
        'Голосовой ввод недоступен на этом устройстве.',
      );
    } on PlatformException catch (e) {
      throw FormatException(e.message ?? 'Голосовой ввод недоступен.');
    }
  }
}
