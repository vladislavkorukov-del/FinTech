import 'dart:convert';

import 'finance_engine.dart';
import 'models.dart';
import 'voice_entry_parser.dart';

/// Operations from other finance apps and banks as CSV (Finora 1.35):
/// Дзен-мани, CoinKeeper, Money Manager, Monefy, Wallet, Toshl, Spendee,
/// 1Money, bank statements and any table with a date and a sum.
///
/// The file is read in any of UTF-8, UTF-16 or Windows-1251, with `,`, `;`
/// or tab; the header row is found among the first lines (banks put a title
/// above it); each column gets a role from its header, which the person can
/// change. Operations are added to the base — nothing existing is replaced.
enum CsvRole {
  skip,
  date,
  time,
  amount,
  expense,
  income,
  kind,
  category,
  subcategory,
  account,
  toAccount,
  currency,
  toCurrency,
  payee,
  note,
  tags,
  status,
  amountMinor,
  accountAmount,
}

const csvRoleNames = {
  CsvRole.skip: 'Не загружать',
  CsvRole.date: 'Дата',
  CsvRole.time: 'Время',
  CsvRole.amount: 'Сумма (± или с типом)',
  CsvRole.expense: 'Сумма расхода',
  CsvRole.income: 'Сумма дохода',
  CsvRole.kind: 'Тип (расход / доход / перевод)',
  CsvRole.category: 'Категория',
  CsvRole.subcategory: 'Подкатегория',
  CsvRole.account: 'Счёт',
  CsvRole.toAccount: 'Счёт зачисления',
  CsvRole.currency: 'Валюта',
  CsvRole.toCurrency: 'Валюта зачисления',
  CsvRole.payee: 'Получатель / место',
  CsvRole.note: 'Комментарий',
  CsvRole.tags: 'Метки',
  CsvRole.status: 'Статус',
  CsvRole.amountMinor: 'Сумма в копейках',
  CsvRole.accountAmount: 'Сумма в валюте счёта',
};

class ForeignTable {
  ForeignTable({
    required this.headers,
    required this.rows,
    required this.roles,
    required this.format,
    required this.delimiter,
  });
  final List<String> headers;
  final List<List<String>> rows;

  /// Guessed roles, one per column.
  final List<CsvRole> roles;

  /// The app the file looks like, or «Таблица операций».
  final String format;
  final String delimiter;
}

/// One operation read from the file, before it meets the base.
class ForeignRow {
  ForeignRow({
    required this.line,
    required this.date,
    required this.kind,
    required this.amountMinor,
    this.toAmountMinor,
    this.account = '',
    this.toAccount = '',
    this.category = '',
    this.subcategory = '',
    this.currency,
    this.toCurrency,
    this.payee = '',
    this.note = '',
    this.tags = const [],
  });
  final int line;
  final DateTime date;
  final EntryKind kind;
  final int amountMinor;
  final int? toAmountMinor;
  final String account, toAccount, category, subcategory, payee, note;
  final String? currency, toCurrency;
  final List<String> tags;
}

class ForeignParse {
  ForeignParse(this.rows, this.skipped, {required this.signed});
  final List<ForeignRow> rows;

  /// Why lines were left out → how many.
  final Map<String, int> skipped;

  /// The sums carry their sign (or a type column / separate columns says
  /// what they are); otherwise [ForeignOptions.unsignedAs] decides.
  final bool signed;

  int count(EntryKind kind) => rows.where((r) => r.kind == kind).length;
  int get skippedTotal => skipped.values.fold(0, (a, b) => a + b);

  /// Account names from the file (sources and destinations), in order.
  List<String> get accounts => {
    for (final r in rows) ...[
      r.account,
      if (r.kind == EntryKind.transfer) r.toAccount,
    ],
  }.toList();
}

class ForeignOptions {
  const ForeignOptions({
    this.unsignedAs = EntryKind.expense,
    this.accountMap = const {},
    this.defaultAccountId,
    this.createCategories = true,
    this.skipDuplicates = true,
  });

  /// What a sum without a sign or type is.
  final EntryKind unsignedAs;

  /// File account name → an existing account id; missing (or null) — found
  /// by name or created.
  final Map<String, String?> accountMap;

  /// For lines without an account; null — «Импорт» (created).
  final String? defaultAccountId;
  final bool createCategories;
  final bool skipDuplicates;
}

class ForeignReport {
  int added = 0, duplicates = 0, failed = 0;
  final newAccounts = <String>[];
  final newCategories = <String>[];
}

abstract final class ForeignCsv {
  static const maxBytes = 20 * 1024 * 1024;

  // ── Bytes → text ───────────────────────────────────────────────────────

  static String decode(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _utf16(bytes.sublist(2), little: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _utf16(bytes.sublist(2), little: false);
    }
    var body = bytes;
    if (body.length >= 3 &&
        body[0] == 0xEF &&
        body[1] == 0xBB &&
        body[2] == 0xBF) {
      body = body.sublist(3);
    }
    try {
      return utf8.decode(body);
    } on FormatException {
      return cp1251(body);
    }
  }

  static String _utf16(List<int> bytes, {required bool little}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        little
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// Windows-1251, the old Russian Excel/bank encoding.
  static String cp1251(List<int> bytes) {
    const high =
        'ЂЃ‚ѓ„…†‡€‰Љ‹ЊЌЋЏђ‘’“”•–—�™љ›њќћџ ЎўЈ¤Ґ¦§Ё©Є«¬­®Ї°±Ііґµ¶·ё№є»јЅѕї';
    final out = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else if (b >= 0xC0) {
        out.writeCharCode(0x0410 + b - 0xC0);
      } else {
        out.write(high[b - 0x80]);
      }
    }
    return out.toString();
  }

  // ── Text → table ───────────────────────────────────────────────────────

  static ForeignTable read(String text) {
    if (text.startsWith('﻿')) text = text.substring(1);
    if (text.trimLeft().startsWith('"Finora CSV"') ||
        text.trimLeft().startsWith('Finora CSV')) {
      throw const FormatException(
        'Это полная копия Finora — восстановите её через «Из таблицы CSV».',
      );
    }
    final delimiter = _delimiter(text);
    final all = parse(
      text,
      delimiter,
    ).where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (all.isEmpty) {
      throw const FormatException('Файл пустой');
    }
    // The header: the first of the top lines with a date and a sum column.
    var headerAt = -1;
    for (var i = 0; i < all.length && i < 40; i++) {
      final roles = guessRoles(all[i]);
      final hasSum = roles.any(
        (r) =>
            r == CsvRole.amount ||
            r == CsvRole.expense ||
            r == CsvRole.income ||
            r == CsvRole.amountMinor,
      );
      if (roles.contains(CsvRole.date) && hasSum) {
        headerAt = i;
        break;
      }
    }
    final List<String> headers;
    final List<CsvRole> roles;
    if (headerAt < 0) {
      // No recognisable header: columns are named by the first line and
      // the person assigns the roles.
      headerAt = 0;
      headers = [for (final h in all.first) h.trim()];
      roles = List.filled(headers.length, CsvRole.skip);
    } else {
      headers = [for (final h in all[headerAt]) h.trim()];
      roles = guessRoles(headers);
    }
    final width = headers.length;
    final rows = [
      for (final r in all.skip(headerAt + 1))
        [for (var i = 0; i < width; i++) i < r.length ? r[i] : ''],
    ];
    return ForeignTable(
      headers: headers,
      rows: rows,
      roles: roles,
      format: _format(headers),
      delimiter: delimiter,
    );
  }

  static String _delimiter(String text) {
    final lines = const LineSplitter().convert(text).take(40).toList();
    var best = ',';
    var bestScore = -1;
    for (final d in const [';', ',', '\t', '|']) {
      final counts = <int>[];
      for (final line in lines) {
        var n = 0, quoted = false;
        for (var i = 0; i < line.length; i++) {
          if (line[i] == '"') quoted = !quoted;
          if (!quoted && line[i] == d) n++;
        }
        if (n > 0) counts.add(n);
      }
      if (counts.isEmpty) continue;
      // The most common count, times how many lines have it.
      final freq = <int, int>{};
      for (final c in counts) {
        freq[c] = (freq[c] ?? 0) + 1;
      }
      final top = freq.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final score = top.value * 100 + top.key;
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  /// RFC 4180 with any [delimiter].
  static List<List<String>> parse(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else if (ch != '\r') {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  // ── Headers → roles ────────────────────────────────────────────────────

  static String _norm(String h) => h
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll('﻿', '')
      .replaceAll(RegExp(r'[_"\.:]+'), ' ')
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static const _exact = <String, CsvRole>{
    // Дзен-мани
    'outcomeaccountname': CsvRole.account,
    'incomeaccountname': CsvRole.toAccount,
    'outcome': CsvRole.expense,
    'income': CsvRole.income,
    'outcomecurrencyshorttitle': CsvRole.currency,
    'incomecurrencyshorttitle': CsvRole.toCurrency,
    'categoryname': CsvRole.category,
    'createddate': CsvRole.skip,
    'changeddate': CsvRole.skip,
    // CoinKeeper («Данные» is its «Дата»)
    'данные': CsvRole.date,
    'из': CsvRole.account,
    'в': CsvRole.toAccount,
    'сумма в валюте': CsvRole.skip,
    'повторение': CsvRole.skip,
    // Money Manager
    'income/expense': CsvRole.kind,
    'income expense': CsvRole.kind,
    // Finora operations table
    'amount minor': CsvRole.amountMinor,
    'destination account': CsvRole.toAccount,
    'destination minor': CsvRole.skip,
    'destination goal': CsvRole.skip,
    'member': CsvRole.skip,
    'id': CsvRole.skip,
    // Tinkoff / banks
    'дата платежа': CsvRole.skip,
    'сумма платежа': CsvRole.accountAmount,
    'валюта платежа': CsvRole.skip,
    'номер карты': CsvRole.account,
    'mcc': CsvRole.skip,
    'кэшбэк': CsvRole.skip,
    'сумма в валюте счета': CsvRole.accountAmount,
    'converted amount': CsvRole.skip,
    'ref currency amount': CsvRole.skip,
    'in main currency': CsvRole.skip,
    'main currency': CsvRole.skip,
  };

  static final _patterns = <(RegExp, CsvRole)>[
    (
      RegExp(
        r'^(дата|date|day|день)(?=\s|$|/)|дата операции|transaction date|дата и время',
      ),
      CsvRole.date,
    ),
    (RegExp(r'^(время|time)$|время операции'), CsvRole.time),
    (RegExp(r'^подкатегор|^subcategor|^sub category'), CsvRole.subcategory),
    (RegExp(r'категор|categor|статья'), CsvRole.category),
    (
      RegExp(r'^(тип|type|вид|направление|direction)(?=\s|$|/)|тип операции'),
      CsvRole.kind,
    ),
    (
      RegExp(
        r'^(расход|расходы|списание|сумма списания|дебет|debit|withdrawal|expense amount|expense|outflow|spent)$',
      ),
      CsvRole.expense,
    ),
    (
      RegExp(
        r'^(доход|доходы|зачисление|сумма зачисления|поступление|приход|кредит|credit|deposit|income amount|inflow)$',
      ),
      CsvRole.income,
    ),
    (
      RegExp(r'^(сумма|amount|sum|value|итого|сумма операции|total)(?=\s|$|/)'),
      CsvRole.amount,
    ),
    (RegExp(r'^(счет зачисления|на счет|to account|to)$'), CsvRole.toAccount),
    (
      RegExp(
        r'^(счет|account|wallet|кошелек|карта|card|счет списания|from account|from|источник)(?=\s|$|/)',
      ),
      CsvRole.account,
    ),
    (RegExp(r'^(валюта|currency)(?=\s|$|/)'), CsvRole.currency),
    (
      RegExp(
        r'получател|плательщик|контрагент|payee|merchant|магазин|^место$|^shop$|^store$|^counterparty',
      ),
      CsvRole.payee,
    ),
    (
      RegExp(r'^(комментари|примечани|заметк|comment|note|memo|назначение)'),
      CsvRole.note,
    ),
    (RegExp(r'^(описание|description|details|детали)'), CsvRole.note),
    (RegExp(r'^(метк|тег|tag|label)'), CsvRole.tags),
    (RegExp(r'^(статус|status|state)$'), CsvRole.status),
  ];

  static List<CsvRole> guessRoles(List<String> headers) {
    final roles = <CsvRole>[];
    final used = <CsvRole>{};
    for (final h in headers) {
      final n = _norm(h);
      var role = _exact[n.replaceAll(' ', '')] ?? _exact[n];
      role ??= _patterns.where((p) => p.$1.hasMatch(n)).firstOrNull?.$2;
      role ??= CsvRole.skip;
      // One column per role (the first); a second «описание» is a payee
      // when there is no payee yet.
      if (role != CsvRole.skip && used.contains(role)) {
        role = role == CsvRole.note && !used.contains(CsvRole.payee)
            ? CsvRole.payee
            : CsvRole.skip;
      }
      if (role != CsvRole.skip) used.add(role);
      roles.add(role);
    }
    // A bank's «описание» is the place, not a note.
    final note = roles.indexOf(CsvRole.note);
    if (note >= 0 &&
        !used.contains(CsvRole.payee) &&
        RegExp(r'^(описание|description)').hasMatch(_norm(headers[note]))) {
      roles[note] = CsvRole.payee;
    }
    return roles;
  }

  static String _format(List<String> headers) {
    final h = headers.map(_norm).map((s) => s.replaceAll(' ', '')).toSet();
    bool has(String s) => h.contains(s);
    if (has('outcomeaccountname')) return 'Дзен-мани';
    if (has('данные') && has('из') && has('в')) return 'CoinKeeper';
    if (has('income/expense') || has('incomeexpense')) return 'Money Manager';
    if (has('refcurrencyamount')) return 'Wallet';
    if (has('convertedamount')) return 'Monefy';
    if (has('expenseamount') && has('incomeamount')) return 'Toshl';
    if (has('датаплатежа') && (has('mcc') || has('кэшбэк'))) {
      return 'Т-Банк (выписка)';
    }
    if (has('amountminor')) return 'Finora — операции';
    if (has('wallet') && has('categoryname')) return 'Spendee';
    return 'Таблица операций';
  }

  // ── Table → operations ─────────────────────────────────────────────────

  static ForeignParse rows(
    ForeignTable table,
    List<CsvRole> roles, {
    EntryKind unsignedAs = EntryKind.expense,
  }) {
    int col(CsvRole r) => roles.indexOf(r);
    final iDate = col(CsvRole.date), iTime = col(CsvRole.time);
    final iAmount = col(CsvRole.amount), iMinor = col(CsvRole.amountMinor);
    final iOut = col(CsvRole.expense), iIn = col(CsvRole.income);
    final iKind = col(CsvRole.kind), iStatus = col(CsvRole.status);
    final iCat = col(CsvRole.category), iSub = col(CsvRole.subcategory);
    final iAcc = col(CsvRole.account), iTo = col(CsvRole.toAccount);
    final iCur = col(CsvRole.currency), iToCur = col(CsvRole.toCurrency);
    final iPayee = col(CsvRole.payee), iNote = col(CsvRole.note);
    final iTags = col(CsvRole.tags), iAccAmount = col(CsvRole.accountAmount);
    String at(List<String> r, int i) {
      final s = i < 0 || i >= r.length ? '' : r[i].trim();
      // Spreadsheet guard apostrophe («'=…», «'-…») from exports like ours.
      return RegExp(r"^'\s*[=+@\-]").hasMatch(s) ? s.substring(1) : s;
    }

    final skipped = <String, int>{};
    void skip(String why) => skipped[why] = (skipped[why] ?? 0) + 1;
    if (iDate < 0 || (iAmount < 0 && iMinor < 0 && iOut < 0 && iIn < 0)) {
      return ForeignParse(const [], {
        'Не выбраны столбцы даты и суммы': table.rows.length,
      }, signed: true);
    }
    final dayFirst = _dayFirst([for (final r in table.rows) at(r, iDate)]);
    // Sums with a sign (or a type / two columns) say what they are.
    final signed =
        iKind >= 0 ||
        iOut >= 0 ||
        iIn >= 0 ||
        table.rows.any(
          (r) => (amount(at(r, iAmount >= 0 ? iAmount : iMinor)) ?? 0) < 0,
        );
    final out = <ForeignRow>[];
    for (var n = 0; n < table.rows.length; n++) {
      final r = table.rows[n];
      final status = at(r, iStatus).toLowerCase();
      if (RegExp(
        r'fail|отклон|отмен|cancel|declin|error|ошибк',
      ).hasMatch(status)) {
        skip('Отменённые или отклонённые');
        continue;
      }
      var date = parseDate(at(r, iDate), dayFirst: dayFirst);
      if (date == null) {
        skip('Без даты');
        continue;
      }
      final time = iTime >= 0 ? _time(at(r, iTime)) : null;
      if (time != null) {
        date = DateTime(
          date.year,
          date.month,
          date.day,
          time.$1,
          time.$2,
          time.$3,
        );
      }
      int? sum;
      if (iMinor >= 0) {
        sum = int.tryParse(at(r, iMinor).replaceAll(RegExp(r'\s'), ''));
      } else if (iAmount >= 0) {
        sum = amount(at(r, iAmount));
      }
      final outSum = iOut >= 0 ? amount(at(r, iOut))?.abs() ?? 0 : 0;
      final inSum = iIn >= 0 ? amount(at(r, iIn))?.abs() ?? 0 : 0;
      final typeText = at(r, iKind).toLowerCase();
      var account = at(r, iAcc);
      var toAccount = at(r, iTo);
      var category = at(r, iCat);
      String? currency = currencyCode(at(r, iCur));
      String? toCurrency = currencyCode(at(r, iToCur));
      int? toSum;
      EntryKind kind;
      if (RegExp(r'transfer.?in|перевод.?(вход|получ)').hasMatch(typeText)) {
        // Money Manager writes each transfer twice; the «out» half is kept.
        skip('Вторая половина перевода');
        continue;
      }
      if (iKind >= 0 && typeText.isNotEmpty) {
        kind =
            _kindOf(typeText) ??
            ((sum ?? 0) < 0 ? EntryKind.expense : unsignedAs);
        sum = (sum ?? (outSum > 0 ? outSum : inSum)).abs();
      } else if (sum == null && (iOut >= 0 || iIn >= 0)) {
        if (outSum > 0 && inSum > 0) {
          kind = EntryKind.transfer;
          sum = outSum;
          toSum = inSum;
        } else if (outSum > 0) {
          kind = EntryKind.expense;
          sum = outSum;
        } else {
          kind = EntryKind.income;
          sum = inSum;
          // Дзен-мани: an income lands on the «income» account.
          if (toAccount.isNotEmpty) account = toAccount;
          if (toCurrency != null) currency = toCurrency;
        }
      } else if (sum != null) {
        kind = sum < 0
            ? EntryKind.expense
            : (signed ? EntryKind.income : unsignedAs);
        sum = sum.abs();
      } else {
        skip('Без суммы');
        continue;
      }
      if (sum == 0) {
        skip('Нулевая сумма');
        continue;
      }
      if (sum > FinanceEngine.maxMinor) {
        skip('Слишком большая сумма');
        continue;
      }
      // Amount already in the account's currency (bank statements).
      final accountSum = iAccAmount >= 0
          ? amount(at(r, iAccAmount))?.abs()
          : null;
      if (accountSum != null && accountSum > 0 && accountSum != sum) {
        sum = accountSum;
        currency = null;
      }
      // CoinKeeper: «Из» → «В» are account → category for an expense and
      // category → account for an income.
      if (iCat < 0 && iTo >= 0 && kind != EntryKind.transfer) {
        if (kind == EntryKind.expense) {
          category = toAccount;
        } else {
          category = account;
          account = toAccount;
        }
        toAccount = '';
      }
      if (kind == EntryKind.transfer) {
        if (toAccount.isEmpty) {
          // A Money Manager transfer names its target in «Category».
          toAccount = category;
        }
        if (toAccount.isEmpty || toAccount == account) {
          skip('Переводы без счёта зачисления');
          continue;
        }
        toSum ??= sum;
      }
      final tags = at(r, iTags)
          .split(RegExp(r'[,;|#]'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      out.add(
        ForeignRow(
          line: n + 1,
          date: date,
          kind: kind,
          amountMinor: sum,
          toAmountMinor: kind == EntryKind.transfer ? toSum : null,
          account: account,
          toAccount: kind == EntryKind.transfer ? toAccount : '',
          category: kind == EntryKind.transfer ? '' : category,
          subcategory: kind == EntryKind.transfer ? '' : at(r, iSub),
          currency: currency,
          toCurrency: toCurrency,
          payee: at(r, iPayee),
          note: at(r, iNote),
          tags: tags,
        ),
      );
    }
    return ForeignParse(out, skipped, signed: signed);
  }

  static EntryKind? _kindOf(String t) {
    if (RegExp(r'перевод|transfer|между сч').hasMatch(t)) {
      return EntryKind.transfer;
    }
    if (RegExp(
      r'доход|income|зачисл|пополн|поступ|приход|возврат|refund|credit|^\+$|^inc',
    ).hasMatch(t)) {
      return EntryKind.income;
    }
    if (RegExp(
      r'расход|expense|outcome|списан|покупк|оплат|платеж|снятие|debit|^-$|^exp',
    ).hasMatch(t)) {
      return EntryKind.expense;
    }
    return null;
  }

  /// «1 234,56», «-1,234.56», «1 234,56 ₽», «−500», «(500)», «500-».
  /// Kopecks; null when there is no number.
  static int? amount(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    var negative = false;
    if (s.startsWith('(') && s.endsWith(')')) {
      negative = true;
      s = s.substring(1, s.length - 1);
    }
    s = s.replaceAll(RegExp('[−‒–—]'), '-');
    if (s.contains('-')) negative = true;
    s = s.replaceAll(RegExp(r"[^0-9.,]"), '');
    if (s.isEmpty || !RegExp(r'\d').hasMatch(s)) return null;
    final lastDot = s.lastIndexOf('.'), lastComma = s.lastIndexOf(',');
    final sep = lastDot > lastComma ? lastDot : lastComma;
    var whole = s, frac = '';
    if (sep >= 0) {
      final tail = s.substring(sep + 1);
      final both = lastDot >= 0 && lastComma >= 0;
      // «1,234» / «12.500» / «1.234.567» with one kind of separator and
      // groups of three digits — thousands, not kopecks.
      final thousands =
          !both &&
          tail.length == 3 &&
          RegExp(r'^[1-9]\d{0,2}([.,]\d{3})+$').hasMatch(s);
      if (!thousands) {
        whole = s.substring(0, sep);
        frac = tail;
      }
    }
    whole = whole.replaceAll(RegExp(r'[.,]'), '');
    if (whole.isEmpty) whole = '0';
    if (whole.length > 15) return null;
    var minor = int.parse(whole) * 100;
    if (frac.isNotEmpty) {
      final f = '${frac}00'.substring(0, 2);
      minor += int.parse(f);
      if (frac.length > 2 && int.parse(frac[2]) >= 5) minor += 1;
    }
    return negative ? -minor : minor;
  }

  /// Day before month for «03/04/2026»? Decided by the whole column.
  static bool _dayFirst(List<String> values) {
    for (final v in values) {
      final m = RegExp(r'^(\d{1,2})/(\d{1,2})/\d{2,4}').firstMatch(v.trim());
      if (m == null) continue;
      if (int.parse(m[1]!) > 12) return true;
      if (int.parse(m[2]!) > 12) return false;
    }
    return true;
  }

  static (int, int, int)? _time(String s) {
    final m = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(s);
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    final sec = int.tryParse(m[3] ?? '') ?? 0;
    if (h > 23 || min > 59 || sec > 59) return null;
    return (h, min, sec);
  }

  static const _months = {
    'янв': 1,
    'фев': 2,
    'мар': 3,
    'апр': 4,
    'мая': 5,
    'май': 5,
    'июн': 6,
    'июл': 7,
    'авг': 8,
    'сен': 9,
    'окт': 10,
    'ноя': 11,
    'дек': 12,
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static DateTime? parseDate(String raw, {bool dayFirst = true}) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    DateTime? make(int y, int m, int d) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2200) {
        return null;
      }
      final t = _time(s.substring(_timeStart(s)));
      final date = DateTime(y, m, d, t?.$1 ?? 12, t?.$2 ?? 0, t?.$3 ?? 0);
      return date.month == m ? date : null;
    }

    var m = RegExp(r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})').firstMatch(s);
    if (m != null) {
      if (s.contains('T') &&
          (s.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s))) {
        final parsed = DateTime.tryParse(s);
        if (parsed != null) return parsed.toLocal();
      }
      return make(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    m = RegExp(r'^(\d{1,2})([./-])(\d{1,2})\2(\d{2,4})').firstMatch(s);
    if (m != null) {
      final a = int.parse(m[1]!), b = int.parse(m[3]!);
      final y = int.parse(m[4]!);
      final slash = m[2] == '/';
      return slash && !dayFirst ? make(y, a, b) : make(y, b, a);
    }
    m = RegExp(
      r'^(\d{1,2})\s+([a-zа-я]{3})[a-zа-я]*\.?\s+(\d{4})',
      caseSensitive: false,
    ).firstMatch(s.toLowerCase());
    if (m != null) {
      final month = _months[m[2]!];
      if (month != null) return make(int.parse(m[3]!), month, int.parse(m[1]!));
    }
    return null;
  }

  /// Where the time part could start (after the date).
  static int _timeStart(String s) {
    final i = s.indexOf(RegExp(r'[ T]'));
    return i < 0 ? s.length : i;
  }

  static const _currencies = {
    '₽': 'RUB',
    'руб': 'RUB',
    'р': 'RUB',
    'rur': 'RUB',
    'rub': 'RUB',
    r'$': 'USD',
    'usd': 'USD',
    'долл': 'USD',
    '€': 'EUR',
    'eur': 'EUR',
    'евро': 'EUR',
    '₸': 'KZT',
    'тг': 'KZT',
    'kzt': 'KZT',
    '£': 'GBP',
    '¥': 'CNY',
    'юань': 'CNY',
    'cny': 'CNY',
    'byn': 'BYN',
    'бел руб': 'BYN',
    '₴': 'UAH',
    'грн': 'UAH',
    '₺': 'TRY',
    '֏': 'AMD',
    '₾': 'GEL',
  };

  static String? currencyCode(String raw) {
    final s = raw.trim().toLowerCase().replaceAll('.', '');
    if (s.isEmpty) return null;
    final known = _currencies[s];
    if (known != null) return known;
    final up = raw.trim().toUpperCase();
    return RegExp(r'^[A-Z]{3}$').hasMatch(up)
        ? (up == 'RUR' ? 'RUB' : up)
        : null;
  }

  // ── Operations → base ──────────────────────────────────────────────────

  /// [data] with [rows] added. New accounts and categories are created as
  /// needed; [iconFor] picks an icon for a new category by its name.
  static (FinanceData, ForeignReport) apply(
    FinanceData data,
    List<ForeignRow> rows,
    ForeignOptions options, {
    required String Function() newId,
    int Function(String name)? iconFor,
    List<int> colors = const [0xFFBEA07A],
  }) {
    final report = ForeignReport();
    final accounts = [...data.accounts];
    final categories = [...data.categories];
    final entries = <FinanceEntry>[];
    final base = data.preferences.baseCurrency;
    String low(String s) => s.trim().toLowerCase().replaceAll('ё', 'е');

    String accountFor(String name, String? currency) {
      final mapped = options.accountMap[name];
      if (name.isEmpty && options.defaultAccountId != null) {
        final a = accounts
            .where((a) => a.id == options.defaultAccountId)
            .firstOrNull;
        if (a != null && (currency == null || a.currency == currency)) {
          return a.id;
        }
      }
      if (mapped != null) {
        final a = accounts.where((a) => a.id == mapped).firstOrNull;
        if (a != null && (currency == null || a.currency == currency)) {
          return a.id;
        }
      }
      final title = name.isEmpty ? 'Импорт' : name;
      final same = accounts.where((a) => low(a.name) == low(title));
      final exact = same
          .where((a) => currency == null || a.currency == currency)
          .firstOrNull;
      if (exact != null) return exact.id;
      final withCurrency = same.isEmpty ? title : '$title ($currency)';
      final again = accounts
          .where((a) => low(a.name) == low(withCurrency))
          .firstOrNull;
      if (again != null) return again.id;
      final created = Account(
        id: newId(),
        name: withCurrency.length > 80
            ? withCurrency.substring(0, 80)
            : withCurrency,
        currency: currency ?? base,
        color: colors[accounts.length % colors.length],
      );
      accounts.add(created);
      report.newAccounts.add(created.name);
      return created.id;
    }

    String? categoryFor(ForeignRow r) {
      final kind = r.kind;
      final name = r.category.trim();
      Category? found;
      if (name.isNotEmpty) {
        final matches = categories.where(
          (c) => c.kind == kind && low(c.name) == low(name),
        );
        found =
            matches.where((c) => !c.archived).firstOrNull ??
            matches.firstOrNull;
        if (found == null && options.createCategories) {
          found = Category(
            id: newId(),
            name: name.length > 80 ? name.substring(0, 80) : name,
            kind: kind,
            color: colors[categories.length % colors.length],
            icon: iconFor?.call(name) ?? 26,
            order: categories.where((c) => c.kind == kind).length,
          );
          categories.add(found);
          report.newCategories.add(found.name);
        }
      }
      if (found == null) {
        final active = categories
            .where((c) => c.kind == kind && !c.archived)
            .toList();
        final guess = VoiceEntryParser.categoryFor(
          '${r.payee} $name'.trim(),
          kind,
          active,
        );
        found =
            active.where((c) => c.id == guess).firstOrNull ??
            active
                .where((c) => RegExp(r'друг|проч|other').hasMatch(low(c.name)))
                .firstOrNull ??
            active.firstOrNull;
      }
      if (found == null) {
        found = Category(
          id: newId(),
          name: kind == EntryKind.income ? 'Прочие доходы' : 'Прочие расходы',
          kind: kind,
          icon: 26,
        );
        categories.add(found);
        report.newCategories.add(found.name);
      }
      return found.id;
    }

    String? subcategoryFor(String categoryId, String sub) {
      final s = sub.trim();
      if (s.isEmpty) return null;
      final i = categories.indexWhere((c) => c.id == categoryId);
      final c = categories[i];
      if (c.subcategories.contains(s)) return s;
      final same = c.subcategories.where((x) => low(x) == low(s)).firstOrNull;
      if (same != null) return same;
      if (c.subcategories.length >= 100 || s.length > 200) return null;
      categories[i] = c.copyWith(subcategories: [...c.subcategories, s]);
      return s;
    }

    // Duplicates: what the base already has, by account, kind, sum and day.
    String key(String account, EntryKind kind, int sum, DateTime d) =>
        '$account|${kind.name}|$sum|${d.year}-${d.month}-${d.day}';
    final existing = <String, int>{};
    for (final e in data.entries) {
      final k = key(e.accountId, e.kind, e.amountMinor, e.date);
      existing[k] = (existing[k] ?? 0) + 1;
    }
    final member = data.members.isEmpty ? 'me' : data.members.first.id;

    for (final r in rows) {
      final accountId = accountFor(r.account, r.currency);
      final account = accounts.firstWhere((a) => a.id == accountId);
      final k = key(accountId, r.kind, r.amountMinor, r.date);
      if (options.skipDuplicates && (existing[k] ?? 0) > 0) {
        existing[k] = existing[k]! - 1;
        report.duplicates++;
        continue;
      }
      String? toId;
      int? destination;
      String? categoryId;
      String? sub;
      if (r.kind == EntryKind.transfer) {
        toId = accountFor(r.toAccount, r.toCurrency ?? r.currency);
        if (toId == accountId) {
          report.failed++;
          continue;
        }
        final to = accounts.firstWhere((a) => a.id == toId);
        if (to.currency != account.currency) {
          destination = r.toAmountMinor ?? r.amountMinor;
        }
      } else {
        categoryId = categoryFor(r);
        sub = categoryId == null
            ? null
            : subcategoryFor(categoryId, r.subcategory);
      }
      String cut(String s, int n) => s.length > n ? s.substring(0, n) : s;
      entries.add(
        FinanceEntry(
          id: newId(),
          kind: r.kind,
          amountMinor: r.amountMinor,
          currency: account.currency,
          accountId: accountId,
          toAccountId: toId,
          destinationMinor: destination,
          categoryId: categoryId,
          subcategory: sub,
          date: r.date,
          payee: cut(r.payee, 500),
          note: cut(r.note, 10000),
          memberId: member,
          tags: [
            for (final t in r.tags.take(100))
              if (t.trim().isNotEmpty) cut(t.trim(), 200),
          ],
        ),
      );
      report.added++;
    }
    return (
      data.copyWith(
        accounts: accounts,
        categories: categories,
        entries: [...data.entries, ...entries],
      ),
      report,
    );
  }
}
