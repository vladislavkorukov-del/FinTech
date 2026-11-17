import 'finance_engine.dart';
import 'models.dart';

/// The shopping list's logic, apart from its screen: reading a typed line,
/// the shop's departments, quantities, what is bought often, and the list
/// as text to send.
abstract final class Shopping {
  /// The main list's name (its id is '').
  static const mainList = 'Покупки';

  static const maxHistory = 150;

  /// Departments in the order of a usual walk through a supermarket, with
  /// the words that put an item there.
  static const sections = <(String, List<String>)>[
    (
      'Овощи и фрукты',
      [
        'яблок',
        'банан',
        'апельсин',
        'мандарин',
        'лимон',
        'груш',
        'виноград',
        'картоф',
        'картош',
        'морков',
        'лук',
        'чеснок',
        'помидор',
        'томат',
        'огур',
        'капуст',
        'перец',
        'кабач',
        'баклаж',
        'зелен',
        'укроп',
        'петруш',
        'салат',
        'авокадо',
        'ягод',
        'клубник',
        'гриб',
        'шампиньон',
        'свекл',
        'тыкв',
        'киви',
        'персик',
        'слив',
        'арбуз',
        'дын',
      ],
    ),
    (
      'Хлеб и выпечка',
      [
        'хлеб',
        'батон',
        'булк',
        'багет',
        'лаваш',
        'пирог',
        'круассан',
        'лепешк',
        'лепёшк',
        'тортилья',
      ],
    ),
    (
      'Молочное и яйца',
      [
        'молок',
        'кефир',
        'йогурт',
        'творог',
        'сметан',
        'сливк',
        'сыр',
        'масло сливоч',
        'ряженк',
        'простокваш',
        'яйц',
        'яйко',
        'айран',
      ],
    ),
    (
      'Мясо и рыба',
      [
        'мяс',
        'кур',
        'говяд',
        'свинин',
        'фарш',
        'индейк',
        'колбас',
        'сосиск',
        'ветчин',
        'бекон',
        'рыб',
        'лосос',
        'семг',
        'сёмг',
        'форел',
        'креветк',
        'тунец',
        'филе',
        'стейк',
        'котлет',
      ],
    ),
    (
      'Бакалея',
      [
        'макарон',
        'спагетти',
        'рис',
        'греч',
        'овсян',
        'мука',
        'сахар',
        'соль',
        'масло подсолн',
        'масло олив',
        'масло растит',
        'крупа',
        'чечевиц',
        'фасол',
        'горох',
        'консерв',
        'соус',
        'кетчуп',
        'майонез',
        'специ',
        'хлопья',
        'мюсли',
        'мед',
        'мёд',
        'варень',
      ],
    ),
    (
      'Сладости и снеки',
      [
        'шоколад',
        'конфет',
        'печень',
        'торт',
        'чипс',
        'орех',
        'мороженое',
        'вафл',
        'зефир',
        'пастил',
        'батончик',
        'сухарик',
      ],
    ),
    (
      'Напитки',
      [
        'вода',
        'сок',
        'чай',
        'кофе',
        'лимонад',
        'газиров',
        'кола',
        'пиво',
        'вино',
        'морс',
        'компот',
        'квас',
        'энергетик',
      ],
    ),
    ('Заморозка', ['пельмен', 'вареник', 'заморож', 'пицца', 'наггетс']),
    (
      'Бытовая химия',
      [
        'порош',
        'гель для стир',
        'средство',
        'моющ',
        'губк',
        'отбелив',
        'кондиционер для бел',
        'освежит',
        'мешки для мус',
        'пакеты для мус',
        'салфетк',
        'фольг',
        'пленк',
        'плёнк',
      ],
    ),
    (
      'Гигиена и красота',
      [
        'шампун',
        'мыло',
        'зубн',
        'паст',
        'дезодор',
        'бритв',
        'крем',
        'бумаг',
        'туалетн',
        'прокладк',
        'тампон',
        'ватн',
        'гель для душ',
      ],
    ),
    (
      'Аптека',
      [
        'таблет',
        'лекарст',
        'витамин',
        'пластыр',
        'бинт',
        'аспирин',
        'парацетамол',
        'ибупрофен',
        'капли',
        'сироп',
        'градусник',
      ],
    ),
    ('Для детей', ['подгуз', 'пюре детск', 'детск', 'смесь']),
    ('Для животных', ['корм', 'наполнит', 'лакомств для', 'кошач', 'собач']),
  ];

  static const other = 'Другое';

  /// The department for [name], or «Другое».
  static String sectionOf(String name) {
    final t = ' ${name.toLowerCase().replaceAll('ё', 'е')}';
    for (final (section, words) in sections) {
      for (final w in words) {
        if (t.contains(' ${w.replaceAll('ё', 'е')}')) return section;
      }
    }
    return other;
  }

  /// The item's department: as set, or found from its name.
  static String sectionFor(ShoppingItem item) =>
      item.section.isNotEmpty ? item.section : sectionOf(item.name);

  /// Order of departments on the screen.
  static int sectionRank(String section) {
    final i = sections.indexWhere((s) => s.$1 == section);
    return i < 0 ? sections.length : i;
  }

  /// «молоко 2 шт 89» → name «молоко», quantity «2 шт», price 89.
  static ShoppingItem parse(String id, String text, {String list = ''}) {
    var rest = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    var quantity = '';
    final q = RegExp(
      r'(?:^|\s)(\d+(?:[.,]\d+)?\s?(?:шт|кг|гр|г|л|мл|уп|пач|бут|банк)[а-яё]*\.?)(?=\s|$)',
      caseSensitive: false,
    ).firstMatch(rest);
    if (q != null) {
      quantity = q.group(1)!.trim();
      rest = '${rest.substring(0, q.start)} ${rest.substring(q.end)}'
          .trim()
          .replaceAll(RegExp(r'\s+'), ' ');
    }
    int? price;
    final p = RegExp(
      r'^(.*?\S)\s+((?:\d{1,3}(?: \d{3})+|\d+)(?:[.,]\d{1,2})?)'
      r'\s*(?:₽|р\.?|руб\.?|рублей)?$',
    ).firstMatch(rest);
    if (p != null) {
      try {
        price = FinanceEngine.parseMinor(p.group(2)!);
        rest = p.group(1)!;
      } on FormatException {
        price = null;
      }
    }
    final name = rest.isEmpty ? text.trim() : rest;
    return ShoppingItem(
      id: id,
      name: name.length > 200 ? name.substring(0, 200) : name,
      quantity: quantity,
      priceMinor: price,
      list: list,
    );
  }

  /// «2 шт» + [by] → «3 шт»; a bare number works too; never below 1.
  /// Null when the quantity has no number to change.
  static String? bump(String quantity, int by) {
    final m = RegExp(r'^(\d+)(.*)$').firstMatch(quantity.trim());
    if (quantity.trim().isEmpty) return by > 0 ? '${1 + by} шт' : null;
    if (m == null) return null;
    final n = int.parse(m.group(1)!) + by;
    return n < 1 ? null : '$n${m.group(2)}';
  }

  /// The history after buying [names]: counts up, the rarest dropped past
  /// [maxHistory].
  static Map<String, int> remember(
    Map<String, int> history,
    List<String> names,
  ) {
    final out = {...history};
    for (final n in names) {
      final key = n.trim().toLowerCase();
      if (key.isEmpty) continue;
      out[key] = (out[key] ?? 0) + 1;
    }
    if (out.length <= maxHistory) return out;
    final kept = out.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {for (final e in kept.take(maxHistory)) e.key: e.value};
  }

  /// What is often bought and is not on [list] yet, most frequent first.
  static List<String> suggestions(
    Map<String, int> history,
    Iterable<ShoppingItem> list, {
    int count = 8,
  }) {
    final on = {for (final s in list) s.name.trim().toLowerCase()};
    final ranked = history.entries.where((e) => !on.contains(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in ranked.take(count))
        e.key[0].toUpperCase() + e.key.substring(1),
    ];
  }

  /// The list as plain text to send: by department, ✓ for bought.
  static String asText(
    String title,
    List<ShoppingItem> items,
    String currency,
  ) {
    final out = StringBuffer('$title\n');
    final bySection = <String, List<ShoppingItem>>{};
    for (final s in items) {
      bySection.putIfAbsent(sectionFor(s), () => []).add(s);
    }
    final order = bySection.keys.toList()
      ..sort((a, b) => sectionRank(a).compareTo(sectionRank(b)));
    for (final section in order) {
      out.write('\n$section\n');
      for (final s in bySection[section]!) {
        out.write('${s.done ? '✓' : '•'} ${s.name}');
        if (s.quantity.isNotEmpty) out.write(' — ${s.quantity}');
        out.write('\n');
      }
    }
    return out.toString().trimRight();
  }
}
