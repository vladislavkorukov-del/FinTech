import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/domain/models.dart';
import 'package:finora/services/notification_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const device = MethodChannel('finora/device');
  final calls = <MethodCall>[];
  // Scheduling happens in the future relative to the package's own system-clock
  // validation, while application business time remains deterministic in tests.
  final now = DateTime.utc(DateTime.now().year + 1, 3, 15, 12);

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(device, (
      call,
    ) async {
      if (call.method == 'timeZone') {
        return 'UTC';
      }
      throw MissingPluginException();
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'requestNotificationsPermission':
          return true;
        case 'pendingNotificationRequests':
          return <Map<String, Object>>[];
        default:
          return null;
      }
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(device, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'stale monthly reminder advances to the next original anchor day',
    () async {
      final service = NotificationService(now: () => now);
      final rule = RecurringRule(
        id: 'rent',
        name: 'Аренда',
        accountId: 'cash',
        amountMinor: 10000,
        nextDate: DateTime.utc(now.year - 8, 1, 31, 12),
        frequency: 'monthly',
        automatic: false,
      );
      await service.sync(FinanceData(recurring: [rule]));
      final reminder = calls.singleWhere(
        (call) =>
            call.method == 'zonedSchedule' &&
            (call.arguments as Map)['title'] == 'Скоро регулярная операция',
      );
      final args = reminder.arguments as Map;
      // Next payment is March 31; reminder is the preceding day at 10:00 UTC.
      expect(args['scheduledDateTime'], '${now.year}-03-30T10:00:00');
      expect(args['timeZoneName'], 'UTC');
      expect(rule.nextDate.year, now.year - 8);
      expect(calls.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test(
    'years-old daily reminders jump directly to a future occurrence',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(
        FinanceData(
          recurring: [
            RecurringRule(
              id: 'daily',
              name: 'Проверить баланс',
              accountId: 'cash',
              amountMinor: 100,
              frequency: 'daily',
              nextDate: DateTime.utc(2000, 1, 1, 9),
            ),
          ],
        ),
      );
      final reminders = calls.where(
        (call) =>
            call.method == 'zonedSchedule' &&
            (call.arguments as Map)['title'] == 'Скоро регулярная операция',
      );
      expect(reminders, hasLength(1));
      final scheduled = DateTime.parse(
        (reminders.single.arguments as Map)['scheduledDateTimeISO8601']
            as String,
      );
      expect(scheduled.isAfter(now), isTrue);
      expect(scheduled.isBefore(now.add(const Duration(days: 2))), isTrue);
    },
  );

  test(
    'cancelAll waits for an in-flight sync before cancelling schedules',
    () async {
      final enteredSchedule = Completer<void>();
      final releaseSchedule = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'initialize') {
          return true;
        }
        if (call.method == 'pendingNotificationRequests') {
          return <Map<String, Object>>[];
        }
        if (call.method == 'zonedSchedule' && !enteredSchedule.isCompleted) {
          enteredSchedule.complete();
          await releaseSchedule.future;
        }
        return null;
      });
      final service = NotificationService(now: () => now);
      final sync = service.sync(FinanceData.empty());
      await enteredSchedule.future;
      final cancel = service.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'cancelAll'), isEmpty);
      releaseSchedule.complete();
      await Future.wait([sync, cancel]);
      expect(calls.last.method, 'cancelAll');
    },
  );

  test(
    'disabled notifications cancel existing schedules and create none',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(
        const FinanceData(preferences: AppPreferences(notifications: false)),
      );
      expect(calls.where((call) => call.method == 'cancelAll'), hasLength(1));
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
      expect(calls.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test(
    'budget threshold and reached goal notify once across refreshes',
    () async {
      final service = NotificationService(now: () => now);
      final data = FinanceData(
        budgets: const [Budget(id: 'month', name: 'Месяц', limitMinor: 10000)],
        goals: const [
          Goal(
            id: 'holiday',
            name: 'Отпуск',
            targetMinor: 10000,
            savedMinor: 10000,
          ),
        ],
        entries: [
          FinanceEntry(
            id: 'expense',
            kind: EntryKind.expense,
            amountMinor: 9000,
            currency: 'RUB',
            accountId: 'cash',
            date: now,
          ),
        ],
      );
      await service.sync(data);
      await service.sync(data);
      final shown = calls.where((call) => call.method == 'show').toList();
      expect(shown, hasLength(2));
      expect(
        shown.map((call) => (call.arguments as Map)['title']),
        containsAll(['Бюджет почти исчерпан', 'Цель достигнута!']),
      );
    },
  );
  test(
    'dream milestone uses posted goal transfers and deduplicates edits and undo',
    () async {
      final service = NotificationService(now: () => now);
      const goal = Goal(
        id: 'trip',
        name: 'Море',
        targetMinor: 10000,
        savedMinor: 2000,
      );
      FinanceEntry transfer(
        String id,
        int amount, {
        String status = 'posted',
        String? goalId = 'trip',
      }) => FinanceEntry(
        id: id,
        kind: EntryKind.transfer,
        amountMinor: amount,
        currency: 'RUB',
        accountId: 'card',
        toAccountId: goalId == null ? 'reserve' : null,
        toGoalId: goalId,
        date: now,
        status: status,
      );
      final waiting = FinanceData(
        goals: const [goal],
        entries: [
          transfer('pending', 8000, status: 'pending'),
          transfer('cancelled', 8000, status: 'cancelled'),
          transfer('other', 8000, goalId: null),
        ],
      );
      await service.sync(waiting);
      expect(
        calls.where(
          (c) =>
              c.method == 'show' &&
              (c.arguments as Map)['title'] == 'Цель достигнута!',
        ),
        isEmpty,
      );

      final reached = waiting.copyWith(entries: [transfer('fund', 8000)]);
      await service.sync(reached);
      // A refresh, an amount edit, and an undo/re-add keep the same milestone.
      await service.sync(reached);
      await service.sync(reached.copyWith(entries: [transfer('fund', 9000)]));
      await service.sync(reached.copyWith(entries: []));
      await service.sync(reached);
      final celebrations = calls
          .where(
            (c) =>
                c.method == 'show' &&
                (c.arguments as Map)['title'] == 'Цель достигнута!',
          )
          .toList();
      expect(celebrations, hasLength(1));

      await service.sync(
        reached.copyWith(
          goals: [goal.copyWith(targetMinor: 15000)],
          entries: [transfer('fund', 13000)],
        ),
      );
      final nextMilestone = calls
          .where(
            (c) =>
                c.method == 'show' &&
                (c.arguments as Map)['title'] == 'Цель достигнута!',
          )
          .toList();
      expect(nextMilestone, hasLength(2));
      expect(
        (nextMilestone.last.arguments as Map)['id'],
        isNot((celebrations.single.arguments as Map)['id']),
      );
    },
  );
}
