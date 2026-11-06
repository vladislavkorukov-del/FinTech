import 'package:finora/data/demo_data.dart';
import 'package:finora/domain/bank_statement_parser.dart';
import 'package:finora/domain/category_hints.dart';
import 'package:finora/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finance 1.13: operations from a screenshot get their category from the
/// store or service they were paid to (Пятёрочка → Продукты, Whoosh →
/// Транспорт), unless the person already chose one for that payee.
void main() {
  final categories = createDemoData(DateTime(2026, 11, 6)).categories;
  String? name(String? id) =>
      categories.where((c) => c.id == id).map((c) => c.name).firstOrNull;
  String? hint(String payee, {List<Category>? own}) => name(
    CategoryHints.forPayee(
      payee,
      kind: EntryKind.expense,
      categories: own ?? categories,
    ),
  );

  test('stores map to the default categories', () {
    const expected = {
      'Пятёрочка': 'Продукты',
      'PYATEROCHKA 5521 MOSCOW': 'Продукты',
      'MAGNIT MM KOSTROMA': 'Продукты',
      'ВкусВилл': 'Продукты',
      'Самокат': 'Продукты',
      'Whoosh': 'Транспорт',
      'WHOOSH': 'Транспорт',
      'Юрент': 'Транспорт',
      'Яндекс Go': 'Транспорт',
      'YANDEX*GO': 'Транспорт',
      'Делимобиль': 'Транспорт',
      'Московское метро': 'Транспорт',
      'Вкусно и точка': 'Кафе и рестораны',
      'Додо Пицца': 'Кафе и рестораны',
      'Яндекс Еда': 'Кафе и рестораны',
      'Cofix': 'Кафе и рестораны',
      'Аптека Апрель': 'Аптека',
      'Горздрав': 'Аптека',
      'Инвитро': 'Здоровье',
      'РЖД': 'Путешествия',
      'Аэрофлот': 'Путешествия',
      'Авиасейлс': 'Путешествия',
      'Роснефть': 'Автомобиль',
      'Газпромнефть': 'Автомобиль',
      'OZON.RU': 'Покупки',
      'WILDBERRIES 12345': 'Покупки',
      'Lamoda': 'Одежда',
      'Детский мир': 'Дети',
      'DNS-SHOP': 'Покупки',
      'Золотое Яблоко': 'Покупки',
      'ЦИАН': 'Жильё',
      'КАРО': 'Развлечения',
      'World Class': 'Здоровье',
      'Spotify': 'Подписки',
      'Яндекс Плюс': 'Подписки',
    };
    for (final MapEntry(key: payee, value: category) in expected.entries) {
      expect(hint(payee), category, reason: payee);
    }
  });

  test('unknown payees, income and transfers get no guess', () {
    expect(hint('Иван Петров'), isNull);
    expect(hint('Магнитогорский рынок'), isNull);
    // A parent brand alone is not its subscription (Сбербанк ≠ СберПрайм).
    expect(hint('Сбербанк'), isNull);
    expect(hint('СберПрайм'), 'Подписки');
    for (final kind in [EntryKind.income, EntryKind.transfer, null]) {
      expect(
        CategoryHints.forPayee('Пятёрочка', kind: kind, categories: categories),
        isNull,
      );
    }
  });

  test('renamed categories still match; two candidates are not guessed', () {
    const own = [
      Category(id: 'eat', name: 'Еда', kind: EntryKind.expense),
      Category(id: 'ride', name: 'Такси и самокаты', kind: EntryKind.expense),
    ];
    expect(
      CategoryHints.forPayee(
        'Пятёрочка',
        kind: EntryKind.expense,
        categories: own,
      ),
      'eat',
    );
    expect(
      CategoryHints.forPayee(
        'Whoosh',
        kind: EntryKind.expense,
        categories: own,
      ),
      'ride',
    );
    const twice = [
      Category(id: 'a', name: 'Продукты дом', kind: EntryKind.expense),
      Category(id: 'b', name: 'Продукты дача', kind: EntryKind.expense),
    ];
    expect(
      CategoryHints.forPayee(
        'Магнит',
        kind: EntryKind.expense,
        categories: twice,
      ),
      isNull,
    );
    const archived = [
      Category(
        id: 'old',
        name: 'Продукты',
        kind: EntryKind.expense,
        archived: true,
      ),
    ];
    expect(
      CategoryHints.forPayee(
        'Магнит',
        kind: EntryKind.expense,
        categories: archived,
      ),
      isNull,
    );
  });

  test('a bank screenshot fills categories; the person\'s own choice wins', () {
    const text = '''История операций
5 ноября 2026
Пятёрочка -1 250,50 ₽
Whoosh -189 ₽
Вкусно и точка -420 ₽
Аптека Апрель -560 ₽
Иван П. -1 000 ₽''';
    final doc = BankStatementParser.parse(
      text,
      categories: categories,
      now: DateTime(2026, 11, 5, 18),
    );
    expect(doc.drafts.map((d) => d.payee).take(4), [
      'Пятёрочка',
      'Whoosh',
      'Вкусно и точка',
      'Аптека Апрель',
    ]);
    expect(doc.drafts.map((d) => name(d.categoryId)).take(4), [
      'Продукты',
      'Транспорт',
      'Кафе и рестораны',
      'Аптека',
    ]);
    // Earlier the person put Whoosh under «Развлечения»: that is kept.
    final fun = categories.firstWhere((c) => c.name == 'Развлечения');
    final again = BankStatementParser.parse(
      text,
      categories: categories,
      now: DateTime(2026, 11, 5, 18),
      history: [
        FinanceEntry(
          id: 'old',
          kind: EntryKind.expense,
          amountMinor: 15000,
          currency: 'RUB',
          accountId: 'card',
          categoryId: fun.id,
          date: DateTime(2026, 10, 1),
          payee: 'WHOOSH',
        ),
      ],
    );
    expect(
      again.drafts.firstWhere((d) => d.payee == 'Whoosh').categoryId,
      fun.id,
    );
  });
}
