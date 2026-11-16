import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/presentation/voice_commands.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.23: the voice orb understands commands, not only operations.
void main() {
  final now = DateTime(2026, 11, 6); // Friday
  final categories = createDemoData(now).categories;
  const accounts = [
    Account(id: 'tb', name: 'Тинькофф Black'),
    Account(id: 'cash', name: 'Наличные'),
  ];
  VoiceCommand? parse(String phrase) => VoiceCommandParser.parse(
    [phrase],
    categories: categories,
    accounts: accounts,
    now: now,
  );
  ShowEntriesCommand show(String phrase) =>
      parse(phrase)! as ShowEntriesCommand;
  String category(String? id) => categories.firstWhere((c) => c.id == id).name;

  test('operations stay operations', () {
    for (final phrase in [
      'пятерочка 450 рублей',
      'кофе 300',
      'зарплата 90 тысяч',
      'на такси 500 рублей',
      'цветы маме 2000',
      'потратил 1200 на продукты',
      'перевод на накопительный 5000',
    ]) {
      expect(parse(phrase), isNull, reason: phrase);
    }
  });

  test('expenses for a month', () {
    final c = show('Покажи расходы за июнь');
    expect(c.kind, EntryKind.expense);
    expect(c.start, DateTime(2026, 6));
    expect(c.end, DateTime(2026, 6, 30));
    expect(c.title, 'Расходы · июнь 2026');
    // A month that has not come yet this year is last year's.
    expect(show('расходы за декабрь').start, DateTime(2025, 12));
    expect(show('траты в мае 2025').start, DateTime(2025, 5));
    expect(show('покажи траты в мае 2025').end, DateTime(2025, 5, 31));
  });

  test('income for the year and other periods', () {
    final year = show('покажи доход за год');
    expect(year.kind, EntryKind.income);
    expect(year.start, DateTime(2026));
    expect(year.end, DateTime(2026, 12, 31));
    expect(year.title, 'Доходы · 2026 год');
    expect(show('доходы за прошлый год').start, DateTime(2025));
    expect(show('покажи расходы за 2024 год').end, DateTime(2024, 12, 31));
    final month = show('покажи расходы за прошлый месяц');
    expect(month.start, DateTime(2026, 10));
    expect(month.end, DateTime(2026, 10, 31));
    expect(show('покажи расходы за эту неделю').start, DateTime(2026, 11, 2));
    expect(show('покажи расходы за прошлую неделю').end, DateTime(2026, 11, 1));
    expect(show('покажи расходы за сегодня').start, now);
    expect(show('покажи расходы за вчера').start, DateTime(2026, 11, 5));
    final recent = show('покажи доходы за последние 3 месяца');
    expect(recent.start, DateTime(2026, 8, 7));
    expect(recent.end, now);
    expect(
      show('покажи расходы за последние семь дней').start,
      DateTime(2026, 10, 31),
    );
    // No period: this month, like the main screen.
    final plain = show('покажи расходы');
    expect(plain.start, DateTime(2026, 11));
    expect(plain.end, DateTime(2026, 11, 30));
    final all = show('покажи все расходы за все время');
    expect(all.start, isNull);
  });

  test('categories and accounts', () {
    final cafe = show('сколько я потратил на кафе в мае');
    expect(cafe.kind, EntryKind.expense);
    expect(category(cafe.categoryId), 'Кафе и рестораны');
    expect(cafe.start, DateTime(2026, 5));
    final food = show('покажи продукты за прошлый месяц');
    expect(category(food.categoryId), 'Продукты');
    expect(food.kind, EntryKind.expense);
    expect(food.title, 'Расходы · Продукты · прошлый месяц');
    final salary = show('покажи зарплату за год');
    expect(salary.kind, EntryKind.income);
    expect(category(salary.categoryId), 'Зарплата');
    final card = show('покажи расходы по тинькофф за июнь');
    expect(card.accountId, 'tb');
    final cash = show('покажи операции по наличным');
    expect(cash.accountId, 'cash');
    expect(cash.start, isNull);
  });

  test('screens', () {
    VoiceScreen? screen(String phrase) =>
        (parse(phrase) as OpenScreenCommand?)?.screen;
    expect(screen('открой настройки'), VoiceScreen.settings);
    expect(screen('покажи аналитику'), VoiceScreen.analytics);
    expect(screen('покажи статистику за июнь'), VoiceScreen.analytics);
    expect(screen('открой счета'), VoiceScreen.accounts);
    expect(screen('мои цели'), VoiceScreen.goals);
    expect(screen('открой бюджеты'), VoiceScreen.budgets);
    expect(screen('открой календарь'), VoiceScreen.calendar);
    expect(screen('покажи категории'), VoiceScreen.categories);
    expect(screen('покажи подписки'), VoiceScreen.recurring);
    expect(screen('открой семью'), VoiceScreen.members);
    expect(screen('на главную'), VoiceScreen.home);
    expect(screen('домой'), VoiceScreen.home);
    expect(screen('покажи операции'), VoiceScreen.operations);
    expect(screen('открой перенос счетов'), VoiceScreen.importAccounts);
    expect(parse('покажи что-нибудь интересное'), isA<UnknownCommand>());
  });

  test('a later hypothesis can be the command', () {
    final c = VoiceCommandParser.parse(
      ['покажи что то такое', 'покажи расходы за июнь'],
      categories: categories,
      now: now,
    );
    expect((c! as ShowEntriesCommand).kind, EntryKind.expense);
  });

  group('theme', () {
    ThemeCommand theme(String phrase) => parse(phrase)! as ThemeCommand;

    test('a colour keeps the one style (Release)', () {
      for (final phrase in [
        'поменяй тему на зеленую',
        'сделай тему синей',
        'серая тема',
      ]) {
        expect(VoiceCommands.pickAccent(theme(phrase), 'coffee'), 'coffee');
      }
      expect(theme('поменяй тему на зеленую').hasColor, isTrue);
    });

    test('names and modes', () {
      expect(theme('тема сансет').preset, 'sunset');
      expect(theme('включи изумрудную тему').preset, isNull);
      expect(
        VoiceCommands.pickAccent(theme('включи изумрудную тему'), 'x'),
        'coffee',
      );
      expect(theme('сделай темную тему').mode, 'dark');
      expect(theme('включи светлую тему').mode, 'light');
      expect(theme('включи светлую').mode, 'light');
      expect(theme('тема как в системе').mode, 'system');
      final both = theme('сделай светлую синюю тему');
      expect(both.mode, 'light');
      expect(both.hue, 215);
      expect(theme('поменяй тему').anyOther, isTrue);
    });
  });
}
