import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/category_hints.dart';
import 'package:finora/domain/models.dart';
import 'package:finora/domain/service_recognizer.dart';
import 'package:finora/domain/voice_command_parser.dart';
import 'package:finora/domain/voice_entry_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finora 1.26: services said or typed in Cyrillic are recognized.
void main() {
  final categories = createDemoData(DateTime(2026, 11, 6)).categories;
  String? name(String text) => ServiceRecognizer.find(text)?.name;
  String category(String? id) => categories.firstWhere((c) => c.id == id).name;

  test('names in Cyrillic, any spelling', () {
    for (final (said, service) in [
      ('чат гпт', 'ChatGPT'),
      ('ЧатГПТ', 'ChatGPT'),
      ('Чат ГПТ подписка', 'ChatGPT'),
      ('chat gpt', 'ChatGPT'),
      ('нетфликс', 'Netflix'),
      ('нетфликс подписка', 'Netflix'),
      ('спотифай', 'Spotify'),
      ('ютуб премиум', 'YouTube Premium'),
      ('дискорд нитро', 'Discord Nitro'),
      ('айклауд', 'iCloud+'),
      ('клод', 'Claude Pro'),
      ('дипсик', 'DeepSeek'),
      ('дуолинго', 'Duolingo'),
      ('фигма', 'Figma'),
      ('плейстейшн плюс', 'PlayStation Plus'),
      ('яндекс плюс', 'Яндекс Плюс'),
      ('кинопоиск', 'Кинопоиск'),
    ]) {
      expect(name(said), service, reason: said);
    }
  });

  test('ordinary words and banks are not services', () {
    for (final text in [
      'вид на море',
      'бокс',
      'старт',
      'сбербанк',
      'перевод маме',
      'кофе',
      'такси',
      'продукты',
    ]) {
      expect(name(text), isNull, reason: text);
    }
  });

  test('voice entry: «чат гпт 2000» is ChatGPT in subscriptions', () {
    final d = VoiceEntryParser.parse('чат гпт 2000', categories: categories);
    expect(d.payee, 'ChatGPT');
    expect(d.serviceId, 'chatgpt');
    expect(d.amountMinor, 200000);
    expect(category(d.categoryId), 'Подписки');
    final n = VoiceEntryParser.parse(
      'нетфликс 799 рублей',
      categories: categories,
    );
    expect(n.serviceId, 'netflix');
  });

  test('typed payee in Cyrillic gets the category', () {
    expect(
      category(
        CategoryHints.forPayee(
          'чат гпт',
          kind: EntryKind.expense,
          categories: categories,
        ),
      ),
      'Подписки',
    );
    // A bank stays a bank (not СберПрайм).
    expect(
      CategoryHints.forPayee(
        'Сбербанк',
        kind: EntryKind.expense,
        categories: categories,
      ),
      isNull,
    );
  });

  test('voice subscription: «подписка чат гпт 2000 в месяц»', () {
    final c =
        VoiceCommandParser.parse(
              ['подписка чат гпт 2000 в месяц'],
              categories: categories,
              now: DateTime(2026, 11, 6),
            )!
            as CreateRecurringCommand;
    expect(c.name, 'ChatGPT');
    expect(c.serviceId, 'chatgpt');
    expect(c.paymentType, 'subscription');
  });

  test('«Финора, …» addresses the assistant', () {
    final c =
        VoiceCommandParser.parse(
              ['Финора, покажи расходы за июнь'],
              categories: categories,
              now: DateTime(2026, 11, 6),
            )!
            as ShowEntriesCommand;
    expect(c.kind, EntryKind.expense);
    expect(c.start, DateTime(2026, 6));
    final d = VoiceEntryParser.parse(
      'финора пятерочка 450',
      categories: categories,
    );
    expect(d.payee, 'Пятёрочка');
  });
}
