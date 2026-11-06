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
  }) => lines.isEmpty
      ? _fromText(text, defaultCurrency)
      : _fromLines(lines, defaultCurrency);

  /// Plain text: a name with its balance on one line, or the name on the
  /// first line above the balance (a thin caption like «Личное» between them
  /// is not the name).
  static List<AccountDraft> _fromText(String text, String currency) {
    final drafts = <AccountDraft>[];
    String? firstName;
    for (final raw in text.split('\n')) {
      final row = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (row.isEmpty) continue;
      final money = _money(row);
      if (money == null) {
        final name = _cleanName(row);
        if (name.isNotEmpty && !_skip(name)) firstName ??= row;
        continue;
      }
      var nameText = row.replaceRange(money.start, money.end, ' ').trim();
      if (_cleanName(nameText).isEmpty && firstName != null) {
        nameText = firstName;
      }
      firstName = null;
      final draft = _draft(nameText, money, currency);
      if (draft != null) drafts.add(draft);
    }
    return drafts;
  }

  /// Screen geometry, anchored on the balances: each balance on the right
  /// belongs to the name on its left at its height or just above it — the
  /// bold top line of a list item. The thin caption under the name
  /// («Личное») sits below the balance and is not taken; icon circles (read
  /// as «©», «@», «0») have no letters and are ignored.
  static List<AccountDraft> _fromLines(
    List<RecognizedLine> lines,
    String currency,
  ) {
    final sorted = [...lines]..sort((a, b) => a.top.compareTo(b.top));
    final used = <RecognizedLine>{};
    final drafts = <AccountDraft>[];
    for (final line in sorted) {
      final text = line.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final money = _money(text);
      if (money == null) continue;
      // The name in the same line («Наличные 10 000,00 ₽»).
      var nameText = text.replaceRange(money.start, money.end, ' ').trim();
      if (_cleanName(nameText).isEmpty) {
        final h = line.bottom - line.top;
        final mid = (line.top + line.bottom) / 2;
        RecognizedLine? best;
        for (final other in sorted) {
          if (identical(other, line) || used.contains(other)) continue;
          if (other.left >= line.left) continue; // names are on the left
          if (_money(other.text) != null) continue;
          final name = _cleanName(other.text);
          if (name.isEmpty || _skip(name)) continue;
          final center = (other.top + other.bottom) / 2;
          // At the balance's height or up to about one line above it.
          if (center < mid - 1.6 * h || center > mid + .2 * h) continue;
          if (best == null || other.top < best.top) best = other;
        }
        if (best == null) continue;
        used.add(best);
        nameText = best.text;
      }
      final draft = _draft(nameText, money, currency);
      if (draft != null) drafts.add(draft);
    }
    return drafts;
  }

  static AccountDraft? _draft(
    String nameText,
    ({int minor, String? currency, int start, int end}) money,
    String currency,
  ) {
    final name = _cleanName(nameText);
    if (name.isEmpty || _skip(name)) return null;
    final four = RegExp(
      r'(?:[*•·∙●.xх]{2,}|№)\s?(\d{4})\b',
    ).firstMatch(nameText)?.group(1);
    return AccountDraft(
      name: name,
      amountMinor: money.minor,
      currency: money.currency ?? currency,
      lastFour: four ?? '',
      bank: _bank(name),
    );
  }

  static const _currencies = <String, String>{
    '₽': 'RUB',
    'руб': 'RUB',
    'р': 'RUB',
    'p': 'RUB', // OCR often reads ₽ as a Latin P
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
      r'(₽|руб\.?|р\.?|p\.?|rub|rur|\$|usd|€|eur|₸|kzt|¥|cny|₺|try|£|gbp|₾|gel|aed|chf)?'
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
    r'кредитный лимит|лимит|личное|общее|семейное|совместное|'
    r'total|balance|accounts|net worth)$',
  );

  static bool _skip(String name) =>
      _skipWords.hasMatch(name.toLowerCase().replaceAll('ё', 'е').trim());

  /// The account name without card masks, symbols and stray digits.
  static String _cleanName(String value) => _dropIcons(value)
      .replaceAll(RegExp(r'(?:[*•·∙●.xх]{2,}|№)\s?\d{4}\b'), ' ')
      .replaceAll(RegExp(r'[|•·∙●*>›»<‹«]+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–—:]+|[\s\-–—:]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Leading tokens without letters are icons read as text («©», «@»,
  /// «(=)», «00000000»).
  static String _dropIcons(String value) {
    final words = value.trim().split(RegExp(r'\s+'));
    var i = 0;
    while (i < words.length &&
        !RegExp(r'[a-zа-яё]', caseSensitive: false).hasMatch(words[i])) {
      i++;
    }
    return words.sublist(i).join(' ');
  }

  /// The account type its name suggests: cash, deposit, savings, credit,
  /// investment, wallet, debit card or bank account.
  static String typeFor(String name, int amount, String lastFour) {
    final n = name.toLowerCase();
    if (n.contains('налич')) return 'cash';
    if (n.contains('вклад') || n.contains('депозит')) return 'deposit';
    if (n.contains('накопит') || n.contains('копилк') || n.contains('сбереж')) {
      return 'savings';
    }
    if (n.contains('кредит') || amount < 0) return 'credit';
    if (n.contains('инвест') || n.contains('брокер') || n.contains('иис')) {
      return 'investment';
    }
    if (n.contains('кошел') || n.contains('юmoney') || n.contains('qiwi')) {
      return 'wallet';
    }
    // Card digits («•• 4821») or the word «карта» mean a card.
    if (lastFour.isNotEmpty || n.contains('карт') || n.contains('card')) {
      return 'debit';
    }
    return 'bank';
  }

  /// A bank named in the account name («Тинькофф Black» → Т-Банк).
  static String bankFor(String name) => _bank(name);

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
}
