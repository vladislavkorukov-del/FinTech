import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/domain/voice_entry_parser.dart';
import 'package:finora/presentation/screens/voice_help.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora 1.33: every example in «Голосовые команды» really works.
void main() {
  final now = DateTime(2026, 11, 7);
  final demo = createDemoData(now);
  const accounts = [Account(id: 'tb', name: 'Тинькофф Black')];
  VoiceCommand? parse(String p) => VoiceCommandParser.parse(
    [p],
    categories: demo.categories,
    accounts: accounts,
    now: now,
  );

  for (final (title, _, _, examples) in VoiceHelpScreen.groups) {
    for (final e in examples) {
      if (e.contains('·')) continue;
      test('$title: $e', () {
        final c = parse(e);
        switch (title) {
          case 'Записать трату или доход':
            expect(c, isNull);
            final d = VoiceEntryParser.parse(e, categories: demo.categories);
            expect(d.amountMinor, isNotNull);
            expect(d.payee, isNotEmpty);
          case 'Показать операции':
            expect(c, isA<ShowEntriesCommand>());
          case 'Подписки и обязательные платежи':
            expect(c, isA<CreateRecurringCommand>());
            expect((c! as CreateRecurringCommand).amountMinor, isNotNull);
          case 'Мечты, счета, бюджеты, категории':
            expect(
              c,
              anyOf(
                isA<CreateGoalCommand>(),
                isA<CreateAccountCommand>(),
                isA<CreateBudgetCommand>(),
                isA<CreateCategoryCommand>(),
              ),
            );
          case 'Открыть экран':
            expect(c, isA<OpenScreenCommand>());
          case 'Тема оформления':
            expect(c, isA<ThemeCommand>());
        }
      });
    }
  }

  test('examples read right', () {
    final t2 = VoiceEntryParser.parse(
      'Т2 695 рублей',
      categories: demo.categories,
    );
    expect(t2.payee, 'Т2');
    expect(t2.amountMinor, 69500);
    final taxi = VoiceEntryParser.parse(
      'Такси 1 300 рублей 20 копеек',
      categories: demo.categories,
    );
    expect(taxi.amountMinor, 130020);
    final gpt = VoiceEntryParser.parse(
      'Чат ГПТ 2000',
      categories: demo.categories,
    );
    expect(gpt.payee, 'ChatGPT');
  });
}
