import 'package:intl/intl.dart';

import '../../../domain/models.dart';
import '../../../domain/payment_plan.dart';
import '../../../presentation/widgets/common.dart' show money;

enum ReportPeriod { week, month }

/// One category in a report.
class ReportCategory {
  const ReportCategory(
    this.id,
    this.name,
    this.amountMinor,
    this.previousMinor,
  );
  final String id, name;
  final int amountMinor, previousMinor;
  int get deltaMinor => amountMinor - previousMinor;
}

/// A finished period in numbers (Phase 7, AI reports and digest). Every
/// number is counted from the operations; the text only reports them.
class FinanceReport {
  const FinanceReport({
    required this.period,
    required this.start,
    required this.end,
    required this.currency,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.previousIncomeMinor,
    required this.previousExpenseMinor,
    required this.count,
    required this.categories,
    required this.biggest,
    required this.debtPaidMinor,
    required this.debtLeftMinor,
    required this.savedToGoalsMinor,
  });
  final ReportPeriod period;
  final DateTime start, end;
  final String currency;
  final int incomeMinor, expenseMinor;
  final int previousIncomeMinor, previousExpenseMinor;
  final int count;

  /// Up to five categories, biggest first.
  final List<ReportCategory> categories;

  /// The biggest single expense.
  final FinanceEntry? biggest;
  final int debtPaidMinor, debtLeftMinor, savedToGoalsMinor;

  int get netMinor => incomeMinor - expenseMinor;

  /// Share of income kept (savings rate), percent; null without income.
  int? get savedPercent =>
      incomeMinor <= 0 ? null : (netMinor * 100 / incomeMinor).round();
}

abstract final class ReportBuilder {
  /// The report for the [period] that contains [now] — or, with
  /// [previous], the one before it (a finished week or month).
  static FinanceReport build(
    FinanceData data, {
    ReportPeriod period = ReportPeriod.month,
    bool previous = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final prefs = data.preferences;
    final currency = prefs.baseCurrency;
    var (start, end) = _range(period, clock, prefs.monthStart, prefs.weekStart);
    if (previous) {
      (start, end) = _shift(period, start, -1);
    }
    final (pStart, pEnd) = _shift(period, start, -1);
    bool inside(FinanceEntry e, DateTime a, DateTime b) =>
        e.status == 'posted' &&
        e.currency == currency &&
        !e.date.isBefore(a) &&
        e.date.isBefore(b);

    var income = 0, expense = 0, pIncome = 0, pExpense = 0, count = 0;
    var toGoals = 0;
    final byCat = <String, int>{}, byCatPrev = <String, int>{};
    FinanceEntry? biggest;
    for (final e in data.entries) {
      if (inside(e, start, end)) {
        count++;
        switch (e.kind) {
          case EntryKind.income:
            income += e.amountMinor;
          case EntryKind.expense:
            expense += e.amountMinor;
            final k = e.categoryId ?? '';
            byCat[k] = (byCat[k] ?? 0) + e.amountMinor;
            if (biggest == null || e.amountMinor > biggest.amountMinor) {
              biggest = e;
            }
          case EntryKind.transfer:
            if (e.toGoalId != null) toGoals += e.amountMinor;
        }
      } else if (inside(e, pStart, pEnd)) {
        if (e.kind == EntryKind.income) pIncome += e.amountMinor;
        if (e.kind == EntryKind.expense) {
          pExpense += e.amountMinor;
          final k = e.categoryId ?? '';
          byCatPrev[k] = (byCatPrev[k] ?? 0) + e.amountMinor;
        }
      }
    }
    final names = {for (final c in data.categories) c.id: c.name};
    final categories = [
      for (final e in byCat.entries)
        ReportCategory(
          e.key,
          names[e.key] ?? 'Без категории',
          e.value,
          byCatPrev[e.key] ?? 0,
        ),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    var debtPaid = 0, debtLeft = 0;
    for (final r in data.recurring) {
      if (r.kind != EntryKind.expense || r.currency != currency) continue;
      if (r.totalMinor == null && !r.isLoan) continue;
      for (final e in data.entries) {
        if (inside(e, start, end) && PaymentPlan.belongs(e, r)) {
          debtPaid += e.amountMinor;
        }
      }
      debtLeft += PaymentPlan.of(r, data.entries, now: clock).leftMinor;
    }
    return FinanceReport(
      period: period,
      start: start,
      end: end,
      currency: currency,
      incomeMinor: income,
      expenseMinor: expense,
      previousIncomeMinor: pIncome,
      previousExpenseMinor: pExpense,
      count: count,
      categories: categories.take(5).toList(),
      biggest: biggest,
      debtPaidMinor: debtPaid,
      debtLeftMinor: debtLeft,
      savedToGoalsMinor: toGoals,
    );
  }

  /// The report as text: a short digest for the chat and for sharing.
  static String text(FinanceReport r, {String locale = 'ru'}) {
    String m(int v) => money(v, r.currency);
    final f = DateFormat('d MMMM', locale);
    final last = r.end.subtract(const Duration(days: 1));
    final title = r.period == ReportPeriod.week
        ? 'Отчёт за неделю ${f.format(r.start)} — ${f.format(last)}'
        : 'Отчёт за ${DateFormat('LLLL yyyy', locale).format(r.start)}';
    if (r.count == 0) {
      return '$title\nОпераций за этот период нет.';
    }
    String change(int now, int before) {
      if (before <= 0) return '';
      final p = ((now - before) * 100 / before).round();
      if (p == 0) return ' (как в прошлый раз)';
      return ' (${p > 0 ? '+' : ''}$p % к прошлому)';
    }

    final lines = <String>[
      title,
      'Доходы: ${m(r.incomeMinor)}${change(r.incomeMinor, r.previousIncomeMinor)}',
      'Расходы: ${m(r.expenseMinor)}${change(r.expenseMinor, r.previousExpenseMinor)}',
      'Итог: ${r.netMinor >= 0 ? '+' : '−'}${m(r.netMinor.abs())}'
          '${r.savedPercent != null && r.savedPercent! > 0 ? ' — сохранено ${r.savedPercent} % дохода' : ''}',
    ];
    if (r.categories.isNotEmpty) {
      lines.add(
        'Больше всего: ${r.categories.take(3).map((c) => '${c.name} ${m(c.amountMinor)}').join(', ')}.',
      );
      final grew = [...r.categories]
        ..sort((a, b) => b.deltaMinor.compareTo(a.deltaMinor));
      final top = grew.first;
      if (top.previousMinor > 0 && top.deltaMinor > 0) {
        lines.add(
          'Сильнее всего выросли: ${top.name} (+${m(top.deltaMinor)}).',
        );
      }
    }
    final b = r.biggest;
    if (b != null) {
      lines.add(
        'Самая крупная трата: ${b.payee.isEmpty ? 'без названия' : b.payee} — '
        '${m(b.amountMinor)}, ${f.format(b.date)}.',
      );
    }
    if (r.savedToGoalsMinor > 0) {
      lines.add('Отложено в мечты: ${m(r.savedToGoalsMinor)}.');
    }
    if (r.debtPaidMinor > 0 || r.debtLeftMinor > 0) {
      lines.add(
        'Долги: выплачено ${m(r.debtPaidMinor)}, осталось ${m(r.debtLeftMinor)}.',
      );
    }
    return lines.join('\n');
  }

  static (DateTime, DateTime) _range(
    ReportPeriod p,
    DateTime now,
    int monthStart,
    int weekStart,
  ) {
    final day = DateTime(now.year, now.month, now.day);
    if (p == ReportPeriod.week) {
      final start = day.subtract(Duration(days: (day.weekday - weekStart) % 7));
      return (start, start.add(const Duration(days: 7)));
    }
    var start = DateTime(now.year, now.month, monthStart);
    if (start.isAfter(day)) {
      start = DateTime(now.year, now.month - 1, monthStart);
    }
    return (start, DateTime(start.year, start.month + 1, start.day));
  }

  static (DateTime, DateTime) _shift(ReportPeriod p, DateTime start, int n) {
    if (p == ReportPeriod.week) {
      final s = DateTime(start.year, start.month, start.day + 7 * n);
      return (s, DateTime(s.year, s.month, s.day + 7));
    }
    final s = DateTime(start.year, start.month + n, start.day);
    return (s, DateTime(s.year, s.month + 1, s.day));
  }

  static final _ask = RegExp(r'отч[её]т|дайджест', caseSensitive: false);

  /// «отчёт за неделю», «дайджест за прошлый месяц» → the period asked;
  /// null when the text asks for something else.
  static (ReportPeriod, bool)? parseRequest(String text) {
    final t = text.toLowerCase().replaceAll('ё', 'е');
    if (!_ask.hasMatch(t)) return null;
    final week = RegExp(r'недел').hasMatch(t);
    final previous = RegExp(r'прошл').hasMatch(t);
    return (week ? ReportPeriod.week : ReportPeriod.month, previous);
  }
}
