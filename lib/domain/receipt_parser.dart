import 'category_hints.dart';
import 'finance_engine.dart';
import 'models.dart';
import 'scan_draft.dart';

/// Conservative, deterministic extraction from OCR, not a bank integration.
/// No operation, account, category, or financial balance is ever mutated here.
abstract final class ReceiptParser {
  static ScanDraft parse(
    String text, {
    required List<Category> categories,
    List<FinanceEntry> history = const [],
    DateTime? now,
  }) {
    final warnings = <String>[];
    final source = normalizeText(text);
    final lines = source
        .split(RegExp(r'[\r\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final lower = source.toLowerCase().replaceAll('ё', 'е');
    if (lines.isEmpty) {
      return ScanDraft(
        rawText: text,
        warnings: const [
          'Текст не распознан. Введите данные вручную или выберите более чёткое изображение.',
        ],
      );
    }
    final receipt = RegExp(
      r'кассовый\s*чек|товарный\s*чек|фискальн|(?:^|[^а-я])ндс(?=$|[^а-я])|grand\s+total|subtotal|(?:^|[^а-я])итого?(?=$|[^а-я])|к\s+оплате',
    ).hasMatch(lower);
    // Fiscal/till receipts list many prices, VAT, tender and change. Only an
    // explicit total may become the operation amount there; otherwise the
    // amount is left empty for review instead of picking or adding up items.
    final fiscal = isReceiptText(source);
    final candidates = <_Amount>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final masked = _maskMetadata(line);
      final prefix = i > 0 ? lines[i - 1].toLowerCase() : '';
      for (final match in _number.allMatches(masked)) {
        final candidate = parseOcrAmount(match.group(0)!);
        final value = candidate?.minor;
        if (value == null || value == 0) continue;
        final before = masked.substring(0, match.start).toLowerCase();
        final after = masked.substring(match.end).toLowerCase();
        if (RegExp(r'^[oOоО]').hasMatch(after) ||
            RegExp(r'\d[oOоО]$').hasMatch(before)) {
          continue;
        }
        if (after.trimLeft().startsWith('%')) continue;
        // `5908,` — OCR cut the kopecks off a receipt amount; not a value.
        if (fiscal && RegExp(r'^[.,](?!\s?\d)').hasMatch(after)) continue;
        final anchor = _anchor(before);
        final excluded = _last(_excluded, before);
        if (excluded > anchor.index ||
            (anchor.score == 0 && _metadataLine.hasMatch(line.toLowerCase()))) {
          continue;
        }
        final nearby = masked.substring(
          match.start > 8 ? match.start - 8 : 0,
          match.end + 12 < masked.length ? match.end + 12 : masked.length,
        );
        var currency = _currency(nearby);
        var score = anchor.score;
        var residue = '$before$after';
        for (final pattern in _currencyPatterns.values) {
          residue = residue.replaceAll(pattern, '');
        }
        final amountOnly = residue
            .replaceAll(RegExp(r'[\s:：=()\[\]*]'), '')
            .isEmpty;
        if (score == 0 && amountOnly) {
          final previous = _maskMetadata(prefix);
          final previousAnchor = _anchor(previous);
          if (_metadataLine.hasMatch(previous) ||
              _last(_excluded, previous) > previousAnchor.index ||
              (receipt &&
                  RegExp(
                    r'наличными|получено|внесено|tender|cash\s+received',
                  ).hasMatch(previous))) {
            continue;
          }
          score = previousAnchor.score;
          if (currency == null) {
            for (final adjacent in [
              if (i > 0) lines[i - 1],
              if (i + 1 < lines.length) lines[i + 1],
            ]) {
              if (_onlyCurrency(adjacent)) currency = _currency(adjacent);
            }
          }
          // Mobile bank screens often show the sum as a large, unlabelled
          // value. A signed value or a unique decimal in a purchase context is
          // useful even when OCR drops the currency glyph. Metadata above has
          // already excluded balances, cashback, card numbers and commissions.
          if (score == 0 && RegExp(r'^\s*[+-]').hasMatch(match.group(0)!)) {
            score = 65;
          }
          if (score == 0 &&
              RegExp(
                r'покупка|оплата|списан|зачислен|поступлен|purchase|payment',
              ).hasMatch(lower) &&
              RegExp(r'[.,]\s*\d{1,2}\s*$').hasMatch(match.group(0)!)) {
            score = 55;
          }
        }
        if (score == 0 && currency != null) score = 60;
        if (score == 0) continue;
        if (receipt &&
            RegExp(
              r'наличными|получено|внесено|сдача|tender|cash\s+received',
            ).hasMatch(before)) {
          continue;
        }
        candidates.add(
          _Amount(
            value.abs(),
            currency,
            score,
            match.group(0)!.trimLeft().startsWith('-')
                ? -1
                : match.group(0)!.trimLeft().startsWith('+')
                ? 1
                : 0,
            candidate!.hadCurrencyArtifact,
          ),
        );
      }
    }
    _Amount? amount;
    if (fiscal) {
      // Paper/till receipt recognition was removed at the owner's request:
      // only bank-app screenshots are recognized. Nothing is pre-filled.
      candidates.clear();
      warnings.add(paperReceiptWarning);
    }
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => b.score.compareTo(a.score));
      final strongest = candidates
          .where((c) => c.score == candidates.first.score)
          .toList();
      if (strongest.map((c) => c.minor).toSet().length == 1 &&
          strongest.map((c) => c.currency).whereType<String>().toSet().length <=
              1) {
        amount =
            strongest.where((c) => c.currency != null).firstOrNull ??
            strongest.first;
      } else {
        warnings.add(
          'Найдено несколько возможных итоговых сумм. Выберите сумму операции вручную.',
        );
      }
    }
    if (amount == null && warnings.isEmpty) {
      warnings.add('Не удалось уверенно определить итоговую сумму.');
    }
    if (amount?.hadCurrencyArtifact == true) {
      warnings.add(
        'После суммы распознан лишний символ. Проверьте сумму и валюту.',
      );
    }
    final currencies = _allCurrencies(source);
    final currency =
        amount?.currency ?? (currencies.length == 1 ? currencies.single : null);
    if (currency == null) {
      warnings.add(
        currencies.length > 1
            ? 'Найдено несколько валют. Уточните валюту операции.'
            : 'Валюта не распознана.',
      );
    }
    final kind = _kind(lower, receipt, amount?.sign ?? 0, warnings);
    final payee = _payee(lines);
    if (payee == null) warnings.add('Получатель или магазин не распознан.');
    final date = _date(source, now ?? DateTime.now());
    if (date == null) {
      warnings.add('Дата не распознана. Проверьте дату операции.');
    }
    final categoryId = _category(payee, lower, kind, categories, history);
    if (categoryId == null && kind != null && kind != EntryKind.transfer) {
      warnings.add('Выберите категорию операции.');
    }
    return ScanDraft(
      rawText: text,
      amountMinor: amount?.minor,
      currency: currency,
      payee: payee,
      date: date,
      kind: kind,
      categoryId: categoryId,
      comment:
          _field(
            lines,
            RegExp(
              r'^(?:назначение(?:\s+платежа)?|комментарий|сообщение|comment|payment\s+purpose)\s*[:：-]?\s*',
              caseSensitive: false,
            ),
          ) ??
          '',
      warnings: List.unmodifiable(warnings),
    );
  }

  /// Shared normalization keeps screenshot/statement money parsing consistent.
  /// OCR often splits or mixes Latin/Cyrillic letters in total labels
  /// (`И Т О Г`, `ИTОГ`, `ИТ0Г`, `К0ПЛАТЕ`). Only such damaged labels are
  /// rewritten; ordinary text keeps its original spelling.
  static String normalizeText(String text) => text
      .replaceAll(RegExp('[\u00a0\u202f\u2009\t]'), ' ')
      .replaceAll(RegExp('[−–—﹣－]'), '-')
      .replaceAll('≡', '=')
      .replaceAllMapped(_damagedTotal, (m) {
        final value = m.group(0)!;
        if (RegExp(r'^[а-яё]+$', caseSensitive: false).hasMatch(value)) {
          return value;
        }
        return RegExp(r'[оo]$', caseSensitive: false).hasMatch(value)
            ? 'ИТОГО'
            : 'ИТОГ';
      })
      .replaceAllMapped(_damagedDue, (m) {
        final value = m.group(0)!;
        return RegExp(r'^к оплате$', caseSensitive: false).hasMatch(value)
            ? value
            : 'К ОПЛАТЕ';
      })
      .replaceAllMapped(_letterZeros, (m) {
        // `-10 ОООР`, `+10 OOO P`: thin banking fonts read zero groups as
        // the letter O. Only for a number ending its line (± a ruble glyph).
        final groups = m.group(2)!;
        if (!RegExp('[OОoо]').hasMatch(groups)) return m.group(0)!;
        // Unsigned numbers need the ruble glyph as evidence of money.
        if (!RegExp(r'^[+-]').hasMatch(m.group(1)!) &&
            m.group(3)!.trim().isEmpty) {
          return m.group(0)!;
        }
        return '${m.group(1)}${groups.replaceAll(RegExp('[OОoо]'), '0')}${m.group(3)}';
      })
      .replaceAllMapped(_detachedRubleTwo, (m) => '${m.group(1)} 2');

  /// Signed amount (or one followed by a ruble glyph) whose 3-digit groups
  /// contain O/О letters instead of zeros.
  static final _letterZeros = RegExp(
    r'((?:[+-]\s?|(?<![\dA-Za-zА-Яа-яЁё.,]))\d{1,3})((?:\s?[0-9OОoо]{3})+)([ \t]*[₽РPрp]?)(?=[ \t]*$)',
    multiLine: true,
  );

  /// The ruble glyph read as a trailing `2` glued to a complete signed amount:
  /// `-10 0002` → `-10 000 2`, `-82,902` → `-82,90 2`. [parseOcrAmount] then
  /// drops the detached `2` and the caller warns about the artifact.
  static final _detachedRubleTwo = RegExp(
    r'([+-]\s?\d{1,3}(?:\s\d{3})+|[+-]\s?\d{1,3}(?:\s?\d{3})*[.,]\d{2})2(?=\s|[₽РPрp]|$)',
  );

  static final _damagedTotal = RegExp(
    r'(?<![а-яёa-z0-9])и ?[тt] ?[оo0] ?г(?:[оo])?(?![а-яёa-z])',
    caseSensitive: false,
  );
  static final _damagedDue = RegExp(
    r'(?<![а-яёa-z])[кk] ?[оo0] ?п ?л ?[аa] ?[тt] ?[еe](?![а-яёa-z])',
    caseSensitive: false,
  );

  static const paperReceiptWarning =
      'Похоже на бумажный чек. Распознавание чеков отключено — введите сумму вручную или выберите скриншот из банковского приложения.';

  /// Shop/till receipt evidence that survives a partly lost header: fiscal
  /// fields, a total label, payment-method lines or quantity × price rows.
  static bool isReceiptText(String text) {
    final lower = normalizeText(text).toLowerCase().replaceAll('ё', 'е');
    if (_fiscalMarker.hasMatch(lower)) return true;
    final items = _itemRow.allMatches(lower).length;
    final total = RegExp(
      r'(?<![а-яa-z])итого?(?![а-яa-z])|grand\s+total|subtotal',
    ).hasMatch(lower);
    final tender = RegExp(
      r'безналичн|наличными|электронными|сдача|внесено|получено\s+от\s+покуп',
    ).hasMatch(lower);
    return items >= 2 || (total && (items > 0 || tender));
  }

  static final _fiscalMarker = RegExp(
    r'кассовый\s*чек|товарный\s*чек|фискальн|(?<![а-яa-z])(?:ккт|рн\s*ккт|зн\s*ккт|фн|фд|фпд?)(?![а-яa-z])\s*[:№#]?\s*\d|кассир|смена\s*[№#]?\s*\d|полный\s+расч[её]т|признак\s+(?:способа|предмета)\s+расч|(?<![а-яa-z])сно(?![а-яa-z])|nalog\.(?:ru|gov)|сайт\s+фнс',
  );
  static final _itemRow = RegExp(
    r'\d+(?:[.,]\d{1,3})?\s*(?:шт\.?|кг|г|л)?\s*[xх×*]\s*\d+(?:[.,]\d{1,2})?',
  );

  static int? parseAmount(String text) => _minor(normalizeText(text));

  /// Tesseract can render a detached ruble glyph as a trailing `2` after an
  /// already complete two-digit fraction. Keep the complete monetary token,
  /// never append that glyph as cents or a thousands group. Callers must show
  /// the artifact warning before saving the suggestion.
  static ({int minor, bool hadCurrencyArtifact})? parseOcrAmount(String text) {
    final strict = parseAmount(text);
    if (strict != null) return (minor: strict, hadCurrencyArtifact: false);
    final artifact = RegExp(
      r'^([+-]?\s*\d[\d .,\x27’]*[.,]\s*\d{2}|[+-]?\s*\d{1,3}(?:[ .]\d{3})+)\s+2$',
    ).firstMatch(normalizeText(text).trim());
    if (artifact == null) return null;
    final value = parseAmount(artifact[1]!);
    return value == null ? null : (minor: value, hadCurrencyArtifact: true);
  }

  static String? detectCurrency(String text) => _currency(normalizeText(text));
  static DateTime? parseDate(String text, {DateTime? now}) =>
      _date(normalizeText(text), now ?? DateTime.now());
  static String? suggestCategory({
    String? payee,
    required String text,
    required EntryKind? kind,
    required List<Category> categories,
    List<FinanceEntry> history = const [],
  }) => _category(
    payee,
    text.toLowerCase().replaceAll('ё', 'е'),
    kind,
    categories,
    history,
  );

  static bool _onlyCurrency(String text) {
    var residue = text.trim();
    if (RegExp(r'^[рp]\.?$', caseSensitive: false).hasMatch(residue)) {
      return true;
    }
    for (final pattern in _currencyPatterns.values) {
      residue = residue.replaceAll(pattern, '');
    }
    return residue.trim().isEmpty;
  }

  static final _number = RegExp(r'[+-]?\s*\d(?:[\d .,\x27’]*\d)?');
  static final _datePattern = RegExp(
    r'(?<!\d)(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[./-]\d{1,2}[./-]\d{2,4})(?!\d)',
  );
  static final _timePattern = RegExp(
    r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?(?!\d)',
  );
  static final _excluded = RegExp(
    r'баланс|остаток|доступно|лимит|к[эе]шб[эе]к|cashback|balance|commission|комисси|ндс|vat|налог|сдача|скидк|бонус|subtotal|подытог|tender|cash\s+received',
  );
  static final _metadataLine = RegExp(
    r'(?:^|[^а-яa-z])(?:инн|фн|фд|фп|ккт|rrn|iban|бик|корр)(?=$|[^а-яa-z])|кассир|авторизац|терминал|телефон|тел\.|номер\s+чека|карта|карты|card|счет|счёт|\*{2,}|•{2,}|адрес|\bул\.',
  );

  static String _maskMetadata(String line) {
    String mask(Match m) => ' ' * m.group(0)!.length;
    return line
        .replaceAllMapped(
          RegExp(r'без\s+ндс|no\s+vat|tax\s+exempt', caseSensitive: false),
          mask,
        )
        .replaceAllMapped(_datePattern, mask)
        .replaceAllMapped(_timePattern, mask)
        .replaceAllMapped(RegExp(r'(?:\*|•|[xX]){2,}\s*\d{4}\b'), mask);
  }

  static ({int score, int index}) _anchor(String before) {
    var best = (score: 0, index: -1);
    for (final (pattern, score) in [
      (RegExp(r'к\s+оплате|grand\s+total|amount\s+due'), 140),
      (
        RegExp(
          r'(?<![а-яa-z])итого?(?![а-яa-z])|(?<![a-z])total(?![a-z])|(?<![а-яa-z])всего(?![а-яa-z])|сумма\s+(?:по\s+)?чек[ау]?',
        ),
        130,
      ),
      (
        RegExp(
          r'сумма\s+(?:операции|перевода|платежа|покупки|списания|получения)|transaction\s+amount',
        ),
        120,
      ),
      (
        RegExp(r'сумма|amount|списано|зачислено|поступило|оплата|стоимость'),
        90,
      ),
    ]) {
      final index = _last(pattern, before);
      if (index >= 0 && score > best.score) best = (score: score, index: index);
    }
    return best;
  }

  static int _last(RegExp pattern, String value) {
    final matches = pattern.allMatches(value);
    return matches.isEmpty ? -1 : matches.last.start;
  }

  static int? _minor(String value) {
    var raw = value.trim();
    raw = raw.replaceAllMapped(
      RegExp(r'\s*([.,])\s+(\d{1,2})$|\s+([.,])(\d{1,2})$'),
      (m) => '${m[1] ?? m[3]}${m[2] ?? m[4]}',
    );
    var sign = '';
    if (raw.startsWith('+') || raw.startsWith('-')) {
      sign = raw[0];
      raw = raw.substring(1).trimLeft();
    }
    final position = raw.lastIndexOf('.') > raw.lastIndexOf(',')
        ? raw.lastIndexOf('.')
        : raw.lastIndexOf(',');
    String whole = raw;
    String? fraction;
    if (position >= 0) {
      final tail = raw.substring(position + 1);
      if (RegExp(r'^\d{1,2}$').hasMatch(tail)) {
        whole = raw.substring(0, position);
        fraction = tail;
      }
    }
    if (!RegExp(r'^\d+$').hasMatch(whole) &&
        !RegExp(r"^\d{1,3}(?:[ .,'’]\d{3})+$").hasMatch(whole)) {
      return null;
    }
    whole = whole.replaceAll(RegExp(r"[ .,'’]"), '');
    final normalized = '$sign$whole${fraction == null ? '' : '.$fraction'}';
    try {
      return FinanceEngine.parseMinor(normalized);
    } on FormatException {
      return null;
    }
  }

  static final _currencyPatterns = <String, RegExp>{
    'RUB': RegExp(
      r'₽|\brub\b|\brur\b|руб(?:ль|ля|лей)?(?:\.|(?=$|[^а-я]))|(?<=\d)\s*[рp](?=$|[\s.])',
      caseSensitive: false,
    ),
    'USD': RegExp(r'\$|\busd\b|доллар', caseSensitive: false),
    'EUR': RegExp(r'€|\beur\b|евро', caseSensitive: false),
    'CNY': RegExp(r'¥|元|\bcny\b|юан', caseSensitive: false),
    'TRY': RegExp(r'₺|\btry\b', caseSensitive: false),
    'GEL': RegExp(r'₾|\bgel\b', caseSensitive: false),
    'GBP': RegExp(r'£|\bgbp\b', caseSensitive: false),
    'AED': RegExp(r'\baed\b|дирхам', caseSensitive: false),
    'KZT': RegExp(r'₸|\bkzt\b', caseSensitive: false),
    'CHF': RegExp(r'\bchf\b', caseSensitive: false),
  };
  static Set<String> _allCurrencies(String text) => {
    for (final item in _currencyPatterns.entries)
      if (item.value.hasMatch(text)) item.key,
  };
  static String? _currency(String text) {
    if (RegExp(r'^[рp]\.?$', caseSensitive: false).hasMatch(text.trim())) {
      return 'RUB';
    }
    final codes = _allCurrencies(text);
    return codes.length == 1 ? codes.single : null;
  }

  static EntryKind? _kind(
    String text,
    bool receipt,
    int sign,
    List<String> warnings,
  ) {
    if (RegExp(
      r'между\s+(?:(?:своими|собственными)\s+)?счетами|на\s+свой\s+счет|на\s+свою\s+карту|(?:^|[^а-я])себе(?=$|[^а-я])|own\s+accounts|self\s+transfer',
    ).hasMatch(text)) {
      return EntryKind.transfer;
    }
    if (RegExp(
      r'(?:^|[^а-я])сбп(?=$|[^а-я])|\bsbp\b|перевод|\btransfer\b',
    ).hasMatch(text)) {
      warnings.add(
        'Уточните тип перевода: между своими счетами, доход или расход. СБП не считается расходом автоматически.',
      );
      return null;
    }
    if (RegExp(
      r'возврат\s+(?:прихода|покупки|средств)|refund|зачислен|поступлен|поступило|зарплата|доход|получен(?:о)?\s+от',
    ).hasMatch(text)) {
      return EntryKind.income;
    }
    if (RegExp(
          r'списан|оплата|покупка|расход|payment|purchase|paid',
        ).hasMatch(text) ||
        receipt ||
        sign < 0) {
      return EntryKind.expense;
    }
    if (sign > 0) return EntryKind.income;
    warnings.add(
      'Тип операции не определён. Выберите доход, расход или перевод.',
    );
    return null;
  }

  static String? _field(List<String> lines, RegExp label) {
    for (var i = 0; i < lines.length; i++) {
      final match = label.firstMatch(lines[i]);
      if (match == null) continue;
      final value = lines[i].substring(match.end).trim();
      if (value.isNotEmpty) return value;
      if (i + 1 < lines.length && _plausiblePayee(lines[i + 1])) {
        return lines[i + 1];
      }
    }
    return null;
  }

  static String? _payee(List<String> lines) {
    final field = _field(
      lines,
      RegExp(
        r'^(?:получатель|магазин|продавец|торговая\s+точка|merchant|payee|кому|оплата\s+в|покупка\s+в)\s*[:：-]?\s*',
        caseSensitive: false,
      ),
    );
    if (field != null && _plausiblePayee(field)) return field;
    for (final line in lines) {
      if (_plausiblePayee(line)) return line;
    }
    return null;
  }

  static bool _plausiblePayee(String line) {
    final lower = line.toLowerCase();
    if (line.length < 2 ||
        line.length > 100 ||
        !RegExp(r'[а-яА-Яa-zA-ZёЁ]').hasMatch(line)) {
      return false;
    }
    if (_metadataLine.hasMatch(lower) ||
        _excluded.hasMatch(lower) ||
        _anchor(lower).score > 0 ||
        _allCurrencies(line).isNotEmpty ||
        _datePattern.hasMatch(line)) {
      return false;
    }
    return !RegExp(
      r'^(?:сбер(?:банк)?|т-банк|тинькофф|втб|альфа.?банк|банк|кассовый|товарный|чек|приход|расход|операция|успеш|исполнен|оплачен|покупка|списание|платеж|перевод|сбп|дата|время|сегодня|вчера|спасибо|итог|наличными|безналичными|получатель|касса|фискальн|зачисл|поступл|пополн|отправл|получен|реквизит|квитанц|bank statement|transaction|payment|receipt)',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static DateTime? _date(String text, DateTime now) {
    final time = _timePattern.firstMatch(text);
    final hour = time == null ? 0 : int.parse(time.group(1)!);
    final minute = time == null ? 0 : int.parse(time.group(2)!);
    final second = time?.group(3) == null ? 0 : int.parse(time!.group(3)!);
    DateTime? create(int year, int month, int day) {
      if (year < 1900 ||
          year > 2200 ||
          month < 1 ||
          month > 12 ||
          day < 1 ||
          day > 31) {
        return null;
      }
      final date = DateTime(year, month, day, hour, minute, second);
      return date.year == year && date.month == month && date.day == day
          ? date
          : null;
    }

    for (final match in _datePattern.allMatches(text)) {
      final parts = match
          .group(0)!
          .split(RegExp(r'[./-]'))
          .map(int.parse)
          .toList();
      final iso = parts[0] > 31;
      var year = iso ? parts[0] : parts[2];
      if (year < 100) year += 2000;
      final result = create(year, parts[1], iso ? parts[2] : parts[0]);
      if (result != null) return result;
    }
    final lower = text.toLowerCase();
    if (lower.contains('сегодня') || lower.contains('вчера')) {
      final relative = now.subtract(
        Duration(days: lower.contains('вчера') ? 1 : 0),
      );
      return create(relative.year, relative.month, relative.day);
    }
    const months = [
      'январ',
      'феврал',
      'март',
      'апрел',
      'мая',
      'июн',
      'июл',
      'август',
      'сентябр',
      'октябр',
      'ноябр',
      'декабр',
    ];
    final words = RegExp(
      r'\b(\d{1,2})\s+([а-я]+)(?:\s+(\d{4}))?',
      caseSensitive: false,
    );
    for (final match in words.allMatches(lower)) {
      final month = months.indexWhere((m) => match.group(2)!.startsWith(m));
      if (month < 0) continue;
      final result = create(
        match.group(3) == null ? now.year : int.parse(match.group(3)!),
        month + 1,
        int.parse(match.group(1)!),
      );
      if (result != null) return result;
    }
    return null;
  }

  static String _merchantKey(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^a-zа-я0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  static String? _category(
    String? payee,
    String text,
    EntryKind? kind,
    List<Category> categories,
    List<FinanceEntry> history,
  ) {
    if (kind == null || kind == EntryKind.transfer) return null;
    final active = categories
        .where((c) => c.kind == kind && !c.archived)
        .toList();
    if (payee != null) {
      final matched =
          history
              .where(
                (entry) =>
                    entry.status == 'posted' &&
                    entry.kind == kind &&
                    _merchantKey(entry.payee) == _merchantKey(payee) &&
                    active.any((c) => c.id == entry.categoryId),
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      if (matched.isNotEmpty) return matched.first.categoryId;
    }
    // A known store or service decides next (Пятёрочка → Продукты).
    final hinted = CategoryHints.forPayee(
      payee,
      kind: kind,
      categories: categories,
    );
    if (hinted != null) return hinted;
    final rules = kind == EntryKind.income
        ? [
            (RegExp(r'зарплат|salary|payroll'), RegExp(r'зарплат|salary')),
            (RegExp(r'возврат|refund'), RegExp(r'возврат|refund|прочее|other')),
          ]
        : [
            (
              RegExp(
                r'пятероч|pyateroch|перекрест|perekrest|вкусвилл|vkusvill|магнит|magnit|лента|\blenta\b|\bspar\b|ашан|auchan|дикси|dixy|молоко|хлеб|продукты',
              ),
              RegExp(r'продукт|супермаркет|grocer|питание'),
            ),
            (
              RegExp(
                r'такси|taxi|uber|яндекс\s*go|yandex\s*go|ситимобил|метро|\bmetro\b',
              ),
              RegExp(r'транспорт|такси|transport'),
            ),
            (
              RegExp(
                r'азс|лукойл|lukoil|роснефть|rosneft|газпромнефть|\bshell\b|\bfuel\b',
              ),
              RegExp(r'авто|топлив|бензин|\bcar\b|fuel'),
            ),
            (
              RegExp(r'аптек|apteka|pharmac|горздрав|ригла'),
              RegExp(r'аптек|здоров|health|medic'),
            ),
            (
              RegExp(
                r'spotify|netflix|youtube|яндекс\s+плюс|yandex\s+plus|ivi|okko|кинопоиск|apple\s+music|подписк',
              ),
              RegExp(r'подписк|subscription'),
            ),
            (
              RegExp(
                r'кофейн|кофе|cafe|coffee|starbucks|ресторан|restaurant|бургер|burger',
              ),
              RegExp(r'кафе|ресторан|cafe|restaurant'),
            ),
          ];
    List<String> suggestions(String value) => {
      for (final (merchant, category) in rules)
        if (merchant.hasMatch(value))
          for (final c in active)
            if (category.hasMatch(
              '${c.name} ${c.subcategories.join(' ')}'.toLowerCase(),
            ))
              c.id,
    }.toList();
    final merchantSuggestions = suggestions(
      payee?.toLowerCase().replaceAll('ё', 'е') ?? '',
    );
    if (merchantSuggestions.length == 1) return merchantSuggestions.single;
    final full = suggestions(text);
    return full.length == 1 ? full.single : null;
  }
}

class _Amount {
  const _Amount(
    this.minor,
    this.currency,
    this.score,
    this.sign,
    this.hadCurrencyArtifact,
  );
  final int minor;
  final String? currency;
  final int score;
  final int sign;
  final bool hadCurrencyArtifact;
}
