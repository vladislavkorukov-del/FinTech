import 'models.dart';
import 'service_catalog.dart';
import 'service_recognizer.dart';

/// Category for a known payee (Finance 1.13): Пятёрочка → «Продукты»,
/// Whoosh → «Транспорт», a subscription → «Подписки».
///
/// The payee is looked up in the store and subscription catalog (the same
/// matching that shows its logo, so «MAGNIT MM KOSTROMA» is Магнит). Each
/// kind of place lists the category names it fits, most specific first;
/// a name rule is used only when exactly one of the person's own active
/// categories matches it, so renamed categories («Еда», «Такси») still work
/// and nothing is guessed between two candidates.
abstract final class CategoryHints {
  static const _groceries = [r'продукт|супермаркет|grocer|питани|^еда$'];
  static const _food = [
    r'кафе|ресторан|фастфуд|еда вне|кофе|cafe|restaurant|fast ?food',
  ];
  static const _shopping = [r'покупк|шопинг|маркетплейс|товар|shopping'];
  static const _clothes = [r'одежд|обув|clothes|apparel', ..._shopping];
  static const _beauty = [r'красот|космет|уход|beauty', ..._shopping];
  static const _pharmacy = [
    r'аптек|лекарств|pharm',
    r'здоров|медиц|врач|health|medic',
  ];
  static const _health = [r'здоров|медиц|анализ|health|medic', ..._pharmacy];
  static const _transport = [
    r'транспорт|такси|самокат|каршеринг|проезд|transport|taxi',
  ];
  static const _travel = [
    r'путешеств|отпуск|поездк|travel|trip',
    ..._transport,
  ];
  static const _car = [
    r'авто|машин|топлив|бензин|азс|\bcar\b|fuel',
    ..._transport,
  ];
  static const _home = [r'дом|ремонт|мебел|жиль|home', ..._shopping];
  static const _tech = [r'техник|электрон|гаджет|electronic', ..._shopping];
  static const _kids = [r'дет|ребен|kids|child', ..._shopping];
  static const _books = [r'книг|образован|books|education', ..._shopping];
  static const _sport = [
    r'(^|[^а-я])спорт|фитнес|sport|fitness',
    r'здоров|health',
  ];
  static const _fun = [r'развлеч|кино|досуг|отдых|entertain|cinema'];
  static const _housing = [r'жиль|аренд|недвиж|квартир|rent|housing'];
  static const _delivery = [r'почт|доставк|посылк|услуг|delivery|post'];
  static const _services = [r'услуг|сервис|services'];
  static const _subscriptions = [r'подписк|subscription'];

  static const _byGroup = <String, List<String>>{
    'groceries': _groceries,
    'food': _food,
    'shops': _shopping,
    'beauty': _beauty,
    'pharmacy': _pharmacy,
    'transport': _transport,
    'travel': _travel,
    'fuel': _car,
    'services': _services,
  };

  /// Places whose own business differs from their catalog group.
  static const _byStore = <String, List<String>>{
    'store_lamoda': _clothes,
    'store_gloria_jeans': _clothes,
    'store_familia': _clothes,
    'store_sportmaster': [r'(^|[^а-я])спорт|sport', ..._clothes],
    'store_lemana_pro': _home,
    'store_petrovich': _home,
    'store_hoff': _home,
    'store_mvideo': _tech,
    'store_dns': _tech,
    'store_citilink': _tech,
    'store_detmir': _kids,
    'store_chitai_gorod': _books,
    'store_invitro': _health,
    'store_gemotest': _health,
    'store_mosmetro': _transport,
    'store_aeroexpress': _transport,
    'store_pochta': _delivery,
    'store_cdek': _delivery,
    'store_cian': _housing,
    'store_profi': _services,
    'store_world_class': _sport,
    'store_ddx': _sport,
    'store_karo': _fun,
  };

  /// Category id for an expense with [payee], or null when the payee is not
  /// a known place or no single category of the person fits it.
  static String? forPayee(
    String? payee, {
    required EntryKind? kind,
    required List<Category> categories,
  }) {
    if (payee == null || kind != EntryKind.expense) return null;
    // 1.26: names in Cyrillic too («чат гпт» → ChatGPT).
    final spoken = ServiceRecognizer.find(payee);
    final place = ServiceCatalog.byName(payee) ?? spoken;
    if (place == null || place.group == 'banks') return null;
    final store = place.id.startsWith('store_');
    // A subscription counts only when the payee names the subscription
    // itself (Spotify, Яндекс Плюс), not just its parent brand: «Сбербанк» on
    // a bank screenshot is usually a transfer, not СберПрайм.
    if (!store &&
        spoken?.id != place.id &&
        !_loose(payee).contains(_loose(place.name))) {
      return null;
    }
    final rules = store
        ? _byStore[place.id] ?? _byGroup[place.group]
        : _subscriptions;
    if (rules == null) return null;
    final active = categories
        .where((c) => c.kind == kind && !c.archived)
        .toList();
    for (final rule in rules) {
      final pattern = RegExp(rule, caseSensitive: false);
      final matches = active.where((c) {
        final name = c.name.toLowerCase().replaceAll('ё', 'е').trim();
        final subs = c.subcategories.join(' ').toLowerCase();
        return pattern.hasMatch(name) || pattern.hasMatch(subs);
      }).toList();
      if (matches.length == 1) return matches.single.id;
    }
    return null;
  }

  static String _loose(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}
