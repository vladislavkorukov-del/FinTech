import '../finance_engine.dart';
import '../models.dart';
import 'goal_planner.dart';
import 'income_planner.dart';

/// The financial picture as the app saw it: balances, goals with their
/// planned dates, budgets, obligations, expected incomes, free money.
class PlanSnapshot {
  const PlanSnapshot(this.json);
  final Map<String, Object?> json;

  DateTime get at => DateTime.parse(json['at'] as String);
  int get totalMinor => (json['totalMinor'] as num).toInt();
  int get freeMinor => (json['freeMinor'] as num).toInt();
  Map<String, int> get balances => {
    for (final e in (json['balances'] as Map? ?? const {}).entries)
      '${e.key}': (e.value as num).toInt(),
  };
  List<Map<String, Object?>> list(String key) => [
    for (final x in json[key] as List? ?? const [])
      Map<String, Object?>.from(x as Map),
  ];
  List<Map<String, Object?>> get goals => list('goals');
  List<Map<String, Object?>> get budgets => list('budgets');
  List<Map<String, Object?>> get obligations => list('obligations');
  List<Map<String, Object?>> get incomes => list('incomes');

  /// The state of [data] at [now], computed the way the app computes it
  /// today (goal plan, income plan).
  static PlanSnapshot compute(FinanceData data, DateTime now) {
    final currency = data.preferences.baseCurrency;
    final goals = GoalPlanner.plan(data, now: now);
    final income = IncomePlanner.plan(data, now: now);
    return PlanSnapshot({
      'at': now.toIso8601String(),
      'currency': currency,
      'balances': {
        for (final a in data.accounts.where((a) => !a.archived))
          a.id: FinanceEngine.balance(a, data.entries),
      },
      'totalMinor': income.balanceMinor,
      'freeMinor': income.availableNowMinor,
      'goals': [
        for (final g in goals.goals)
          {
            'id': g.goal.id,
            'name': g.goal.name,
            'targetMinor': g.goal.targetMinor,
            'savedMinor': g.savedMinor,
            'deadline': g.goal.deadline?.toIso8601String(),
            'monthlyMinor': g.allocatedMinor,
            'date': g.date?.toIso8601String(),
          },
      ],
      'budgets': [
        for (final b in data.budgets)
          {'id': b.id, 'name': b.name, 'limitMinor': b.limitMinor},
      ],
      'obligations': [
        for (final e in income.events.where((e) => !e.income))
          {
            'name': e.name,
            'amountMinor': e.amountMinor,
            'date': e.date.toIso8601String(),
          },
      ],
      'incomes': [
        for (final e in income.events.where((e) => e.income))
          {
            'name': e.name,
            'amountMinor': e.amountMinor,
            'date': e.date.toIso8601String(),
            'ruleId': e.ruleId,
          },
      ],
    });
  }
}

/// What the time machine shows for a past day.
class TimeMachineView {
  const TimeMachineView({
    required this.date,
    required this.saved,
    required this.then,
    required this.now,
    required this.changes,
    required this.lateEntries,
  });
  final DateTime date;

  /// True — a plan state the app saved that day (or the last before it);
  /// false — rebuilt from the operations (no saved state that early).
  final bool saved;
  final PlanSnapshot then;
  final PlanSnapshot now;

  /// Concrete changes since then, in words.
  final List<String> changes;

  /// Operations dated on or before [date] that the app learned of later
  /// (added or corrected afterwards).
  final List<FinanceEntry> lateEntries;
}

/// «Финансовая машина времени» (Phase 8). A past day is shown from the
/// plan state saved that day — or, before the history began, rebuilt from
/// the operations dated up to it and labelled so. Operations entered or
/// corrected after that day are left out of the saved picture and listed
/// separately: a correction later never rewrites what the app knew. Looking
/// back changes nothing.
abstract final class TimeMachine {
  static TimeMachineView view(
    FinanceData data,
    List<HistoryEvent> history,
    DateTime date, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final snapshots =
        history
            .where((e) => e.kind == 'snapshot' && !e.at.isAfter(day))
            .toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    final current = PlanSnapshot.compute(data, clock);
    PlanSnapshot then;
    final saved = snapshots.isNotEmpty;
    if (saved) {
      then = PlanSnapshot(snapshots.last.payload);
    } else {
      // Rebuilt: the operations dated up to that day, known by then when
      // the app recorded when it learned of them.
      final known = data.entries
          .where(
            (e) =>
                !e.date.isAfter(day) &&
                (e.recordedAt == null || !e.recordedAt!.isAfter(day)),
          )
          .toList();
      then = PlanSnapshot.compute(data.copyWith(entries: known), day);
    }
    final late =
        data.entries
            .where(
              (e) =>
                  !e.date.isAfter(day) &&
                  e.recordedAt != null &&
                  e.recordedAt!.isAfter(saved ? then.at : day),
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return TimeMachineView(
      date: date,
      saved: saved,
      then: then,
      now: current,
      changes: explain(then, current, history, late),
      lateEntries: late,
    );
  }

  /// The differences between [then] and [now], each through the change in
  /// the journal that caused it where one is recorded.
  static List<String> explain(
    PlanSnapshot then,
    PlanSnapshot now,
    List<HistoryEvent> history,
    List<FinanceEntry> late,
  ) {
    final out = <String>[];
    String m(int v) => _money(v);
    String d(String? iso) => iso == null ? '—' : _day(DateTime.parse(iso));
    final since = history.where((e) => e.at.isAfter(then.at)).toList();

    // Goals: dates and amounts.
    final before = {for (final g in then.goals) g['id']: g};
    for (final g in now.goals) {
      final b = before[g['id']];
      final name = g['name'];
      if (b == null) {
        out.add('Мечта «$name» появилась позже.');
        continue;
      }
      if (b['date'] != g['date']) {
        out.add(
          '«$name»: срок был ${d(b['date'] as String?)}, сейчас '
          '${d(g['date'] as String?)}.',
        );
      }
      if (b['targetMinor'] != g['targetMinor']) {
        out.add(
          '«$name»: сумма цели ${m(b['targetMinor'] as int)} → '
          '${m(g['targetMinor'] as int)}.',
        );
      }
      if (b['monthlyMinor'] != g['monthlyMinor']) {
        out.add(
          '«$name»: взнос в месяц ${m(b['monthlyMinor'] as int)} → '
          '${m(g['monthlyMinor'] as int)}.',
        );
      }
    }
    // Expected incomes changed (amount or date) in the journal.
    for (final e in since.where((e) => e.kind == 'rule')) {
      final b = e.payload['before'] as Map?;
      final a = e.payload['after'] as Map?;
      if (b == null || a == null || a['kind'] != 'income') continue;
      final name = a['name'];
      final db = (b['amountMinor'] as num).toInt();
      final da = (a['amountMinor'] as num).toInt();
      if (db != da) {
        out.add(
          'Ожидаемый доход «$name» ${da < db ? 'уменьшился' : 'вырос'} на '
          '${m((da - db).abs())} (${_day(e.at)}).',
        );
      }
      if (b['nextDate'] != a['nextDate']) {
        out.add(
          'Дата дохода «$name» перенесена: ${d(b['nextDate'] as String?)} → '
          '${d(a['nextDate'] as String?)}.',
        );
      }
    }
    // Money taken from or put into goals after that day.
    for (final e in since.where((e) => e.kind == 'entry')) {
      final a = e.payload['after'] as Map?;
      if (e.payload['action'] != 'add' || a == null) continue;
      if (a['kind'] == 'transfer' && a['toGoalId'] != null) {
        out.add(
          '${_day(e.at)}: в мечту отложено ${m((a['amountMinor'] as num).toInt())}.',
        );
      }
    }
    for (final e in since.where((e) => e.kind == 'goalFunding')) {
      out.add('${_day(e.at)}: изменено распределение денег между целями.');
    }
    for (final e in since.where((e) => e.kind == 'goal')) {
      final b = e.payload['before'] as Map?;
      final a = e.payload['after'] as Map?;
      if (b != null && a != null && b['savedMinor'] != a['savedMinor']) {
        final diff =
            (a['savedMinor'] as num).toInt() - (b['savedMinor'] as num).toInt();
        out.add(
          '${_day(e.at)}: ${diff < 0 ? 'из накоплений «${a['name']}» перенаправлено' : 'в «${a['name']}» добавлено'} '
          '${m(diff.abs())}.',
        );
      }
    }
    for (final e in since.where((e) => e.kind == 'budget')) {
      final b = e.payload['before'] as Map?;
      final a = e.payload['after'] as Map?;
      if (b != null && a != null && b['limitMinor'] != a['limitMinor']) {
        out.add(
          'Бюджет «${a['name']}»: ${m((b['limitMinor'] as num).toInt())} → '
          '${m((a['limitMinor'] as num).toInt())}.',
        );
      }
    }
    for (final e in since.where((e) => e.kind == 'reconciliation')) {
      final diff =
          (e.payload['actualMinor'] as num).toInt() -
          (e.payload['bookMinor'] as num).toInt();
      if (diff != 0) {
        out.add('${_day(e.at)}: сверка остатка, разница ${m(diff)}.');
      }
    }
    if (late.isNotEmpty) {
      final sum = late.fold<int>(
        0,
        (s, e) =>
            s + (e.kind == EntryKind.income ? e.amountMinor : -e.amountMinor),
      );
      out.add(
        '${late.length} операц. той даты внесены или исправлены позже '
        '(итого ${m(sum)}).',
      );
    }
    final free = now.freeMinor - then.freeMinor;
    if (free != 0) {
      out.add('Свободные деньги: ${m(then.freeMinor)} → ${m(now.freeMinor)}.');
    }
    return out;
  }

  static String _day(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static String _money(int v) {
    final neg = v < 0;
    final s = (v.abs() ~/ 100).toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    final c = v.abs() % 100;
    return '${neg ? '−' : ''}$b${c == 0 ? '' : ',${c.toString().padLeft(2, '0')}'} ₽';
  }
}
