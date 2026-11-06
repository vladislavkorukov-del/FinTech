import 'finance_engine.dart';

/// Result of [ReceiptTotal.find]: the printed total of a till receipt and how
/// it was confirmed. [warning] asks the person to check a weaker match.
class ReceiptTotalMatch {
  const ReceiptTotalMatch(this.minor, this.evidence, {this.warning});
  final int minor;
  final List<String> evidence;
  final String? warning;
}

/// Finds the total of a shop receipt from OCR rows (top to bottom).
///
/// Owner's rule (1.6.3): the amount is **the value of the «ИТОГ» row** and
/// nothing else. `ИТОГ`/`ИТОГО` rows win; `ИТОГ К ОПЛАТЕ`/`К ОПЛАТЕ` are used
/// only when the receipt has no plain `ИТОГ` row, `ВСЕГО`/`TOTAL` only when
/// it has neither. Cash, cashless, VAT, `СУММА`, items and change are never
/// the amount. They only help to choose between several OCR readings of the
/// same «ИТОГ» row (main pass, whole-page block pass, enlarged band re-read):
/// the most frequent reading wins, a `≡` misread as a leading digit
/// (`52550.00` beside `2550.00`) is merged, and a damaged reading
/// (`=4199_o0`) counts only when cashless payment or VAT confirm it exactly.
/// Unresolved disagreement leaves the amount empty.
abstract final class ReceiptTotal {
  static ReceiptTotalMatch? find(
    List<String> rows, {
    List<String> focusRows = const [],
  }) {
    final parsed = [for (final row in rows) _Row.parse(row)];
    final focus = [for (final row in focusRows) _Row.parse(row)];
    final all = [...parsed, ...focus];
    final readings = <(int rank, int value, bool loose)>[];
    for (final list in [parsed, focus]) {
      for (var i = 0; i < list.length; i++) {
        final row = list[i];
        if (row.kind != _Kind.total) continue;
        int? value = row.amounts.isEmpty ? null : row.amounts.last;
        // Value printed below the label (big «ИТОГ» font shifts the column).
        for (var j = i + 1; value == null && j <= i + 2; j++) {
          if (j >= list.length) break;
          final next = list[j];
          if (next.kind != _Kind.none) break;
          if (next.amounts.length == 1) value = next.amounts.single;
        }
        value ??= row.wholeTail;
        if (value != null) {
          readings.add((row.rank, value, false));
        } else {
          for (final loose in row.loose) {
            readings.add((row.rank, loose, true));
          }
        }
      }
    }
    if (readings.isEmpty) return null;
    var bestRank = readings.map((r) => r.$1).reduce((a, b) => a < b ? a : b);
    // «ИТОГО 1 200 · СКИДКА 200 · К ОПЛАТЕ 1 000»: the discounted amount due
    // is what was charged. Only a discount row between them changes the rule.
    if (bestRank == 1 && readings.any((r) => r.$1 == 2)) {
      final first = parsed.indexWhere(
        (r) => r.kind == _Kind.total && r.rank == 1,
      );
      final due = parsed.lastIndexWhere(
        (r) => r.kind == _Kind.total && r.rank == 2,
      );
      if (first >= 0 &&
          due > first &&
          parsed
              .sublist(first + 1, due)
              .any((r) => r.kind == _Kind.excluded && r.discount)) {
        bestRank = 2;
      }
    }
    final chosen = readings.where((r) => r.$1 == bestRank).toList();

    // Independent confirmations, used only to choose among «ИТОГ» readings.
    final confirm = <int, Set<String>>{};
    for (final row in all) {
      if (row.kind == _Kind.payment && row.amounts.isNotEmpty) {
        (confirm[row.amounts.last] ??= {}).add('payment');
      }
    }
    final vats = <(int, int)>{
      for (final row in all)
        if (row.vat != null) row.vat!,
    };
    bool vatFits(int value) =>
        vats.length == 1 &&
        ((value * vats.single.$1 / (100 + vats.single.$1)) - vats.single.$2)
                .abs() <=
            1.01;

    final votes = <int, int>{};
    for (final r in chosen.where((r) => !r.$3)) {
      votes[r.$2] = (votes[r.$2] ?? 0) + 1;
    }
    // A damaged reading counts only with an exact confirmation.
    for (final r in chosen.where((r) => r.$3)) {
      if (confirm.containsKey(r.$2) || vatFits(r.$2)) {
        votes[r.$2] = (votes[r.$2] ?? 0) + 1;
      }
    }
    if (votes.isEmpty) return null;
    // The same number printed elsewhere on the receipt (cash/cashless rows,
    // a bare value of the total column) supports that reading.
    int seen(int v) => all
        .where(
          (r) =>
              (r.kind == _Kind.none || r.kind == _Kind.payment) &&
              r.amounts.contains(v),
        )
        .length;
    int support(int v) =>
        (votes[v] ?? 0) * 10 +
        (confirm[v]?.isNotEmpty ?? false ? 5 : 0) +
        (vatFits(v) ? 5 : 0) +
        (seen(v) > 3 ? 3 : seen(v)) * 3;
    // Two readings where one has an extra leading digit: «≡» read as 5 or 3
    // (52550.00 beside 2550.00), or a digit lost at the edge (570.00 beside
    // 1570.00). Evidence decides; otherwise only a leading 5/3 is a glyph.
    for (final long in votes.keys.toList()) {
      for (final short in votes.keys.toList()) {
        if (!votes.containsKey(long) || !votes.containsKey(short)) continue;
        final l = '$long', t = '$short';
        if (l.length != t.length + 1 || !l.endsWith(t)) continue;
        final keepShort = support(short) != support(long)
            ? support(short) > support(long)
            : (l[0] == '5' || l[0] == '3');
        final winner = keepShort ? short : long;
        final loser = keepShort ? long : short;
        votes[winner] = votes[winner]! + votes.remove(loser)!;
      }
    }
    final ranked = votes.keys.toList()
      ..sort((a, b) => support(b).compareTo(support(a)));
    var best = ranked.first;
    if (ranked.length > 1 && support(ranked[1]) == support(best)) return null;
    // Readings that differ in one digit with no confirmation: do not guess.
    if (ranked.length > 1 &&
        _oneDigitApart(best, ranked[1]) &&
        support(best) - support(ranked[1]) < 5) {
      return null;
    }
    // A single «ИТОГ» reading with a misread digit: the same number printed
    // in the total's column (or on the cashless row) that VAT / payment
    // confirm is the correct reading of that row. A reading contradicted by
    // the single VAT row is left for review.
    var corrected = false;
    final sure = vatFits(best) || (confirm[best]?.isNotEmpty ?? false);
    if (!sure && votes[best]! < 2) {
      final printed = <int>{
        for (final row in all)
          if (row.kind == _Kind.none ||
              row.kind == _Kind.total ||
              row.kind == _Kind.payment)
            ...row.amounts,
      };
      final fitting = printed
          .where((v) => _oneDigitApart(best, v) && vatFits(v))
          .toList();
      if (fitting.length == 1) {
        best = fitting.single;
        corrected = true;
      } else if (vats.length == 1 &&
          vats.single.$2 < best * .25 &&
          !vatFits(best)) {
        return null;
      }
    }
    // The «ИТОГ» reading is a VAT amount (rows joined across a skewed photo
    // or columns swapped by OCR): never pre-fill it.
    final printedAll = <int>{for (final row in all) ...row.amounts};
    final isVat =
        vats.any((v) => v.$2 == best) ||
        printedAll.any(
          (v) =>
              v > best &&
              const [
                22,
                20,
                18,
                10,
              ].any((rate) => ((v * rate / (100 + rate)) - best).abs() <= 1.01),
        );
    if (isVat && !(confirm[best]?.isNotEmpty ?? false)) return null;
    final evidence = <String>{
      bestRank == 1 ? 'label' : 'label-rank-$bestRank',
      if ((votes[best] ?? 0) > 1) 'repeat',
      if (corrected) 'corrected',
      ...?confirm[best],
      if (vatFits(best)) 'vat',
      if (chosen.any((r) => r.$3 && r.$2 == best)) 'loose',
    };
    final distinct = chosen.map((r) => r.$2).toSet().length;
    return ReceiptTotalMatch(
      best,
      evidence.toList()..sort(),
      warning:
          corrected ||
              evidence.contains('loose') ||
              (distinct > 1 && (votes[best] ?? 0) < 2)
          ? 'Строка «ИТОГ» распознана нечётко. Проверьте сумму.'
          : null,
    );
  }

  static bool _oneDigitApart(int a, int b) {
    final x = '$a', y = '$b';
    if (x.length != y.length) return false;
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) diff++;
    }
    return diff == 1;
  }

  /// `(rate, amount)` of a VAT row such as `СУММА НДС 20% =1345.52`.
  static (int, int)? vatOf(String row) {
    final words = row.split(RegExp(r'\s+')).map(letters);
    if (!words.any((w) => w == 'НДС' || w == 'НАС' || w == 'НДО')) return null;
    if (letters(row).contains('БЕЗНДС')) return null;
    final rate = RegExp(
      r'(?<!\d)(5|7|10|18|20|22)\s*(?:%|/\s*1[0-2]\d)',
    ).firstMatch(row);
    final money = amounts(row);
    if (rate == null || money.isEmpty) return null;
    return (int.parse(rate.group(1)!), money.last);
  }

  /// Distinct values printed on total rows (for an «several totals» note).
  static Set<int> totalRowValues(Iterable<String> rows) => {
    for (final row in rows)
      if (isTotalRow(row)) ...amounts(row),
  };

  /// Whether an OCR row is a (possibly damaged) total label.
  static bool isTotalRow(String row) =>
      RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(row) &&
      _classify(row) == _Kind.total;

  static int _rank(String row) {
    final joined = letters(row);
    if (joined.contains('КОПЛАТ') || joined.contains('ОПЛАТЕ')) return 2;
    final first = row
        .split(RegExp(r'\s+'))
        .map(letters)
        .firstWhere((w) => w.isNotEmpty, orElse: () => '');
    if (_distance(first, 'ВСЕГО') <= 1 ||
        RegExp(r'TOTAL', caseSensitive: false).hasMatch(row)) {
      return 3;
    }
    return 1;
  }

  /// Latin/digit look-alikes that OCR puts into Cyrillic receipt words.
  static const _homoglyphs = {
    'A': 'А',
    'B': 'В',
    'C': 'С',
    'E': 'Е',
    'H': 'Н',
    'K': 'К',
    'M': 'М',
    'O': 'О',
    'P': 'Р',
    'T': 'Т',
    'X': 'Х',
    'Y': 'У',
    'N': 'И',
    'U': 'И',
    'W': 'И',
    'R': 'Г',
    'F': 'Г',
    'L': 'Л',
    '0': 'О',
    '3': 'З',
    '6': 'Б',
    'Ë': 'Е',
    'Ё': 'Е',
    'Й': 'И',
  };

  /// Upper-case Cyrillic letters only, with look-alikes mapped.
  static String letters(String value) {
    final upper = value.toUpperCase();
    final out = StringBuffer();
    for (final rune in upper.runes) {
      final ch = String.fromCharCode(rune);
      final mapped = _homoglyphs[ch] ?? ch;
      if (RegExp(r'[А-ЯЁ]').hasMatch(mapped)) out.write(mapped);
    }
    return out.toString();
  }

  static int _distance(String a, String b) {
    if (a == b) return 0;
    var previous = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 0; i < a.length; i++) {
      final current = <int>[i + 1];
      for (var j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        current.add(
          [
            current[j] + 1,
            previous[j + 1] + 1,
            previous[j] + cost,
          ].reduce((x, y) => x < y ? x : y),
        );
      }
      previous = current;
    }
    return previous.last;
  }

  static const _totalWords = ['ИТОГ', 'ИТОГО', 'ВСЕГО', 'КОПЛАТЕ'];
  static const _excludedWords = [
    'НДС',
    'СДАЧА',
    'НАЛИЧНЫМИ',
    'НАЛИЧНЫЕ',
    'ВНЕСЕНО',
    'ПОЛУЧЕНО',
    'СКИДКА',
    'СКИДКИ',
    'БОНУС',
    'БОНУСЫ',
    'БАЛЛЫ',
    'БАЛЛОВ',
    'НАЛОГ',
    'ОКРУГЛЕНИЕ',
    'БАЛАНС',
    'ОСТАТОК',
  ];
  static const _paymentWords = [
    'БЕЗНАЛИЧНЫМИ',
    'ЭЛЕКТРОННЫМИ',
    'КАРТОЙ',
    'БЕЗНАЛИЧНЫЙ',
    'ЭЛЕКТРОННЫЙ',
  ];

  /// Label class of a row by its first words, tolerant to OCR damage.
  static _Kind _classify(String row) {
    final head = row.replaceAll(RegExp(r'[=≡*#:]'), ' ').trim();
    final words = head
        .split(RegExp(r'\s+'))
        .where((w) => RegExp(r'[A-Za-zА-Яа-яЁё]').hasMatch(w))
        .take(3)
        .map(letters)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return _Kind.none;
    bool near(String word, List<String> targets, {int tolerance = 1}) =>
        targets.any(
          (t) =>
              _distance(word, t) <=
              (t.length <= 3 ? 0 : (t.length >= 8 ? 2 : tolerance)),
        );
    final joined = words.join();
    final first = words.first;
    // OCR noise from the paper edge can precede the label: look at the
    // first three words, not only the first one.
    if (words.take(3).any((w) => w.length >= 3 && near(w, _excludedWords))) {
      return _Kind.excluded;
    }
    // «ИТОГО К ОПЛАТЕ», «К ОПЛАТЕ», split «И ТОГ», «ИТОГ:».
    if (words.take(3).any((w) => near(w, _totalWords)) ||
        near(joined, ['ИТОГОКОПЛАТЕ', 'КОПЛАТЕ', 'ИТОГ', 'ИТОГО']) ||
        (words.length >= 2 && near(words[0] + words[1], _totalWords))) {
      return _Kind.total;
    }
    if (RegExp(
      r'^(?:TOTAL|GRANDTOTAL|AMOUNTDUE)',
    ).hasMatch(head.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), ''))) {
      return _Kind.total;
    }
    if (words.take(3).any((w) => near(w, _paymentWords, tolerance: 2)) ||
        (first == 'ОПЛАТА' && words.length > 1 && near(words[1], ['КАРТОЙ']))) {
      return _Kind.payment;
    }
    return _Kind.item;
  }

  /// Monetary values with two decimals, OCR-repaired (`О`→0, `З`→3, …).
  static List<int> amounts(String row) {
    final repaired = row.replaceAllMapped(
      RegExp(r'[\dОоOoЗзбlI|SB][\dОоOoЗзбlI|SB ]*[.,]\s?[\dОоOoЗзбlI|SB]{2}'),
      (m) {
        final token = m.group(0)!;
        final digits = token.replaceAll(RegExp(r'[^0-9]'), '').length;
        if (digits * 2 < token.replaceAll(RegExp(r'[ .,]'), '').length) {
          return token;
        }
        return token
            .replaceAll(RegExp('[ОоOo]'), '0')
            .replaceAll(RegExp('[Зз]'), '3')
            .replaceAll('б', '6')
            .replaceAll(RegExp('[lI|]'), '1')
            .replaceAll('S', '5')
            .replaceAll('B', '8');
      },
    );
    final result = <int>[];
    for (final m in RegExp(
      r'(?<![\d.,])\d{1,3}(?:[  ]?\d{3})*\s?[.,]\s?\d{2}(?![\d%]|[.,]\d)|(?<![\d.,])\d+\s?[.,]\s?\d{2}(?![\d%]|[.,]\d)',
    ).allMatches(repaired)) {
      final raw = m.group(0)!.replaceAll(RegExp(r'\s'), '');
      final normalized = raw.replaceAll(',', '.');
      try {
        final value = FinanceEngine.parseMinor(normalized);
        if (value > 0) result.add(value);
      } on FormatException {
        continue;
      }
    }
    // Whole rubles written out: `1 250 рублей`, `1 250 руб.`, `1 250 ₽`.
    for (final m in RegExp(
      r'(?<![\d.,])(\d{1,3}(?:[ \u00a0]\d{3})*|\d+)\s*(?:руб(?:лей|ля|ль)?\.?|₽)',
      caseSensitive: false,
    ).allMatches(repaired)) {
      if (RegExp(
        r'[.,]\s?\d{2}\s*$',
      ).hasMatch(repaired.substring(0, m.start + m.group(1)!.length))) {
        continue;
      }
      final value = int.tryParse(m.group(1)!.replaceAll(RegExp(r'\s'), ''));
      if (value != null && value > 0 && !result.contains(value * 100)) {
        result.add(value * 100);
      }
    }
    // Quantity × price rows: the last value is the line amount.
    return result;
  }
}

enum _Kind { none, total, payment, excluded, item }

class _Row {
  const _Row(
    this.kind,
    this.amounts, [
    this.vat,
    this.loose = const [],
    this.rank = 1,
    this.discount = false,
    this.wholeTail,
  ]);
  final _Kind kind;
  final List<int> amounts;
  final (int, int)? vat;

  /// Numbers whose separator was lost or kopecks damaged: `2548 20`,
  /// `2548 ‘ 20`, `=4199_o0`.
  final List<int> loose;

  /// For total rows: 1 `ИТОГ`/`ИТОГО`, 2 `… К ОПЛАТЕ`, 3 `ВСЕГО`/`TOTAL`.
  final int rank;

  /// An excluded `СКИДКА` row.
  final bool discount;

  /// Total rows only: a whole-ruble value ending the row (`ИТОГО 1000`,
  /// `Итого 1000 RUB`) when no kopeck amount was printed.
  final int? wholeTail;
  static _Row parse(String text) {
    final amounts = ReceiptTotal.amounts(text);
    final vat = ReceiptTotal.vatOf(text);
    if (vat != null) return _Row(_Kind.excluded, amounts, vat);
    final loose = [
      for (final m in RegExp(
        r'(?<![\d.,])(\d{2,6})\s?[^\d\sA-Za-zА-Яа-яЁё]?\s?([0-9oOоО@]{2})(?![\d%])',
      ).allMatches(text))
        int.parse(m.group(1)!) * 100 +
            int.parse(m.group(2)!.replaceAll(RegExp('[oOоО@]'), '0')),
    ];
    final plain = _plain(text, amounts);
    final rank = plain.kind == _Kind.total ? ReceiptTotal._rank(text) : 1;
    return _Row(
      plain.kind,
      plain.amounts,
      null,
      loose,
      rank,
      plain.kind == _Kind.excluded &&
          ReceiptTotal.letters(text).contains('СКИДК'),
      plain.kind == _Kind.total && amounts.isEmpty ? _wholeTail(text) : null,
    );
  }

  static int? _wholeTail(String text) {
    final match = RegExp(
      r'(?<![\d.,])(\d{1,3}(?:[ \u00a0]\d{3})+|\d{2,7})\s*(?:rub|rur|руб\S*|₽)?\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    final value = int.tryParse(
      match?.group(1)?.replaceAll(RegExp(r'\s'), '') ?? '',
    );
    return value == null || value <= 0 ? null : value * 100;
  }

  static _Row _plain(String text, List<int> amounts) {
    final hasLetters = RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(
      text.replaceAll(
        RegExp(r'руб(?:лей|ля|ль)?\.?|rub', caseSensitive: false),
        '',
      ),
    );
    if (!hasLetters) {
      // `1 x 545.80 =545.80` or a bare `=5824.20` value row.
      final multiplied = RegExp(r'\d\s*[xхX×*]\s*\d').hasMatch(text);
      return _Row(multiplied ? _Kind.item : _Kind.none, amounts);
    }
    return _Row(ReceiptTotal._classify(text), amounts);
  }
}
