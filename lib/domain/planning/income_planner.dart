import '../finance_engine.dart';
import '../models.dart';

/// A money event ahead: an expected income or an obligation.
class CashEvent {
  const CashEvent({
    required this.date,
    required this.amountMinor,
    required this.name,
    required this.income,
    this.ruleId,
    this.entryId,
    this.scenario = '',
  });
  final DateTime date;

  /// Positive kopecks; [income] tells the direction.
  final int amountMinor;
  final String name;
  final bool income;
  final String? ruleId, entryId;

  /// What the scenario did to it («задержка 7 дн.», «меньше на 8 000 ₽»).
  final String scenario;
}

/// A day of the forecast: the balance after that day's events.
class CashPoint {
  const CashPoint(this.date, this.balanceMinor, this.events);
  final DateTime date;
  final int balanceMinor;
  final List<CashEvent> events;
}

/// «What if the payment is late» for one expected income.
class IncomeScenario {
  const IncomeScenario({
    this.delayDays = 0,
    this.reduceMinor = 0,
    this.cancel = false,
    this.target,
  });

  /// The income it applies to (rule id or entry id); null — the next one.
  final String? target;
  final int delayDays, reduceMinor;
  final bool cancel;
  bool get isNone => delayDays == 0 && reduceMinor == 0 && !cancel;
}

class IncomePlan {
  const IncomePlan({
    required this.start,
    required this.end,
    required this.horizonChosen,
    required this.needsHorizon,
    required this.balanceMinor,
    required this.reserveMinor,
    required this.obligationsMinor,
    required this.expectedMinor,
    required this.events,
    required this.points,
    required this.gapDate,
    required this.gapMinor,
    required this.belowReserveDate,
    required this.assumptions,
    required this.sources,
  });
  final DateTime start, end;

  /// The period was set by the person (no next income known).
  final bool horizonChosen;

  /// No expected income and no chosen horizon: ask for one.
  final bool needsHorizon;

  /// Money on the accounts now (posted operations only).
  final int balanceMinor;
  final int reserveMinor;

  /// Obligations due in the period (each counted once).
  final int obligationsMinor;

  /// Expected incomes in the period (not in the balance until received).
  final int expectedMinor;
  final List<CashEvent> events;
  final List<CashPoint> points;

  /// The first day the money does not cover the planned payments.
  final DateTime? gapDate;
  final int gapMinor;

  /// The first day the balance dips into the protected reserve.
  final DateTime? belowReserveDate;
  final List<String> assumptions;

  /// Income sources (by name) with what is expected from each.
  final Map<String, int> sources;

  int get days {
    final d = end.difference(start).inDays;
    return d < 1 ? 1 : d;
  }

  /// Free now, from the money there is: balance − obligations − reserve.
  int get availableNowMinor => balanceMinor - obligationsMinor - reserveMinor;

  /// Free once the expected income arrives.
  int get availableWithIncomeMinor => availableNowMinor + expectedMinor;

  /// A daily spending limit from the money there is (never negative).
  int get dailyLimitMinor =>
      availableNowMinor <= 0 ? 0 : availableNowMinor ~/ days;
  int get weeklyLimitMinor => dailyLimitMinor * 7;
}

/// Money with an irregular income (Phase 8): the period runs to the next
/// expected income (or a horizon the person chose — never an invented date),
/// obligations by their dates, a protected reserve, a daily limit and the
/// balance day by day, with a cash gap if one comes. Expected income never
/// adds to the actual balance; a scenario (late, smaller, cancelled income)
/// is computed on a copy and changes no operation. An obligation is counted
/// once: a planned (pending) payment linked to a rule's date replaces that
/// date of the rule, and budgets are not subtracted on top.
abstract final class IncomePlanner {
  static IncomePlan plan(
    FinanceData data, {
    DateTime? now,
    int? horizonDays,
    int? reserveMinor,
    IncomeScenario scenario = const IncomeScenario(),
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final currency = data.preferences.baseCurrency;
    final settings = data.extras.incomePlan;
    final reserve = reserveMinor ?? settings.reserveMinor;
    final chosen = horizonDays ?? settings.horizonDays;
    final balance = data.accounts
        .where((a) => !a.archived && !a.excluded && a.currency == currency)
        .fold<int>(0, (s, a) => s + FinanceEngine.balance(a, data.entries));

    // Everything expected in the next 120 days, to find the period's end.
    final far = today.add(const Duration(days: 120));
    final all = _events(data, today, far, currency);
    final incomes = all.where((e) => e.income).toList();
    // The scenario acts on the chosen income, or the next one.
    final targetIndex = scenario.isNone
        ? -1
        : incomes.indexWhere(
            (e) =>
                scenario.target == null ||
                e.ruleId == scenario.target ||
                e.entryId == scenario.target,
          );
    final events = <CashEvent>[];
    for (final e in all) {
      if (!e.income || targetIndex < 0 || !identical(e, incomes[targetIndex])) {
        events.add(e);
        continue;
      }
      if (scenario.cancel) continue;
      final amount = (e.amountMinor - scenario.reduceMinor).clamp(
        0,
        e.amountMinor,
      );
      final date = e.date.add(Duration(days: scenario.delayDays));
      events.add(
        CashEvent(
          date: date,
          amountMinor: amount,
          name: e.name,
          income: true,
          ruleId: e.ruleId,
          entryId: e.entryId,
          scenario: [
            if (scenario.delayDays > 0) 'позже на ${scenario.delayDays} дн.',
            if (scenario.reduceMinor > 0) 'меньше',
          ].join(', '),
        ),
      );
    }
    events.sort((a, b) => a.date.compareTo(b.date));

    // The period: to the next expected income (the original one, so a delay
    // shows the gap), or the chosen horizon.
    final nextIncome = incomes.isEmpty ? null : incomes.first.date;
    final needsHorizon = nextIncome == null && chosen == null;
    final end = chosen != null
        ? today.add(Duration(days: chosen))
        : nextIncome != null
        ? DateTime(nextIncome.year, nextIncome.month, nextIncome.day + 1)
        : today.add(const Duration(days: 30));
    // The forecast runs past a delayed income, so the gap and the recovery
    // are both seen.
    final shown = events.where((e) => e.date.isBefore(end)).toList();
    final obligations = shown
        .where((e) => !e.income)
        .fold<int>(0, (s, e) => s + e.amountMinor);
    final expected = shown
        .where((e) => e.income)
        .fold<int>(0, (s, e) => s + e.amountMinor);

    final points = <CashPoint>[];
    var running = balance;
    DateTime? gap, below;
    var gapMinor = 0;
    final byDay = <DateTime, List<CashEvent>>{};
    final horizonEvents = events
        .where(
          (e) =>
              e.date.isBefore(end.add(Duration(days: scenario.delayDays + 1))),
        )
        .toList();
    for (final e in horizonEvents) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      (byDay[d] ??= []).add(e);
    }
    for (final d in byDay.keys.toList()..sort()) {
      final list = byDay[d]!;
      // Money in comes before money out on the same day.
      for (final e in list.where((e) => e.income)) {
        running += e.amountMinor;
      }
      for (final e in list.where((e) => !e.income)) {
        running -= e.amountMinor;
      }
      points.add(CashPoint(d, running, list));
      if (running < 0 && gap == null) {
        gap = d;
        gapMinor = -running;
      }
      if (running < reserve && below == null) below = d;
    }
    final sources = <String, int>{};
    for (final e in shown.where((e) => e.income)) {
      sources[e.name] = (sources[e.name] ?? 0) + e.amountMinor;
    }
    final assumptions = <String>[
      'Остаток — по проведённым операциям на счетах в $currency.',
      'Ожидаемые доходы не входят в остаток, пока не получены.',
      'Обязательные платежи — по регулярным платежам и запланированным '
          'операциям; каждый учтён один раз.',
      if (reserve > 0) 'Резерв ${_m(reserve)} не тратится на лимит.',
      if (chosen != null)
        'Период выбран вами: $chosen дн.'
      else if (nextIncome != null)
        'Период — до ближайшего ожидаемого дохода.',
      if (!scenario.isNone) 'Сценарий не меняет операции — это расчёт.',
    ];
    return IncomePlan(
      start: today,
      end: end,
      horizonChosen: chosen != null,
      needsHorizon: needsHorizon,
      balanceMinor: balance,
      reserveMinor: reserve,
      obligationsMinor: obligations,
      expectedMinor: expected,
      events: shown,
      points: points,
      gapDate: gap,
      gapMinor: gapMinor,
      belowReserveDate: below,
      assumptions: assumptions,
      sources: sources,
    );
  }

  static String _m(int v) {
    final s = (v ~/ 100).toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return '$b ₽';
  }

  /// Expected incomes and obligations from [from] to [to].
  static List<CashEvent> _events(
    FinanceData data,
    DateTime from,
    DateTime to,
    String currency,
  ) {
    final out = <CashEvent>[];
    // Planned operations (pending) first: they replace a rule's date.
    final replaced = <String>{};
    for (final e in data.entries) {
      if (e.status != 'pending' ||
          e.currency != currency ||
          e.kind == EntryKind.transfer ||
          e.date.isAfter(to)) {
        continue;
      }
      if (e.recurringRuleId != null && e.plannedDueDate != null) {
        replaced.add('${e.recurringRuleId}|${_day(e.plannedDueDate!)}');
      }
      out.add(
        CashEvent(
          date: e.date.isBefore(from) ? from : e.date,
          amountMinor: e.amountMinor,
          name: e.payee.isEmpty ? 'Запланировано' : e.payee,
          income: e.kind == EntryKind.income,
          entryId: e.id,
          ruleId: e.recurringRuleId,
        ),
      );
    }
    for (final r in data.recurring) {
      if (!r.enabled ||
          r.currency != currency ||
          r.kind == EntryKind.transfer) {
        continue;
      }
      // Money owed back is not a planned income.
      if (r.kind == EntryKind.income && (r.totalMinor != null || r.isLoan)) {
        continue;
      }
      var rule = r;
      for (var i = 0; i < 400 && !rule.nextDate.isAfter(to); i++) {
        final d = rule.nextDate;
        // A date already passed and not paid (or not received) still
        // counts — today.
        if (!replaced.contains('${r.id}|${_day(d)}')) {
          out.add(
            CashEvent(
              date: d.isBefore(from) ? from : d,
              amountMinor: r.amountMinor,
              name: r.name,
              income: r.kind == EntryKind.income,
              ruleId: r.id,
            ),
          );
        }
        try {
          rule = rule.copyWith(nextDate: FinanceEngine.nextOccurrence(rule));
        } on FormatException {
          break;
        }
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
