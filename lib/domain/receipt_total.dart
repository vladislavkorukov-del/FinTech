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
/// The amount always is a number printed on the receipt. It is selected by
/// evidence, never computed:
///  * a total label (`ИТОГ`, `ИТОГО`, `К ОПЛАТЕ`, `ВСЕГО`, `TOTAL`) read with
///    OCR tolerance — Latin look-alikes, one wrong/missing letter, spaces;
///    the value is on the label row or on one of the next two rows;
///  * an independent confirmation: the same value on a cashless payment row
///    (`БЕЗНАЛИЧНЫМИ`, `ЭЛЕКТРОННЫМИ`, `КАРТОЙ`) or equal to the sum of the
///    printed item amounts.
/// Item prices, VAT, cash tendered, change, discounts and bonuses never win.
/// Two different, equally supported values give null (review by the person).
abstract final class ReceiptTotal {
  static ReceiptTotalMatch? find(
    List<String> rows, {
    List<String> focusRows = const [],
  }) {
    final parsed = [for (final row in rows) _Row.parse(row)];
    final focus = [for (final row in focusRows) _Row.parse(row)];
    final scores = <int, int>{};
    final evidence = <int, Set<String>>{};
    void add(int value, int score, String why) {
      if (value <= 0) return;
      scores[value] = (scores[value] ?? 0) + score;
      (evidence[value] ??= {}).add(why);
    }

    for (final list in [parsed, focus]) {
      final focused = identical(list, focus);
      for (var i = 0; i < list.length; i++) {
        final row = list[i];
        if (row.kind != _Kind.total) continue;
        var value = row.amounts.isEmpty ? null : row.amounts.last;
        // Value printed below the label (next row or one row further when the
        // big «ИТОГ» font shifts the right column), skipping excluded rows.
        for (var j = i + 1; value == null && j <= i + 2; j++) {
          if (j >= list.length) break;
          final next = list[j];
          if (next.kind == _Kind.total || next.kind == _Kind.excluded) break;
          if (next.kind == _Kind.none && next.amounts.length == 1) {
            value = next.amounts.single;
          }
        }
        if (value != null) {
          add(value, focused ? 110 : 100, focused ? 'focus-label' : 'label');
        }
      }
    }
    final all = [...parsed, ...focus];
    // Every value printed on a non-item row (total, bare value, payment).
    final printed = <int>{
      for (final row in all)
        if (row.kind == _Kind.none ||
            row.kind == _Kind.total ||
            row.kind == _Kind.payment)
          ...row.amounts,
    };
    // Cashless payment always equals the amount charged.
    for (final value in <int>{
      for (final row in all)
        if (row.kind == _Kind.payment && row.amounts.isNotEmpty)
          row.amounts.last,
    }) {
      add(value, 45, 'payment');
    }
    // A single VAT line fixes the total: VAT = total × rate / (100 + rate).
    final vats = <(int, int)>{
      for (final row in all)
        if (row.vat != null) row.vat!,
    };
    // A VAT row counts only when its amount really is the VAT of a printed
    // value; a skewed photo can join «НДС 20%» with the total's row.
    final vatValues = <int>{};
    if (vats.length == 1) {
      final (rate, vat) = vats.single;
      for (final value in {...printed, ...scores.keys}) {
        if (value > vat &&
            ((value * rate / (100 + rate)) - vat).abs() <= 1.01) {
          add(value, 45, 'vat');
          vatValues.add(vat);
        }
      }
    }
    // A total whose decimal separator OCR lost («2548 ‘ 20») is accepted
    // only when it matches the single VAT row exactly.
    if (vats.length == 1) {
      final (rate, vat) = vats.single;
      for (final row in all) {
        if (row.kind == _Kind.excluded || row.kind == _Kind.item) continue;
        for (final value in row.loose) {
          if (!printed.contains(value) &&
              value > vat &&
              ((value * rate / (100 + rate)) - vat).abs() <= 1.01) {
            add(value, 45, 'vat');
            add(value, 10, 'loose');
          }
        }
      }
    }
    // Implicit VAT pairs (the VAT row's label was lost): total T and VAT
    // T × rate / (100 + rate) printed as separate values. The VAT value
    // can never be the total.
    for (final value in printed) {
      for (final other in printed) {
        if (other >= value) continue;
        for (final rate in const [22, 20, 10]) {
          if (((value * rate / (100 + rate)) - other).abs() <= 1.01) {
            add(value, 30, 'vat');
            vatValues.add(other);
          }
        }
      }
    }
    // The same value read on two rows (or in both passes) is corroborated.
    final counts = <int, int>{};
    for (final row in all) {
      if (row.kind == _Kind.item || row.kind == _Kind.excluded) continue;
      for (final value in row.amounts.toSet()) {
        counts[value] = (counts[value] ?? 0) + 1;
      }
    }
    counts.forEach((value, count) {
      if (count >= 2 && scores.containsKey(value)) add(value, 20, 'repeat');
    });
    // Sum of printed item amounts confirms a printed value; never invents one.
    final items = [
      for (final row in parsed)
        if (row.kind == _Kind.item && row.amounts.isNotEmpty) row.amounts.last,
    ];
    if (items.length >= 2) {
      final sum = items.fold<int>(0, (a, b) => a + b);
      if (scores.containsKey(sum) || printed.contains(sum)) {
        add(sum, 40, 'items-sum');
      }
    }
    for (final value in vatValues) {
      if (!(evidence[value]?.contains('payment') ?? false)) {
        scores.remove(value);
        evidence.remove(value);
      }
    }
    if (scores.isEmpty) return null;
    bool labelled(int v) =>
        evidence[v]!.contains('label') || evidence[v]!.contains('focus-label');
    bool confirmed(int v) =>
        evidence[v] != null &&
        evidence[v]!.any(
          (w) =>
              w == 'payment' || w == 'vat' || w == 'items-sum' || w == 'repeat',
        );
    final ranked = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    var best = ranked.first.key;
    if (ranked.length > 1 && ranked[1].value == ranked.first.value) {
      final tied = ranked.where((e) => e.value == ranked.first.value);
      final sure = tied.where((e) => confirmed(e.key)).toList();
      if (sure.length != 1) return null;
      best = sure.single.key;
    }
    // Without a readable label a value needs an independent confirmation.
    if (!labelled(best) && !confirmed(best)) return null;
    // The same printed number read twice with one different digit: trust the
    // confirmed reading; with no confirmation leave the amount for review.
    var switched = false;
    if (!confirmed(best)) {
      final rivals = {
        ...printed,
        ...scores.keys,
      }.where((v) => v != best && _oneDigitApart(v, best)).toList();
      if (rivals.isNotEmpty) {
        final sure = rivals.where(confirmed).toList();
        if (sure.length != 1) return null;
        best = sure.single;
        switched = true;
      }
    }
    // A label-only total contradicted by the single VAT row is a misread
    // digit somewhere: leave it for review instead of guessing.
    if (!confirmed(best) && vats.length == 1) {
      final (rate, vat) = vats.single;
      if (vat < best * .25 &&
          ((best * rate / (100 + rate)) - vat).abs() > 1.01) {
        return null;
      }
    }
    if (labelled(best) && !switched) {
      // Another value with its own label is a conflict, not a choice.
      for (final other in ranked) {
        if (other.key == best || !labelled(other.key)) continue;
        if (!confirmed(best) || confirmed(other.key)) return null;
      }
    }
    final why = evidence[best]!;
    return ReceiptTotalMatch(
      best,
      why.toList()..sort(),
      warning: labelled(best) && !switched
          ? null
          : why.contains('payment')
          ? 'Надпись «ИТОГ» не распознана. Сумма взята из строки безналичной оплаты — проверьте.'
          : 'Надпись «ИТОГ» распознана нечётко. Сумма подтверждена по НДС или сумме позиций — проверьте.',
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
    final rate = RegExp(r'(?<!\d)(5|7|10|20|22)\s*%').firstMatch(row);
    final money = amounts(row);
    if (rate == null || money.isEmpty) return null;
    return (int.parse(rate.group(1)!), money.last);
  }

  /// Whether an OCR row is a (possibly damaged) total label.
  static bool isTotalRow(String row) =>
      RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(row) &&
      _classify(row) == _Kind.total;

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
    // Quantity × price rows: the last value is the line amount.
    return result;
  }
}

enum _Kind { none, total, payment, excluded, item }

class _Row {
  const _Row(this.kind, this.amounts, [this.vat, this.loose = const []]);
  final _Kind kind;
  final List<int> amounts;
  final (int, int)? vat;

  /// Numbers whose separator was lost: `2548 20`, `2548 ‘ 20`.
  final List<int> loose;
  static _Row parse(String text) {
    final amounts = ReceiptTotal.amounts(text);
    final vat = ReceiptTotal.vatOf(text);
    if (vat != null) return _Row(_Kind.excluded, amounts, vat);
    final loose = [
      for (final m in RegExp(
        r'(?<![\d.,])(\d{2,6})\s?[^\d\sA-Za-zА-Яа-яЁё]?\s?(\d{2})(?![\d%])',
      ).allMatches(text))
        int.parse(m.group(1)!) * 100 + int.parse(m.group(2)!),
    ];
    if (loose.isNotEmpty) {
      final row = _Row._plain(text, amounts);
      return _Row(row.kind, row.amounts, null, loose);
    }
    return _Row._plain(text, amounts);
  }

  static _Row _plain(String text, List<int> amounts) {
    final hasLetters = RegExp(r'[A-Za-zА-Яа-яЁё]{2,}').hasMatch(text);
    if (!hasLetters) {
      // `1 x 545.80 =545.80` or a bare `=5824.20` value row.
      final multiplied = RegExp(r'\d\s*[xхX×*]\s*\d').hasMatch(text);
      return _Row(multiplied ? _Kind.item : _Kind.none, amounts);
    }
    return _Row(ReceiptTotal._classify(text), amounts);
  }
}
