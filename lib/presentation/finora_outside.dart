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
    final key = [
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
    final moods = <String, String>{};
    for (final (name, m) in const [
      ('happy', FinoraMood.happy),
      ('thinking', FinoraMood.thinking),
      ('attention', FinoraMood.attention),
      ('angry', FinoraMood.angry),
      ('sleep', FinoraMood.sleep),
    ]) {
      moods['image_$name'] = await _picture(
        m,
        '${dir.path}/finora_widget_$name.png',
      );
    }
    final month = DateFormat('LLLL', AppLanguage.intl).format(DateTime.now());
    await FinoraSystem.updateWidgets({
      'balance': balance,
      'month': '${month[0].toUpperCase()}${month.substring(1)}',
      'income': '+${money(totals.income, c.currency)}',
      'expense': '−${money(totals.expense, c.currency)}',
      'say': say,
      'image': image,
      ...moods,
      'lastEntry': lastEntry,
      'streak': '$days',
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
