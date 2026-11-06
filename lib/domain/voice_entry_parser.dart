import 'models.dart';
import 'receipt_parser.dart';
import 'service_catalog.dart';
import 'store_catalog.dart';

/// What a spoken phrase becomes (Finance 1.19). Always reviewed in the entry
/// editor before anything is saved.
class VoiceDraft {
  const VoiceDraft({
    required this.heard,
    required this.kind,
    this.amountMinor,
    this.payee = '',
    this.categoryId,
    this.serviceId,
    this.date,
  });

  /// The phrase as recognized.
  final String heard;
  final EntryKind kind;
  final int? amountMinor;
  final String payee;
  final String? categoryId;

  /// Store or service the payee was recognized as (shows its logo).
  final String? serviceId;
  final DateTime? date;
}

/// Turns a spoken Russian phrase into an operation draft: «Пятёрочка 450
/// рублей», «потратил 1 250 в магните вчера», «зарплата 90 тысяч», «кофе 250».
abstract final class VoiceEntryParser {
  /// The first hypothesis with an amount wins; otherwise the first one.
  static VoiceDraft parseBest(
    List<String> hypotheses, {
    required List<Category> categories,
    List<FinanceEntry> history = const [],
    DateTime? now,
  }) {
    final drafts = [
      for (final h in hypotheses)
        parse(h, categories: categories, history: history, now: now),
    ];
    return drafts.firstWhere(
      (d) => d.amountMinor != null,
      orElse: () => drafts.isEmpty
          ? const VoiceDraft(heard: '', kind: EntryKind.expense)
          : drafts.first,
    );
  }

  static VoiceDraft parse(
    String heard, {
    required List<Category> categories,
    List<FinanceEntry> history = const [],
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    var text = _norm(heard);

    // Income or expense.
    final kind = _income.hasMatch(text) ? EntryKind.income : EntryKind.expense;

    // Date words.
    DateTime? date;
    final today = DateTime(
      clock.year,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
    );
    if (RegExp(r'(^|\s)позавчера(\s|$)').hasMatch(text)) {
      date = today.subtract(const Duration(days: 2));
    } else if (RegExp(r'(^|\s)вчера(\s|$)').hasMatch(text)) {
      date = today.subtract(const Duration(days: 1));
    }

    // Amount.
    final amount = _amount(text);
    if (amount != null) text = text.replaceRange(amount.start, amount.end, ' ');

    // What is left names the payee (after service and filler words). A
    // store is looked for first, while «и» of «Вкусно и точка» is still there.
    final rest = text
        .replaceAll(_currency, ' ')
        .replaceAll(_dateWords, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words = rest
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_filler.contains(w))
        .where((w) => !_kindWords.hasMatch(w) || kind == EntryKind.expense)
        .toList();
    final phrase = words.join(' ');

    final store = _store(rest);
    final payee = store?.name ?? _capitalize(phrase);
    String? category;
    if (payee.isNotEmpty) {
      category = ReceiptParser.suggestCategory(
        payee: payee,
        text: '',
        kind: kind,
        categories: categories,
        history: history,
      );
    }
    category ??= _named(phrase, kind, categories);
    category ??= _byWords('$phrase ${_norm(heard)}', kind, categories);
    return VoiceDraft(
      heard: heard.trim(),
      kind: kind,
      amountMinor: amount?.minor,
      payee: payee,
      categoryId: category,
      serviceId: store?.id,
      date: date,
    );
  }

  static String _norm(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[«»"“”!?;:]'), ' ')
      .replaceAll(RegExp(r'(?<=\d)\s+(?=\d{3}(\D|$))'), '') // 1 250 → 1250
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static final _income = RegExp(
    r'(^|\s)(доход[а-яёa-z]*|зарплат[а-яёa-z]*|зп|получил[а-яёa-z]*|пришл[оаи]|поступил[а-яёa-z]*|поступлени[а-яёa-z]*|'
    r'заработал[а-яёa-z]*|преми[яюи]|аванс[а-яёa-z]*|к[еэ]шб[еэ]к[а-яёa-z]*|возврат[а-яёa-z]*|вернули|'
    r'подработк[а-яёa-z]*|скинули|перевели мне)(\s|$)',
  );
  static final _kindWords = RegExp(
    r'^(доход[а-яёa-z]*|получил[а-яёa-z]*|пришл[оаи]|поступил[а-яёa-z]*|поступлени[а-яёa-z]*|заработал[а-яёa-z]*|'
    r'вернули|скинули|расход[а-яёa-z]*|потратил[а-яёa-z]*|купил[а-яёa-z]*|заплатил[а-яёa-z]*|оплатил[а-яёa-z]*|'
    r'оплата|траты?|списани[а-яёa-z]*)$',
  );
  static final _currency = RegExp(
    r'(^|\s)(рубл[а-яёa-z]*|руб|р|₽|копе[а-яёa-z]*|коп|тысяч[а-яёa-z]*|тыс)(?=\s|$)',
  );
  static final _dateWords = RegExp(r'(^|\s)(сегодня|вчера|позавчера)(?=\s|$)');
  static const _filler = {
    'на',
    'в',
    'во',
    'за',
    'из',
    'с',
    'со',
    'у',
    'по',
    'и',
    'это',
    'мне',
    'я',
    'а',
    'ну',
    'вот',
    'там',
    'еще',
    'ещё',
    'сумма',
    'сумму',
    'потратил',
    'потратила',
    'купил',
    'купила',
    'заплатил',
    'заплатила',
    'оплатил',
    'оплатила',
    'оплата',
    'расход',
    'трата',
    'траты',
    'доход',
    'получил',
    'получила',
    'пришло',
    'пришла',
    'пришли',
    'поступило',
    'поступление',
    'заработал',
    'заработала',
    'вернули',
    'скинули',
  };

  static const _units = {
    'один': 1,
    'одна': 1,
    'одну': 1,
    'два': 2,
    'две': 2,
    'три': 3,
    'четыре': 4,
    'пять': 5,
    'шесть': 6,
    'семь': 7,
    'восемь': 8,
    'девять': 9,
    'десять': 10,
    'двадцать': 20,
    'тридцать': 30,
    'сорок': 40,
    'пятьдесят': 50,
    'шестьдесят': 60,
    'семьдесят': 70,
    'восемьдесят': 80,
    'девяносто': 90,
    'сто': 100,
    'двести': 200,
    'триста': 300,
    'четыреста': 400,
    'пятьсот': 500,
    'шестьсот': 600,
    'семьсот': 700,
    'восемьсот': 800,
    'девятьсот': 900,
  };

  /// Amount in minor units and where it was in [text].
  static ({int minor, int start, int end})? _amount(String text) {
    // «полторы тысячи», «тысяча/тысячу» alone, «пол тысячи».
    final words = RegExp(
      r'(полторы|пол)\s*тысяч[а-яёa-z]*|(^|\s)(тысяч[ау])(?=\s|$)',
    ).firstMatch(text);
    // Digits: «1250», «1250,50», «5 тысяч 300», «5к», «2,5 тысячи»,
    // «250 рублей 50 копеек».
    final digits = RegExp(
      r'(\d+(?:[.,]\d{1,2})?)\s*(тысяч[а-яёa-z]*|тыс\.?|к|млн|миллион[а-яёa-z]*)?(?:\s+(\d{1,3}))?'
      r'(?:\s*(?:рубл[а-яёa-z]*|руб\.?|р\.?|₽))?(?:\s+(\d{1,2})\s*(?:копе[а-яёa-z]*|коп\.?))?',
    );
    ({int minor, int start, int end})? best;
    for (final m in digits.allMatches(text)) {
      final number = double.parse(m.group(1)!.replaceAll(',', '.'));
      final unit = m.group(2) ?? '';
      var minor = (number * 100).round();
      if (unit.startsWith('тыс') || unit == 'к') {
        minor *= 1000;
        final tail = m.group(3);
        if (tail != null) minor += int.parse(tail) * 100;
      } else if (unit.startsWith('мил') || unit == 'млн') {
        minor *= 1000000;
      } else if (m.group(3) != null) {
        // «250 50» without units: not an amount pair; keep the first number.
        final cut = m.start + m.group(0)!.indexOf(m.group(3)!);
        final value = (minor, m.start, cut);
        if (best == null || value.$1 > best.minor) {
          best = (minor: value.$1, start: value.$2, end: value.$3);
        }
        continue;
      }
      final kopecks = m.group(4);
      if (kopecks != null) minor += int.parse(kopecks);
      if (minor <= 0) continue;
      // The largest number is the amount («такси 600 на 3 человек» → 600).
      if (best == null || minor > best.minor) {
        best = (minor: minor, start: m.start, end: m.end);
      }
    }
    if (best != null) return best;
    if (words != null) {
      final w = words.group(0)!.trim();
      final minor = w.startsWith('полтор')
          ? 150000
          : w.startsWith('пол')
          ? 50000
          : 100000;
      return (minor: minor, start: words.start, end: words.end);
    }
    // Spelled out: «пятьсот рублей», «двести пятьдесят».
    final spelled = RegExp(
      '(?:(?:${_units.keys.join('|')})\\s*)+(?=рубл|руб|₽|\$|\\s)',
    ).firstMatch(text);
    if (spelled != null) {
      final value = spelled
          .group(0)!
          .trim()
          .split(RegExp(r'\s+'))
          .fold<int>(0, (sum, w) => sum + (_units[w] ?? 0));
      if (value > 0) {
        return (minor: value * 100, start: spelled.start, end: spelled.end);
      }
    }
    return null;
  }

  static String _loose(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  /// A store named in the phrase, in any grammatical case («в пятерочке»,
  /// «в магните», «на озоне»). Multi-word names must appear as a whole.
  static SubscriptionService? _store(String phrase) {
    final key = _loose(phrase);
    if (key.isEmpty) return null;
    final words = key.split(' ');
    SubscriptionService? best;
    var length = 0;
    for (final store in StoreCatalog.entries) {
      for (final name in [store.name, ...store.aliases]) {
        final brand = _loose(name);
        if (brand.length < 3) continue;
        final hit = brand.contains(' ')
            ? ' $key '.contains(' $brand ')
            : words.any((w) => _sameWord(w, brand));
        if (hit && brand.length > length) {
          best = store;
          length = brand.length;
        }
      }
    }
    return best ?? ServiceCatalog.store(phrase);
  }

  /// «пятерочке» ~ «пятерочка», «магните» ~ «магнит»: the same word with a
  /// different case ending (at most two letters differ at the end).
  static bool _sameWord(String word, String brand) {
    if (word == brand) return true;
    if (brand.length < 4 || word.length < 4) return false;
    var common = 0;
    while (common < word.length &&
        common < brand.length &&
        word[common] == brand[common]) {
      common++;
    }
    return common >= brand.length - 1 && word.length - common <= 2 ||
        common >= brand.length - 2 &&
            brand.length >= 6 &&
            word.length - common <= 3;
  }

  /// A category named outright («на продукты», «транспорт»).
  static String? _named(
    String phrase,
    EntryKind kind,
    List<Category> categories,
  ) {
    final words = _loose(phrase).split(' ');
    final hits = categories.where((c) {
      if (c.archived || c.kind != kind) return false;
      final name = _loose(c.name).split(' ').first;
      if (name.length < 4) return false;
      final stem = name.substring(0, name.length - 1);
      return words.any((w) => w.length >= 4 && w.startsWith(stem));
    }).toList();
    return hits.length == 1 ? hits.single.id : null;
  }

  /// Everyday words → category names (кофе → кафе, такси → транспорт).
  static String? _byWords(
    String text,
    EntryKind kind,
    List<Category> categories,
  ) {
    const expense = [
      (
        r'продукт|супермаркет|еды домой|молок|хлеб',
        r'продукт|супермаркет|питани',
      ),
      (
        r'кофе|обед|ужин|завтрак|кафе|ресторан|пицц|бургер|шаурм|суши|роллы|столов',
        r'кафе|ресторан|еда вне|кофе',
      ),
      (
        r'такси|метро|автобус|самокат|электричк|проезд|трамва|троллейбус|маршрутк|каршеринг',
        r'транспорт|такси|проезд',
      ),
      (
        r'бензин|заправк|топлив|парковк|мойк|шиномонтаж|автосервис|страховк осаго',
        r'авто|машин|топлив|бензин',
      ),
      (r'аптек|лекарств|таблетк|витамин', r'аптек|лекарств'),
      (r'врач|анализ|стоматолог|зубн|клиник|больниц', r'здоров|медиц|врач'),
      (r'кино|театр|концерт|игр|боулинг|бар', r'развлеч|досуг|отдых'),
      (r'одежд|обув|кроссовк|куртк|футболк|джинс', r'одежд|обув'),
      (r'аренд|квартир|ипотек', r'жиль|аренд|квартир'),
      (
        r'коммунал|жкх|квартплат|электричеств|свет за|газ за|вода за',
        r'коммунал|жкх',
      ),
      (r'интернет|связь|телефон|мобильн|симк', r'связь|интернет|коммунал'),
      (r'подписк', r'подписк'),
      (r'подар', r'подар'),
      (r'курс|учеб|школ|репетитор|книг', r'образован|учеб'),
      (r'корм|ветеринар|кошк|собак', r'животн|питом'),
      (r'налог|штраф', r'налог'),
      (r'кредит|займ|рассрочк', r'кредит'),
    ];
    const income = [
      (r'зарплат|зп|аванс|преми', r'зарплат'),
      (r'подработк|фриланс|халтур', r'подработ'),
      (r'процент|вклад|кэшбэк|кешбэк|кешбек', r'процент|кэшбэк|кешбэк'),
      (r'дивиденд|акци|инвест', r'инвест'),
      (r'возврат|вернули', r'возврат'),
      (r'подар', r'подар'),
    ];
    final rules = kind == EntryKind.income ? income : expense;
    final active = categories.where((c) => c.kind == kind && !c.archived);
    for (final (words, names) in rules) {
      if (!RegExp(words).hasMatch(text)) continue;
      final pattern = RegExp(names);
      final hits = active
          .where((c) => pattern.hasMatch(_loose(c.name)))
          .toList();
      if (hits.length == 1) return hits.single.id;
    }
    return null;
  }
}
