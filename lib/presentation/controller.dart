import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/finance_repository.dart';
import '../domain/achievements.dart';
import '../domain/models.dart';
import '../domain/payment_plan.dart';
import '../domain/finance_engine.dart';
import '../domain/scan_import.dart';
import '../features/finora_ai/services/finora_ai.dart';
import '../services/notification_service.dart';

const notificationSyncWarning =
    'Данные сохранены, но не удалось обновить уведомления. '
    'Повторите обновление в настройках уведомлений.';

/// Scheduling is independent of the already committed financial data. Explicit
/// notification actions can await this result without retrying their data write.
class NotificationSyncResult {
  const NotificationSyncResult.success() : error = null;
  const NotificationSyncResult.failure(this.error);
  final Object? error;
  bool get succeeded => error == null;
}

class FinanceController extends ChangeNotifier {
  FinanceController(this.repository, this.notifications, this.data);
  final FinanceRepository repository;
  final NotificationService notifications;
  FinanceData data;
  Future<void> _tail = Future.value();
  Future<NotificationSyncResult> _lastNotificationSync = Future.value(
    const NotificationSyncResult.success(),
  );
  NotificationSyncResult? _notificationSyncResult;
  bool _notificationSyncPending = false;
  bool _disposed = false;
  int _notificationRevision = 0;

  bool get notificationSyncPending => _notificationSyncPending;
  NotificationSyncResult? get notificationSyncResult => _notificationSyncResult;

  /// Await the sync already scheduled by mutate/replace; never schedules twice.
  Future<NotificationSyncResult> waitForNotificationSync() =>
      _lastNotificationSync;

  /// Retry only the native notification plan, with no second financial write.
  Future<NotificationSyncResult> retryNotificationSync() {
    _queueNotificationSync(data);
    notifyListeners();
    return _lastNotificationSync;
  }

  void _queueNotificationSync(FinanceData snapshot) {
    final revision = ++_notificationRevision;
    _notificationSyncPending = true;
    _lastNotificationSync =
        Future<void>.sync(() => notifications.sync(snapshot))
            .then<NotificationSyncResult>(
              (_) => const NotificationSyncResult.success(),
              onError: (Object error, StackTrace _) =>
                  NotificationSyncResult.failure(error),
            )
            .then((result) {
              if (!_disposed && revision == _notificationRevision) {
                _notificationSyncPending = false;
                _notificationSyncResult = result;
                notifyListeners();
              }
              return result;
            });
  }

  @override
  void dispose() {
    _disposed = true;
    _unlocks.close();
    super.dispose();
  }

  // ── 1.44: achievements ─────────────────────────────────────────────────

  final _unlocks = StreamController<List<AchievementDefinition>>.broadcast();

  /// Achievements received by a change, in the order received.
  Stream<List<AchievementDefinition>> get achievementUnlocks => _unlocks.stream;

  /// The clock of the achievement engine (tests set it).
  DateTime Function() achievementClock = DateTime.now;

  AchievementReport get achievements => AchievementEngine.report(
    data,
    data.achievements,
    now: achievementClock(),
  );

  FinanceData _withAchievements(
    FinanceData before,
    FinanceData next, {
    bool activity = false,
    bool events = true,
    List<PaymentMark> payments = const [],
  }) {
    var state = AchievementEngine.merge(next.achievements, before.achievements);
    if (payments.isNotEmpty) {
      state = state.copyWith(payments: [...state.payments, ...payments]);
    }
    final (updated, fresh) = AchievementEngine.update(
      before,
      next,
      state,
      now: achievementClock(),
      activity: activity,
      events: events,
    );
    if (fresh.isNotEmpty && !_unlocks.isClosed) {
      scheduleMicrotask(() {
        if (!_unlocks.isClosed) _unlocks.add(fresh);
      });
    }
    return next.copyWith(achievements: updated);
  }

  /// Only the achievement state changes (a screen was opened).
  Future<void> _noteAchievements(
    AchievementState Function(AchievementState) change, {
    bool activity = false,
  }) => _mutate(
    (d) => d.copyWith(achievements: change(d.achievements)),
    activity: activity,
  );

  /// Whether looking at screens is written down (analytics periods, a day
  /// of activity, «seen»). Off in widget tests that do not test it: such a
  /// write would otherwise run in the test's fake time.
  static bool screenNotes = !Platform.environment.containsKey('FLUTTER_TEST');

  /// A period of analytics was looked at («Аналитик»).
  Future<void> noteAnalytics(String period, {DateTime? now}) {
    if (!screenNotes) return Future.value();
    final clock = now ?? achievementClock();
    final key = '$period:${AchievementState.day(clock)}';
    if (data.achievements.analyticsPeriods.contains(key)) {
      return Future.value();
    }
    return _noteAchievements(
      (s) => s.copyWith(analyticsPeriods: {...s.analyticsPeriods, key}),
      activity: true,
    );
  }

  /// The budgets were looked at: a day of activity for the series.
  Future<void> noteActivity() {
    if (!screenNotes) return Future.value();
    final day = AchievementState.day(achievementClock());
    if (data.achievements.activityDays.contains(day)) return Future.value();
    return _noteAchievements((s) => s, activity: true);
  }

  /// The achievements screen was opened: nothing is «Новое» any more.
  Future<void> markAchievementsSeen() => screenNotes
      ? _noteAchievements((s) => s.copyWith(seenAt: achievementClock()))
      : Future.value();

  String id() => const Uuid().v4();
  DateTime get periodStart {
    final now = DateTime.now();
    final day = data.preferences.monthStart;
    final month = now.day < day ? now.month - 1 : now.month;
    return DateTime(now.year, month, day);
  }

  DateTime get periodEnd =>
      DateTime(periodStart.year, periodStart.month + 1, periodStart.day);
  Account? account(String id) =>
      data.accounts.where((a) => a.id == id).firstOrNull;
  Category? category(String? id) =>
      data.categories.where((a) => a.id == id).firstOrNull;
  Goal? goal(String? id) => data.goals.where((g) => g.id == id).firstOrNull;
  String destinationName(FinanceEntry entry) => entry.toGoalId != null
      ? 'Мечта: ${goal(entry.toGoalId)?.name ?? 'Цель'}'
      : account(entry.toAccountId ?? '')?.name ?? 'Счёт';
  String get currency => data.preferences.baseCurrency;
  int get balance => FinanceEngine.totalBalance(
    data.accounts,
    data.entries,
    currency,
    data.goals,
  );
  Future<void> mutate(FinanceData Function(FinanceData) transform) =>
      _mutate(transform);

  Future<void> _mutate(
    FinanceData Function(FinanceData) transform, {
    bool activity = false,
    List<PaymentMark> Function()? payments,
    bool synchronizeNotifications = true,
  }) {
    final result = _tail.then((_) async {
      final before = data;
      final next = _withAchievements(
        before,
        FinanceRepository.normalizeCategoryPreferences(transform(before)),
        activity: activity,
        payments: payments?.call() ?? const [],
      );
      await repository.save(next);
      data = next;
      // Commit first. Ordinary ledger actions stay nonblocking, while explicit
      // reminder editors can wait for this same result and surface failures.
      if (synchronizeNotifications) _queueNotificationSync(data);
      notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> preferences(AppPreferences value) =>
      mutate((d) => d.copyWith(preferences: value));
  Future<void> saveEntry(FinanceEntry entry) async {
    final before = data.entries.where((e) => e.id == entry.id).firstOrNull;
    await mutate((d) {
      FinanceEngine.validateEntry(entry, d);
      final existing = d.entries.where((e) => e.id == entry.id).firstOrNull;
      final entries = [...d.entries.where((e) => e.id != entry.id), entry];
      if (entry.recurringRuleId != null &&
          entry.status == 'posted' &&
          existing?.status != 'posted') {
        final rule = d.recurring
            .where((r) => r.id == entry.recurringRuleId)
            .firstOrNull;
        if (rule == null) {
          throw const FormatException(
            'Исходный долг удалён. Создайте обычную операцию вместо плановой выплаты.',
          );
        }
        if (PaymentPlan.requiredForOccurrence(
              rule,
              d.entries,
              entry.plannedDueDate!,
              now: achievementClock(),
            ) <=
            0) {
          throw const FormatException(
            'Этот платёж уже выполнен или график изменился. Пересчитайте план.',
          );
        }
      }
      final affected = {
        entry.recurringRuleId,
        existing?.recurringRuleId,
        for (final r in d.recurring)
          if (PaymentPlan.belongs(entry, r) ||
              existing != null && PaymentPlan.belongs(existing, r))
            r.id,
      }..remove(null);
      return d.copyWith(
        entries: entries,
        recurring: [
          for (final r in d.recurring)
            affected.contains(r.id)
                ? PaymentPlan.reconcile(
                    r,
                    d.entries,
                    entries,
                    now: achievementClock(),
                  )
                : r,
        ],
      );
    });
    // Finora AI learns the person's categories (a changed category is a
    // correction); her memory lives apart from the ledger. Not with
    // personalization turned off.
    if (data.preferences.ai.personalization) {
      unawaited(
        FinoraAi.instance.ready().then(
          (_) => FinoraAi.instance.observeSave(entry, before: before),
        ),
      );
    }
  }

  Future<void> deleteEntry(String id) => mutate((d) {
    final old = d.entries.where((e) => e.id == id).firstOrNull;
    final entries = d.entries.where((e) => e.id != id).toList();
    return d.copyWith(
      entries: entries,
      recurring: [
        for (final r in d.recurring)
          old != null && PaymentPlan.belongs(old, r)
              ? PaymentPlan.reconcile(
                  r,
                  d.entries,
                  entries,
                  now: achievementClock(),
                )
              : r,
      ],
    );
  });

  Future<void> saveAccount(Account value) => mutate(
    (d) => d.copyWith(
      accounts: [...d.accounts.where((a) => a.id != value.id), value],
    ),
  );
  Future<void> deleteAccount(String id) => mutate((d) {
    if (d.entries.any((e) => e.accountId == id || e.toAccountId == id) ||
        d.recurring.any((r) => r.accountId == id)) {
      throw const FormatException(
        'По этому счёту есть операции. Архивируйте его, чтобы сохранить историю.',
      );
    }
    return d.copyWith(accounts: d.accounts.where((a) => a.id != id).toList());
  });
  Future<void> saveCategory(Category value) => mutate(
    (d) => d.copyWith(
      categories: [...d.categories.where((a) => a.id != value.id), value],
    ),
  );

  /// Adds subcategory [name] to category [id] (keeps the category's place
  /// in the list). A name already there, ignoring case, is not repeated.
  Future<void> addSubcategory(String id, String name) => mutate(
    (d) => d.copyWith(
      categories: [
        for (final c in d.categories)
          if (c.id != id ||
              c.subcategories.any((s) => s.toLowerCase() == name.toLowerCase()))
            c
          else
            c.copyWith(subcategories: [...c.subcategories, name]),
      ],
    ),
  );
  Future<void> deleteCategory(String id) => mutate((d) {
    final linked =
        d.entries.any((e) => e.categoryId == id) ||
        d.budgets.any((b) => b.categoryId == id) ||
        d.recurring.any((r) => r.categoryId == id);
    return d.copyWith(
      categories: [
        for (final c in d.categories)
          if (c.id != id) c else if (linked) c.copyWith(archived: true),
      ],
    );
  });
  AppPreferences rememberCategory(FinanceData before, FinanceEntry entry) {
    if (before.entries.any((e) => e.id == entry.id) ||
        entry.categoryId == null ||
        entry.kind == EntryKind.transfer) {
      return before.preferences;
    }
    return entry.kind == EntryKind.expense
        ? before.preferences.copyWith(lastExpenseCategoryId: entry.categoryId)
        : before.preferences.copyWith(lastIncomeCategoryId: entry.categoryId);
  }

  Future<void> saveBudget(Budget value) => mutate(
    (d) => d.copyWith(
      budgets: [...d.budgets.where((a) => a.id != value.id), value],
    ),
  );
  Future<void> saveGoal(Goal value) => mutate(
    (d) =>
        d.copyWith(goals: [...d.goals.where((a) => a.id != value.id), value]),
  );
  Future<void> deleteGoal(String id) => mutate((d) {
    if (d.entries.any((e) => e.toGoalId == id)) {
      throw const FormatException(
        'В мечте есть переводы. Сначала измените или удалите связанные операции, чтобы сохранить корректный баланс.',
      );
    }
    return d.copyWith(goals: d.goals.where((g) => g.id != id).toList());
  });
  Future<void> saveRecurring(RecurringRule value) => mutate(
    (d) => d.copyWith(
      recurring: [...d.recurring.where((a) => a.id != value.id), value],
    ),
  );
  Future<void> importScanned(
    List<ScanImportItem> items, {
    String? attachmentPath,
  }) => mutate((data) {
    final entries = ScanImport.entries(
      items,
      data,
      newId: id,
      attachmentPath: attachmentPath,
    );
    var preferences = data.preferences;
    final chronological = [...entries]
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final entry in chronological) {
      preferences = rememberCategory(
        data.copyWith(preferences: preferences),
        entry,
      );
    }
    return data.copyWith(
      entries: [...data.entries, ...entries],
      preferences: preferences,
    );
  });
  Future<void> _replace(
    Future<void> Function(FinanceSnapshotTransform) action,
  ) {
    final result = _tail.then((_) async {
      final before = data;
      // Merge receipts before the repository's single commit. A failed restore
      // cannot leave a stale reward ledger on disk between two writes.
      await action(
        (loaded) => _withAchievements(before, loaded, events: false),
      );
      data = await repository.load();
      _queueNotificationSync(data);
      notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> clearDemo() =>
      _replace((merge) => repository.clearDemo(transform: merge));

  /// Erases all the person's data (see [FinanceRepository.resetAll]).
  Future<void> resetAll() async {
    await _replace((merge) => repository.resetAll(transform: merge));
    await FinoraAi.instance.memoryRepository.clear();
  }

  /// The demo ledger into an empty app (see [FinanceRepository.loadDemo]).
  Future<void> loadDemo() =>
      _replace((merge) => repository.loadDemo(transform: merge));
  Future<void> importJson(String content) =>
      _replace((merge) => repository.importJson(content, transform: merge));
  Future<void> importCsv(String content) =>
      _replace((merge) => repository.importCsv(content, transform: merge));
  Future<void> restore(String path) =>
      _replace((merge) => repository.restoreDatabase(path, transform: merge));

  /// Payments due today or overdue that the person has not answered yet
  /// (1.27), oldest first. «Напомнить позже» hides one for three hours.
  List<RecurringRule> duePayments({DateTime? now}) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day + 1);
    return data.recurring
        .where(
          (r) =>
              r.enabled &&
              r.kind == EntryKind.expense &&
              r.nextDate.isBefore(today) &&
              !(_snoozed[r.id]?.isAfter(clock) ?? false),
        )
        .toList()
      ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
  }

  /// 1.36: the payment an operation came from (its id is
  /// `recurring:<rule>:…`), or one with the same name — for its icon.
  RecurringRule? ruleOf(FinanceEntry e) {
    if (e.recurringRuleId != null) {
      final linked = data.recurring
          .where((r) => r.id == e.recurringRuleId)
          .firstOrNull;
      if (linked != null) return linked;
    }
    if (e.id.startsWith('recurring:')) {
      final id = e.id.split(':')[1];
      final rule = data.recurring.where((r) => r.id == id).firstOrNull;
      if (rule != null) return rule;
    }
    if (e.payee.isEmpty || e.kind != EntryKind.expense) return null;
    final name = e.payee.trim().toLowerCase();
    return data.recurring
        .where((r) => r.name.trim().toLowerCase() == name)
        .firstOrNull;
  }

  final _snoozed = <String, DateTime>{};

  void snoozePayment(String ruleId, {DateTime? now}) =>
      _snoozed[ruleId] = (now ?? DateTime.now()).add(const Duration(hours: 3));

  /// «Оплачено»: the expense goes into the ledger on its date, and the rule
  /// moves to the next date. 1.36: [amountMinor] — what was actually paid
  /// (a subscription's price changes); [remember] makes it the new price.
  /// A loan whose whole sum is paid is switched off.
  Future<FinanceEntry?> confirmPayment(
    String ruleId, {
    int? amountMinor,
    bool remember = false,
    DateTime? expectedDueDate,
    String? confirmationId,
    RecurringRule? expectedRule,
    FinanceEntry? expectedPlannedEntry,
  }) => _pay(
    ruleId,
    amountMinor: amountMinor,
    remember: remember,
    expectedDueDate: expectedDueDate,
    confirmationId: confirmationId,
    expectedRule: expectedRule,
    expectedPlannedEntry: expectedPlannedEntry,
  );

  /// 1.36: paid ahead of time (a swipe to the right): the operation is
  /// recorded today. A full payment moves the date on; a smaller one only
  /// lowers what is left of a loan.
  Future<FinanceEntry?> payEarly(
    String ruleId, {
    int? amountMinor,
    DateTime? now,
  }) => _pay(ruleId, amountMinor: amountMinor, early: now ?? DateTime.now());

  Future<FinanceEntry?> _pay(
    String ruleId, {
    int? amountMinor,
    bool remember = false,
    DateTime? early,
    DateTime? expectedDueDate,
    String? confirmationId,
    RecurringRule? expectedRule,
    FinanceEntry? expectedPlannedEntry,
  }) async {
    FinanceEntry? posted;
    PaymentMark? mark;
    await _mutate((d) {
      final r = d.recurring.where((x) => x.id == ruleId).firstOrNull;
      if (r == null) {
        if (expectedRule != null ||
            expectedDueDate != null ||
            expectedPlannedEntry != null) {
          throw const FormatException(
            'Платёж удалён. Подтверждение больше не действует.',
          );
        }
        return d;
      }
      final confirmedId = confirmationId == null
          ? null
          : 'recurring:${r.id}:confirmation:$confirmationId';
      if (confirmedId != null) {
        final prior = d.entries
            .where((e) => e.id == confirmedId && e.status == 'posted')
            .firstOrNull;
        if (prior != null) {
          posted = prior;
          return d;
        }
      }
      if (expectedRule != null &&
          jsonEncode(expectedRule.toJson()) != jsonEncode(r.toJson())) {
        throw const FormatException(
          'Условия платежа изменились. Проверьте счёт, сумму и дату заново.',
        );
      }
      if (expectedPlannedEntry != null) {
        final current = d.entries
            .where((e) => e.id == expectedPlannedEntry.id)
            .firstOrNull;
        if (current == null ||
            current.status != 'pending' ||
            jsonEncode(current.toJson()) !=
                jsonEncode(expectedPlannedEntry.toJson())) {
          throw const FormatException(
            'Плановая выплата изменилась. Откройте подтверждение заново.',
          );
        }
      }
      if (expectedDueDate != null &&
          !PaymentPlan.sameDay(r.nextDate, expectedDueDate)) {
        throw const FormatException(
          'Дата платежа изменилась. Откройте подтверждение заново.',
        );
      }
      if (r.kind == EntryKind.expense) {
        mark = PaymentMark(
          ruleId: r.id,
          due: r.nextDate,
          paid: early ?? achievementClock(),
        );
      }
      final remaining = early == null
          ? PaymentPlan.requiredForOccurrence(
              r,
              d.entries,
              r.nextDate,
              now: achievementClock(),
            )
          : r.amountMinor;
      final sum = amountMinor ?? remaining;
      if (early == null && remaining == 0) {
        throw const FormatException('Этот платёж уже учтён. Обновите список.');
      }
      if (sum <= 0) {
        throw const FormatException('Введите сумму больше нуля');
      }
      final entry = FinanceEntry(
        id:
            confirmedId ??
            (early == null
                ? 'recurring:${r.id}:${r.nextDate.toIso8601String()}${PaymentPlan.confirmedForOccurrence(r, d.entries, r.nextDate) == 0 ? '' : ':part:${PaymentPlan.confirmedForOccurrence(r, d.entries, r.nextDate)}'}'
                : 'recurring:${r.id}:early:${early.microsecondsSinceEpoch}'),
        kind: r.kind,
        amountMinor: sum,
        currency: r.currency,
        accountId: expectedPlannedEntry?.accountId ?? r.accountId,
        categoryId: r.categoryId,
        date: early ?? r.nextDate,
        payee: r.name,
        note: early == null ? '' : 'Досрочно',
        recurrence: r.frequency,
        serviceId: r.serviceId,
        serviceIconPath: r.customIconPath,
        recurringRuleId: early == null ? r.id : null,
        planningBatchId: early == null ? 'confirmed-payment' : null,
        plannedDueDate: early == null ? r.nextDate : null,
        memberId: d.members.any((m) => m.id == 'me')
            ? 'me'
            : d.members.first.id,
      );
      FinanceEngine.validateEntry(entry, d);
      if (d.accounts
          .where((a) => a.id == entry.accountId && !a.archived)
          .isEmpty) {
        throw const FormatException(
          'Счёт платежа архивирован. Выберите действующий счёт.',
        );
      }
      posted = entry;
      final entries = [...d.entries.where((e) => e.id != entry.id), entry];
      var next = remember && sum != r.amountMinor
          ? r.copyWith(amountMinor: sum)
          : r;
      final afterRemaining = PaymentPlan.requiredForOccurrence(
        next,
        entries,
        r.nextDate,
        now: achievementClock(),
      );
      // Replace fulfilled scheduled placeholders, never a user's posted row.
      entries.removeWhere(
        (e) =>
            e.status == 'pending' &&
            e.recurringRuleId == r.id &&
            e.plannedDueDate != null &&
            PaymentPlan.sameDay(e.plannedDueDate!, r.nextDate) &&
            afterRemaining == 0,
      );
      if (afterRemaining > 0) {
        for (var i = 0; i < entries.length; i++) {
          final e = entries[i];
          if (e.status == 'pending' &&
              e.recurringRuleId == r.id &&
              e.plannedDueDate != null &&
              PaymentPlan.sameDay(e.plannedDueDate!, r.nextDate) &&
              e.amountMinor > afterRemaining) {
            entries[i] = e.copyWith(amountMinor: afterRemaining);
          }
        }
      }
      if (early == null) {
        next = PaymentPlan.reconcile(
          next,
          d.entries,
          entries,
          now: achievementClock(),
        );
      } else {
        if (sum >= r.amountMinor) {
          next = next.copyWith(nextDate: FinanceEngine.nextOccurrence(next));
        }
        if (PaymentPlan.of(next, entries).done) {
          next = next.copyWith(enabled: false);
        }
      }
      return d.copyWith(
        entries: entries,
        recurring: [for (final x in d.recurring) x.id == r.id ? next : x],
      );
    }, payments: () => [?mark]);
    return posted;
  }

  /// «Не платить в этот раз»: the date moves on, nothing is posted.
  Future<void> skipPayment(String ruleId) => mutate(
    (d) => d.copyWith(
      recurring: [
        for (final x in d.recurring)
          x.id == ruleId
              ? x.copyWith(nextDate: FinanceEngine.nextOccurrence(x))
              : x,
      ],
    ),
  );

  Future<void> processRecurring() => mutate((d) {
    final now = DateTime.now();
    final entries = [...d.entries];
    final rules = <RecurringRule>[];
    for (final original in d.recurring) {
      var r = original;
      var generated = 0;
      // 1.27: payments (expenses) are never posted by themselves — the
      // person confirms each one when Finora asks ([duePayments]).
      while (r.enabled &&
          r.automatic &&
          r.kind != EntryKind.expense &&
          !r.nextDate.isAfter(now) &&
          generated < 1000) {
        final entry = FinanceEntry(
          id: 'recurring:${r.id}:${r.nextDate.toIso8601String()}',
          kind: r.kind,
          amountMinor: r.amountMinor,
          currency: r.currency,
          accountId: r.accountId,
          categoryId: r.categoryId,
          date: r.nextDate,
          payee: r.name,
          recurrence: r.frequency,
          serviceId: r.serviceId,
          serviceIconPath: r.customIconPath,
          memberId: d.members.any((m) => m.id == 'me')
              ? 'me'
              : d.members.first.id,
        );
        FinanceEngine.validateEntry(entry, d);
        if (!entries.any((e) => e.id == entry.id)) {
          entries.add(entry);
        }
        r = r.copyWith(nextDate: FinanceEngine.nextOccurrence(r));
        generated++;
      }
      rules.add(r);
    }
    return d.copyWith(entries: entries, recurring: rules);
  });
}

class FinanceScope extends InheritedNotifier<FinanceController> {
  const FinanceScope({
    super.key,
    required FinanceController controller,
    required super.child,
  }) : super(notifier: controller);
  static FinanceController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FinanceScope>()!.notifier!;

  /// The controller without listening to it (null outside the app).
  static FinanceController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FinanceScope>()?.notifier;
}
