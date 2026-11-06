import 'models.dart';
import 'receipt_parser.dart';
import 'scan_document.dart';
import 'scan_draft.dart';

/// Parses bank history pages into independent reviewable operations. Geometry
/// joins merchant/amount columns by visual rows instead of OCR reading order.
/// Does not create accounts, categories, operations or financial balances.
abstract final class BankStatementParser {
  static ScanDocument parse(
    String text, {
    List<RecognizedLine> lines = const [],
    required List<Category> categories,
    List<FinanceEntry> history = const [],
    DateTime? now,
    String? defaultCurrency,
    List<RecognizedLine> amountLines = const [],
  }) {
    final clock = now ?? DateTime.now();
    final source = ReceiptParser.normalizeText(text);
    final visual = _visualRows(source, _withAmountLines(lines, amountLines));
    final heading = _historyHeading.hasMatch(source.toLowerCase());
    final signedRows = visual
        .where((r) => _amounts(r.text).any((a) => a.signed != 0))
        .length;
    final total = RegExp(
      r'(?<![а-я])итого?(?![а-я])|grand\s+total|subtotal',
      caseSensitive: false,
    ).hasMatch(source);
    // A shop receipt stays one operation even when OCR lost its header:
    // fiscal fields, quantity × price rows, tender lines or a total without
    // signed bank-history rows all keep it out of the bulk-import path.
    final receipt =
        _receiptMarker.hasMatch(source.toLowerCase()) ||
        ReceiptParser.isReceiptText(source) ||
        (total && (!heading || signedRows == 0));
    ScanDocument single() {
      String parseText = text;
      // Columns of a receipt are joined by their visual row, so a total
      // printed in a separate right column still meets its «ИТОГ» label.
      if (lines.isNotEmpty) {
        final joined = visual.map((r) => r.text).join('\n');
        if (joined.trim().isNotEmpty) parseText = joined;
      }
      var draft = ReceiptParser.parse(
        parseText,
        categories: categories,
        history: history,
        now: clock,
      );
      if (!identical(parseText, text)) {
        if (draft.amountMinor == null) {
          final plain = ReceiptParser.parse(
            text,
            categories: categories,
            history: history,
            now: clock,
          );
          if (plain.amountMinor != null) draft = plain;
        }
        draft = draft.copyWith(rawText: text);
      }
      return ScanDocument(drafts: [draft]);
    }

    if (receipt) return single();
    final monetaryRows = visual
        .where((r) => !_ignored(r.text) && _amounts(r.text).isNotEmpty)
        .length;
    if (monetaryRows < 2 && !(heading && monetaryRows > 0)) return single();

    final drafts = <ScanDraft>[];
    final warnings = <String>[];
    final pending = <String>[];
    DateTime? currentDate;
    var skipNextAmount = false;
    var skipped = 0;
    var unmatched = 0;
    for (var index = 0; index < visual.length; index++) {
      final row = visual[index];
      final value = row.text.trim();
      if (value.isEmpty) continue;
      if (_ignored(value)) {
        if (_metadataLabel.hasMatch(value.toLowerCase()) &&
            _amounts(value).isEmpty) {
          skipNextAmount = true;
        }
        pending.clear();
        continue;
      }
      final date = _date(value, clock);
      if (date != null &&
          _dateHeader(value) &&
          (pending.isEmpty ||
              _fullDate.hasMatch(value) ||
              RegExp(r'[а-яa-z]', caseSensitive: false).hasMatch(value))) {
        if (pending.any((p) => _merchant(p, categories) != null)) unmatched++;
        pending.clear();
        currentDate = date;
        skipNextAmount = false;
        continue;
      }
      final rowAmounts = _amounts(value);
      if (rowAmounts.isEmpty) {
        if (_onlyCurrency(value)) continue;
        if (_metadataLabel.hasMatch(value.toLowerCase())) {
          skipNextAmount = true;
          pending.clear();
          continue;
        }
        if (!_noise.hasMatch(value.toLowerCase())) {
          skipNextAmount = false;
          pending.add(value);
          if (pending.length > 6) {
            pending.removeAt(0);
            unmatched++;
          }
        }
        continue;
      }
      final amounts = rowAmounts.where((a) => a.minor != 0).toList();
      if (amounts.isEmpty) continue;
      final primary = amounts.length == 1 ? amounts.single : null;
      final inline = primary == null
          ? null
          : _merchant(
              _removeRange(value, primary.start, primary.end),
              categories,
              allowCategory: true,
            );
      if (skipNextAmount && inline == null) {
        skipped++;
        skipNextAmount = false;
        pending.clear();
        continue;
      }
      skipNextAmount = false;
      final pendingMerchants = pending
          .map((p) => _merchant(p, categories))
          .whereType<String>()
          .toList();
      // More than one unmatched merchant followed by a bare amount is a lost
      // table layout. Keep the row but ask for a payee; never zip two columns by
      // arbitrary OCR reading order.
      final merchant =
          inline ??
          (pendingMerchants.length == 1 ? pendingMerchants.single : null);
      final context = <String>[if (inline == null) ...pending, value];
      if (index + 1 < visual.length &&
          _isCategory(visual[index + 1].text, categories)) {
        context.add(visual[index + 1].text);
      }
      final rowWarnings = <String>[];
      if (primary?.hadCurrencyArtifact == true) {
        rowWarnings.add(
          'После суммы распознан лишний символ. Проверьте сумму и валюту.',
        );
      }
      if (primary == null) {
        rowWarnings.add(
          'В строке несколько сумм. Уточните сумму этой операции.',
        );
      }
      if (merchant == null) {
        rowWarnings.add(
          'Не удалось сопоставить получателя этой строки. Уточните название.',
        );
      }
      final raw = context.join('\n');
      final parsed = ReceiptParser.parse(
        '${merchant == null ? '' : 'Магазин: $merchant\n'}$raw',
        categories: categories,
        history: history,
        now: clock,
      );
      final amount = primary?.minor.abs();
      String? currency = primary?.currency;
      if (currency == null) {
        final rowCurrency = ReceiptParser.detectCurrency(raw);
        final globalCurrency = ReceiptParser.detectCurrency(source);
        currency = rowCurrency ?? globalCurrency;
      }
      if (currency == null && defaultCurrency != null) {
        currency = defaultCurrency;
        rowWarnings.add(
          'Валюта не распознана. Предложена валюта счёта $defaultCurrency — проверьте.',
        );
      } else if (currency == null) {
        rowWarnings.add('Валюта этой операции не распознана.');
      }
      var kind = parsed.kind;
      final lower = raw.toLowerCase().replaceAll('ё', 'е');
      final ambiguousTransfer = RegExp(
        r'перевод|сбп|\btransfer\b|\bsbp\b',
      ).hasMatch(lower);
      if (!ambiguousTransfer && kind == null && primary != null) {
        if (primary.signed < 0) kind = EntryKind.expense;
        if (primary.signed > 0) kind = EntryKind.income;
      }
      if (RegExp(
        r'отмен[её]н|отклон[её]н|не\s+выполнен|declined|cancelled|canceled',
        caseSensitive: false,
      ).hasMatch(raw)) {
        kind = null;
        rowWarnings.add(
          'Строка помечена как отменённая или отклонённая. Проверьте, нужно ли её добавлять.',
        );
      }
      if (kind == null) {
        rowWarnings.add(
          ambiguousTransfer
              ? 'Уточните тип перевода: доход, расход или перевод между своими счетами.'
              : 'Уточните тип операции: доход или расход.',
        );
      }
      final operationDate =
          rowAmounts.isNotEmpty &&
              _dateHeader(value) &&
              !_fullDate.hasMatch(value)
          ? currentDate
          : date ?? currentDate;
      if (operationDate == null) {
        rowWarnings.add('Дата этой операции не распознана.');
      }
      var category = ReceiptParser.suggestCategory(
        payee: merchant,
        text: raw,
        kind: kind,
        categories: categories,
        history: history,
      );
      // Bank category captions can name any of the user's active categories,
      // including ones outside the built-in merchant keyword rules.
      if (category == null && kind != null && kind != EntryKind.transfer) {
        String key(String s) => s.trim().toLowerCase().replaceAll('ё', 'е');
        final captions = context.map(key).toSet();
        final matches = categories
            .where(
              (c) =>
                  !c.archived &&
                  c.kind == kind &&
                  captions.contains(key(c.name)),
            )
            .toList();
        if (matches.length == 1) category = matches.single.id;
      }
      if (category == null && kind != null && kind != EntryKind.transfer) {
        rowWarnings.add('Выберите категорию этой операции.');
      }
      if (row.confidence < .55) {
        rowWarnings.add(
          'Текст строки распознан неуверенно. Проверьте сумму и получателя.',
        );
      }
      drafts.add(
        ScanDraft(
          rawText: raw,
          amountMinor: amount,
          currency: currency,
          payee: merchant,
          date: operationDate,
          kind: kind,
          categoryId: category,
          comment: parsed.comment,
          warnings: List.unmodifiable(rowWarnings),
        ),
      );
      pending.clear();
    }
    if (drafts.isEmpty) return single();
    if (unmatched > 0) {
      warnings.add(
        'Некоторые строки без суммы не удалось сопоставить. Сверьте список с изображением.',
      );
    }
    if (skipped > 0) {
      warnings.add(
        'Баланс, комиссии в реквизитах и другие служебные суммы не добавлены как покупки.',
      );
    }
    warnings.add(
      'Проверьте ${drafts.length} распознанных операций перед сохранением.',
    );
    return ScanDocument(
      drafts: List.unmodifiable(drafts),
      warnings: List.unmodifiable(warnings),
      isStatement: true,
    );
  }

  static final _historyHeading = RegExp(
    r'истори[яи]\s+(?:операц|платеж)|список\s+операц|все\s+операции|операции\s+по\s+(?:карте|сч[её]ту)|выписка|bank\s+statement|transaction\s+history|recent\s+transactions|\bоперации\b',
  );
  static final _receiptMarker = RegExp(
    r'кассовый\s*чек|товарный\s*чек|фискальн|(?:^|[^а-я])ндс(?:$|[^а-я])|cashier|tax\s+invoice|sales\s+receipt',
  );
  static final _metadataLabel = RegExp(
    r'^(?:баланс(?:\s+карты)?|остаток(?:\s+на\s+сч[её]те)?|доступно|к[эе]шб[эе]к|cashback|balance|commission|комиссия|ндс|vat|итого|всего|расходы\s+за|доходы\s+за|сумма\s+(?:расходов|доходов)|оборот|начальный\s+остаток|конечный\s+остаток)(?:\s*[:：]?\s*)$',
  );
  static final _noise = RegExp(
    r'^(?:история|операции|все\s+операции|поиск|фильтр|настройки|главная|аналитика|мои\s+финансы|сбербанк|сбер|т-банк|тинькофф|втб|альфа.?банк|дата\s+операции|дата\s+описание|описание\s+сумма|период|отч[её]т|transaction\s+history|bank\s+statement|recent\s+transactions|date\s+description)(?:$|\s*[:：])',
  );
  static final _number = RegExp(r'[+-]?\s*\d(?:[\d .,\x27’]*\d)?');
  static final _fullDate = RegExp(
    r'(?<!\d)(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[./-]\d{1,2}[./-]\d{2,4})(?!\d)',
  );
  static final _time = RegExp(
    r'(?<!\d)(?:[01]?\d|2[0-3]):[0-5]\d(?::[0-5]\d)?(?!\d)',
  );
  static final _partialDate = RegExp(
    r'(?<!\d)(\d{1,2})[./](\d{1,2})(?![./\d])',
  );
  static final _currencySuffix = RegExp(
    r'^\s*(?:₽|\$|€|¥|元|₺|₾|£|₸|[рp]\.?|руб(?:\.|лей|ля|ль)?|[A-Z]{3})(?=$|[^a-zа-я])',
    caseSensitive: false,
  );

  static bool _ignored(String text) {
    final lower = text.toLowerCase();
    if (RegExp(
      r'^(?:баланс|остаток|доступно|к[эе]шб[эе]к|cashback|balance|ндс|vat|сдача|скидк|итого|всего|сумма\s+(?:расходов|доходов)|оборот|расходы\s+за|доходы\s+за)\b',
    ).hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'^(?:комиссия|commission)\s*[:：]?\s*[\d+-]').hasMatch(lower)) {
      return true;
    }
    return RegExp(
      r'^(?:карта|сч[её]т|инн|фн|фд|фп|rrn|iban|бик|телефон|тел\.|адрес)\s*[:：*•\d]',
    ).hasMatch(lower);
  }

  static bool _onlyCurrency(String text) => RegExp(
    r'^\s*(?:₽|\$|€|[A-Z]{3}|руб\.?|[рp]\.?)\s*$',
    caseSensitive: false,
  ).hasMatch(text);

  static List<_Money> _amounts(String text) {
    final normalized = ReceiptParser.normalizeText(text);
    String blank(Match m) => ' ' * m.group(0)!.length;
    var masked = normalized
        .replaceAllMapped(_fullDate, blank)
        .replaceAllMapped(_time, blank);
    // Partial dates are masked only before a non-money field or when alone;
    // a decimal amount such as 12.50 must remain money.
    masked = masked.replaceAllMapped(
      RegExp(
        r'^\s*\d{1,2}[./]\d{1,2}(?=\s+[а-яa-z]|\s*\|)',
        caseSensitive: false,
      ),
      blank,
    );
    final result = <_Money>[];
    for (final match in _number.allMatches(masked)) {
      final raw = match.group(0)!.trim();
      final candidate = ReceiptParser.parseOcrAmount(raw);
      final minor = candidate?.minor;
      if (minor == null) continue;
      final before = masked.substring(0, match.start);
      final after = masked.substring(match.end);
      if (RegExp(r'^\s*%').hasMatch(after) ||
          RegExp(r'[*•xX]{2,}\s*$').hasMatch(before)) {
        continue;
      }
      final signed = raw.startsWith('-')
          ? -1
          : raw.startsWith('+')
          ? 1
          : 0;
      final suffix = _currencySuffix.firstMatch(after);
      final nearby =
          '${before.length > 8 ? before.substring(before.length - 8) : before}$raw${suffix?.group(0) ?? ''}';
      var currency = ReceiptParser.detectCurrency(nearby);
      if (currency == null && suffix != null) {
        final code = RegExp(r'\b[A-Z]{3}\b').firstMatch(suffix.group(0)!);
        currency = code?.group(0)?.toUpperCase();
      }
      final decimal = RegExp(r'[.,]\s*\d{1,2}$').hasMatch(raw);
      if (signed == 0 && currency == null && !decimal) continue;
      if (match.start > 0 &&
          RegExp(r'[a-zа-яА-Я]').hasMatch(masked[match.start - 1])) {
        continue;
      }
      final end = match.end + (suffix?.end ?? 0);
      result.add(
        _Money(
          minor,
          currency,
          signed,
          match.start,
          end,
          candidate!.hadCurrencyArtifact,
        ),
      );
    }
    return result;
  }

  static String _removeRange(String value, int start, int end) =>
      '${value.substring(0, start)} ${value.substring(end)}';

  static bool _isCategory(String text, List<Category> categories) {
    final key = text.trim().toLowerCase().replaceAll('ё', 'е');
    return categories.any(
      (c) => !c.archived && c.name.toLowerCase().replaceAll('ё', 'е') == key,
    );
  }

  static String? _merchant(
    String text,
    List<Category> categories, {
    bool allowCategory = false,
  }) {
    var candidate = text.replaceAll(_fullDate, '').replaceAll(_time, '');
    candidate = candidate.replaceAll(RegExp(r'^\s*\d{1,2}[./]\d{1,2}\s*'), '');
    candidate = candidate.replaceAll(
      RegExp(
        r'^\s*(?:магазин|получатель|merchant|payee)\s*[:：]\s*',
        caseSensitive: false,
      ),
      '',
    );
    candidate = candidate.replaceAll(
      RegExp(r'^\s*(?:покупка|оплата)\s*[:：-]?\s+', caseSensitive: false),
      '',
    );
    candidate = candidate
        .replaceAll(RegExp(r'^[\s|:：;•-]+|[\s|:：;•-]+$'), '')
        .trim();
    if (candidate.length < 2 ||
        candidate.length > 160 ||
        !RegExp(r'[а-яa-zё]', caseSensitive: false).hasMatch(candidate) ||
        (!allowCategory && _isCategory(candidate, categories)) ||
        _ignored(candidate) ||
        _metadataLabel.hasMatch(candidate.toLowerCase()) ||
        _noise.hasMatch(candidate.toLowerCase()) ||
        _onlyCurrency(candidate) ||
        _dateHeader(candidate)) {
      return null;
    }
    return candidate;
  }

  static bool _dateHeader(String text) {
    var residue = text.replaceAll(_fullDate, '').replaceAll(_time, '');
    residue = residue.replaceAll(
      RegExp(
        r'\b\d{1,2}\s+(?:янв[а-я]*|фев[а-я]*|мар[а-я]*|апр[а-я]*|ма[йя]|июн[а-я]*|июл[а-я]*|авг[а-я]*|сен[а-я]*|окт[а-я]*|ноя[а-я]*|дек[а-я]*)(?:\s+\d{4})?',
        caseSensitive: false,
      ),
      '',
    );
    residue = residue
        .replaceAll(
          RegExp(r'сегодня|вчера|today|yesterday', caseSensitive: false),
          '',
        )
        .replaceAll(_partialDate, '');
    return residue.replaceAll(RegExp(r'[\s,.:|;-]'), '').isEmpty;
  }

  static DateTime? _date(String text, DateTime now) {
    final direct = ReceiptParser.parseDate(text, now: now);
    if (direct != null) return direct;
    if (_dateHeader(text)) {
      final partial = _partialDate.firstMatch(text);
      if (partial != null) {
        final day = int.parse(partial[1]!);
        final month = int.parse(partial[2]!);
        final value = DateTime(now.year, month, day);
        if (value.month == month && value.day == day) return value;
      }
    }
    return null;
  }

  /// Native re-reads of the amount column (one per row, digits only) replace
  /// the weak first reading of that column in the same row. Rows without a
  /// re-read keep their original text; nothing is added without geometry.
  static List<RecognizedLine> _withAmountLines(
    List<RecognizedLine> lines,
    List<RecognizedLine> amounts,
  ) {
    bool ok(RecognizedLine l) =>
        [
          l.left,
          l.top,
          l.right,
          l.bottom,
          l.confidence,
        ].every((v) => v.isFinite && v >= 0 && v <= 1) &&
        l.right > l.left &&
        l.bottom > l.top;
    final useful = amounts
        .where((a) => ok(a) && _amounts(a.text).any((m) => m.minor != 0))
        .toList();
    if (lines.isEmpty || useful.isEmpty) return lines;
    bool replaced(RecognizedLine l) {
      final center = (l.top + l.bottom) / 2;
      return useful.any(
        (a) => center >= a.top && center <= a.bottom && l.left >= a.left - .03,
      );
    }

    return [...lines.where((l) => !replaced(l)), ...useful];
  }

  static List<_VisualRow> _visualRows(
    String source,
    List<RecognizedLine> lines,
  ) {
    final valid = lines
        .where(
          (l) =>
              l.text.trim().isNotEmpty &&
              [
                l.left,
                l.top,
                l.right,
                l.bottom,
                l.confidence,
              ].every((v) => v.isFinite && v >= 0 && v <= 1) &&
              l.right > l.left &&
              l.bottom > l.top,
        )
        .toList();
    if (valid.isEmpty) {
      return source
          .split(RegExp(r'[\r\n]+'))
          .map((t) => _VisualRow(ReceiptParser.normalizeText(t).trim(), 1))
          .where((r) => r.text.isNotEmpty)
          .toList();
    }
    // App icons and avatars become tiny or very tall OCR fragments («9»,
    // «©», «® =» spanning three rows). They are not text of any row and must
    // not pull a neighbour's amount into the wrong row.
    final heights = [for (final l in valid) l.bottom - l.top]..sort();
    final typical = heights[heights.length ~/ 2];
    valid.removeWhere((l) {
      if (_amounts(l.text).isNotEmpty) return false;
      final meaningful = l.text.replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё]'), '');
      return meaningful.length <= 2 || (l.bottom - l.top) > typical * 3;
    });
    if (valid.isEmpty) return const [];
    valid.sort(
      (a, b) => ((a.top + a.bottom) / 2).compareTo((b.top + b.bottom) / 2),
    );
    final groups = <List<RecognizedLine>>[];
    for (final line in valid) {
      List<RecognizedLine>? group;
      for (final existing in groups.reversed) {
        final reference = existing.first;
        final center = (line.top + line.bottom) / 2;
        final other = (reference.top + reference.bottom) / 2;
        final height =
            (line.bottom - line.top) < (reference.bottom - reference.top)
            ? (line.bottom - line.top)
            : (reference.bottom - reference.top);
        if ((center - other).abs() <= height * .6) {
          group = existing;
          break;
        }
        if (center - other > .08) break;
      }
      (group ?? (groups..add(<RecognizedLine>[])).last).add(line);
    }
    return groups.map((g) {
      g.sort((a, b) => a.left.compareTo(b.left));
      return _VisualRow(
        g.map((l) => ReceiptParser.normalizeText(l.text)).join(' ').trim(),
        g.map((l) => l.confidence).reduce((a, b) => a < b ? a : b),
      );
    }).toList();
  }
}

class _Money {
  const _Money(
    this.minor,
    this.currency,
    this.signed,
    this.start,
    this.end,
    this.hadCurrencyArtifact,
  );
  final int minor, signed, start, end;
  final String? currency;
  final bool hadCurrencyArtifact;
}

class _VisualRow {
  const _VisualRow(this.text, this.confidence);
  final String text;
  final double confidence;
}
