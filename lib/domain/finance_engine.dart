import 'models.dart';

/// Monetary arithmetic and period semantics shared by every presentation screen.
/// Periods are inclusive at [start] and exclusive at [end]. Only posted entries
/// affect balances, budgets and statistics. Transfers affect balances only.
abstract final class FinanceEngine {
  static const int maxMinor = 9007199254740991;

  static int _checked(BigInt value) {
    if (value.abs() > BigInt.from(maxMinor)) {
      throw const FormatException(
        'Совокупная сумма превышает допустимый денежный диапазон',
      );
    }
    return value.toInt();
  }

  static int _add(int left, int right) =>
      _checked(BigInt.from(left) + BigInt.from(right));

  static int totalBalance(
    List<Account> accounts,
    List<FinanceEntry> entries,
    String currency, [
    List<Goal> goals = const [],
  ]) {
    var result = BigInt.zero;
    for (final account in accounts.where(
      (a) => a.currency == currency && !a.excluded && !a.archived,
    )) {
      result += BigInt.from(balance(account, entries));
    }
    for (final goal in goals.where((g) => g.currency == currency)) {
      for (final contribution in goalContributions(goal, entries)) {
        result += BigInt.from(
          contribution.destinationMinor ?? contribution.amountMinor,
        );
      }
    }
    return _checked(result);
  }

  /// Goal.savedMinor remains a legacy/manual opening allocation. Only actual
  /// ledger contributions count toward the aggregate wallet balance.
  static int goalSaved(Goal goal, List<FinanceEntry> entries) {
    var result = BigInt.from(goal.savedMinor);
    for (final contribution in goalContributions(goal, entries)) {
      result += BigInt.from(
        contribution.destinationMinor ?? contribution.amountMinor,
      );
    }
    return _checked(result);
  }

  static List<FinanceEntry> goalContributions(
    Goal goal,
    List<FinanceEntry> entries,
  ) => entries
      .where(
        (entry) =>
            entry.kind == EntryKind.transfer &&
            entry.status == 'posted' &&
            entry.toGoalId == goal.id,
      )
      .toList();

  static bool _inPeriod(FinanceEntry entry, DateTime start, DateTime end) =>
      entry.status == 'posted' &&
      !entry.date.isBefore(start) &&
      entry.date.isBefore(end);

  static int balance(Account account, List<FinanceEntry> entries) {
    var result = BigInt.from(account.openingMinor);
    for (final entry in entries) {
      if (entry.status != 'posted') {
        continue;
      }
      if (entry.accountId == account.id) {
        result += BigInt.from(
          entry.kind == EntryKind.income
              ? entry.amountMinor
              : -entry.amountMinor,
        );
      }
      if (entry.kind == EntryKind.transfer && entry.toAccountId == account.id) {
        result += BigInt.from(entry.destinationMinor ?? entry.amountMinor);
      }
    }
    return _checked(result);
  }

  static ({int income, int expense, int net}) totals(
    List<FinanceEntry> entries,
    DateTime start,
    DateTime end,
    String currency,
  ) {
    var income = 0;
    var expense = 0;
    for (final entry in entries) {
      if (entry.currency != currency || !_inPeriod(entry, start, end)) {
        continue;
      }
      switch (entry.kind) {
        case EntryKind.income:
          income = _add(income, entry.amountMinor);
        case EntryKind.expense:
          expense = _add(expense, entry.amountMinor);
        case EntryKind.transfer:
          break;
      }
    }
    return (income: income, expense: expense, net: income - expense);
  }

  static int budgetSpent(
    Budget budget,
    List<FinanceEntry> entries,
    DateTime start,
    DateTime end,
  ) => entries
      .where(
        (entry) =>
            entry.kind == EntryKind.expense &&
            entry.currency == budget.currency &&
            (budget.categoryId == null ||
                entry.categoryId == budget.categoryId) &&
            _inPeriod(entry, start, end),
      )
      .fold(0, (sum, entry) => _add(sum, entry.amountMinor));

  static Map<String, int> categoryTotals(
    List<FinanceEntry> entries,
    DateTime start,
    DateTime end,
    String currency,
    EntryKind kind,
  ) {
    if (kind == EntryKind.transfer) {
      return {};
    }
    final result = <String, int>{};
    for (final entry in entries) {
      if (entry.kind != kind ||
          entry.currency != currency ||
          !_inPeriod(entry, start, end)) {
        continue;
      }
      final id = entry.categoryId ?? '';
      result[id] = _add(result[id] ?? 0, entry.amountMinor);
    }
    return result;
  }

  /// Parse decimal input without floating-point conversion. Both decimal marks
  /// are accepted; grouping spaces are accepted; exponent notation is rejected.
  static int parseMinor(String input) {
    final text = input.trim().replaceAll(RegExp(r'[ \u00a0\u202f]'), '');
    final match = RegExp(r'^([+-]?)(\d+)(?:[.,](\d{1,2}))?$').firstMatch(text);
    if (match == null) {
      throw const FormatException('Введите сумму с точностью до двух знаков');
    }
    final whole = BigInt.parse(match.group(2)!);
    final fraction = (match.group(3) ?? '').padRight(2, '0');
    var minor = whole * BigInt.from(100) + BigInt.parse(fraction);
    if (match.group(1) == '-') {
      minor = -minor;
    }
    if (minor.abs() > BigInt.from(maxMinor)) {
      throw const FormatException('Сумма превышает допустимый предел');
    }
    return minor.toInt();
  }

  static void validateEntry(FinanceEntry entry, FinanceData data) {
    if (entry.id.trim().isEmpty) {
      throw const FormatException('Не задан идентификатор операции');
    }
    if (entry.amountMinor <= 0 || entry.amountMinor > maxMinor) {
      throw const FormatException('Сумма должна быть больше нуля');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(entry.currency)) {
      throw const FormatException('Некорректный код валюты');
    }
    if (!const ['posted', 'pending', 'cancelled'].contains(entry.status)) {
      throw const FormatException('Некорректный статус операции');
    }
    final sources = data.accounts.where((a) => a.id == entry.accountId);
    if (sources.isEmpty) {
      throw const FormatException('Счёт не найден');
    }
    final source = sources.first;
    if (source.currency != entry.currency) {
      throw const FormatException('Валюта операции должна совпадать со счётом');
    }
    if (entry.kind == EntryKind.transfer) {
      if (entry.toAccountId == source.id) {
        throw const FormatException('Выберите разные счета для перевода');
      }
      if ((entry.toAccountId == null) == (entry.toGoalId == null)) {
        throw const FormatException(
          'Выберите только один счёт или цель зачисления',
        );
      }
      late String destinationCurrency;
      if (entry.toGoalId != null) {
        final goals = data.goals.where((g) => g.id == entry.toGoalId);
        if (goals.isEmpty) {
          throw const FormatException('Цель накопления не найдена');
        }
        destinationCurrency = goals.first.currency;
      } else {
        final destinations = data.accounts.where(
          (a) => a.id == entry.toAccountId,
        );
        if (destinations.isEmpty) {
          throw const FormatException('Счёт зачисления не найден');
        }
        destinationCurrency = destinations.first.currency;
      }
      if (source.currency != destinationCurrency &&
          entry.destinationMinor == null) {
        throw const FormatException(
          'Укажите сумму зачисления в валюте получателя',
        );
      }
      if (entry.destinationMinor != null &&
          (entry.destinationMinor! <= 0 ||
              entry.destinationMinor! > maxMinor)) {
        throw const FormatException('Некорректная сумма зачисления');
      }
      if (source.currency == destinationCurrency &&
          entry.destinationMinor != null &&
          entry.destinationMinor != entry.amountMinor) {
        throw const FormatException(
          'Суммы перевода в одной валюте должны совпадать',
        );
      }
      if (entry.categoryId != null || entry.subcategory != null) {
        throw const FormatException(
          'Перевод не относится к категории доходов или расходов',
        );
      }
    } else {
      if (entry.toAccountId != null ||
          entry.toGoalId != null ||
          entry.destinationMinor != null) {
        throw const FormatException(
          'Счёт зачисления допустим только для перевода',
        );
      }
      final matches = data.categories.where((c) => c.id == entry.categoryId);
      if (matches.isEmpty || matches.first.kind != entry.kind) {
        throw const FormatException('Выберите категорию подходящего типа');
      }
      if (entry.subcategory != null &&
          !matches.first.subcategories.contains(entry.subcategory)) {
        throw const FormatException('Подкатегория не найдена');
      }
    }
    if ((entry.latitude == null) != (entry.longitude == null) ||
        (entry.latitude != null &&
            (!entry.latitude!.isFinite || entry.latitude!.abs() > 90)) ||
        (entry.longitude != null &&
            (!entry.longitude!.isFinite || entry.longitude!.abs() > 180))) {
      throw const FormatException('Некорректные координаты');
    }
  }

  /// Advance on the calendar rather than adding a fixed 30-day duration.
  /// The original anchor day survives short months and leap years.
  /// Custom recurrence intervals are measured in calendar days.
  static DateTime nextOccurrence(RecurringRule rule) {
    if (rule.anchorDay < 1 || rule.anchorDay > 31) {
      throw const FormatException('Некорректный день повторения');
    }
    if (rule.interval < 1 || rule.interval > 36600) {
      throw const FormatException('Некорректный интервал повторения');
    }
    final current = rule.nextDate;
    DateTime create(int year, int month, int day) => current.isUtc
        ? DateTime.utc(
            year,
            month,
            day,
            current.hour,
            current.minute,
            current.second,
            current.millisecond,
            current.microsecond,
          )
        : DateTime(
            year,
            month,
            day,
            current.hour,
            current.minute,
            current.second,
            current.millisecond,
            current.microsecond,
          );
    switch (rule.frequency) {
      case 'daily':
      case 'custom':
        return create(current.year, current.month, current.day + rule.interval);
      case 'weekly':
        return create(
          current.year,
          current.month,
          current.day + 7 * rule.interval,
        );
      case 'monthly':
      case 'yearly':
        final target = create(
          current.year,
          current.month + rule.interval * (rule.frequency == 'yearly' ? 12 : 1),
          1,
        );
        final lastDay = create(target.year, target.month + 1, 0).day;
        final day = rule.anchorDay > lastDay ? lastDay : rule.anchorDay;
        return create(target.year, target.month, day);
      default:
        throw const FormatException('Неизвестный период повторения');
    }
  }
}
