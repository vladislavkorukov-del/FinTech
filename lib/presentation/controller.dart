import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/finance_repository.dart';
import '../domain/models.dart';
import '../domain/finance_engine.dart';
import '../services/notification_service.dart';

class FinanceController extends ChangeNotifier {
  FinanceController(this.repository, this.notifications, this.data);
  final FinanceRepository repository;
  final NotificationService notifications;
  FinanceData data;
  Future<void> _tail = Future.value();
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
  bool get hidden => data.preferences.hideAmounts;
  String get currency => data.preferences.baseCurrency;
  int get balance =>
      FinanceEngine.totalBalance(data.accounts, data.entries, currency);
  Future<void> mutate(FinanceData Function(FinanceData) transform) {
    final result = _tail.then((_) async {
      final next = transform(data);
      await repository.save(next);
      data = next;
      notifyListeners();
      // Notifications must never roll back an already committed financial operation.
      unawaited(notifications.sync(data).catchError((Object _) {}));
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
    if (d.entries.any((e) => e.categoryId == id) ||
        d.budgets.any((b) => b.categoryId == id) ||
        d.recurring.any((r) => r.categoryId == id)) {
      throw const FormatException(
        'Категория используется. Сначала перенесите её операции и связанные бюджеты.',
      );
    }
    return d.copyWith(
      categories: d.categories.where((a) => a.id != id).toList(),
    );
  });
  Future<void> saveBudget(Budget value) => mutate(
    (d) => d.copyWith(
      budgets: [...d.budgets.where((a) => a.id != value.id), value],
    ),
  );
  Future<void> saveGoal(Goal value) => mutate(
    (d) =>
        d.copyWith(goals: [...d.goals.where((a) => a.id != value.id), value]),
  );
  Future<void> saveRecurring(RecurringRule value) => mutate(
    (d) => d.copyWith(
      recurring: [...d.recurring.where((a) => a.id != value.id), value],
    ),
  );
  Future<void> _replace(Future<void> Function() action) {
    final result = _tail.then((_) async {
      await action();
      data = await repository.load();
      notifyListeners();
      unawaited(notifications.sync(data).catchError((Object _) {}));
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  Future<void> clearDemo() => _replace(repository.clearDemo);
  Future<void> importJson(String content) =>
      _replace(() => repository.importJson(content));
  Future<void> restore(String path) =>
      _replace(() => repository.restoreDatabase(path));
  Future<void> processRecurring() => mutate((d) {
    final now = DateTime.now();
    final entries = [...d.entries];
    final rules = <RecurringRule>[];
    for (final original in d.recurring) {
      var r = original;
      var generated = 0;
      while (r.enabled &&
          r.automatic &&
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
