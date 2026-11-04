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
      if (!RegExp(r'^(?:GMT|UTC)[+-]\d{1,2}:\d{2}$').hasMatch(zone)) {
        rethrow;
      }
      tz.setLocalLocation(
        tz.Location(zone, const [], const [], [
          tz.TimeZone(
            DateTime.now().timeZoneOffset.inMilliseconds,
            isDst: false,
            abbreviation: zone,
          ),
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
    final now = tz.TZDateTime.from(_now(), tz.local);
    final raw = await _storage.read(key: 'finora.notification.seen');
    final seen = raw == null
        ? <String>{}
        : (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();

    Future<void> showOnce(String key, String title, String body) async {
      if (!seen.add(key)) {
        return;
      }
      await _plugin.show(_id(key), title, body, _details);
    }

    for (final rule in data.recurring.where((rule) => rule.enabled)) {
      final occurrence = _firstFutureOccurrence(rule, now);
      final due = tz.TZDateTime.from(occurrence, tz.local);
      var reminder = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day - 1,
        10,
      );
      if (!reminder.isAfter(now) && due.isAfter(now)) {
        reminder = now.add(const Duration(seconds: 3));
      }
      if (reminder.isAfter(now)) {
        await _schedule(
          'recurring:${rule.id}',
          'Скоро регулярная операция',
          '${rule.name}. Проверьте календарь платежей в Finora.',
          reminder,
        );
      }
    }

    final startDay = data.preferences.monthStart.clamp(1, 28).toInt();
    final start = DateTime(now.year, now.month, startDay);
    final monthStart = now.isBefore(start)
        ? DateTime(now.year, now.month - 1, startDay)
        : start;
    final end = DateTime(monthStart.year, monthStart.month + 1, startDay);
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
          'inactive',
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
      'weekly',
      'Ваш финансовый отчёт за неделю',
      'Откройте аналитику и посмотрите, как прошла неделя.',
      weekly,
      match: DateTimeComponents.dayOfWeekAndTime,
    );
    final monthly = tz.TZDateTime(tz.local, now.year, now.month + 1, 1, 10);
    await _schedule(
      'monthly',
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
    String key,
    String title,
    String body,
    tz.TZDateTime date, {
    DateTimeComponents? match,
  }) => _plugin.zonedSchedule(
    _id(key),
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

  /// Reminder-only rules are not mutated into financial operations. Jump close
  /// to the current period before using the domain calendar recurrence, so a
  /// years-old daily rule cannot monopolize startup with an unbounded loop.
  static DateTime _firstFutureOccurrence(RecurringRule rule, DateTime now) {
    if (rule.nextDate.isAfter(now)) {
      return rule.nextDate;
    }
    if (rule.interval < 1) {
      throw const FormatException(
        'Интервал регулярной операции должен быть положительным',
      );
    }
    final original = rule.nextDate;
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
    var current = rule;
    switch (rule.frequency) {
      case 'daily':
      case 'custom':
      case 'weekly':
        final stride = rule.interval * (rule.frequency == 'weekly' ? 7 : 1);
        final fromDay = DateTime.utc(
          original.year,
          original.month,
          original.day,
        );
        final toDay = DateTime.utc(now.year, now.month, now.day);
        final steps = toDay.difference(fromDay).inDays ~/ stride;
        if (steps > 1) {
          current = rule.copyWith(
            nextDate: create(
              original.year,
              original.month,
              original.day + (steps - 1) * stride,
            ),
          );
        }
      case 'monthly':
      case 'yearly':
        final stride = rule.interval * (rule.frequency == 'yearly' ? 12 : 1);
        final months =
            (now.year - original.year) * 12 + now.month - original.month;
        final steps = months ~/ stride;
        if (steps > 1) {
          // Keep the preceding occurrence in the original anchor month; the
          // domain function decides month-end/leap-day clamping.
          current = rule.copyWith(
            nextDate: create(
              original.year,
              original.month + (steps - 1) * stride,
              1,
            ),
          );
          final target = current.nextDate;
          final last = create(target.year, target.month + 1, 0).day;
          final day = original.day > last ? last : original.day;
          current = current.copyWith(
            nextDate: create(target.year, target.month, day),
          );
        }
      default:
        throw const FormatException('Неизвестный период регулярной операции');
    }
    // The arithmetic jump leaves at most a handful of calendar steps even
    // across DST transitions; fail explicitly if a corrupted rule cannot advance.
    for (var step = 0; step < 8; step++) {
      if (current.nextDate.isAfter(now)) {
        return current.nextDate;
      }
      final next = FinanceEngine.nextOccurrence(current);
      if (!next.isAfter(current.nextDate)) {
        throw const FormatException('Регулярная операция не продвигает дату');
      }
      current = current.copyWith(nextDate: next);
    }
    throw const FormatException(
      'Не удалось рассчитать следующую дату операции',
    );
  }
}
