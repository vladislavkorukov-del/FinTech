import 'models.dart';
import 'receipt_parser.dart';
import 'service_catalog.dart';
import 'service_recognizer.dart';
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

  /// The amount in a phrase and the rest of it, lower case, without the
  /// amount and currency words (voice commands, 1.24).
  static ({int minor, String rest})? amountIn(String heard) {
    final text = _norm(heard);
    final found = _amount(text);
    if (found == null) return null;
    return (
      minor: found.minor,
      rest: text
          .replaceRange(found.start, found.end, ' ')
          .replaceAll(_currency, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  /// The expense or income category a phrase suggests, if any.
  static String? categoryFor(
    String phrase,
    EntryKind kind,
    List<Category> categories,
  ) {
    final store = _store(phrase);
    final payee = store?.name ?? phrase;
    return (payee.isEmpty
            ? null
            : ReceiptParser.suggestCategory(
                payee: payee,
                text: '',
                kind: kind,
                categories: categories,
                history: const [],
              )) ??
        _named(phrase, kind, categories) ??
        _byWords(phrase, kind, categories);
  }

  static String _norm(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[«»"“”!?;:]'), ' ')
      // Thousands separators as speech services write them: «1.300»,
      // «1 300», «12.500.000», «1,300» (a group of exactly three digits).
      .replaceAll(RegExp('(?<=\\d)[\\s.,\u00a0\u202f](?=\\d{3}(?!\\d))'), '')
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
    'финора',
    'finora',
    // 1.31: how Finora's own ear hears her name.
    'фигура',
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

  /// Spelled numbers, as recognizers sometimes leave them.
  static const _words = <String, int>{
    'ноль': 0,
    'один': 1,
    'одна': 1,
    'одну': 1,
    'одной': 1,
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
    'одиннадцать': 11,
    'двенадцать': 12,
    'тринадцать': 13,
    'четырнадцать': 14,
    'пятнадцать': 15,
    'шестнадцать': 16,
    'семнадцать': 17,
    'восемнадцать': 18,
    'девятнадцать': 19,
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

  /// «тысяча», «млн», «миллиардов», «к» → their factor.
  static int? _multiplier(String w) {
    if (w == 'к' || w == 'k' || w == 'тыс' || w.startsWith('тысяч')) {
      return 1000;
    }
    if (w == 'млн' || w.startsWith('миллион')) return 1000000;
    if (w == 'млрд' || w.startsWith('миллиард')) return 1000000000;
    return null;
  }

  static bool _rubles(String w) =>
      w == 'р' || w == '₽' || w == 'руб' || w.startsWith('рубл');
  static bool _kopecks(String w) => w == 'коп' || w.startsWith('копе');

  /// A number word or token in minor units (×100): «1300» → 130000,
  /// «2,5» → 250, «триста» → 30000, «полторы» → 150; null if not a number.
  static int? _number(String w) {
    final digits = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$').firstMatch(w);
    if (digits != null) {
      final whole = int.parse(digits.group(1)!);
      final fraction = (digits.group(2) ?? '').padRight(2, '0');
      return whole * 100 + int.parse(fraction);
    }
    if (w == 'полторы' || w == 'полтора') return 150;
    if (w == 'пол') return 50;
    final value = _words[w];
    return value == null ? null : value * 100;
  }

  /// Amount in minor units and where it was in [text].
  ///
  /// Reads runs of numbers and factors the usual way («2 миллиона 300
  /// тысяч 50» = 2 300 050; «одна тысяча триста» = 1300), then optional
  /// «руб» and «N коп». Integer arithmetic only, so any size is exact. The
  /// largest run wins («такси на 3 человек 600» → 600).
  static ({int minor, int start, int end})? _amount(String text) {
    // «5к», «10k» → «5 к».
    final spaced = text.replaceAllMapped(
      RegExp(r'(?<=\d)(к|k)(?=\s|$)'),
      (m) => ' ${m.group(1)}',
    );
    final tokens = RegExp(r'\S+').allMatches(spaced).toList();
    // Map offsets back to [text] (only «5к» splits change them).
    int back(int offset) {
      var shift = 0;
      for (final m in RegExp(r'(?<=\d)(к|k)(?=\s|$)').allMatches(text)) {
        if (m.start + shift < offset) shift++;
      }
      return offset - shift;
    }

    ({int minor, int start, int end})? best;
    var i = 0;
    while (i < tokens.length) {
      // «пол» is a half only before a factor («пол тысячи»), not «на пол».
      bool half(int k) =>
          tokens[k].group(0) == 'пол' &&
          (k + 1 >= tokens.length ||
              _multiplier(tokens[k + 1].group(0)!) == null);
      final first = half(i) ? null : _number(tokens[i].group(0)!);
      if (first == null) {
        i++;
        continue;
      }
      // Run: numbers and factors.
      var total = 0, current = 0, j = i;
      while (j < tokens.length) {
        final w = tokens[j].group(0)!;
        final n = half(j) ? null : _number(w);
        final m = _multiplier(w);
        if (n != null) {
          current += n;
        } else if (m != null) {
          total += (current == 0 ? 100 : current) * m;
          current = 0;
        } else {
          break;
        }
        j++;
      }
      var minor = total + current;
      var end = tokens[j - 1].end;
      // «руб» then «N коп».
      if (j < tokens.length && _rubles(tokens[j].group(0)!)) {
        end = tokens[j].end;
        j++;
      }
      if (j + 1 < tokens.length && _kopecks(tokens[j + 1].group(0)!)) {
        final kop =
            int.tryParse(tokens[j].group(0)!) ?? (_words[tokens[j].group(0)!]);
        if (kop != null && kop < 100) {
          minor = minor - minor % 100 + kop;
          end = tokens[j + 1].end;
          j += 2;
        }
      }
      if (minor > 0 && (best == null || minor > best.minor)) {
        best = (minor: minor, start: back(tokens[i].start), end: back(end));
      }
      i = j > i ? j : i + 1;
    }
    return best;
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
    // 1.26: also subscriptions and names said in Cyrillic («чат гпт»).
    return best ??
        ServiceCatalog.store(phrase) ??
        ServiceRecognizer.find(phrase);
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
