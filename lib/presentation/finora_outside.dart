import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/finance_engine.dart';
import '../domain/models.dart';
import '../services/finora_system.dart';
import 'controller.dart';
import 'widgets/common.dart';
import 'widgets/finora_orb.dart';
import 'i18n.dart';

/// Keeps Finora's widgets and shade controls up to date (1.27): numbers,
/// her mood and a picture of her in that mood.
abstract final class FinoraOutside {
  static Timer? _timer;
  static String? _last;

  /// Called whenever the data changes; the work runs a moment later, once.
  static void schedule(FinanceController c) {
    _timer?.cancel();
    // Only where the bridge exists (not in tests): no stray timers.
    unawaited(
      FinoraSystem.available.then((yes) {
        if (!yes) return;
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 1500), () => push(c));
      }),
    );
  }

  static void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// The mood of the main widget and its line.
  static (FinoraMood, String) mood(FinanceController c, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final due = c.duePayments(now: clock);
    final today = DateTime(clock.year, clock.month, clock.day);
    final overdue = due.where((r) => r.nextDate.isBefore(today)).toList();
    if (overdue.isNotEmpty) {
      return (FinoraMood.angry, 'Просрочен платёж: ${overdue.first.name}');
    }
    if (due.isNotEmpty) {
      final r = due.first;
      return (
        FinoraMood.attention,
        'Сегодня: ${r.name} ${money(r.amountMinor, r.currency)}',
      );
    }
    for (final b in c.data.budgets) {
      final spent = FinanceEngine.budgetSpent(
        b,
        c.data.entries,
        c.periodStart,
        c.periodEnd,
      );
      if (spent > b.limitMinor) {
        return (FinoraMood.angry, 'Бюджет «${b.name}» превышен');
      }
    }
    final totals = FinanceEngine.totals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
    );
    if (totals.income > 0 && totals.net >= 0) {
      return (FinoraMood.happy, 'Месяц в плюсе');
    }
    return (FinoraMood.idle, 'Нажмите и скажите');
  }

  /// 1.41: which of Finora's pictures the widget shows for the data, and a
  /// line with a number for some of them (the widget itself adds the clock:
  /// night, nothing recorded yet, payments).
  static (String, String) tileWithLine(FinanceController c, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);
    final d = c.data;
    String m(int v) => money(v, c.currency);
    bool sameDay(DateTime x) =>
        x.year == today.year && x.month == today.month && x.day == today.day;
    final start = c.periodStart, end = c.periodEnd;
    final day = clock.difference(start).inDays;
    final spentNow = FinanceEngine.totals(
      d.entries,
      start,
      clock,
      c.currency,
    ).expense;
    final prevStart = DateTime(start.year, start.month - 1, start.day);
    final spentBefore = FinanceEngine.totals(
      d.entries,
      prevStart,
      prevStart.add(clock.difference(start)),
      c.currency,
    ).expense;
    final budgets = [
      for (final b in d.budgets.where((b) => b.limitMinor > 0))
        (b, FinanceEngine.budgetSpent(b, d.entries, start, end)),
    ];
    final over = budgets.where((x) => x.$2 > x.$1.limitMinor);
    if (over.isNotEmpty) {
      return (
        'budget_topup',
        'Бюджет «${over.first.$1.name}» превышен на '
            '${m(over.first.$2 - over.first.$1.limitMinor)}',
      );
    }
    final near = budgets.where((x) => x.$2 * 10 >= x.$1.limitMinor * 9);
    if (near.isNotEmpty) {
      return (
        'limit',
        'В «${near.first.$1.name}» осталось '
            '${m(near.first.$1.limitMinor - near.first.$2)}',
      );
    }
    final incomeToday = d.entries
        .where((e) => e.kind == EntryKind.income && sameDay(e.date))
        .fold(0, (sum, e) => sum + e.amountMinor);
    if (incomeToday > 0) return ('income', 'Пришло ${m(incomeToday)}!');
    for (final g in d.goals) {
      final saved = FinanceEngine.goalSaved(g, d.entries);
      if (g.targetMinor > 0 &&
          saved * 10 >= g.targetMinor * 8 &&
          saved < g.targetMinor) {
        return (
          'dream_savings',
          'До «${g.name}» осталось ${m(g.targetMinor - saved)}',
        );
      }
    }
    if (spentBefore > 0 && day >= 5) {
      if (spentNow * 10 > spentBefore * 11) {
        return (
          'growing',
          'Расходы на ${((spentNow / spentBefore - 1) * 100).round()}% '
              'больше прошлого месяца',
        );
      }
      if (spentNow * 10 < spentBefore * 9) {
        return (
          'saving',
          'Экономите ${m(spentBefore - spentNow)} к прошлому месяцу',
        );
      }
    }
    if (day < 3 && d.entries.isNotEmpty) {
      return (
        clock.month.isEven ? 'budget_month_pink' : 'budget_month',
        'Новый месяц — время задать бюджет',
      );
    }
    final totals = FinanceEngine.totals(d.entries, start, end, c.currency);
    if (day >= 5 && totals.income == 0 && d.entries.isNotEmpty) {
      return ('income_tracking', 'Доходов за месяц пока нет — запишите');
    }
    final spentToday = d.entries
        .where((e) => e.kind == EntryKind.expense && sameDay(e.date))
        .fold(0, (sum, e) => sum + e.amountMinor);
    if (spentToday > 0) {
      return streak(d.entries, now: clock) >= 3
          ? ('forward', 'Сегодня записано ${m(spentToday)}')
          : ('expenses_today', 'Сегодня потрачено ${m(spentToday)}');
    }
    if (totals.income > 0 && totals.net >= 0) {
      return ('plus', 'Месяц в плюсе: ${m(totals.net)}');
    }
    if (budgets.isNotEmpty) {
      final left = budgets.fold(0, (sum, x) => sum + x.$1.limitMinor - x.$2);
      final days = end.difference(today).inDays.clamp(1, 31);
      return ('limit_today', 'Можно потратить сегодня: ${m(left ~/ days)}');
    }
    for (final g in d.goals) {
      final pace = FinanceEngine.savingsPace(
        g,
        FinanceEngine.goalSaved(g, d.entries),
        now: clock,
      );
      if (pace != null && pace.days > 0) {
        return ('goal_month', 'На «${g.name}» — ${m(pace.month)} в месяц');
      }
    }
    if (d.entries.any(
      (e) =>
          e.toGoalId != null &&
          today
                  .difference(DateTime(e.date.year, e.date.month, e.date.day))
                  .inDays <
              7,
    )) {
      return ('piggy', 'Копилка растёт — так держать!');
    }
    if (d.budgets.isEmpty && d.entries.isNotEmpty) {
      return ('plan_budget', 'Задайте бюджет — Финора будет следить');
    }
    return ('check', '');
  }

  static String tile(FinanceController c, {DateTime? now}) =>
      tileWithLine(c, now: now).$1;

  /// 1.39: days in a row with at least one record, ending on the last
  /// day that has one (the widget decides whether it is still alive).
  static int streak(List<FinanceEntry> entries, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final days = {
      for (final e in entries)
        if (!e.date.isAfter(clock))
          DateTime(e.date.year, e.date.month, e.date.day),
    };
    if (days.isEmpty) return 0;
    var day = days.reduce((a, b) => a.isAfter(b) ? a : b);
    var n = 0;
    while (days.contains(day) && n < 3650) {
      n++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return n;
  }

  /// Up to four next payments, «12.11 · Netflix · 799 ₽».
  static List<String> payments(FinanceController c) {
    final rules =
        c.data.recurring
            .where((r) => r.enabled && r.kind == EntryKind.expense)
            .toList()
          ..sort((a, b) => a.nextDate.compareTo(b.nextDate));
    return [
      for (final r in rules.take(4))
        '${DateFormat('dd.MM').format(r.nextDate)} · ${r.name} · '
            '${money(r.amountMinor, r.currency)}',
    ];
  }

  static Future<void> push(FinanceController c) async {
    if (!await FinoraSystem.available) return;
    final prefs = c.data.preferences;
    final (mood, say) = FinoraOutside.mood(c);
    final totals = FinanceEngine.totals(
      c.data.entries,
      c.periodStart,
      c.periodEnd,
      c.currency,
    );
    final balance = money(c.balance, c.currency);
    final list = payments(c);
    final paymentsMood =
        mood == FinoraMood.angry || mood == FinoraMood.attention
        ? mood
        : (list.isEmpty ? FinoraMood.calm : FinoraMood.idle);
    // 1.36: the main widgets choose her mood by the clock (see
    // FinoraWidgets.mood): the day of the last record and a payment alert.
    final today = DateTime.now();
    final past = c.data.entries
        .where((e) => !e.date.isAfter(today))
        .map((e) => e.date)
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final lastEntry = past == null ? '' : DateFormat('yyyy-MM-dd').format(past);
    final days = streak(c.data.entries, now: today);
    final alert = mood == FinoraMood.angry || mood == FinoraMood.attention
        ? say
        : '';
    final (picture, pictureLine) = tileWithLine(c, now: today);
    final due = c.duePayments(now: today);
    final day = DateTime(today.year, today.month, today.day);
    final soon = c.data.recurring.any(
      (r) =>
          r.enabled &&
          r.kind == EntryKind.expense &&
          r.nextDate.difference(day).inDays <= 3,
    );
    final payState = due.any((r) => r.nextDate.isBefore(day))
        ? 'overdue'
        : due.isNotEmpty
        ? 'today'
        : soon
        ? 'soon'
        : '';
    final key = [
      picture,
      pictureLine,
      payState,
      lastEntry,
      days,
      FinoraOrbPainter.theme.toARGB32(),
      balance,
      totals.income,
      totals.expense,
      mood,
      say,
      list.join('|'),
      prefs.shadeControls,
    ].join('#');
    if (key == _last) return;
    _last = key;
    final dir = await getApplicationSupportDirectory();
    final image = await _picture(mood, '${dir.path}/finora_widget.png');
    final paymentsImage = await _picture(
      paymentsMood,
      '${dir.path}/finora_widget_payments.png',
    );
    final month = DateFormat('LLLL', AppLanguage.intl).format(DateTime.now());
    await FinoraSystem.updateWidgets({
      'balance': balance,
      'month': '${month[0].toUpperCase()}${month.substring(1)}',
      'income': '+${money(totals.income, c.currency)}',
      'expense': '−${money(totals.expense, c.currency)}',
      'say': say,
      'image': image,
      'lastEntry': lastEntry,
      'streak': '$days',
      'tile': picture,
      'tileSay': pictureLine,
      'payState': payState,
      'alert': alert,
      'alertMood': alert.isEmpty ? '' : mood.name,
      'paymentsImage': paymentsImage,
      'paymentsTitle': list.isEmpty ? 'Платежей нет' : 'Ближайшие платежи',
      'payments': list.isEmpty
          ? 'Финора спокойна: ничего не ждёт оплаты'
          : list.join('\n'),
    });
    await FinoraSystem.shade(
      on: prefs.shadeControls,
      title: 'Финора · $balance',
      text: say,
    );
  }

  /// Finora in [mood] as a PNG (with room for her sign).
  static Future<String> _picture(FinoraMood mood, String path) async {
    const size = 256.0, pad = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(pad, pad);
    FinoraOrbPainter(t: .1, mood: mood).paint(canvas, const Size.square(size));
    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (size + pad * 2).round(),
      (size + pad * 2).round(),
    );
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    img.dispose();
    if (bytes == null) return '';
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return path;
  }
}
