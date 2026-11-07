import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/finance_engine.dart';
import '../domain/models.dart';

/// Notifications use inexact Android alarms: no invasive exact-alarm permission.
/// The OS may defer delivery under battery restrictions or Doze.
class NotificationService {
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now,
       _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           );

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  final FlutterSecureStorage _storage;
  bool _initialized = false;
  Future<void> _pending = Future<void>.value();

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'finora_finance',
      'Финансовые напоминания',
      channelDescription: 'Платежи, бюджеты, цели и финансовые отчёты',
      icon: 'ic_notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      visibility: NotificationVisibility.private,
      enableVibration: false,
    ),
  );

  Future<void> initialize() async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
    }
    final zone = await const MethodChannel(
      'finora/device',
    ).invokeMethod<String>('timeZone');
    if (zone == null) {
      throw StateError('Часовой пояс устройства недоступен');
    }
    try {
      tz.setLocalLocation(tz.getLocation(zone));
    } on tz.LocationNotFoundException {
      // Android also permits manually selected fixed-offset zones, such as
      // GMT+05:45, which do not have an IANA database entry or DST transitions.
      final fixed = RegExp(
        r'^(?:GMT|UTC)([+-])(\d{1,2}):(\d{2})$',
      ).firstMatch(zone);
      if (fixed == null) {
        rethrow;
      }
      final hours = int.parse(fixed.group(2)!);
      final minutes = int.parse(fixed.group(3)!);
      if (hours > 18 || minutes > 59 || (hours == 18 && minutes != 0)) {
        rethrow;
      }
      final offset =
          Duration(hours: hours, minutes: minutes).inMilliseconds *
          (fixed.group(1) == '-' ? -1 : 1);
      tz.setLocalLocation(
        tz.Location(zone, const [], const [], [
          tz.TimeZone(offset, isDst: false, abbreviation: zone),
        ]),
      );
    }
    if (_initialized) {
      return;
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> cancelAll() {
    final operation = _pending.then((_) async {
      await initialize();
      await _plugin.cancelAll();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  /// Serializes refreshes so an older state cannot overwrite newer schedules.
  Future<void> sync(FinanceData data) {
    final operation = _pending.then((_) => _sync(data));
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _sync(FinanceData data) async {
    await initialize();
    for (final request in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(request.id);
    }
    if (!data.preferences.notifications) {
      await _plugin.cancelAll();
      return;
    }
    final permission = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.areNotificationsEnabled();
    if (permission != true) {
      // Permission requests belong to an explicit user gesture. A denied
      // permission never consumes milestone deduplication or creates new alarms.
      await _plugin.cancelAll();
      return;
    }
    final now = tz.TZDateTime.from(_now(), tz.local);
    final allocated = <int>{};
    final identities = <String, int>{};
    int identifier(String key) => identities.putIfAbsent(key, () {
      var id = _id(key);
      while (!allocated.add(id)) {
        id = (id + 1) & 0x7fffffff;
      }
      return id;
    });
    // Android OEMs may enforce a 500-alarm limit. Leave headroom for the OS and
    // reserve three slots for weekly/monthly reports and inactivity reminders.
    final planned = _planRecurring(data.recurring, data.entries, now);
    final raw = await _storage.read(key: 'finora.notification.seen');
    final seen = raw == null
        ? <String>{}
        : (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();

    Future<void> showOnce(String key, String title, String body) async {
      if (!seen.add(key)) {
        return;
      }
      await _plugin.show(identifier(key), title, body, _details);
    }

    for (final reminder in planned) {
      await _schedule(
        identifier(reminder.key),
        reminder.rule.paymentType == 'subscription'
            ? 'Скоро оплата подписки'
            : 'Скоро обязательный платёж',
        '${reminder.rule.name} · ${_formatAmount(reminder.rule.amountMinor)} ${reminder.rule.currency}\n'
        'Оплата ${_formatDate(reminder.due)}',
        reminder.date,
      );
    }

    // 1.36: a late payment is recalled every day for three days.
    final today = DateTime(now.year, now.month, now.day);
    for (final rule in data.recurring.where(
      (r) => r.enabled && r.kind == EntryKind.expense,
    )) {
      final due = DateTime(
        rule.nextDate.year,
        rule.nextDate.month,
        rule.nextDate.day,
      );
      if (!due.isBefore(today)) continue;
      for (var k = 0; k < 3; k++) {
        final at = tz.TZDateTime(
          tz.local,
          today.year,
          today.month,
          today.day + k,
          rule.reminderHour,
          rule.reminderMinute,
        );
        if (!at.isAfter(now)) continue;
        await _schedule(
          identifier('overdue:${rule.id}:${_formatDate(due)}:$k'),
          'Просрочен платёж',
          '${rule.name} · ${_formatAmount(rule.amountMinor)} ${rule.currency}\n'
              'Нужно было оплатить ${_formatDate(due)}',
          at,
        );
      }
    }

    final startDay = data.preferences.monthStart.clamp(1, 28).toInt();
    final start = tz.TZDateTime(tz.local, now.year, now.month, startDay);
    final monthStart = now.isBefore(start)
        ? tz.TZDateTime(tz.local, now.year, now.month - 1, startDay)
        : start;
    final end = tz.TZDateTime(
      tz.local,
      monthStart.year,
      monthStart.month + 1,
      startDay,
    );
    for (final budget in data.budgets) {
      if (budget.limitMinor <= 0) {
        continue;
      }
      final spent = FinanceEngine.budgetSpent(
        budget,
        data.entries,
        monthStart,
        end,
      );
      if (spent * 10 >= budget.limitMinor * 9) {
        final crossed = spent >= budget.limitMinor;
        await showOnce(
          'budget:${budget.id}:${monthStart.toIso8601String()}:$crossed',
          crossed ? 'Бюджет исчерпан' : 'Бюджет почти исчерпан',
          '${budget.name}: ${crossed ? 'лимит достигнут' : 'использовано не менее 90% лимита'}.',
        );
      }
    }
    for (final goal in data.goals) {
      if (goal.targetMinor > 0 &&
          FinanceEngine.goalSaved(goal, data.entries) >= goal.targetMinor) {
        // One celebration per goal/target, including after transfer edits or
        // an undo/re-add. A genuinely changed target receives its own milestone.
        await showOnce(
          'goal:${goal.id}:${goal.targetMinor}',
          'Цель достигнута!',
          'Вы накопили на «${goal.name}».',
        );
      }
    }
    final dates = data.entries.map((entry) => entry.date).toList()..sort();
    if (dates.isNotEmpty) {
      final inactiveSince = dates.last.add(const Duration(days: 7));
      var reminder = tz.TZDateTime.from(inactiveSince, tz.local);
      if (!reminder.isAfter(now)) {
        final key = 'inactive:${dates.last.toIso8601String()}';
        await showOnce(
          key,
          'Как ваши финансы?',
          'Вы давно не добавляли операции. Обновите учёт в Finora.',
        );
      } else {
        await _schedule(
          identifier('inactive'),
          'Как ваши финансы?',
          'Самое время обновить учёт операций.',
          reminder,
        );
      }
    }
    var weekly = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18);
    while (weekly.weekday != DateTime.sunday || !weekly.isAfter(now)) {
      weekly = tz.TZDateTime(
        tz.local,
        weekly.year,
        weekly.month,
        weekly.day + 1,
        18,
      );
    }
    await _schedule(
      identifier('weekly'),
      'Ваш финансовый отчёт за неделю',
      'Откройте аналитику и посмотрите, как прошла неделя.',
      weekly,
      match: DateTimeComponents.dayOfWeekAndTime,
    );
    final monthly = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, 10);
    await _schedule(
      identifier('monthly'),
      'Итоги финансового месяца',
      'Доходы, расходы и прогресс целей — в аналитике Finora.',
      monthly,
      match: DateTimeComponents.dayOfMonthAndTime,
    );
    // Keep the most recent deduplication keys without unbounded storage growth.
    await _storage.write(
      key: 'finora.notification.seen',
      value: jsonEncode(
        seen.toList().reversed.take(256).toList().reversed.toList(),
      ),
    );
  }

  Future<void> _schedule(
    int id,
    String title,
    String body,
    tz.TZDateTime date, {
    DateTimeComponents? match,
  }) => _plugin.zonedSchedule(
    id,
    title,
    body,
    date,
    _details,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    matchDateTimeComponents: match,
  );

  // Stable across processes; Dart String.hashCode is not a persistence contract.
  static int _id(String text) {
    var hash = 2166136261;
    for (final code in text.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static const _perRuleHorizon = 12;
  static const _recurringCapacity = 397;

  /// A finite batch remains scheduled in Android after the app is closed. A
  /// later sync replenishes it; this service never creates ledger entries.
  static List<_PlannedReminder> _planRecurring(
    List<RecurringRule> rules,
    List<FinanceEntry> entries,
    tz.TZDateTime now,
  ) {
    final result = <_PlannedReminder>[];
    for (final rule in rules.where((r) => r.enabled && r.reminderEnabled)) {
      _validateReminder(rule);
      var start = rule;
      if (rule.automatic && rule.reminderDaysBefore == 0) {
        // Automatic bookkeeping may already have advanced nextDate at midnight.
        // Keep a still-future same-day reminder for an actual posted occurrence;
        // ordinary/manual transactions or an id-prefix lookalike cannot create it.
        final today = entries.where(
          (entry) =>
              entry.status == 'posted' &&
              entry.kind == rule.kind &&
              entry.currency == rule.currency &&
              entry.id ==
                  'recurring:${rule.id}:${entry.date.toIso8601String()}' &&
              entry.date.year == now.year &&
              entry.date.month == now.month &&
              entry.date.day == now.day,
        );
        if (today.isNotEmpty) {
          start = rule.copyWith(nextDate: today.first.date);
        }
      }
      var current = _nearCurrentOccurrence(start, now);
      var count = 0;
      // The calendar jump is at most one occurrence behind the relevant day.
      // Keep a separate bounded guard for corrupt/non-advancing recurrence data.
      for (var step = 0; step < _perRuleHorizon + 4; step++) {
        final due = current.nextDate;
        final reminder = tz.TZDateTime(
          tz.local,
          due.year,
          due.month,
          due.day - rule.reminderDaysBefore,
          rule.reminderHour,
          rule.reminderMinute,
        );
        if (reminder.isAfter(now)) {
          final signature = jsonEncode({
            'name': rule.name,
            'amountMinor': rule.amountMinor,
            'currency': rule.currency,
            'paymentType': rule.paymentType,
            'frequency': rule.frequency,
            'interval': rule.interval,
            'anchorDay': rule.anchorDay,
            'lead': rule.reminderDaysBefore,
            'hour': rule.reminderHour,
            'minute': rule.reminderMinute,
          });
          result.add(
            _PlannedReminder(
              rule: rule,
              due: due,
              date: reminder,
              key: 'recurring:${rule.id}:${_formatDate(due)}:$signature',
            ),
          );
          count++;
          if (count == _perRuleHorizon) {
            break;
          }
        }
        final next = FinanceEngine.nextOccurrence(current);
        if (!next.isAfter(current.nextDate)) {
          throw const FormatException('Регулярная операция не продвигает дату');
        }
        current = current.copyWith(nextDate: next);
      }
      if (count != _perRuleHorizon) {
        throw const FormatException(
          'Не удалось рассчитать напоминания операции',
        );
      }
    }
    // Prefer soonest reminders across all rules, independently of UI ordering.
    result.sort((left, right) {
      final byDate = left.date.compareTo(right.date);
      return byDate == 0 ? left.key.compareTo(right.key) : byDate;
    });
    return result.take(_recurringCapacity).toList();
  }

  static void _validateReminder(RecurringRule rule) {
    if (!const [0, 1, 3, 7].contains(rule.reminderDaysBefore) ||
        rule.reminderHour < 0 ||
        rule.reminderHour > 23 ||
        rule.reminderMinute < 0 ||
        rule.reminderMinute > 59 ||
        rule.interval < 1 ||
        rule.interval > 36600 ||
        rule.anchorDay < 1 ||
        rule.anchorDay > 31 ||
        rule.amountMinor <= 0 ||
        rule.amountMinor > FinanceEngine.maxMinor ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(rule.currency)) {
      throw const FormatException('Некорректные настройки напоминания');
    }
    if (!const [
      'daily',
      'custom',
      'weekly',
      'monthly',
      'yearly',
    ].contains(rule.frequency)) {
      throw const FormatException('Неизвестный период регулярной операции');
    }
  }

  /// Date fields are calendar payment dates, not a time-of-day cutoff. In
  /// particular, today's midnight payment may still remind today at 10:00.
  /// Jump near the first due date whose *reminder* can still be in the future.
  static RecurringRule _nearCurrentOccurrence(
    RecurringRule rule,
    tz.TZDateTime now,
  ) {
    final original = rule.nextDate;
    final target = DateTime.utc(
      now.year,
      now.month,
      now.day + rule.reminderDaysBefore,
    );
    final origin = DateTime.utc(original.year, original.month, original.day);
    if (target.isBefore(origin)) {
      return rule;
    }
    DateTime create(int year, int month, int day) => original.isUtc
        ? DateTime.utc(
            year,
            month,
            day,
            original.hour,
            original.minute,
            original.second,
            original.millisecond,
            original.microsecond,
          )
        : DateTime(
            year,
            month,
            day,
            original.hour,
            original.minute,
            original.second,
            original.millisecond,
            original.microsecond,
          );
    switch (rule.frequency) {
      case 'daily':
      case 'custom':
      case 'weekly':
        final stride = rule.interval * (rule.frequency == 'weekly' ? 7 : 1);
        final steps = target.difference(origin).inDays ~/ stride;
        return rule.copyWith(
          nextDate: create(
            original.year,
            original.month,
            original.day + steps * stride,
          ),
        );
      case 'monthly':
      case 'yearly':
        final stride = rule.interval * (rule.frequency == 'yearly' ? 12 : 1);
        final months =
            (target.year - original.year) * 12 + target.month - original.month;
        final steps = months ~/ stride;
        if (steps == 0) {
          return rule;
        }
        final month = create(original.year, original.month + steps * stride, 1);
        final lastDay = create(month.year, month.month + 1, 0).day;
        return rule.copyWith(
          nextDate: create(
            month.year,
            month.month,
            rule.anchorDay > lastDay ? lastDay : rule.anchorDay,
          ),
        );
      default:
        throw const FormatException('Неизвестный период регулярной операции');
    }
  }

  static String _formatAmount(int minor) {
    final whole = (minor ~/ 100).toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]}\u202f',
    );
    return '$whole,${(minor % 100).toString().padLeft(2, '0')}';
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.'
      '${date.month.toString().padLeft(2, '0')}.${date.year}';
}

class _PlannedReminder {
  const _PlannedReminder({
    required this.rule,
    required this.due,
    required this.date,
    required this.key,
  });
  final RecurringRule rule;
  final DateTime due;
  final tz.TZDateTime date;
  final String key;
}
