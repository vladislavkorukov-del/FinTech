import 'bank_catalog.dart';
import 'scan_document.dart';

/// One account found on a screenshot of another finance app (Finance 1.21).
/// Always reviewed by the person before anything is created.
class AccountDraft {
  const AccountDraft({
    required this.name,
    required this.amountMinor,
    required this.currency,
    this.lastFour = '',
    this.bank = '',
  });
  final String name;

  /// Balance in minor units; negative for a debt (credit card, loan).
  final int amountMinor;
  final String currency;
  final String lastFour;

  /// A bank from the Bank of Russia catalog, when the name names one.
  final String bank;
}

/// Reads a list of accounts with balances from OCR text: «Наличные 12 500 ₽»,
/// «Тинькофф Black •• 4821  −3 200,50 ₽», a name on one line and its balance
/// on the next. Totals and headings are skipped.
abstract final class AccountImportParser {
  static List<AccountDraft> parse(
    String text, {
    List<RecognizedLine> lines = const [],
    String defaultCurrency = 'RUB',
  }) {
    final rows = lines.isEmpty
        ? text.split('\n')
        : _visualRows(lines).map((r) => r.text).toList();
    final drafts = <AccountDraft>[];
    String? pendingName;
    for (final raw in rows) {
      final row = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (row.isEmpty) continue;
      final money = _money(row);
      if (money == null) {
        // A name line waiting for its balance on the next line.
        final name = _cleanName(row);
        pendingName = name.isEmpty || _skip(name) ? null : row;
        continue;
      }
      var nameText = row.replaceRange(money.start, money.end, ' ').trim();
      if (_cleanName(nameText).isEmpty && pendingName != null) {
        nameText = pendingName;
      }
      pendingName = null;
      final name = _cleanName(nameText);
      if (name.isEmpty || _skip(name)) continue;
      final four = RegExp(
        r'(?:[*•·∙●.xх]{2,}|№)\s?(\d{4})\b',
      ).firstMatch(nameText)?.group(1);
      drafts.add(
        AccountDraft(
          name: name,
          amountMinor: money.minor,
          currency: money.currency ?? defaultCurrency,
          lastFour: four ?? '',
          bank: _bank(name),
        ),
      );
    }
    return drafts;
  }

  static const _currencies = <String, String>{
    '₽': 'RUB',
    'руб': 'RUB',
    'р': 'RUB',
    'rub': 'RUB',
    'rur': 'RUB',
    r'$': 'USD',
    'usd': 'USD',
    '€': 'EUR',
    'eur': 'EUR',
    '₸': 'KZT',
    'kzt': 'KZT',
    '¥': 'CNY',
    'cny': 'CNY',
    '₺': 'TRY',
    'try': 'TRY',
    '£': 'GBP',
    'gbp': 'GBP',
    '₾': 'GEL',
    'gel': 'GEL',
    'aed': 'AED',
    'chf': 'CHF',
  };

  /// The balance in a row: grouped digits with optional kopecks, sign and
  /// currency. A bare short number (a card's last four digits, a date) is
  /// not a balance.
  static ({int minor, String? currency, int start, int end})? _money(
    String row,
  ) {
    final pattern = RegExp(
      r'([-−–+]?)\s?(\$|€|₽|£|¥|₸|₺|₾)?\s?'
      r'(\d{1,3}(?:[   .,]\d{3})+|\d+)'
      r'(?:([.,])(\d{1,2}))?(?!\d)\s?'
      r'(₽|руб\.?|р\.?|rub|rur|\$|usd|€|eur|₸|kzt|¥|cny|₺|try|£|gbp|₾|gel|aed|chf)?'
      r'(?![а-яa-z])',
      caseSensitive: false,
    );
    ({int minor, String? currency, int start, int end})? best;
    for (final m in pattern.allMatches(row)) {
      final symbol = (m.group(2) ?? m.group(6))?.toLowerCase();
      final currency = symbol == null
          ? null
          : _currencies[symbol.replaceAll('.', '')];
      final whole = m.group(3)!;
      final grouped = RegExp(r'[   .,]').hasMatch(whole);
      final kopecks = m.group(5);
      // Needs a currency, a thousands group or kopecks to count as money.
      if (currency == null && !grouped && kopecks == null) continue;
      // A date («12.11.2026») is not a balance.
      final after = row.substring(m.end);
      final before = row.substring(0, m.start);
      if (RegExp(r'^[./-]\d').hasMatch(after) ||
          RegExp(r'\d[./-]$').hasMatch(before)) {
        continue;
      }
      // «4821» after dots is a card number, not a balance.
      if (RegExp(r'[*•·∙●]\s?$').hasMatch(before)) continue;
      final value =
          int.parse(whole.replaceAll(RegExp(r'[   .,]'), '')) * 100 +
          int.parse((kopecks ?? '0').padRight(2, '0'));
      final sign = (m.group(1) ?? '').isNotEmpty && m.group(1) != '+' ? -1 : 1;
      final found = (
        minor: sign * value,
        currency: currency,
        start: m.start,
        end: m.end,
      );
      // The rightmost money in the row is its balance.
      if (best == null || m.start >= best.start) best = found;
    }
    return best;
  }

  static final _skipWords = RegExp(
    r'^(итог[оа]?|всего|общий баланс|баланс|все счета|мои счета|счета|'
    r'доступно|доступный остаток|остаток|сумма|капитал|активы|долги|'
    r'кредитный лимит|лимит|total|balance|accounts|net worth)$',
  );

  static bool _skip(String name) =>
      _skipWords.hasMatch(name.toLowerCase().replaceAll('ё', 'е').trim());

  /// The account name without card masks, symbols and stray digits.
  static String _cleanName(String value) => value
      .replaceAll(RegExp(r'(?:[*•·∙●.xх]{2,}|№)\s?\d{4}\b'), ' ')
      .replaceAll(RegExp(r'[|•·∙●*>›»<‹«]+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—:]+|[\s\-–—:]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// A bank named in the account name («Тинькофф Black» → Т-Банк).
  static String _bank(String name) {
    final words = name.split(' ');
    for (var n = words.length; n >= 1; n--) {
      for (var i = 0; i + n <= words.length; i++) {
        final bank = BankCatalog.byName(words.sublist(i, i + n).join(' '));
        if (bank != null) return bank.name;
      }
    }
    return '';
  }

  /// OCR lines joined into visual rows by vertical overlap, left to right.
  static List<({String text, double top})> _visualRows(
    List<RecognizedLine> lines,
  ) {
    final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
    final rows = <List<RecognizedLine>>[];
    for (final line in sorted) {
      final mid = (line.top + line.bottom) / 2;
      final row = rows.where((r) {
        final top = r.map((l) => l.top).reduce((a, b) => a < b ? a : b);
        final bottom = r.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
        return mid > top && mid < bottom;
      }).firstOrNull;
      if (row == null) {
        rows.add([line]);
      } else {
        row.add(line);
      }
    }
    return [
      for (final r in rows)
        (
          text: (r..sort((a, b) => a.left.compareTo(b.left)))
              .map((l) => l.text)
              .join('   '),
          top: r.first.top,
        ),
    ];
  }
}
