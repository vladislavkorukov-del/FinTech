import 'finance_engine.dart';
import 'models.dart';
import 'payment_plan.dart';

/// One debt as the payoff plan sees it.
class DebtItem {
  const DebtItem({
    required this.id,
    required this.name,
    required this.balanceMinor,
    required this.annualRate,
    required this.minimumMinor,
    this.currency = 'RUB',
  });
  final String id, name, currency;

  /// What is owed now (kopecks).
  final int balanceMinor;

  /// Interest, percent a year (0 for a personal debt or an instalment).
  final double annualRate;

  /// The contractual payment per month (0 — no schedule, pay when possible).
  final int minimumMinor;
}

enum DebtStrategy {
  /// Highest rate first: the least interest overall.
  avalanche,

  /// Smallest balance first: the first debt closes sooner.
  snowball,
}

/// One month of the plan: what goes to each debt.
class DebtMonth {
  const DebtMonth(this.index, this.payments, this.interestMinor);
  final int index;
  final Map<String, int> payments;
  final int interestMinor;
  int get totalMinor => payments.values.fold(0, (a, b) => a + b);
}

/// The result of a payoff simulation.
class DebtPayoff {
  const DebtPayoff({
    required this.strategy,
    required this.extraMinor,
    required this.months,
    required this.totalInterestMinor,
    required this.totalPaidMinor,
    required this.payoffMonth,
    required this.order,
    required this.schedule,
    required this.finished,
  });
  final DebtStrategy? strategy;

  /// Paid on top of the minimums every month.
  final int extraMinor;

  /// Months until the last debt is closed (when [finished]).
  final int months;
  final int totalInterestMinor, totalPaidMinor;

  /// Debt id → the month (1-based) it closes.
  final Map<String, int> payoffMonth;

  /// Debt ids in the order they close.
  final List<String> order;

  /// The first months in detail (up to 24).
  final List<DebtMonth> schedule;

  /// False when the payments never close the debts (they do not even cover
  /// the interest) within the 50-year limit.
  final bool finished;
}

/// The money the person can put towards debts each month, from their own
/// operations: income and everyday spending over the last full months,
/// with the debt payments themselves taken out of the spending.
class DebtCapacity {
  const DebtCapacity({
    required this.months,
    required this.incomeMinor,
    required this.spendingMinor,
    required this.minimumsMinor,
  });

  /// Full months the averages are taken over (0 — no history yet).
  final int months;

  /// Average per month.
  final int incomeMinor, spendingMinor;

  /// The contractual debt payments per month.
  final int minimumsMinor;

  /// What is left each month after everyday spending and the minimums.
  int get freeMinor => incomeMinor - spendingMinor - minimumsMinor;

  /// A suggested extra payment: half of what is free, so that a buffer is
  /// kept for the unexpected. Rounded down to 100 ₽.
  int get suggestedExtraMinor {
    final half = freeMinor ~/ 2;
    if (half <= 0) return 0;
    return half - half % 10000;
  }
}

abstract final class DebtStrategies {
  /// The debts in [currency] the person owes: loans and instalments with
  /// what is left from the existing [PaymentPlan].
  static List<DebtItem> debtsOf(
    FinanceData data, {
    required String currency,
    DateTime? now,
  }) {
    final out = <DebtItem>[];
    for (final r in data.recurring) {
      if (r.kind != EntryKind.expense || !r.enabled || r.currency != currency) {
        continue;
      }
      if (r.totalMinor == null && !r.isLoan) continue;
      final plan = PaymentPlan.of(r, data.entries, now: now);
      final left = plan.leftMinor;
      if (left <= 0) continue;
      out.add(
        DebtItem(
          id: r.id,
          name: r.name,
          currency: r.currency,
          balanceMinor: left,
          annualRate: r.isLoan ? r.interestRate! : 0,
          minimumMinor: monthly(r.amountMinor, r.frequency, r.interval),
        ),
      );
    }
    return out;
  }

  /// [amount] per [frequency] as a monthly sum (rounded).
  static int monthly(int amount, String frequency, int interval) {
    final i = interval <= 0 ? 1 : interval;
    return switch (frequency) {
      'daily' => (amount * 304 / (10 * i)).round(),
      'weekly' => (amount * 435 / (100 * i)).round(),
      'yearly' => (amount / (12 * i)).round(),
      _ => (amount / i).round(),
    };
  }

  /// Averages over the last (up to) three full months before [now].
  static DebtCapacity capacity(
    FinanceData data, {
    required String currency,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final debtIds = {
      for (final r in data.recurring)
        if (r.totalMinor != null || r.isLoan) r.id,
    };
    final first = data.entries
        .where((e) => e.currency == currency)
        .map((e) => e.date)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    var months = 0;
    var income = 0, spending = 0;
    for (var m = 1; m <= 3; m++) {
      final start = DateTime(clock.year, clock.month - m);
      final end = DateTime(clock.year, clock.month - m + 1);
      if (first == null || first.isAfter(end)) break;
      months++;
      for (final e in data.entries) {
        if (e.currency != currency ||
            e.status != 'posted' ||
            e.date.isBefore(start) ||
            !e.date.isBefore(end)) {
          continue;
        }
        if (e.kind == EntryKind.income) income += e.amountMinor;
        // Payments of debts are planned separately.
        if (e.kind == EntryKind.expense &&
            !debtIds.contains(e.recurringRuleId) &&
            !data.recurring.any(
              (r) => debtIds.contains(r.id) && PaymentPlan.belongs(e, r),
            )) {
          spending += e.amountMinor;
        }
      }
    }
    final minimums = debtsOf(
      data,
      currency: currency,
      now: clock,
    ).fold<int>(0, (a, d) => a + d.minimumMinor);
    return DebtCapacity(
      months: months,
      incomeMinor: months == 0 ? 0 : income ~/ months,
      spendingMinor: months == 0 ? 0 : spending ~/ months,
      minimumsMinor: minimums,
    );
  }

  /// Simulates paying [debts] month by month: every debt gets its minimum
  /// (never more than it needs), [extraMinor] goes to the target debt of
  /// [strategy], and a closed debt's minimum rolls over to the next one.
  /// Interest is monthly (rate / 12) on the balance at the start of the
  /// month, in whole kopecks. [strategy] null — minimums only.
  static DebtPayoff simulate(
    List<DebtItem> debts, {
    DebtStrategy? strategy = DebtStrategy.avalanche,
    int extraMinor = 0,
    int maxMonths = 600,
  }) {
    final balance = {for (final d in debts) d.id: d.balanceMinor};
    final byId = {for (final d in debts) d.id: d};
    final payoff = <String, int>{};
    final order = <String>[];
    final schedule = <DebtMonth>[];
    var interestTotal = 0, paidTotal = 0, month = 0;
    // The monthly money: minimums + extra; it stays the same when a debt
    // closes (the freed minimum goes on to the others).
    final budget =
        debts.fold<int>(0, (a, d) => a + d.minimumMinor) +
        (strategy == null ? 0 : extraMinor);
    List<String> targets() {
      final open = debts.where((d) => balance[d.id]! > 0).toList();
      switch (strategy) {
        case DebtStrategy.avalanche:
          open.sort((a, b) {
            final r = b.annualRate.compareTo(a.annualRate);
            return r != 0 ? r : balance[a.id]!.compareTo(balance[b.id]!);
          });
        case DebtStrategy.snowball:
          open.sort((a, b) {
            final s = balance[a.id]!.compareTo(balance[b.id]!);
            return s != 0 ? s : b.annualRate.compareTo(a.annualRate);
          });
        case null:
          break;
      }
      return [for (final d in open) d.id];
    }

    while (balance.values.any((b) => b > 0) && month < maxMonths) {
      month++;
      var interest = 0;
      for (final d in debts) {
        final b = balance[d.id]!;
        if (b <= 0 || d.annualRate <= 0) continue;
        // b × rate / 100 / 12, rounded half up, without doubles for money.
        final i = (b * (d.annualRate * 100).round() + 60000) ~/ 120000;
        balance[d.id] = b + i;
        interest += i;
      }
      final payments = <String, int>{};
      var left = budget;
      // Minimums first (as the contracts require).
      for (final d in debts) {
        final b = balance[d.id]!;
        if (b <= 0) continue;
        final pay = [d.minimumMinor, b, left].reduce((a, c) => a < c ? a : c);
        if (pay <= 0) continue;
        balance[d.id] = b - pay;
        payments[d.id] = pay;
        left -= pay;
      }
      // Minimums only: nothing more (freed minimums are not redirected).
      if (strategy != null) {
        for (final id in targets()) {
          if (left <= 0) break;
          final b = balance[id]!;
          final pay = b < left ? b : left;
          balance[id] = b - pay;
          payments[id] = (payments[id] ?? 0) + pay;
          left -= pay;
        }
      }
      for (final d in debts) {
        if (balance[d.id]! <= 0 && !payoff.containsKey(d.id)) {
          payoff[d.id] = month;
          order.add(d.id);
        }
      }
      final paid = payments.values.fold(0, (a, b) => a + b);
      interestTotal += interest;
      paidTotal += paid;
      if (schedule.length < 24) {
        schedule.add(DebtMonth(month, payments, interest));
      }
      // Nothing is paid and nothing closes: the plan cannot finish. A debt
      // growing past any real sum (payments below interest) stops too.
      if (paid == 0 && interest == 0) break;
      if (paidTotal > FinanceEngine.maxMinor ||
          balance.values.any((b) => b > 100000000000000)) {
        break;
      }
    }
    final finished = balance.values.every((b) => b <= 0);
    // Debts that never close (no minimum, no extra) keep their order last.
    for (final d in debts) {
      if (!order.contains(d.id) && balance[d.id]! <= 0) order.add(d.id);
    }
    assert(byId.length == debts.length);
    return DebtPayoff(
      strategy: strategy,
      extraMinor: extraMinor,
      months: finished ? month : 0,
      totalInterestMinor: interestTotal,
      totalPaidMinor: paidTotal,
      payoffMonth: payoff,
      order: order,
      schedule: schedule,
      finished: finished,
    );
  }

  /// The plan Finora recommends: both strategies with [extraMinor] and the
  /// minimums-only baseline; the cheaper of the two (fewer interest, then
  /// sooner) is first.
  static List<DebtPayoff> compare(List<DebtItem> debts, int extraMinor) {
    final avalanche = simulate(debts, extraMinor: extraMinor);
    final snowball = simulate(
      debts,
      strategy: DebtStrategy.snowball,
      extraMinor: extraMinor,
    );
    final base = simulate(debts, strategy: null);
    final pair = [avalanche, snowball]
      ..sort((a, b) {
        if (a.finished != b.finished) return a.finished ? -1 : 1;
        final i = a.totalInterestMinor.compareTo(b.totalInterestMinor);
        return i != 0 ? i : a.months.compareTo(b.months);
      });
    return [...pair, base];
  }
}
