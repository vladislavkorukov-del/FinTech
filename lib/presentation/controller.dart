import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../domain/finance_engine.dart';
import '../domain/scan_import.dart';
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
    super.dispose();
  }

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
  Future<void> mutate(FinanceData Function(FinanceData) transform) {
    final result = _tail.then((_) async {
      final next = FinanceRepository.normalizeCategoryPreferences(
        transform(data),
      );
      await repository.save(next);
      data = next;
      // Commit first. Ordinary ledger actions stay nonblocking, while explicit
      // reminder editors can wait for this same result and surface failures.
      _queueNotificationSync(data);
      notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> preferences(AppPreferences value) =>
      mutate((d) => d.copyWith(preferences: value));
  Future<void> saveEntry(FinanceEntry entry) => mutate((d) {
    FinanceEngine.validateEntry(entry, d);
    return d.copyWith(
      entries: [...d.entries.where((e) => e.id != entry.id), entry],
    );
  });
  Future<void> deleteEntry(String id) => mutate(
    (d) => d.copyWith(entries: d.entries.where((e) => e.id != id).toList()),
  );
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
  Future<void> _replace(Future<void> Function() action) {
    final result = _tail.then((_) async {
      await action();
      data = await repository.load();
      _queueNotificationSync(data);
      notifyListeners();
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> clearDemo() => _replace(repository.clearDemo);

  /// Erases all the person's data (see [FinanceRepository.resetAll]).
  Future<void> resetAll() => _replace(repository.resetAll);

  /// The demo ledger into an empty app (see [FinanceRepository.loadDemo]).
  Future<void> loadDemo() => _replace(repository.loadDemo);
  Future<void> importJson(String content) =>
      _replace(() => repository.importJson(content));
  Future<void> importCsv(String content) =>
      _replace(() => repository.importCsv(content));
  Future<void> restore(String path) =>
      _replace(() => repository.restoreDatabase(path));

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

  final _snoozed = <String, DateTime>{};

  void snoozePayment(String ruleId, {DateTime? now}) =>
      _snoozed[ruleId] = (now ?? DateTime.now()).add(const Duration(hours: 3));

  /// «Оплачено»: the expense goes into the ledger on its date, and the rule
  /// moves to the next date.
  Future<FinanceEntry?> confirmPayment(String ruleId) async {
    FinanceEntry? posted;
    await mutate((d) {
      final r = d.recurring.where((x) => x.id == ruleId).firstOrNull;
      if (r == null) return d;
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
      posted = entry;
      return d.copyWith(
        entries: [...d.entries.where((e) => e.id != entry.id), entry],
        recurring: [
          for (final x in d.recurring)
            x.id == r.id
                ? x.copyWith(nextDate: FinanceEngine.nextOccurrence(x))
                : x,
        ],
      );
    });
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
}
