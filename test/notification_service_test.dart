import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:finora/domain/models.dart';
import 'package:finora/services/notification_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  const device = MethodChannel('finora/device');
  final calls = <MethodCall>[];
  final pending = <int, Map<String, Object?>>{};
  final year = DateTime.now().year + 1;
  late DateTime now;
  late String zone;
  late bool permission;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final args = call.arguments;
    switch (call.method) {
      case 'initialize':
        return true;
      case 'requestNotificationsPermission':
      case 'areNotificationsEnabled':
        return permission;
      case 'pendingNotificationRequests':
        return pending.values
            .map(
              (entry) => {
                'id': entry['id'],
                'title': entry['title'],
                'body': entry['body'],
                'payload': entry['payload'],
              },
            )
            .toList();
      case 'zonedSchedule':
        final data = (args as Map).cast<String, Object?>();
        pending[data['id'] as int] = data;
        return null;
      case 'cancel':
        pending.remove((args as Map)['id']);
        return null;
      case 'cancelAll':
        pending.clear();
        return null;
      default:
        return null;
    }
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    FlutterSecureStorage.setMockInitialValues({});
    calls.clear();
    pending.clear();
    now = DateTime.utc(year, 3, 15, 12);
    zone = 'UTC';
    permission = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(device, (
      call,
    ) async {
      if (call.method == 'timeZone') {
        return zone;
      }
      throw MissingPluginException();
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, handle);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(device, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  FinanceData enabledData(List<RecurringRule> rules) => FinanceData(
    preferences: const AppPreferences(notifications: true),
    recurring: rules,
  );
  RecurringRule rule({
    String id = 'rent',
    String name = 'Аренда',
    DateTime? due,
    int lead = 1,
    int hour = 10,
    int minute = 15,
    bool enabled = true,
    bool reminder = true,
    bool automatic = false,
    String frequency = 'monthly',
    int interval = 1,
    String currency = 'RUB',
    int amount = 129901,
  }) => RecurringRule(
    id: id,
    name: name,
    accountId: 'cash',
    currency: currency,
    amountMinor: amount,
    nextDate: due ?? DateTime.utc(year, 4, 5),
    frequency: frequency,
    interval: interval,
    enabled: enabled,
    reminderEnabled: reminder,
    reminderDaysBefore: lead,
    reminderHour: hour,
    reminderMinute: minute,
    automatic: automatic,
  );
  List<Map<String, Object?>> reminders() =>
      pending.values
          .where(
            (entry) => (entry['body'] as String? ?? '').contains('\nОплата '),
          )
          .toList()
        ..sort(
          (a, b) => (a['scheduledDateTimeISO8601'] as String).compareTo(
            b['scheduledDateTimeISO8601'] as String,
          ),
        );
  List<MethodCall> shown() => calls.where((c) => c.method == 'show').toList();
  DateTime instant(Map<String, Object?> entry) =>
      DateTime.parse(entry['scheduledDateTimeISO8601'] as String);

  test('new profiles default to no notification opt-in', () {
    expect(const AppPreferences().notifications, isFalse);
    expect(rule(reminder: false).reminderEnabled, isFalse);
  });

  for (final lead in [0, 1, 3, 7]) {
    test(
      '$lead-day lead uses chosen local time and exact payment contents',
      () async {
        final service = NotificationService(now: () => now);
        await service.sync(
          enabledData([rule(lead: lead, hour: 9, minute: 45)]),
        );
        final scheduled = reminders();
        expect(scheduled, hasLength(12));
        final expected = DateTime.utc(year, 4, 5 - lead, 9, 45);
        expect(instant(scheduled.first), expected);
        expect(
          scheduled.first['body'],
          'Аренда · 1\u202f299,01 RUB\nОплата 05.04.$year',
        );
        expect(scheduled.first['timeZoneName'], 'UTC');
        expect(
          (scheduled.first['platformSpecifics'] as Map)['scheduleMode'],
          AndroidScheduleMode.inexactAllowWhileIdle.name,
        );
        expect(
          calls.where((c) => c.method == 'requestNotificationsPermission'),
          isEmpty,
        );
      },
    );
  }

  test('currency and kopecks are formatted without double rounding', () async {
    final service = NotificationService(now: () => now);
    await service.sync(
      enabledData([
        rule(id: 'usd', name: 'Хранилище', currency: 'USD', amount: 199),
        rule(id: 'eur', name: 'Клуб', currency: 'EUR', amount: 9900),
      ]),
    );
    expect(
      reminders().any(
        (r) => r['body'] == 'Хранилище · 1,99 USD\nОплата 05.04.$year',
      ),
      isTrue,
    );
    expect(
      reminders().any(
        (r) => r['body'] == 'Клуб · 99,00 EUR\nОплата 05.04.$year',
      ),
      isTrue,
    );
  });

  test(
    'global off removes pending alarms and creates no notifications',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(enabledData([rule()]));
      expect(pending, isNotEmpty);
      calls.clear();
      await service.sync(FinanceData(recurring: [rule()]));
      expect(pending, isEmpty);
      expect(calls.where((c) => c.method == 'cancelAll'), hasLength(1));
      expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
      expect(shown(), isEmpty);
    },
  );

  test(
    'individual opt-out and disabled rules do not schedule payments',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([
          rule(id: 'no-reminder', reminder: false),
          rule(id: 'disabled', enabled: false),
          rule(id: 'automatic-only', reminder: false, automatic: true),
        ]),
      );
      expect(reminders(), isEmpty);
      expect(
        pending,
        hasLength(2),
      ); // Existing weekly/monthly reports are preserved.
    },
  );

  test('today midnight payment reminds today at future chosen time', () async {
    now = DateTime.utc(year, 3, 15, 8);
    final service = NotificationService(now: () => now);
    await service.sync(
      enabledData([
        rule(due: DateTime.utc(year, 3, 15), lead: 0, hour: 10, minute: 25),
      ]),
    );
    final scheduled = reminders();
    expect(instant(scheduled.first), DateTime.utc(year, 3, 15, 10, 25));
    expect(scheduled.first['body'], contains('Оплата 15.03.$year'));
  });

  test(
    'automatic midnight posting retains the future same-day reminder',
    () async {
      now = DateTime.utc(year, 3, 15, 8);
      final service = NotificationService(now: () => now);
      final today = DateTime.utc(year, 3, 15);
      final automatic = rule(
        due: DateTime.utc(year, 4, 15),
        lead: 0,
        hour: 10,
        minute: 0,
        automatic: true,
      );
      final posting = FinanceEntry(
        id: 'recurring:rent:${today.toIso8601String()}',
        kind: EntryKind.expense,
        amountMinor: automatic.amountMinor,
        currency: 'RUB',
        accountId: 'cash',
        date: today,
      );
      await service.sync(enabledData([automatic]).copyWith(entries: [posting]));
      expect(reminders(), hasLength(12));
      expect(instant(reminders().first), DateTime.utc(year, 3, 15, 10));
      expect(
        reminders().where(
          (r) => (r['body'] as String).contains('Оплата 15.03.$year'),
        ),
        hasLength(1),
      );
      expect(instant(reminders()[1]), DateTime.utc(year, 4, 15, 10));
      expect(automatic.nextDate, DateTime.utc(year, 4, 15));
      expect(posting.amountMinor, automatic.amountMinor);
    },
  );

  test(
    'ordinary or pending entries do not resurrect a previous auto occurrence',
    () async {
      now = DateTime.utc(year, 3, 15, 8);
      final service = NotificationService(now: () => now);
      final today = DateTime.utc(year, 3, 15);
      final automatic = rule(
        due: DateTime.utc(year, 4, 15),
        lead: 0,
        automatic: true,
      );
      final posting = FinanceEntry(
        id: 'recurring:rent:${today.toIso8601String()}',
        kind: EntryKind.expense,
        amountMinor: automatic.amountMinor,
        currency: 'RUB',
        accountId: 'cash',
        date: today,
        status: 'pending',
      );
      await service.sync(
        enabledData([automatic]).copyWith(
          entries: [
            posting,
            posting.copyWith(id: 'manual', status: 'posted'),
          ],
        ),
      );
      expect(instant(reminders().first), DateTime.utc(year, 4, 15, 10, 15));
    },
  );

  test(
    'passed reminder time skips to next occurrence without immediate catchup',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([rule(due: DateTime.utc(year, 3, 20), lead: 7)]),
      );
      expect(instant(reminders().first), DateTime.utc(year, 4, 13, 10, 15));
      expect(reminders().first['body'], contains('Оплата 20.04.$year'));
      expect(shown(), isEmpty);
    },
  );

  test(
    'exact current reminder time also advances, avoiding repeated delivery',
    () async {
      now = DateTime.utc(year, 3, 15, 10, 15);
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([rule(due: DateTime.utc(year, 3, 15), lead: 0)]),
      );
      expect(instant(reminders().first), DateTime.utc(year, 4, 15, 10, 15));
    },
  );

  test('month-end anchor survives February and leap year into March', () async {
    var leap = year;
    while (DateTime.utc(leap, 3, 0).day != 29) {
      leap++;
    }
    now = DateTime.utc(leap, 1, 1);
    final service = NotificationService(now: () => now);
    await service.sync(enabledData([rule(due: DateTime.utc(leap, 1, 31))]));
    final scheduled = reminders();
    expect(scheduled.take(3).map((e) => e['scheduledDateTime']), [
      '$leap-01-30T10:15:00',
      '$leap-02-28T10:15:00',
      '$leap-03-30T10:15:00',
    ]);
    expect(scheduled[1]['body'], contains('Оплата 29.02.$leap'));
    expect(scheduled[2]['body'], contains('Оплата 31.03.$leap'));
  });

  test(
    'years-old rule jumps near today and retains original monthly anchor',
    () async {
      final service = NotificationService(now: () => now);
      final old = rule(due: DateTime.utc(2000, 1, 31));
      await service.sync(enabledData([old]));
      expect(instant(reminders().first), DateTime.utc(year, 3, 30, 10, 15));
      expect(old.nextDate, DateTime.utc(2000, 1, 31));
    },
  );

  test(
    'years-old daily rule schedules a future batch rather than one late alert',
    () async {
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([
          rule(due: DateTime.utc(2000, 1, 1), frequency: 'daily', lead: 1),
        ]),
      );
      final scheduled = reminders();
      expect(scheduled, hasLength(12));
      expect(instant(scheduled.first), DateTime.utc(year, 3, 16, 10, 15));
      expect(instant(scheduled.last), DateTime.utc(year, 3, 27, 10, 15));
      expect(shown(), isEmpty);
    },
  );

  for (final frequency in ['weekly', 'custom', 'yearly']) {
    test(
      '$frequency scheduling respects interval across the future batch',
      () async {
        now = DateTime.utc(year, 1, 1);
        final service = NotificationService(now: () => now);
        await service.sync(
          enabledData([
            rule(
              due: DateTime.utc(year, 2, 5),
              frequency: frequency,
              interval: 2,
              lead: 0,
            ),
          ]),
        );
        final scheduled = reminders();
        final expectedSecond = switch (frequency) {
          'weekly' => DateTime.utc(year, 2, 19, 10, 15),
          'custom' => DateTime.utc(year, 2, 7, 10, 15),
          _ => DateTime.utc(year + 2, 2, 5, 10, 15),
        };
        expect(scheduled, hasLength(12));
        expect(instant(scheduled[1]), expectedSecond);
      },
    );
  }

  test('weekly local reminder time remains stable across DST', () async {
    zone = 'Europe/Berlin';
    final marchEnd = DateTime.utc(year, 3, 31);
    final sunday = 31 - marchEnd.weekday % 7;
    now = DateTime.utc(year, 3, sunday - 2, 9);
    final service = NotificationService(now: () => now);
    await service.sync(
      enabledData([
        rule(
          due: DateTime.utc(year, 3, sunday - 1),
          frequency: 'weekly',
          lead: 0,
        ),
      ]),
    );
    final scheduled = reminders();
    expect(scheduled.take(2).map((e) => e['timeZoneName']), [
      'Europe/Berlin',
      'Europe/Berlin',
    ]);
    expect(
      (scheduled[0]['scheduledDateTime'] as String).endsWith('T10:15:00'),
      isTrue,
    );
    expect(
      (scheduled[1]['scheduledDateTime'] as String).endsWith('T10:15:00'),
      isTrue,
    );
    expect(
      instant(scheduled[1]).difference(instant(scheduled[0])),
      const Duration(hours: 167),
    );
  });

  test(
    'spring DST gap normalizes chosen time once to a valid local time',
    () async {
      zone = 'Europe/Berlin';
      final marchEnd = DateTime.utc(year, 3, 31);
      final sunday = 31 - marchEnd.weekday % 7;
      now = DateTime.utc(year, 3, sunday - 1, 12);
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([
          rule(
            due: DateTime.utc(year, 3, sunday),
            frequency: 'weekly',
            lead: 0,
            hour: 2,
            minute: 30,
          ),
        ]),
      );
      final scheduled = reminders();
      expect(
        (scheduled[0]['scheduledDateTime'] as String).endsWith('T03:30:00'),
        isTrue,
      );
      expect(
        (scheduled[1]['scheduledDateTime'] as String).endsWith('T02:30:00'),
        isTrue,
      );
      expect(scheduled.map((r) => r['id']).toSet(), hasLength(12));
    },
  );

  test(
    'fall DST overlap creates one reminder for the ambiguous wall time',
    () async {
      zone = 'Europe/Berlin';
      final octoberEnd = DateTime.utc(year, 10, 31);
      final sunday = 31 - octoberEnd.weekday % 7;
      now = DateTime.utc(year, 10, sunday - 1, 12);
      final service = NotificationService(now: () => now);
      await service.sync(
        enabledData([
          rule(
            due: DateTime.utc(year, 10, sunday),
            frequency: 'weekly',
            lead: 0,
            hour: 2,
            minute: 30,
          ),
        ]),
      );
      final first = reminders().first;
      expect(
        (first['scheduledDateTime'] as String).endsWith('T02:30:00'),
        isTrue,
      );
      expect(
        reminders().where(
          (r) => r['scheduledDateTime'] == first['scheduledDateTime'],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'timezone changes reschedule unchanged rules at the chosen local time',
    () async {
      final service = NotificationService(now: () => now);
      final data = enabledData([rule()]);
      await service.sync(data);
      final before = instant(reminders().first);
      zone = 'Asia/Tokyo';
      await service.sync(data);
      expect(reminders().first['timeZoneName'], 'Asia/Tokyo');
      expect(
        instant(reminders().first).toUtc(),
        before.subtract(const Duration(hours: 9)),
      );
      expect(
        (reminders().first['scheduledDateTime'] as String).endsWith(
          'T10:15:00',
        ),
        isTrue,
      );
    },
  );

  test(
    'fixed-offset Android timezone does not depend on host test timezone',
    () async {
      zone = 'GMT+05:45';
      final service = NotificationService(now: () => now);
      await service.sync(enabledData([rule()]));
      final expected = DateTime.utc(year, 4, 4, 4, 30);
      expect(instant(reminders().first).toUtc(), expected);
      expect(reminders().first['timeZoneName'], 'GMT+05:45');
    },
  );

  test(
    'rule edit cancels old pending IDs and refreshes date and contents',
    () async {
      final service = NotificationService(now: () => now);
      final initial = rule();
      await service.sync(enabledData([initial]));
      final before = reminders().map((e) => e['id']).toSet();
      calls.clear();
      await service.sync(
        enabledData([
          initial.copyWith(
            name: 'Аренда новая',
            amountMinor: 500099,
            reminderDaysBefore: 3,
            reminderHour: 18,
            reminderMinute: 20,
          ),
        ]),
      );
      expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id']),
        containsAll(before),
      );
      final scheduled = reminders();
      expect(
        scheduled.map((e) => e['id']).toSet().intersection(before),
        isEmpty,
      );
      expect(instant(scheduled.first), DateTime.utc(year, 4, 2, 18, 20));
      expect(
        scheduled.first['body'],
        'Аренда новая · 5\u202f000,99 RUB\nОплата 05.04.$year',
      );
    },
  );

  for (final action in ['delete', 'disable', 'opt-out']) {
    test('$action cancels all old individual reminder alarms', () async {
      final service = NotificationService(now: () => now);
      final initial = rule();
      await service.sync(enabledData([initial]));
      final ids = reminders().map((e) => e['id']).toSet();
      calls.clear();
      await service.sync(
        enabledData(switch (action) {
          'delete' => [],
          'disable' => [initial.copyWith(enabled: false)],
          _ => [initial.copyWith(reminderEnabled: false)],
        }),
      );
      expect(reminders(), isEmpty);
      expect(pending.keys.toSet().intersection(ids), isEmpty);
      expect(
        calls
            .where((c) => c.method == 'cancel')
            .map((c) => (c.arguments as Map)['id']),
        containsAll(ids),
      );
    });
  }

  test(
    'unchanged sync replenishes deterministic IDs without duplicates',
    () async {
      final service = NotificationService(now: () => now);
      final data = enabledData([rule(id: 'a'), rule(id: 'b')]);
      await service.sync(data);
      final ids = pending.keys.toSet();
      expect(reminders(), hasLength(24));
      await service.sync(data);
      expect(pending.keys.toSet(), ids);
      expect(reminders(), hasLength(24));
    },
  );

  test('known 31-bit hash collisions allocate distinct stable IDs', () async {
    final service = NotificationService(now: () => now);
    // Independently found collision of the stable FNV prefix
    // "recurring:<id>:", with identical suffixes for each calendar occurrence.
    final first = rule(id: 'kbwqgviaqf');
    final second = rule(id: 'txjghxhdbp');
    await service.sync(enabledData([first, second]));
    expect(reminders(), hasLength(24));
    final ids = pending.keys.toSet();
    expect(
      calls
          .where((c) => c.method == 'zonedSchedule')
          .map((c) => (c.arguments as Map)['id'])
          .toSet(),
      hasLength(26),
    );
    await service.sync(enabledData([second, first]));
    expect(pending.keys.toSet(), ids);
  });

  test(
    'batch remains below Android alarm limits and keeps nearest reminders',
    () async {
      final service = NotificationService(now: () => now);
      final data =
          enabledData(
            List.generate(35, (i) => rule(id: 'r$i', name: 'Платёж $i')),
          ).copyWith(
            entries: [
              FinanceEntry(
                id: 'recent',
                kind: EntryKind.expense,
                amountMinor: 100,
                currency: 'RUB',
                accountId: 'cash',
                date: now,
              ),
            ],
          );
      await service.sync(data);
      expect(reminders(), hasLength(397));
      expect(pending, hasLength(400));
      expect(
        reminders().where(
          (e) => instant(e).month == 4 && instant(e).year == year,
        ),
        hasLength(35),
      );
      expect(pending.keys.toSet(), hasLength(400));
    },
  );

  test(
    'denied permission schedules nothing and consumes no goal milestone',
    () async {
      permission = false;
      final service = NotificationService(now: () => now);
      expect(await service.requestPermission(), isFalse);
      final data = enabledData([rule()]).copyWith(
        goals: const [
          Goal(id: 'done', name: 'Цель', targetMinor: 100, savedMinor: 100),
        ],
      );
      await service.sync(data);
      expect(pending, isEmpty);
      expect(shown(), isEmpty);
      expect(
        calls.where((c) => c.method == 'requestNotificationsPermission'),
        hasLength(1),
      );
      permission = true;
      await service.sync(data);
      expect(reminders(), hasLength(12));
      expect(
        shown().where(
          (c) => (c.arguments as Map)['title'] == 'Цель достигнута!',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'cancelAll waits behind in-flight sync and leaves no schedules',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'zonedSchedule' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return handle(call);
      });
      final service = NotificationService(now: () => now);
      final sync = service.sync(enabledData([rule()]));
      await entered.future;
      final cancel = service.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c.method == 'cancelAll'), isEmpty);
      release.complete();
      await Future.wait([sync, cancel]);
      expect(calls.last.method, 'cancelAll');
      expect(pending, isEmpty);
    },
  );

  test(
    'later global disable cannot be overwritten by older in-flight sync',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'zonedSchedule' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return handle(call);
      });
      final service = NotificationService(now: () => now);
      final first = service.sync(enabledData([rule()]));
      await entered.future;
      final disabled = service.sync(FinanceData(recurring: [rule()]));
      release.complete();
      await Future.wait([first, disabled]);
      expect(pending, isEmpty);
    },
  );

  test(
    'budget threshold and reached goal notify once across refreshes',
    () async {
      final service = NotificationService(now: () => now);
      final data = enabledData([]).copyWith(
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
      expect(shown(), hasLength(2));
      expect(
        shown().map((c) => (c.arguments as Map)['title']),
        containsAll(['Бюджет почти исчерпан', 'Цель достигнута!']),
      );
    },
  );

  test(
    'goal milestone uses posted dream transfers and deduplicates undo',
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
      final waiting = enabledData([]).copyWith(
        goals: const [goal],
        entries: [
          transfer('pending', 8000, status: 'pending'),
          transfer('cancelled', 8000, status: 'cancelled'),
          transfer('other', 8000, goalId: null),
        ],
      );
      await service.sync(waiting);
      expect(shown(), isEmpty);
      final reached = waiting.copyWith(entries: [transfer('fund', 8000)]);
      await service.sync(reached);
      await service.sync(reached);
      await service.sync(reached.copyWith(entries: [transfer('fund', 9000)]));
      await service.sync(reached.copyWith(entries: []));
      await service.sync(reached);
      expect(shown(), hasLength(1));
      await service.sync(
        reached.copyWith(
          goals: [goal.copyWith(targetMinor: 15000)],
          entries: [transfer('fund', 13000)],
        ),
      );
      expect(shown(), hasLength(2));
      expect(
        (shown().first.arguments as Map)['id'],
        isNot((shown().last.arguments as Map)['id']),
      );
    },
  );

  test(
    'scheduling changes neither ledger entries nor recurring rules',
    () async {
      final service = NotificationService(now: () => now);
      final data = enabledData([rule(automatic: true)]);
      final before = data.toJson();
      await service.sync(data);
      expect(data.toJson(), before);
      expect(data.entries, isEmpty);
      expect(data.recurring.single.nextDate, DateTime.utc(year, 4, 5));
    },
  );

  test(
    'invalid reminder configuration fails explicitly instead of scheduling wrong time',
    () async {
      final service = NotificationService(now: () => now);
      await expectLater(
        service.sync(enabledData([rule().copyWith(reminderHour: 25)])),
        throwsFormatException,
      );
      expect(pending, isEmpty);
      // A failed refresh must not poison the serial queue.
      await service.sync(enabledData([rule()]));
      expect(reminders(), hasLength(12));
    },
  );
}
