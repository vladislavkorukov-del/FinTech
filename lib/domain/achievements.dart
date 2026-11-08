import 'dart:math' as math;

import '../data/demo_data.dart';
import 'finance_engine.dart';
import 'models.dart';

/// Finora 1.44: achievements — they reward keeping the books regularly,
/// keeping to a budget, saving and reaching goals; never spending more,
/// loans, or creating records for the sake of it.
///
/// Definitions live here as data; what the person reached is computed from
/// the ledger by [AchievementEngine]; only what cannot be computed again
/// (unlock dates, days of activity, analytics periods seen, payments paid on
/// time, perfect months) is stored in [AchievementState].

enum AchievementCategory {
  start,
  accounting,
  streaks,
  budget,
  savings,
  goals,
  discipline,
  analytics,
  rare,
  secret,
}

const achievementCategoryNames = {
  AchievementCategory.start: 'Старт',
  AchievementCategory.accounting: 'Учёт',
  AchievementCategory.streaks: 'Серии',
  AchievementCategory.budget: 'Бюджет',
  AchievementCategory.savings: 'Накопления',
  AchievementCategory.goals: 'Цели',
  AchievementCategory.discipline: 'Дисциплина',
  AchievementCategory.analytics: 'Аналитика',
  AchievementCategory.rare: 'Редкие',
  AchievementCategory.secret: 'Секретные',
};

enum AchievementRarity { common, uncommon, rare, epic, legendary }

extension AchievementRarityInfo on AchievementRarity {
  /// Points for the level only — no currency, shop or purchases.
  int get points => switch (this) {
    AchievementRarity.common => 10,
    AchievementRarity.uncommon => 20,
    AchievementRarity.rare => 40,
    AchievementRarity.epic => 80,
    AchievementRarity.legendary => 150,
  };

  String get title => switch (this) {
    AchievementRarity.common => 'Обычная',
    AchievementRarity.uncommon => 'Необычная',
    AchievementRarity.rare => 'Редкая',
    AchievementRarity.epic => 'Эпическая',
    AchievementRarity.legendary => 'Легендарная',
  };
}

/// Finora's reaction types (shared with the rest of the app).
enum FinoraReactionType {
  neutral,
  happy,
  proud,
  excited,
  celebrating,
  surprised,
  thinking,
  focused,
  calm,
  supportive,
  worried,
  warning,
  sleepy,
  love,
  success,
}

/// How progress is shown: «327 / 500», «18 / 30 дней», «7 450 / 10 000 ₽».
enum ProgressUnit { count, days, months, money, percent }

class AchievementDefinition {
  const AchievementDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.rarity,
    required this.reaction,
    required this.art,
    required this.quotes,
    required this.target,
    required this.value,
    this.unit = ProgressUnit.count,
    this.secret = false,
  });

  final String id, title, description;

  /// 1.44: a related picture from the first sheets. Since 1.45 every
  /// achievement has its own card, named by [id]; this one is only kept as
  /// the theme of the achievement.
  final String art;
  final AchievementCategory category;
  final AchievementRarity rarity;
  final FinoraReactionType reaction;

  /// Short lines of Finora's, one picked at random on unlock.
  final List<String> quotes;

  /// The goal (for [ProgressUnit.money] — in kopecks).
  final int target;
  final ProgressUnit unit;
  final bool secret;

  /// Current progress from the ledger and the stored state.
  final int Function(AchievementMetrics m) value;
}

/// One achievement as the person sees it now.
class AchievementStatus {
  const AchievementStatus({
    required this.definition,
    required this.current,
    required this.unlockedAt,
  });
  final AchievementDefinition definition;
  final int current;
  final DateTime? unlockedAt;

  bool get unlocked => unlockedAt != null;
  int get target => definition.target;
  double get progress =>
      unlocked ? 1 : (current / math.max(1, target)).clamp(0.0, 1.0);
}

/// A payment answered «Оплачено» (for «Всё вовремя», «Без просрочек»).
class PaymentMark {
  const PaymentMark({
    required this.ruleId,
    required this.due,
    required this.paid,
  });
  final String ruleId;
  final DateTime due, paid;

  bool get onTime => !DateTime(
    paid.year,
    paid.month,
    paid.day,
  ).isAfter(DateTime(due.year, due.month, due.day));

  Map<String, Object?> toJson() => {
    'ruleId': ruleId,
    'due': due.toIso8601String(),
    'paid': paid.toIso8601String(),
  };

  factory PaymentMark.fromJson(Map<String, dynamic> j) => PaymentMark(
    ruleId: j['ruleId'] as String,
    due: DateTime.parse(j['due'] as String),
    paid: DateTime.parse(j['paid'] as String),
  );
}

/// What is stored: only what the ledger alone cannot tell again.
class AchievementState {
  const AchievementState({
    this.unlocked = const {},
    this.activityDays = const {},
    this.analyticsPeriods = const {},
    this.flags = const {},
    this.completedGoals = const {},
    this.perfectMonths = const {},
    this.payments = const [],
    this.firstSeen,
    this.budgetSince,
    this.seenAt,
  });

  /// Achievement id → when it was received. Never taken away.
  final Map<String, DateTime> unlocked;

  /// Days (yyyy-MM-dd) with a meaningful financial action.
  final Set<String> activityDays;
  final Set<String> analyticsPeriods;

  /// One-off events that the ledger does not keep (a record added at night,
  /// a record dated more than 30 days back).
  final Set<String> flags;
  final Set<String> completedGoals;
  final Set<String> perfectMonths;
  final List<PaymentMark> payments;
  final DateTime? firstSeen, budgetSince;

  /// When the achievements screen was last opened («Новое» after it).
  final DateTime? seenAt;

  AchievementState copyWith({
    Map<String, DateTime>? unlocked,
    Set<String>? activityDays,
    Set<String>? analyticsPeriods,
    Set<String>? flags,
    Set<String>? completedGoals,
    Set<String>? perfectMonths,
    List<PaymentMark>? payments,
    DateTime? firstSeen,
    DateTime? budgetSince,
    DateTime? seenAt,
  }) => AchievementState(
    unlocked: unlocked ?? this.unlocked,
    activityDays: activityDays ?? this.activityDays,
    analyticsPeriods: analyticsPeriods ?? this.analyticsPeriods,
    flags: flags ?? this.flags,
    completedGoals: completedGoals ?? this.completedGoals,
    perfectMonths: perfectMonths ?? this.perfectMonths,
    payments: payments ?? this.payments,
    firstSeen: firstSeen ?? this.firstSeen,
    budgetSince: budgetSince ?? this.budgetSince,
    seenAt: seenAt ?? this.seenAt,
  );

  static String day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  AchievementState withActivity(DateTime now) => activityDays.contains(day(now))
      ? this
      : copyWith(activityDays: {...activityDays, day(now)});

  Map<String, Object?> toJson() => {
    'unlocked': {
      for (final e in unlocked.entries) e.key: e.value.toIso8601String(),
    },
    'activityDays': (activityDays.toList()..sort()),
    'analyticsPeriods': analyticsPeriods.toList(),
    'flags': flags.toList(),
    'completedGoals': completedGoals.toList(),
    'perfectMonths': perfectMonths.toList(),
    'payments': [for (final p in payments) p.toJson()],
    'firstSeen': firstSeen?.toIso8601String(),
    'budgetSince': budgetSince?.toIso8601String(),
    'seenAt': seenAt?.toIso8601String(),
  };

  factory AchievementState.fromJson(Map<String, dynamic> j) {
    Set<String> set(String k) => {
      for (final v in j[k] as List<dynamic>? ?? const []) v as String,
    };
    DateTime? date(String k) =>
        j[k] == null ? null : DateTime.tryParse(j[k] as String);
    return AchievementState(
      unlocked: {
        for (final e
            in (j['unlocked'] as Map<String, dynamic>? ?? const {}).entries)
          e.key: DateTime.parse(e.value as String),
      },
      activityDays: set('activityDays'),
      analyticsPeriods: set('analyticsPeriods'),
      flags: set('flags'),
      completedGoals: set('completedGoals'),
      perfectMonths: set('perfectMonths'),
      payments: [
        for (final p in j['payments'] as List<dynamic>? ?? const [])
          PaymentMark.fromJson(Map<String, dynamic>.from(p as Map)),
      ],
      firstSeen: date('firstSeen'),
      budgetSince: date('budgetSince'),
      seenAt: date('seenAt'),
    );
  }
}

/// One calendar month of the person's own money (base currency).
class MonthFacts {
  MonthFacts(this.start, this.end);
  final DateTime start, end;
  int income = 0, expense = 0, otherExpense = 0, records = 0;
  final categories = <String>{};
  double get otherShare => expense == 0 ? 0 : otherExpense / expense;
  String get key => '${start.year}-${start.month.toString().padLeft(2, '0')}';
}

/// Everything the definitions read, computed once per evaluation.
class AchievementMetrics {
  AchievementMetrics._(this.data, this.state, this.now);

  final FinanceData data;
  final AchievementState state;
  final DateTime now;

  late final List<FinanceEntry> entries;
  late final List<FinanceEntry> expenses;
  late final List<Account> accounts;
  late final List<Goal> goals;
  late final List<Budget> budgets;
  late final List<Category> ownCategories;
  late final int ownSubcategories;
  late final int currentStreak, bestStreak;

  /// Complete months, oldest first (the current one is not included).
  late final List<MonthFacts> months;
  late final int savedMinor;
  late final int? averageMonthExpense;
  late final int completedGoalCount;
  late final double bestGoalRatio;
  late final int daysWithFinora;

  static final _seed = createDemoData(DateTime(2026));
  static final _demoEntries = {for (final e in _seed.entries) e.id};
  static final _demoAccounts = {for (final a in _seed.accounts) a.id};
  static final _demoGoals = {for (final g in _seed.goals) g.id};
  static final _demoBudgets = {for (final b in _seed.budgets) b.id};
  static final _defaultCategories = {for (final c in _seed.categories) c.id: c};
  static final _other = RegExp(
    r'прочее|другое|разное|other',
    caseSensitive: false,
  );

  bool isOther(String? categoryId) {
    final c = data.categories.where((x) => x.id == categoryId).firstOrNull;
    return c == null || _other.hasMatch(c.name);
  }

  static AchievementMetrics of(
    FinanceData data,
    AchievementState state,
    DateTime now,
  ) {
    final m = AchievementMetrics._(data, state, now);
    final demo = data.demo;
    final base = data.preferences.baseCurrency;
    m.entries = [
      for (final e in data.entries)
        if (!(demo && _demoEntries.contains(e.id)) &&
            e.status != 'cancelled' &&
            !e.date.isAfter(now))
          e,
    ];
    m.expenses = [
      for (final e in m.entries)
        if (e.kind == EntryKind.expense && e.currency == base) e,
    ];
    m.accounts = [
      for (final a in data.accounts)
        if (!a.archived && !(demo && _demoAccounts.contains(a.id))) a,
    ];
    m.goals = [
      for (final g in data.goals)
        if (!(demo && _demoGoals.contains(g.id))) g,
    ];
    m.budgets = [
      for (final b in data.budgets)
        if (b.limitMinor > 0 && !(demo && _demoBudgets.contains(b.id))) b,
    ];
    m.ownCategories = [
      for (final c in data.categories)
        if (!_defaultCategories.containsKey(c.id)) c,
    ];
    var subs = 0;
    for (final c in data.categories) {
      final seed = _defaultCategories[c.id];
      subs += c.subcategories
          .where((s) => seed == null || !seed.subcategories.contains(s))
          .length;
    }
    m.ownSubcategories = subs;

    // Days of activity: only the days something was really done in the app
    // (records dated back do not make a series).
    final days = <DateTime>{
      for (final d in state.activityDays)
        if (DateTime.tryParse(d) case final x?)
          DateTime(x.year, x.month, x.day),
    }.toList()..sort();
    bool next(DateTime a, DateTime b) =>
        DateTime(a.year, a.month, a.day + 1) == b;
    var best = 0, run = 0;
    for (var i = 0; i < days.length; i++) {
      run = i > 0 && next(days[i - 1], days[i]) ? run + 1 : 1;
      best = math.max(best, run);
    }
    final today = DateTime(now.year, now.month, now.day);
    var current = 0;
    if (days.isNotEmpty && (days.last == today || next(days.last, today))) {
      current = 1;
      for (var i = days.length - 1; i > 0; i--) {
        if (!next(days[i - 1], days[i])) break;
        current++;
      }
    }
    m.currentStreak = current;
    m.bestStreak = math.max(best, current);

    // Complete months from the first record of the person's own.
    final startDay = data.preferences.monthStart.clamp(1, 28);
    DateTime monthOf(DateTime d) => d.day >= startDay
        ? DateTime(d.year, d.month, startDay)
        : DateTime(d.year, d.month - 1, startDay);
    final months = <MonthFacts>[];
    if (m.entries.isNotEmpty) {
      final first = m.entries
          .map((e) => e.date)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      var s = monthOf(first);
      final current = monthOf(now);
      while (s.isBefore(current) && months.length < 240) {
        final e = DateTime(s.year, s.month + 1, startDay);
        months.add(MonthFacts(s, e));
        s = e;
      }
      final s0 = months.isEmpty ? null : months.first.start;
      for (final e in m.entries) {
        if (e.currency != base || s0 == null) continue;
        final ms = monthOf(e.date);
        final i = (ms.year - s0.year) * 12 + ms.month - s0.month;
        if (i < 0 || i >= months.length) continue;
        final mf = months[i];
        mf.records++;
        if (e.kind == EntryKind.income) mf.income += e.amountMinor;
        if (e.kind == EntryKind.expense) {
          mf.expense += e.amountMinor;
          if (e.categoryId != null) mf.categories.add(e.categoryId!);
          if (m.isOther(e.categoryId)) mf.otherExpense += e.amountMinor;
        }
      }
    }
    m.months = months;

    var saved = 0;
    for (final g in m.goals) {
      if (g.currency == base) saved += FinanceEngine.goalSaved(g, data.entries);
    }
    for (final a in m.accounts) {
      if ((a.type == 'savings' || a.type == 'deposit') && a.currency == base) {
        saved += FinanceEngine.balance(a, data.entries);
      }
    }
    m.savedMinor = math.max(0, saved);
    final recent = [
      for (final mf in months.reversed.take(3))
        if (mf.expense > 0) mf.expense,
    ];
    m.averageMonthExpense = recent.isEmpty
        ? null
        : recent.reduce((a, b) => a + b) ~/ recent.length;

    final done = {...state.completedGoals};
    var bestRatio = 0.0;
    for (final g in m.goals) {
      final s = FinanceEngine.goalSaved(g, data.entries);
      if (g.targetMinor > 0) {
        bestRatio = math.max(bestRatio, s / g.targetMinor);
        if (s >= g.targetMinor) done.add(g.id);
      }
    }
    m.completedGoalCount = done.length;
    m.bestGoalRatio = bestRatio;
    final firstSeen = [
      ?state.firstSeen,
      for (final e in m.entries.take(1)) e.date,
      if (m.entries.isNotEmpty)
        m.entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b),
    ].fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    m.daysWithFinora = firstSeen == null ? 0 : now.difference(firstSeen).inDays;
    return m;
  }

  /// The total budget limit for a month: an overall budget, else the sum.
  int get budgetLimit {
    final overall = budgets.where((b) => b.categoryId == null).toList();
    final list = overall.isNotEmpty ? overall : budgets;
    return list.fold(0, (s, b) => s + b.limitMinor);
  }

  /// Complete months since budgets exist.
  List<MonthFacts> get budgetMonths {
    final since = state.budgetSince;
    if (since == null || budgets.isEmpty) return const [];
    return [
      for (final mf in months)
        if (!mf.start.isBefore(DateTime(since.year, since.month, since.day)))
          mf,
    ];
  }

  /// Consecutive months (from the last one) for which [test] holds.
  static int run(List<MonthFacts> list, bool Function(MonthFacts) test) {
    var n = 0;
    for (final mf in list.reversed) {
      if (!test(mf)) break;
      n++;
    }
    return n;
  }

  bool withinBudget(MonthFacts mf) =>
      mf.records > 0 && mf.expense <= budgetLimit;

  List<PaymentMark> paymentsIn(MonthFacts mf) => [
    for (final p in state.payments)
      if (!p.due.isBefore(mf.start) && p.due.isBefore(mf.end)) p,
  ];

  bool paymentsOnTime(MonthFacts mf) => paymentsIn(mf).every((p) => p.onTime);

  bool perfect(MonthFacts mf) =>
      mf.records >= 5 &&
      mf.income > 0 &&
      mf.income >= mf.expense &&
      mf.otherExpense == 0 &&
      paymentsOnTime(mf) &&
      (budgetMonths.contains(mf) ? withinBudget(mf) : true);

  MonthFacts? get lastMonth => months.isEmpty ? null : months.last;

  /// Whether a month was fully covered by the person's records (the first
  /// of them is no later than its third day).
  bool covered(MonthFacts mf) {
    if (entries.isEmpty) return false;
    final first = entries
        .map((e) => e.date)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return !first.isAfter(mf.start.add(const Duration(days: 3)));
  }
}

class AchievementLevel {
  const AchievementLevel(this.title, this.from, this.next);
  final String title;
  final int from;
  final int? next;
}

const achievementLevels = [
  AchievementLevel('Новичок', 0, 50),
  AchievementLevel('Практик', 50, 150),
  AchievementLevel('Организованный', 150, 300),
  AchievementLevel('Стратег', 300, 550),
  AchievementLevel('Эксперт', 550, 900),
  AchievementLevel('Мастер', 900, 1400),
  AchievementLevel('Финансовый гуру', 1400, null),
];

/// The whole picture for the screens.
class AchievementReport {
  const AchievementReport(
    this.statuses,
    this.metrics, {
    this.worldExperience = 0,
  });
  final List<AchievementStatus> statuses;
  final AchievementMetrics metrics;
  final int worldExperience;

  int get unlockedCount => statuses.where((s) => s.unlocked).length;
  int get total => statuses.length;
  double get share => total == 0 ? 0 : unlockedCount / total;
  int get points =>
      worldExperience +
      statuses
          .where((s) => s.unlocked)
          .fold(0, (p, s) => p + s.definition.rarity.points);
  AchievementLevel get level =>
      achievementLevels.lastWhere((l) => points >= l.from);
  int get rareCount => statuses
      .where(
        (s) =>
            s.unlocked &&
            s.definition.rarity.index >= AchievementRarity.rare.index,
      )
      .length;

  AchievementStatus? get last {
    final got = statuses.where((s) => s.unlocked).toList()
      ..sort((a, b) => b.unlockedAt!.compareTo(a.unlockedAt!));
    return got.firstOrNull;
  }

  /// Locked, not secret, the closest to done first.
  List<AchievementStatus> get nearest {
    final list = [
      for (final s in statuses)
        if (!s.unlocked && !s.definition.secret && s.current > 0) s,
    ]..sort((a, b) => b.progress.compareTo(a.progress));
    return list;
  }

  /// Unlocked after the screen was last opened.
  int newSince(DateTime? seen) => statuses
      .where((s) => s.unlocked && (seen == null || s.unlockedAt!.isAfter(seen)))
      .length;
}

abstract final class AchievementEngine {
  /// The progress of every achievement now.
  static AchievementReport report(
    FinanceData data,
    AchievementState state, {
    DateTime? now,
    List<AchievementDefinition>? definitions,
  }) {
    final clock = now ?? DateTime.now();
    final m = AchievementMetrics.of(data, state, clock);
    return AchievementReport(
      [
        for (final d in definitions ?? achievementDefinitions)
          AchievementStatus(
            definition: d,
            current: math.max(0, d.value(m)),
            unlockedAt: state.unlocked[d.id],
          ),
      ],
      m,
      worldExperience: data.world.experience,
    );
  }

  /// After a change of the ledger ([before] → [after]): records what only
  /// can be seen at the moment of the change, and unlocks what is reached.
  /// Returns the new state and the achievements received now. Nothing
  /// already received is ever taken away.
  static (AchievementState, List<AchievementDefinition>) update(
    FinanceData before,
    FinanceData after,
    AchievementState state, {
    DateTime? now,
    bool activity = false,
    bool events = true,
  }) {
    final clock = now ?? DateTime.now();
    var s = state;
    final changed =
        !identical(before.entries, after.entries) ||
        !identical(before.accounts, after.accounts) ||
        !identical(before.budgets, after.budgets) ||
        !identical(before.goals, after.goals) ||
        !identical(before.recurring, after.recurring);
    if (activity || (changed && events)) s = s.withActivity(clock);
    // Only a change of the ledger is a sign of use (a theme switch is not).
    if (s.firstSeen == null && (activity || changed)) {
      s = s.copyWith(firstSeen: clock);
    }
    // Events that the ledger forgets.
    final old = {for (final e in before.entries) e.id};
    for (final e in events ? after.entries : const <FinanceEntry>[]) {
      if (old.contains(e.id) ||
          (after.demo && AchievementMetrics._demoEntries.contains(e.id))) {
        continue;
      }
      if (clock.hour >= 2 && clock.hour < 4) s = s._flag('night');
      if (clock.difference(e.date).inDays > 30) s = s._flag('archaeologist');
    }
    final m0 = AchievementMetrics.of(after, s, clock);
    if (s.budgetSince == null && m0.budgets.isNotEmpty) {
      s = s.copyWith(budgetSince: clock);
    }
    final goalsDone = {
      ...s.completedGoals,
      for (final g in m0.goals)
        if (g.targetMinor > 0 &&
            FinanceEngine.goalSaved(g, after.entries) >= g.targetMinor)
          g.id,
    };
    if (goalsDone.length != s.completedGoals.length) {
      s = s.copyWith(completedGoals: goalsDone);
    }
    final perfect = {
      ...s.perfectMonths,
      for (final mf in m0.months)
        if (m0.perfect(mf)) mf.key,
    };
    if (perfect.length != s.perfectMonths.length) {
      s = s.copyWith(perfectMonths: perfect);
    }
    final r = report(after, s, now: clock);
    final fresh = <AchievementDefinition>[];
    final unlocked = {...s.unlocked};
    // Two passes: «Легенда» depends on the others.
    for (var pass = 0; pass < 2; pass++) {
      if (pass == 1 && fresh.isEmpty) break;
      final rr = pass == 0
          ? r
          : report(after, s.copyWith(unlocked: unlocked), now: clock);
      for (final st in rr.statuses) {
        if (unlocked.containsKey(st.definition.id)) continue;
        if (st.current >= st.target) {
          unlocked[st.definition.id] = clock;
          fresh.add(st.definition);
        }
      }
    }
    if (fresh.isNotEmpty) s = s.copyWith(unlocked: unlocked);
    return (s, fresh);
  }

  /// [a] with everything [b] has received too (the earlier date wins) —
  /// after an import or a restore nothing received is lost.
  static AchievementState merge(AchievementState a, AchievementState b) {
    final unlocked = {...a.unlocked};
    for (final e in b.unlocked.entries) {
      final had = unlocked[e.key];
      if (had == null || e.value.isBefore(had)) unlocked[e.key] = e.value;
    }
    DateTime? early(DateTime? x, DateTime? y) =>
        x == null ? y : (y == null || x.isBefore(y) ? x : y);
    return AchievementState(
      unlocked: unlocked,
      activityDays: {...a.activityDays, ...b.activityDays},
      analyticsPeriods: {...a.analyticsPeriods, ...b.analyticsPeriods},
      flags: {...a.flags, ...b.flags},
      completedGoals: {...a.completedGoals, ...b.completedGoals},
      perfectMonths: {...a.perfectMonths, ...b.perfectMonths},
      payments: [
        ...a.payments,
        for (final p in b.payments)
          if (!a.payments.any((q) => q.ruleId == p.ruleId && q.due == p.due)) p,
      ],
      firstSeen: early(a.firstSeen, b.firstSeen),
      budgetSince: early(a.budgetSince, b.budgetSince),
      seenAt: a.seenAt ?? b.seenAt,
    );
  }

  /// A line of Finora's for [d] (one of its pool).
  static String quote(AchievementDefinition d, [math.Random? random]) =>
      d.quotes[(random ?? math.Random()).nextInt(d.quotes.length)];

  /// Finora's mood on the achievements screen by the share received.
  static FinoraReactionType moodFor(double share) => share >= 1
      ? FinoraReactionType.celebrating
      : share >= .8
      ? FinoraReactionType.excited
      : share >= .5
      ? FinoraReactionType.proud
      : share >= .2
      ? FinoraReactionType.happy
      : FinoraReactionType.supportive;
}

extension on AchievementState {
  AchievementState _flag(String f) =>
      flags.contains(f) ? this : copyWith(flags: {...flags, f});
}

int _monthsRun(AchievementMetrics m, bool Function(MonthFacts) test) =>
    AchievementMetrics.run(m.months, test);

const _rub = 100;

String _plural(int n, String one, String few, String many) {
  final d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return one;
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
  return many;
}

/// The 54 achievements.
final List<AchievementDefinition>
achievementDefinitions = <AchievementDefinition>[
  // ── Старт ──────────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'first_step',
    title: 'Первый шаг',
    description: 'Добавьте первую операцию',
    category: AchievementCategory.start,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'first_step',
    target: 1,
    value: (m) => m.entries.length,
    quotes: ['Ну всё, начали.', 'Первая запись есть.', 'Так уже интереснее.'],
  ),
  AchievementDefinition(
    id: 'ten_records',
    title: 'Финансы под контролем',
    description: 'Добавьте 10 операций',
    category: AchievementCategory.start,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'first_record',
    target: 10,
    value: (m) => m.entries.length,
    quotes: [
      'Десять записей — уже картина.',
      'Дело пошло.',
      'Мне нравится этот темп.',
    ],
  ),
  AchievementDefinition(
    id: 'fifty_records',
    title: 'Начинаем серьёзно',
    description: 'Добавьте 50 операций',
    category: AchievementCategory.start,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.proud,
    art: 'first_expense',
    target: 50,
    value: (m) => m.entries.length,
    quotes: [
      'Полсотни. Это уже система.',
      'Серьёзный подход.',
      'Теперь я много знаю о деньгах.',
    ],
  ),
  AchievementDefinition(
    id: 'archive',
    title: 'Финансовый архив',
    description: 'Добавьте 500 операций',
    category: AchievementCategory.start,
    rarity: AchievementRarity.epic,
    reaction: FinoraReactionType.proud,
    art: 'report_ready',
    target: 500,
    value: (m) => m.entries.length,
    quotes: [
      'Пятьсот записей. Настоящий архив.',
      'Тут уже можно писать мемуары.',
      'Вот это история.',
    ],
  ),
  AchievementDefinition(
    id: 'own_category',
    title: 'Всё по полочкам',
    description: 'Создайте первую собственную категорию',
    category: AchievementCategory.start,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'categories_set',
    target: 1,
    value: (m) => m.ownCategories.length,
    quotes: [
      'Своя категория — свой порядок.',
      'Теперь всё на месте.',
      'Полочка готова.',
    ],
  ),
  // ── Учёт: счета ────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'first_account',
    title: 'Мои деньги',
    description: 'Создайте первый счёт',
    category: AchievementCategory.accounting,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'accounts_added',
    target: 1,
    value: (m) => m.accounts.length,
    quotes: [
      'Первый счёт на месте.',
      'Теперь видно, где деньги.',
      'Начало положено.',
    ],
  ),
  AchievementDefinition(
    id: 'full_picture',
    title: 'Полная картина',
    description: 'Три активных счёта разных типов',
    category: AchievementCategory.accounting,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.proud,
    art: 'balance_plus',
    target: 3,
    value: (m) => {for (final a in m.accounts) a.type}.length,
    quotes: [
      'Вся картина как на ладони.',
      'Карта, наличные и запас — красиво.',
      'Ничего не спрятано.',
    ],
  ),
  AchievementDefinition(
    id: 'cash',
    title: 'Наличка тоже считается',
    description: 'Создайте счёт «Наличные»',
    category: AchievementCategory.accounting,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'first_income',
    target: 1,
    value: (m) => m.accounts.where((a) => a.type == 'cash').length,
    quotes: [
      'Наличные тоже деньги.',
      'Кошелёк под присмотром.',
      'Теперь и бумажки на учёте.',
    ],
  ),
  AchievementDefinition(
    id: 'first_transfer',
    title: 'Всё сошлось',
    description: 'Переведите деньги между своими счетами',
    category: AchievementCategory.accounting,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.success,
    art: 'expenses_control',
    target: 1,
    value: (m) => m.entries
        .where((e) => e.kind == EntryKind.transfer && e.toAccountId != null)
        .length,
    quotes: [
      'Деньги переехали — всё сходится.',
      'Перевод учтён.',
      'Баланс в порядке.',
    ],
  ),
  // ── Серии ──────────────────────────────────────────────────────────────
  for (final (id, title, days, rarity, art, reaction, quotes) in [
    (
      'streak_3',
      'Не забываю',
      3,
      AchievementRarity.common,
      'week_tracking',
      FinoraReactionType.happy,
      [
        'Три дня подряд. Хорошее начало.',
        'Не забываешь — отлично.',
        'Ритм пойман.',
      ],
    ),
    (
      'streak_7',
      'Финансовая привычка',
      7,
      AchievementRarity.uncommon,
      'seven_days',
      FinoraReactionType.excited,
      [
        'О, вот это уже дисциплина.',
        'Семь дней подряд. Красиво.',
        'Похоже, это уже привычка.',
      ],
    ),
    (
      'streak_30',
      'Железная дисциплина',
      30,
      AchievementRarity.epic,
      'month_discipline',
      FinoraReactionType.proud,
      [
        'Вот это выдержка.',
        'Месяц без пропусков. Уважаю.',
        'Похоже, это уже стиль.',
      ],
    ),
    (
      'streak_100',
      'Финансовый марафон',
      100,
      AchievementRarity.legendary,
      'budget_master',
      FinoraReactionType.celebrating,
      ['Сто дней. Это марафон.', 'Сотня! Без слов.', 'Легендарная выдержка.'],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description:
          '$days ${_plural(days, 'день', 'дня', 'дней')} подряд '
          'с финансовыми делами',
      category: AchievementCategory.streaks,
      rarity: rarity,
      reaction: reaction,
      art: art,
      target: days,
      unit: ProgressUnit.days,
      value: (m) => m.bestStreak >= days ? days : m.currentStreak,
      quotes: quotes,
    ),
  // ── Бюджет ─────────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'first_budget',
    title: 'Первый бюджет',
    description: 'Создайте первый месячный бюджет',
    category: AchievementCategory.budget,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.focused,
    art: 'budget_created',
    target: 1,
    value: (m) => m.budgets.length,
    quotes: [
      'Теперь у денег есть план.',
      'Хаос официально отменяется.',
      'Ну всё, бюджет под присмотром.',
    ],
  ),
  for (final (id, title, months, rarity, art, reaction, quotes) in [
    (
      'budget_month',
      'Держу план',
      1,
      AchievementRarity.uncommon,
      'limit_kept',
      FinoraReactionType.success,
      [
        'Бюджет не вышел из берегов.',
        'План выдержан.',
        'Вот так уже спокойнее.',
      ],
    ),
    (
      'budget_3',
      'Точно по плану',
      3,
      AchievementRarity.rare,
      'month_plan',
      FinoraReactionType.proud,
      ['Три месяца по плану.', 'Точность — моё любимое.', 'План работает.'],
    ),
    (
      'budget_6',
      'Мастер бюджета',
      6,
      AchievementRarity.epic,
      'budget_master',
      FinoraReactionType.proud,
      [
        'Полгода в рамках. Мастер.',
        'Корона заслужена.',
        'Бюджет тебя слушается.',
      ],
    ),
    (
      'budget_12',
      'Финансовый дзен',
      12,
      AchievementRarity.legendary,
      'finance_zen',
      FinoraReactionType.calm,
      ['Год в равновесии.', 'Это и есть дзен.', 'Спокойствие и порядок.'],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description: months == 1
          ? 'Закончите месяц в рамках общего бюджета'
          : '$months ${_plural(months, 'месяц', 'месяца', 'месяцев')} подряд '
                'в рамках бюджета',
      category: AchievementCategory.budget,
      rarity: rarity,
      reaction: reaction,
      art: art,
      target: months,
      unit: ProgressUnit.months,
      value: (m) => AchievementMetrics.run(m.budgetMonths, m.withinBudget),
      quotes: quotes,
    ),
  AchievementDefinition(
    id: 'reserve_90',
    title: 'Остался запас',
    description: 'Потратьте за месяц меньше 90% бюджета',
    category: AchievementCategory.budget,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.happy,
    art: 'piggy_opened',
    target: 1,
    value: (m) => m.budgetMonths
        .where((mf) => mf.records > 0 && mf.expense * 10 < m.budgetLimit * 9)
        .length,
    quotes: [
      'Ещё и запас остался.',
      'Монетки остались — приятно.',
      'Хороший финиш месяца.',
    ],
  ),
  AchievementDefinition(
    id: 'reserve_80',
    title: 'Хороший запас',
    description: 'Потратьте за месяц меньше 80% бюджета',
    category: AchievementCategory.budget,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.proud,
    art: 'safety_cushion',
    target: 1,
    value: (m) => m.budgetMonths
        .where((mf) => mf.records > 0 && mf.expense * 10 < m.budgetLimit * 8)
        .length,
    quotes: [
      'Пятая часть бюджета цела.',
      'Вот это запас.',
      'Экономно и спокойно.',
    ],
  ),
  // ── Накопления ─────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'first_topup',
    title: 'Начало положено',
    description: 'Впервые пополните мечту',
    category: AchievementCategory.savings,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.love,
    art: 'piggy_opened',
    target: 1,
    value: (m) => m.entries.where((e) => e.toGoalId != null).length,
    quotes: [
      'Первая монетка в копилке.',
      'Копилка открыта.',
      'С этого всё и начинается.',
    ],
  ),
  for (final (id, title, desc, rub, rarity, art, quotes) in [
    (
      'saved_1000',
      'Первая тысяча',
      'Накопите 1 000 ₽',
      1000,
      AchievementRarity.common,
      'first_income',
      [
        'Первая тысяча отложена.',
        'Золотая монета — твоя.',
        'Хорошее начало запаса.',
      ],
    ),
    (
      'saved_10000',
      'Уже серьёзно',
      'Накопите 10 000 ₽',
      10000,
      AchievementRarity.rare,
      'income_grows',
      [
        'Копилка жиреет. Мне нравится.',
        'По чуть-чуть — и уже результат.',
        'Сбережения пошли в рост.',
      ],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description: desc,
      category: AchievementCategory.savings,
      rarity: rarity,
      reaction: FinoraReactionType.happy,
      art: art,
      target: rub * _rub,
      unit: ProgressUnit.money,
      value: (m) => m.savedMinor,
      quotes: quotes,
    ),
  for (final (id, title, k, rarity, art, quotes) in [
    (
      'cushion_1',
      'Финансовая подушка',
      1,
      AchievementRarity.rare,
      'safety_cushion',
      [
        'Подушка на месяц готова.',
        'Теперь спокойнее.',
        'Запас на чёрный день есть.',
      ],
    ),
    (
      'cushion_3',
      'Спокойнее жить',
      3,
      AchievementRarity.epic,
      'safety_cushion',
      ['Три месяца запаса. Спится крепче.', 'Надёжно.', 'Вот это подушка.'],
    ),
    (
      'cushion_6',
      'Финансовая крепость',
      6,
      AchievementRarity.legendary,
      'invest_started',
      ['Полгода запаса. Крепость.', 'Ничто не страшно.', 'Финансовая броня.'],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description: k == 1
          ? 'Накопите сумму средних расходов за месяц'
          : 'Накопите средние расходы за $k '
                '${_plural(k, 'месяц', 'месяца', 'месяцев')}',
      category: AchievementCategory.savings,
      rarity: rarity,
      reaction: FinoraReactionType.calm,
      art: art,
      target: 100,
      unit: ProgressUnit.percent,
      value: (m) {
        final avg = m.averageMonthExpense;
        if (avg == null || avg == 0) return 0;
        return (m.savedMinor * 100 ~/ (avg * k)).clamp(0, 100);
      },
      quotes: quotes,
    ),
  // ── Цели ───────────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'goal_set',
    title: 'Есть цель',
    description: 'Поставьте первую мечту',
    category: AchievementCategory.goals,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.focused,
    art: 'goal_set',
    target: 1,
    value: (m) => m.goals.length,
    quotes: [
      'Цель на прицеле.',
      'Есть куда стремиться.',
      'Мечта записана — уже полдела.',
    ],
  ),
  for (final (id, title, pct, rarity, quotes) in [
    (
      'goal_half',
      'Полпути',
      50,
      AchievementRarity.uncommon,
      ['Половина пути позади.', 'Уже середина!', 'Дальше будет легче.'],
    ),
    (
      'goal_90',
      'Почти получилось',
      90,
      AchievementRarity.rare,
      ['Совсем чуть-чуть осталось.', 'Финиш близко.', 'Ещё немного!'],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description: 'Накопите $pct% любой мечты',
      category: AchievementCategory.goals,
      rarity: rarity,
      reaction: FinoraReactionType.excited,
      art: 'goal_set',
      target: pct,
      unit: ProgressUnit.percent,
      value: (m) => (m.bestGoalRatio * 100).floor().clamp(0, 100),
      quotes: quotes,
    ),
  for (final (id, title, desc, n, rarity, art, reaction, quotes) in [
    (
      'goal_done',
      'Цель достигнута',
      'Закройте первую мечту',
      1,
      AchievementRarity.rare,
      'goal_done',
      FinoraReactionType.celebrating,
      ['Вот она.', 'Цель закрыта. Красиво.', 'Ну что, следующую?'],
    ),
    (
      'goals_3',
      'Мечты сбываются',
      'Закройте 3 мечты',
      3,
      AchievementRarity.epic,
      'goal_done',
      FinoraReactionType.love,
      ['Три мечты сбылись!', 'Мечтать полезно.', 'Это уже традиция.'],
    ),
    (
      'goals_10',
      'Планировщик',
      'Закройте 10 мечтаний',
      10,
      AchievementRarity.legendary,
      'budget_master',
      FinoraReactionType.celebrating,
      [
        'Десять мечтаний! Настоящий планировщик.',
        'Всё по плану, всё сбывается.',
        'Снимаю шляпу.',
      ],
    ),
  ])
    AchievementDefinition(
      id: id,
      title: title,
      description: desc,
      category: AchievementCategory.goals,
      rarity: rarity,
      reaction: reaction,
      art: art,
      target: n,
      value: (m) => m.completedGoalCount,
      quotes: quotes,
    ),
  // ── Дисциплина: доходы и расходы ───────────────────────────────────────
  AchievementDefinition(
    id: 'plus_month',
    title: 'Положительный месяц',
    description: 'Закончите месяц с доходами выше расходов',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.happy,
    art: 'balance_plus',
    target: 1,
    value: (m) =>
        m.months.where((mf) => mf.income > 0 && mf.income > mf.expense).length,
    quotes: [
      'Доходы победили расходы.',
      'Месяц в плюсе.',
      'Вот такой график я люблю.',
    ],
  ),
  AchievementDefinition(
    id: 'plus_3',
    title: 'Стабильный плюс',
    description: '3 месяца подряд доходы выше расходов',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.proud,
    art: 'income_grows',
    target: 3,
    unit: ProgressUnit.months,
    value: (m) =>
        _monthsRun(m, (mf) => mf.income > 0 && mf.income > mf.expense),
    quotes: [
      'Три месяца в плюсе.',
      'Стабильность — это красиво.',
      'Так держим.',
    ],
  ),
  AchievementDefinition(
    id: 'balance_6',
    title: 'Финансовый баланс',
    description: '6 месяцев подряд доходы не ниже расходов',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.epic,
    reaction: FinoraReactionType.calm,
    art: 'finance_zen',
    target: 6,
    unit: ProgressUnit.months,
    value: (m) =>
        _monthsRun(m, (mf) => mf.income > 0 && mf.income >= mf.expense),
    quotes: ['Полгода в равновесии.', 'Баланс найден.', 'Ровно и спокойно.'],
  ),
  AchievementDefinition(
    id: 'economy',
    title: 'Экономный месяц',
    description: 'Потратьте на 10% меньше, чем в прошлом месяце',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.happy,
    art: 'expenses_control',
    target: 1,
    value: (m) {
      for (var i = 1; i < m.months.length; i++) {
        final prev = m.months[i - 1], cur = m.months[i];
        if (m.covered(prev) &&
            prev.expense > 0 &&
            cur.expense > 0 &&
            cur.expense * 10 <= prev.expense * 9) {
          return 1;
        }
      }
      return 0;
    },
    quotes: [
      'Тратим меньше — живём спокойнее.',
      'Экономия засчитана.',
      'Минус десять процентов. Хитро.',
    ],
  ),
  // ── Дисциплина: платежи ────────────────────────────────────────────────
  AchievementDefinition(
    id: 'on_time',
    title: 'Всё вовремя',
    description: 'Оплатите обязательный платёж не позже срока',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.success,
    art: 'payment_on_time',
    target: 1,
    value: (m) => m.state.payments.where((p) => p.onTime).length,
    quotes: [
      'Оплачено вовремя.',
      'Календарь доволен.',
      'Без опозданий — уважаю.',
    ],
  ),
  AchievementDefinition(
    id: 'no_overdue',
    title: 'Без просрочек',
    description: 'Все платежи месяца оплачены вовремя',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.calm,
    art: 'debt_closed',
    target: 1,
    value: (m) => m.months
        .where((mf) => m.paymentsIn(mf).isNotEmpty && m.paymentsOnTime(mf))
        .length,
    quotes: [
      'Всё оплачено вовремя.',
      'Ни одного хвоста.',
      'Месяц без просрочек. Красиво.',
    ],
  ),
  AchievementDefinition(
    id: 'ideal_year',
    title: 'Идеальный год',
    description: '12 месяцев подряд без просроченных платежей',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.legendary,
    reaction: FinoraReactionType.celebrating,
    art: 'payment_on_time',
    target: 12,
    unit: ProgressUnit.months,
    value: (m) => _monthsRun(
      m,
      (mf) => m.paymentsIn(mf).isNotEmpty && m.paymentsOnTime(mf),
    ),
    quotes: [
      'Год без единой просрочки.',
      'Идеально. Без шуток.',
      'Платёжная легенда.',
    ],
  ),
  // ── Дисциплина: категории ──────────────────────────────────────────────
  AchievementDefinition(
    id: 'organizer',
    title: 'Организатор',
    description: 'Создайте 5 своих категорий или подкатегорий',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.happy,
    art: 'category_master',
    target: 5,
    value: (m) => m.ownCategories.length + m.ownSubcategories,
    quotes: [
      'Всё разложено по папкам.',
      'Порядок — моя радость.',
      'Организованно!',
    ],
  ),
  AchievementDefinition(
    id: 'order',
    title: 'Порядок в финансах',
    description: '10 категорий за месяц, «Прочее» — не больше 20%',
    category: AchievementCategory.discipline,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.proud,
    art: 'categories_set',
    target: 10,
    value: (m) {
      var best = 0;
      for (final mf in m.months) {
        if (mf.otherShare <= .2) best = math.max(best, mf.categories.length);
      }
      return best;
    },
    quotes: [
      'Каждой трате — своё место.',
      'Вот это порядок.',
      'Прочее почти пустое. Люблю.',
    ],
  ),
  // ── Аналитика ──────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'analytics_open',
    title: 'Посмотрим цифры',
    description: 'Впервые откройте аналитику',
    category: AchievementCategory.analytics,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.thinking,
    art: 'analyst',
    target: 1,
    value: (m) => m.state.analyticsPeriods.isEmpty ? 0 : 1,
    quotes: [
      'Ну-ка, что тут у нас.',
      'Цифры любят внимание.',
      'Посмотрим, куда всё уходит.',
    ],
  ),
  AchievementDefinition(
    id: 'analyst_10',
    title: 'Финансовый аналитик',
    description: 'Посмотрите аналитику за 10 разных периодов',
    category: AchievementCategory.analytics,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.thinking,
    art: 'analyst',
    target: 10,
    value: (m) => m.state.analyticsPeriods.length,
    quotes: [
      'Графики тебя уже знают.',
      'Аналитик со стажем.',
      'Цифры не врут — проверено.',
    ],
  ),
  AchievementDefinition(
    id: 'categorized_95',
    title: 'Знаю, куда уходят деньги',
    description: '95% расходов месяца — в понятных категориях',
    category: AchievementCategory.analytics,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.focused,
    art: 'category_master',
    target: 95,
    unit: ProgressUnit.percent,
    value: (m) {
      var best = 0;
      for (final mf in m.months) {
        if (mf.expense > 0 && mf.records >= 10) {
          best = math.max(best, ((1 - mf.otherShare) * 100).floor());
        }
      }
      return best;
    },
    quotes: [
      'Теперь всё понятно.',
      'Ни одной загадки почти.',
      'Деньги на виду.',
    ],
  ),
  AchievementDefinition(
    id: 'categorized_100',
    title: 'Ни одной загадки',
    description: 'Месяц без трат в «Прочем»',
    category: AchievementCategory.analytics,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.success,
    art: 'categories_set',
    target: 1,
    value: (m) => m.months
        .where(
          (mf) => mf.records >= 10 && mf.expense > 0 && mf.otherExpense == 0,
        )
        .length,
    quotes: ['Ни одной загадки.', 'Всё подписано.', 'Чистая работа.'],
  ),
  // ── Редкие ─────────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'perfect_month',
    title: 'Идеальный месяц',
    description: 'Без просрочек, в рамках бюджета, всё по категориям и в плюсе',
    category: AchievementCategory.rare,
    rarity: AchievementRarity.legendary,
    reaction: FinoraReactionType.celebrating,
    art: 'month_discipline',
    target: 1,
    value: (m) => m.state.perfectMonths.length,
    quotes: [
      'Ну это уже почти искусство.',
      'Идеальный месяц. Без шуток.',
      'Так выглядят финансы под контролем.',
    ],
  ),
  AchievementDefinition(
    id: 'perfectionist',
    title: 'Финансовый перфекционист',
    description: 'Три идеальных месяца',
    category: AchievementCategory.rare,
    rarity: AchievementRarity.legendary,
    reaction: FinoraReactionType.proud,
    art: 'budget_master',
    target: 3,
    value: (m) => m.state.perfectMonths.length,
    quotes: [
      'Три идеальных месяца. Перфекционист.',
      'Безупречно.',
      'Это уже стиль жизни.',
    ],
  ),
  AchievementDefinition(
    id: 'year',
    title: 'Год с Finora',
    description: '365 дней вместе',
    category: AchievementCategory.rare,
    rarity: AchievementRarity.epic,
    reaction: FinoraReactionType.love,
    art: 'finance_zen',
    target: 365,
    unit: ProgressUnit.days,
    value: (m) => m.daysWithFinora,
    quotes: [
      'Год вместе! Спасибо.',
      'Целый год порядка.',
      'С днём рождения нас.',
    ],
  ),
  AchievementDefinition(
    id: 'veteran',
    title: 'Ветеран Finora',
    description: 'Два года вместе',
    category: AchievementCategory.rare,
    rarity: AchievementRarity.legendary,
    reaction: FinoraReactionType.proud,
    art: 'month_discipline',
    target: 730,
    unit: ProgressUnit.days,
    value: (m) => m.daysWithFinora,
    quotes: [
      'Два года! Ветеран.',
      'Столько всего вместе прошли.',
      'Старая гвардия.',
    ],
  ),
  AchievementDefinition(
    id: 'legend',
    title: 'Легенда Finora',
    description: 'Получите 90% несекретных достижений',
    category: AchievementCategory.rare,
    rarity: AchievementRarity.legendary,
    reaction: FinoraReactionType.celebrating,
    art: 'goal_done',
    target: 90,
    unit: ProgressUnit.percent,
    value: (m) {
      final pool = achievementDefinitions
          .where((d) => !d.secret && d.id != 'legend')
          .toList();
      final got = pool.where((d) => m.state.unlocked.containsKey(d.id)).length;
      return pool.isEmpty ? 0 : got * 100 ~/ pool.length;
    },
    quotes: [
      'Ладно. Это уже серьёзно.',
      'Почти всё закрыто. Снимаю шляпу.',
      'Финансовая машина.',
    ],
  ),
  // ── Секретные ──────────────────────────────────────────────────────────
  AchievementDefinition(
    id: 'night',
    title: 'Ночная бухгалтерия',
    description: 'Добавьте операцию с 02:00 до 04:00',
    category: AchievementCategory.secret,
    rarity: AchievementRarity.rare,
    reaction: FinoraReactionType.sleepy,
    art: 'no_spend_day',
    target: 1,
    secret: true,
    value: (m) => m.state.flags.contains('night') ? 1 : 0,
    quotes: [
      'Ты чего не спишь?',
      'Ночная смена бухгалтерии.',
      'Записала. А теперь спать.',
    ],
  ),
  AchievementDefinition(
    id: 'big_check',
    title: 'Вот это чек',
    description: 'Операция в 10 раз больше средней траты',
    category: AchievementCategory.secret,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.surprised,
    art: 'cashback',
    target: 1,
    secret: true,
    value: (m) {
      if (m.expenses.length < 20) return 0;
      final avg =
          m.expenses.fold(0, (s, e) => s + e.amountMinor) ~/ m.expenses.length;
      return m.expenses.any((e) => e.amountMinor >= avg * 10) ? 1 : 0;
    },
    quotes: [
      'Ого. Вот это чек.',
      'Я аж подпрыгнула.',
      'Надеюсь, оно того стоило.',
    ],
  ),
  AchievementDefinition(
    id: 'tiny',
    title: 'Копейка рубль бережёт',
    description: 'Запишите трату меньше 10 ₽',
    category: AchievementCategory.secret,
    rarity: AchievementRarity.common,
    reaction: FinoraReactionType.happy,
    art: 'first_income',
    target: 1,
    secret: true,
    value: (m) => m.expenses.any((e) => e.amountMinor < 10 * _rub) ? 1 : 0,
    quotes: [
      'Даже копейку учла!',
      'Вот это внимательность.',
      'Мелочь, а приятно.',
    ],
  ),
  AchievementDefinition(
    id: 'archaeologist',
    title: 'Финансовый археолог',
    description: 'Добавьте операцию задним числом больше чем на 30 дней',
    category: AchievementCategory.secret,
    rarity: AchievementRarity.uncommon,
    reaction: FinoraReactionType.thinking,
    art: 'analyst',
    target: 1,
    secret: true,
    value: (m) => m.state.flags.contains('archaeologist') ? 1 : 0,
    quotes: [
      'Раскопки удались.',
      'Древняя трата найдена.',
      'История восстановлена.',
    ],
  ),
];
