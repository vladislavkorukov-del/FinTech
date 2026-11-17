import 'package:finora/domain/models.dart';
import 'package:finora/domain/shopping.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shopping list as an app of its own: departments, quantities,
/// suggestions from what is bought often, several lists, text to send.
void main() {
  test('items find their department; unknown ones go to «Другое»', () {
    expect(Shopping.sectionOf('Молоко 3,2%'), 'Молочное и яйца');
    expect(Shopping.sectionOf('яблоки'), 'Овощи и фрукты');
    expect(Shopping.sectionOf('Хлеб бородинский'), 'Хлеб и выпечка');
    expect(Shopping.sectionOf('куриное филе'), 'Мясо и рыба');
    expect(Shopping.sectionOf('Зубная паста'), 'Гигиена и красота');
    expect(Shopping.sectionOf('корм для кошки'), 'Для животных');
    expect(Shopping.sectionOf('Лампочка'), Shopping.other);
    // Set by hand wins over the automatic one.
    expect(
      Shopping.sectionFor(
        const ShoppingItem(id: '1', name: 'Лампочка', section: 'Для дома'),
      ),
      'Для дома',
    );
  });

  test('departments follow a walk through the shop', () {
    expect(
      Shopping.sectionRank('Овощи и фрукты'),
      lessThan(Shopping.sectionRank('Бытовая химия')),
    );
    expect(
      Shopping.sectionRank(Shopping.other),
      greaterThan(Shopping.sectionRank('Аптека')),
    );
  });

  test('quantities step up and down, never below one', () {
    expect(Shopping.bump('2 шт', 1), '3 шт');
    expect(Shopping.bump('3 кг', -1), '2 кг');
    expect(Shopping.bump('1 шт', -1), isNull);
    expect(Shopping.bump('', 1), '2 шт');
    expect(Shopping.bump('пачка', 1), isNull);
  });

  test('a typed line keeps its list', () {
    final s = Shopping.parse('1', 'таблетки 2 уп 350', list: 'Аптека');
    expect(s.name, 'таблетки');
    expect(s.quantity, '2 уп');
    expect(s.priceMinor, 35000);
    expect(s.list, 'Аптека');
  });

  test('what is bought often comes back as suggestions', () {
    var h = Shopping.remember(const {}, ['Молоко', 'Хлеб']);
    h = Shopping.remember(h, ['молоко', 'Сыр']);
    expect(h['молоко'], 2);
    final s = Shopping.suggestions(h, const [
      ShoppingItem(id: '1', name: 'Хлеб'),
    ]);
    // Already on the list: not suggested; the most frequent first.
    expect(s.first, 'Молоко');
    expect(s, isNot(contains('Хлеб')));
    // The history stays small.
    final many = Shopping.remember(const {}, [
      for (var i = 0; i < 200; i++) 'item $i',
    ]);
    expect(many.length, Shopping.maxHistory);
  });

  test('the list as text, by department, bought ones ticked', () {
    final text = Shopping.asText('Покупки', const [
      ShoppingItem(id: '1', name: 'Мыло'),
      ShoppingItem(id: '2', name: 'Молоко', quantity: '2 шт', done: true),
      ShoppingItem(id: '3', name: 'Бананы'),
    ], 'RUB');
    expect(text, startsWith('Покупки'));
    expect(text, contains('✓ Молоко — 2 шт'));
    expect(text, contains('• Бананы'));
    // Fruit before dairy before hygiene.
    expect(text.indexOf('Бананы'), lessThan(text.indexOf('Молоко')));
    expect(text.indexOf('Молоко'), lessThan(text.indexOf('Мыло')));
  });

  test('lists, departments and history survive a save', () {
    const item = ShoppingItem(
      id: '1',
      name: 'Лампочка',
      list: 'Дом',
      section: 'Для дома',
    );
    expect(ShoppingItem.fromJson(item.toJson()).toJson(), item.toJson());
    const prefs = AppPreferences(
      shoppingLists: ['Дом', 'Аптека'],
      shoppingHistory: {'молоко': 4},
    );
    final back = AppPreferences.fromJson(prefs.toJson());
    expect(back.shoppingLists, ['Дом', 'Аптека']);
    expect(back.shoppingHistory, {'молоко': 4});
    // Older saves: one list, no history.
    final old = ShoppingItem.fromJson({'id': '2', 'name': 'Хлеб'});
    expect(old.list, '');
    expect(old.section, '');
  });
}
