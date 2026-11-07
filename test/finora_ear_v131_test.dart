import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/domain/voice_entry_parser.dart';
import 'package:finora/presentation/finora_vocabulary.dart';
import 'package:finora/services/finora_ear.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora 1.31: her own silent ear (Vosk). The model hears «Финора» as
/// «фигура» and gives numbers as words; the parsers take both.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 11, 7);
  final demo = createDemoData(now);

  test('«фигура, покажи расходы за июнь» is a command', () {
    final c =
        VoiceCommandParser.parse(
              ['фигура покажи расходы за июнь', 'федора подожди'],
              categories: demo.categories,
              now: now,
            )!
            as ShowEntriesCommand;
    expect(c.kind, EntryKind.expense);
    expect(c.start, DateTime(2026, 6));
  });

  test('numbers as words from the ear', () {
    final d = VoiceEntryParser.parseBest([
      'фигура такси пятьсот рублей',
      'такси пятьсот рублей',
    ], categories: demo.categories);
    expect(d.amountMinor, 50000);
    expect(d.payee, 'Такси');
    final big = VoiceEntryParser.parseBest([
      'зарплата девяносто тысяч',
    ], categories: demo.categories);
    expect(big.amountMinor, 9000000);
  });

  test('vocabulary: commands, numbers, own categories, stores', () {
    final v = FinoraVocabulary.build(demo);
    for (final w in [
      'фигура',
      'покажи',
      'расходы',
      'июнь',
      'четыреста',
      'тысяч',
      'продукты',
      'наличные',
      'пятерочка',
      'зеленую',
    ]) {
      expect(v, contains(w), reason: w);
    }
    expect(v.every((w) => w == w.toLowerCase()), isTrue);
  });

  test('the old system-recognizer setting is not carried over', () {
    final p = AppPreferences.fromJson({
      ...const AppPreferences().toJson(),
      'wakeWord': true,
    });
    expect(p.wakeWord, isFalse);
    final on = const AppPreferences().copyWith(wakeWord: true);
    expect(AppPreferences.fromJson(on.toJson()).wakeWord, isTrue);
    expect(on.quietVoice, isFalse);
  });

  test('without the native ear (tests), it reports unavailable', () async {
    expect(await FinoraEar.available, isFalse);
  });
}
