import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'finance_engine.dart';
import 'models.dart';
import 'payment_plan.dart';

DateTime _day(DateTime date) => DateTime(date.year, date.month, date.day);
String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
int _add(int a, int b) {
  final result = BigInt.from(a) + BigInt.from(b);
  if (result.abs() > BigInt.from(FinanceEngine.maxMinor)) {
    throw const FormatException('Суммы плана превышают допустимый диапазон');
  }
  return result.toInt();
}

/// A row's fingerprint. When the app learned of a row (`recordedAt`, the
/// time machine's stamp) is bookkeeping, not a change to the plan.
String _hash(Object value) => sha256
    .convert(
      utf8.encode(
        jsonEncode(
          value is Map<String, Object?>
              ? (Map<String, Object?>.of(value)..remove('recordedAt'))
              : value,
        ),
      ),
    )
    .toString();

class WeeklyDebtPlanRequest {
  WeeklyDebtPlanRequest({
    required this.sourceAccountId,
    required this.currency,
    required this.budgetMinor,
    required this.reserveMinor,
    required DateTime from,
    required DateTime until,
    this.planningWeekday = DateTime.monday,
  }) : from = _day(from),
       until = _day(until) {
    if (sourceAccountId.isEmpty ||
        currency.isEmpty ||
        budgetMinor < 0 ||
        reserveMinor < 0 ||
        budgetMinor > FinanceEngine.maxMinor ||
        reserveMinor > FinanceEngine.maxMinor ||
        this.until.isBefore(this.from) ||
        this.until.difference(this.from).inDays > 90 ||
        planningWeekday < 1 ||
        planningWeekday > 7) {
      throw const FormatException(
        'Укажите счёт, валюту, неотрицательный бюджет и резерв, период до 90 дней',
      );
    }
  }
  final String sourceAccountId, currency;

  /// The total ceiling for the selected horizon, not a monthly/weekly rate.
  final int budgetMinor, reserveMinor, planningWeekday;
  final DateTime from, until;
  Map<String, Object?> toJson() => {
    'sourceAccountId': sourceAccountId,
    'currency': currency,
    'budgetMinor': budgetMinor,
    'reserveMinor': reserveMinor,
    'from': _dateKey(from),
    'until': _dateKey(until),
    'planningWeekday': planningWeekday,
  };
}

enum DebtDirection { payable, receivable }

class DebtPosition {
  const DebtPosition({
    required this.ruleId,
    required this.name,
    required this.currency,
    required this.direction,
    required this.balanceMinor,
    required this.remainingAfterPlanMinor,
    required this.approximateInterest,
  });
  final String ruleId, name, currency;
  final DebtDirection direction;

  /// Actual debt from the existing PaymentPlan, unaffected by pending rows.
  final int balanceMinor;

  /// Projection only. It is never persisted as a new actual debt balance.
  final int remainingAfterPlanMinor;
  final bool approximateInterest;
}

class WeeklyDebtPlanRow {
  const WeeklyDebtPlanRow({
    required this.id,
    required this.ruleId,
    required this.name,
    required this.contractualDueDate,
    required this.proposedDate,
    required this.weekStart,
    required this.amountMinor,
    required this.expectedBalanceMinor,
    required this.categoryId,
    this.serviceId,
    this.serviceIconPath,
  });
  final String id, ruleId, name;
  final String? categoryId, serviceId, serviceIconPath;
  final DateTime contractualDueDate, proposedDate, weekStart;
  final int amountMinor, expectedBalanceMinor;
  bool get overdue => contractualDueDate.isBefore(proposedDate);
}

class DebtShortage {
  const DebtShortage({
    required this.date,
    required this.amountMinor,
    required this.reason,
    required this.kind,
  });
  final DateTime date;
  final int amountMinor;
  final String reason;

  /// cash and budget are separate constraints and must not be added together.
  final String kind;
}

class WeeklyDebtWeek {
  WeeklyDebtWeek(this.start, List<WeeklyDebtPlanRow> rows)
    : rows = List.unmodifiable(rows),
      totalMinor = rows.fold(0, (sum, row) => _add(sum, row.amountMinor));
  final DateTime start;
  final List<WeeklyDebtPlanRow> rows;
  final int totalMinor;
}

class WeeklyDebtPlan {
  WeeklyDebtPlan._({
    required this.request,
    required this.inputFingerprint,
    required this.rows,
    required this.debts,
    required this.receivables,
    required this.debtTotalsByCurrency,
    required this.receivableTotalsByCurrency,
    required this.shortages,
    required this.needsConditions,
    required this.warnings,
    required this.assumptions,
    required this.initialBalanceMinor,
    required this.endingBalanceMinor,
    required this.usedBudgetMinor,
    required Map<String, String?> previousRows,
  }) : _previousRows = previousRows;
  final WeeklyDebtPlanRequest request;
  final String inputFingerprint;
  final List<WeeklyDebtPlanRow> rows;
  final List<DebtPosition> debts, receivables;
  final Map<String, int> debtTotalsByCurrency, receivableTotalsByCurrency;
  final List<DebtShortage> shortages;
  final List<String> needsConditions, warnings, assumptions;
  final int initialBalanceMinor, endingBalanceMinor, usedBudgetMinor;
  final Map<String, String?> _previousRows;
  int get unusedBudgetMinor =>
      (request.budgetMinor - usedBudgetMinor).clamp(0, request.budgetMinor);
  bool get canSave =>
      rows.isNotEmpty && shortages.isEmpty && needsConditions.isEmpty;
  String get id => _hash({
    'request': request.toJson(),
    'input': inputFingerprint,
  }).substring(0, 24);
  List<WeeklyDebtWeek> get weeks {
    final grouped = <DateTime, List<WeeklyDebtPlanRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.weekStart, () => []).add(row);
    }
    return grouped.entries
        .map((entry) => WeeklyDebtWeek(entry.key, entry.value))
        .toList();
  }

  /// Save only after the UI's explicit confirmation. Revalidation occurs in the
  /// controller's atomic mutate, never before awaiting a confirmation dialog.
  /// Stable occurrence IDs make retries and recalculation idempotent.
  FinanceData applyTo(FinanceData current) {
    if (!canSave) {
      throw const FormatException(
        'План невыполним или требует уточнений. Он не сохранён',
      );
    }
    final ids = rows.map((row) => row.id).toSet();
    if (_fingerprint(current, request, _previousRows.keys.toSet()) !=
        inputFingerprint) {
      throw const FormatException(
        'Финансовые данные изменились. Пересчитайте план',
      );
    }
    for (final previous in _previousRows.entries.where(
      (e) => !ids.contains(e.key),
    )) {
      final existing = current.entries
          .where((e) => e.id == previous.key)
          .firstOrNull;
      if (existing != null &&
          (existing.status != 'pending' ||
              _hash(existing.toJson()) != previous.value)) {
        throw const FormatException(
          'Прежние плановые платежи изменились. Пересчитайте план',
        );
      }
    }
    final entries = <FinanceEntry>[];
    final memberId =
        current.members.where((m) => m.id == 'me').firstOrNull?.id ??
        current.members.firstOrNull?.id ??
        'me';
    for (final row in rows) {
      final entry = FinanceEntry(
        id: row.id,
        kind: EntryKind.expense,
        amountMinor: row.amountMinor,
        currency: request.currency,
        accountId: request.sourceAccountId,
        categoryId: row.categoryId,
        date: row.proposedDate,
        payee: row.name,
        status: 'pending',
        memberId: memberId,
        note:
            'План погашения. Договорная дата: ${_dateKey(row.contractualDueDate)}',
        recurringRuleId: row.ruleId,
        plannedDueDate: row.contractualDueDate,
        planningBatchId: id,
        serviceId: row.serviceId,
        serviceIconPath: row.serviceIconPath,
      );
      final existing = current.entries.where((e) => e.id == row.id).firstOrNull;
      if (existing != null && existing.status != 'pending') {
        throw const FormatException(
          'Один из платежей уже проведён или отменён. Пересчитайте план',
        );
      }
      final existingHash = existing == null ? null : _hash(existing.toJson());
      if (existingHash != _previousRows[row.id] &&
          existingHash != _hash(entry.toJson())) {
        throw const FormatException(
          'Плановые платежи были изменены. Пересчитайте план',
        );
      }
      FinanceEngine.validateEntry(entry, current);
      entries.add(entry);
    }
    return current.copyWith(
      entries: [
        for (final entry in current.entries)
          if (!_previousRows.containsKey(entry.id)) entry,
        ...entries,
      ],
    );
  }
}

String _fingerprint(
  FinanceData data,
  WeeklyDebtPlanRequest request,
  Set<String> proposedIds,
) => _hash({
  'request': request.toJson(),
  'accounts': data.accounts.map((a) => a.toJson()).toList(),
  'categories': data.categories.map((c) => c.toJson()).toList(),
  'entries': data.entries
      .where((e) => !proposedIds.contains(e.id))
      .map((e) => e.toJson())
      .toList(),
  'recurring': data.recurring.map((r) => r.toJson()).toList(),
  'budgets': data.budgets.map((b) => b.toJson()).toList(),
  'members': data.members.map((m) => m.toJson()).toList(),
});

class _Event {
  _Event(this.date, this.amount, this.name, {this.rule, this.payment});
  final DateTime date;

  /// Signed cashflow: income positive, ordinary obligations/debt negative.
  final int amount;
  final String name;
  final RecurringRule? rule;
  final PlannedPayment? payment;
}

abstract final class WeeklyDebtPlanner {
  static WeeklyDebtPlan compute(
    FinanceData data,
    WeeklyDebtPlanRequest request,
  ) {
    final source = data.accounts
        .where((a) => a.id == request.sourceAccountId && !a.archived)
        .firstOrNull;
    if (source == null || source.currency != request.currency) {
      throw const FormatException('Выберите доступный счёт в валюте плана');
    }
    final needs = <String>[];
    final warnings = <String>[];
    final assumptions = <String>[
      'Бюджет погашения — общий предел на выбранный период, а не сумма на каждую неделю.',
      'Платежи сгруппированы по реальным календарным неделям. Договорные даты не изменяются.',
      'Используется только выбранный счёт; переводы с других счетов не предполагаются.',
      'Поступления в день платежа учитываются до списаний. Время внутри дня не известно.',
      'Плановые операции не меняют фактический баланс и долг до проведения.',
      'Неизвестные будущие комиссии не рассчитываются; план не обещает оптимального погашения.',
    ];
    final positions = <DebtPosition>[];
    final debtTotals = <String, int>{}, receivableTotals = <String, int>{};
    final events = <_Event>[];
    final principalToPay = <String, int>{};
    final finiteRules = data.recurring
        .where((r) => r.totalMinor != null || r.principalMinor != null)
        .toList();
    final finiteIds = finiteRules.map((r) => r.id).toSet();
    bool inHorizon(DateTime date) => !_day(date).isAfter(request.until);
    bool sameDay(DateTime a, DateTime b) => _day(a) == _day(b);

    for (final rule in finiteRules) {
      final direction = rule.kind == EntryKind.income
          ? DebtDirection.receivable
          : DebtDirection.payable;
      if (rule.kind == EntryKind.transfer) continue;
      if (rule.principalMinor != null &&
          !rule.isLoan &&
          rule.totalMinor == null) {
        if (direction == DebtDirection.payable &&
            rule.currency == request.currency &&
            rule.enabled) {
          needs.add(
            '${rule.name}: не хватает условий процентов или общей суммы долга.',
          );
        }
        final balance = rule.principalMinor!;
        final totals = direction == DebtDirection.payable
            ? debtTotals
            : receivableTotals;
        totals[rule.currency] = _add(totals[rule.currency] ?? 0, balance);
        positions.add(
          DebtPosition(
            ruleId: rule.id,
            name: rule.name,
            currency: rule.currency,
            direction: direction,
            balanceMinor: balance,
            remainingAfterPlanMinor: balance,
            approximateInterest: true,
          ),
        );
        continue;
      }
      final plan = PaymentPlan.of(rule, data.entries, now: request.from);
      final balance = plan.leftMinor;
      final totals = direction == DebtDirection.payable
          ? debtTotals
          : receivableTotals;
      totals[rule.currency] = _add(totals[rule.currency] ?? 0, balance);
      positions.add(
        DebtPosition(
          ruleId: rule.id,
          name: rule.name,
          currency: rule.currency,
          direction: direction,
          balanceMinor: balance,
          remainingAfterPlanMinor: balance,
          approximateInterest: rule.isLoan,
        ),
      );
      if (rule.isLoan) {
        warnings.add(
          '${rule.name}: проценты приблизительные по существующему расчёту; банковские комиссии и фактические условия могут отличаться.',
        );
      }
      if (!rule.enabled ||
          direction == DebtDirection.receivable ||
          balance <= 0) {
        continue;
      }
      if (rule.currency != request.currency) {
        warnings.add(
          '${rule.name}: ${rule.currency} показан отдельно и не включён в ${request.currency}.',
        );
        continue;
      }
      if (rule.amountMinor <= 0 || plan.loan?.repayable == false) {
        needs.add('${rule.name}: платёж не погашает долг. Уточните условия.');
        continue;
      }
      if (!data.categories.any(
        (c) =>
            c.id == rule.categoryId &&
            !c.archived &&
            c.kind == EntryKind.expense,
      )) {
        needs.add('${rule.name}: выберите действующую категорию расходов.');
      }
      for (final payment in plan.upcoming.where((p) => inHorizon(p.date))) {
        final required = PaymentPlan.requiredForOccurrence(
          rule,
          data.entries,
          payment.date,
          now: request.from,
        );
        final amount = payment.amountMinor < required
            ? payment.amountMinor
            : required;
        if (amount <= 0) continue;
        final proposed = _day(payment.date).isBefore(request.from)
            ? request.from
            : _day(payment.date);
        events.add(
          _Event(proposed, -amount, rule.name, rule: rule, payment: payment),
        );
        final principal = (amount - (payment.interestMinor ?? 0)).clamp(
          0,
          amount,
        );
        principalToPay[rule.id] = _add(principalToPay[rule.id] ?? 0, principal);
        if (proposed != _day(payment.date)) {
          warnings.add(
            '${rule.name}: просрочено с ${_dateKey(payment.date)}. Договорный срок не перенесён.',
          );
        }
      }
    }
    if (positions.any((p) => p.direction == DebtDirection.receivable)) {
      assumptions.add(
        'Суммы, которые должны вам, показаны отдельно и не считаются доступными деньгами до фактического получения.',
      );
    }
    for (final account in data.accounts.where(
      (a) => !a.archived && a.type == 'credit',
    )) {
      if (FinanceEngine.balance(account, data.entries) < 0) {
        final message =
            '${account.name}: отрицательный кредитный счёт без связанного договора. Нужны остаток, минимальный платёж, срок и ставка; он не суммируется с кредитами автоматически.';
        if (account.currency == request.currency) {
          needs.add(message);
        } else {
          warnings.add(message);
        }
      }
    }
    // Ordinary scheduled cashflow is taken from the same rules/calendar, not a
    // parallel ledger. Finite receivables aren't assumed to arrive as income.
    final pending = data.entries
        .where(
          (e) =>
              e.status == 'pending' &&
              !e.id.startsWith('debt-plan:') &&
              !(e.recurringRuleId != null &&
                  finiteIds.contains(e.recurringRuleId)) &&
              !_day(e.date).isBefore(request.from) &&
              inHorizon(e.date),
        )
        .toList();
    for (final entry in pending) {
      if (entry.accountId == source.id) {
        if (entry.currency != request.currency) continue;
        events.add(
          _Event(
            _day(entry.date),
            entry.kind == EntryKind.income
                ? entry.amountMinor
                : -entry.amountMinor,
            entry.payee,
          ),
        );
      } else if (entry.kind == EntryKind.transfer &&
          entry.toAccountId == source.id) {
        if (entry.destinationMinor == null &&
            entry.currency != request.currency) {
          needs.add(
            'Перевод ${entry.id}: не указана сумма в валюте источника плана.',
          );
          continue;
        }
        events.add(
          _Event(
            _day(entry.date),
            entry.destinationMinor ?? entry.amountMinor,
            entry.payee,
          ),
        );
      }
    }
    for (final rule in data.recurring.where(
      (r) =>
          r.enabled &&
          !finiteIds.contains(r.id) &&
          r.accountId == source.id &&
          r.currency == request.currency,
    )) {
      if (rule.kind == EntryKind.transfer || rule.amountMinor <= 0) continue;
      var cursor = rule;
      var count = 0;
      while (inHorizon(cursor.nextDate) && count++ < 600) {
        final due = cursor.nextDate;
        final pendingOccurrence = pending.any(
          (e) =>
              e.recurringRuleId == rule.id &&
              e.plannedDueDate != null &&
              sameDay(e.plannedDueDate!, due),
        );
        final remaining = PaymentPlan.requiredForOccurrence(
          rule,
          data.entries,
          due,
          now: request.from,
        );
        if (remaining > 0 && !pendingOccurrence) {
          if (rule.kind == EntryKind.income &&
              _day(due).isBefore(request.from)) {
            warnings.add(
              '${rule.name}: просроченное поступление не принято за доступные деньги.',
            );
          } else {
            final date = _day(due).isBefore(request.from)
                ? request.from
                : _day(due);
            events.add(
              _Event(
                date,
                rule.kind == EntryKind.income ? remaining : -remaining,
                rule.name,
              ),
            );
          }
        }
        final next = FinanceEngine.nextOccurrence(cursor);
        if (!next.isAfter(cursor.nextDate)) {
          needs.add('${rule.name}: некорректная повторяемость.');
          break;
        }
        cursor = cursor.copyWith(nextDate: next);
      }
      if (count >= 600 && inHorizon(cursor.nextDate)) {
        needs.add(
          '${rule.name}: слишком много просроченных повторений. Уточните график.',
        );
      }
    }
    events.sort((a, b) {
      var result = a.date.compareTo(b.date);
      if (result != 0) return result;
      if ((a.amount > 0) != (b.amount > 0)) return a.amount > 0 ? -1 : 1;
      if ((a.rule != null) != (b.rule != null)) return a.rule == null ? -1 : 1;
      if (a.rule != null && b.rule != null) {
        result = a.payment!.date.compareTo(b.payment!.date);
        if (result != 0) return result;
        result = (b.rule!.interestRate ?? 0).compareTo(
          a.rule!.interestRate ?? 0,
        );
        if (result != 0) return result;
      }
      return a.name.compareTo(b.name);
    });
    final initial = FinanceEngine.balance(source, data.entries);
    var balance = initial, used = 0;
    final rows = <WeeklyDebtPlanRow>[];
    final deficits = <String, DebtShortage>{};
    void deficit(DateTime date, int amount, String kind, String reason) {
      if (amount <= 0) return;
      final key = '$kind:${_dateKey(date)}';
      final old = deficits[key];
      if (old == null || amount > old.amountMinor) {
        deficits[key] = DebtShortage(
          date: date,
          amountMinor: amount,
          reason: reason,
          kind: kind,
        );
      }
    }

    deficit(
      request.from,
      request.reserveMinor - balance,
      'cash',
      'На выбранном счёте недостаточно денег для сохранения резерва.',
    );
    for (final event in events) {
      balance = _add(balance, event.amount);
      deficit(
        event.date,
        request.reserveMinor - balance,
        'cash',
        'Не хватает средств на счёте с учётом обязательств и резерва.',
      );
      if (event.rule == null) continue;
      final amount = -event.amount;
      used = _add(used, amount);
      deficit(
        event.date,
        used - request.budgetMinor,
        'budget',
        'Заданный бюджет погашения не покрывает обязательные платежи.',
      );
      final rule = event.rule!, due = _day(event.payment!.date);
      final week = event.date.subtract(
        Duration(days: (event.date.weekday - request.planningWeekday + 7) % 7),
      );
      rows.add(
        WeeklyDebtPlanRow(
          id: 'debt-plan:${rule.id}:${_dateKey(due)}:${PaymentPlan.confirmedForOccurrence(rule, data.entries, due)}',
          ruleId: rule.id,
          name: rule.name,
          contractualDueDate: due,
          proposedDate: event.date,
          weekStart: week,
          amountMinor: amount,
          expectedBalanceMinor: balance,
          categoryId: rule.categoryId,
          serviceId: rule.serviceId,
          serviceIconPath: rule.customIconPath,
        ),
      );
    }
    final allPositions = positions
        .map(
          (p) => DebtPosition(
            ruleId: p.ruleId,
            name: p.name,
            currency: p.currency,
            direction: p.direction,
            balanceMinor: p.balanceMinor,
            remainingAfterPlanMinor:
                (p.balanceMinor - (principalToPay[p.ruleId] ?? 0)).clamp(
                  0,
                  p.balanceMinor,
                ),
            approximateInterest: p.approximateInterest,
          ),
        )
        .toList();
    final ids = rows.map((r) => r.id).toSet();
    final ignoredIds = {
      ...ids,
      for (final entry in data.entries)
        if (entry.status == 'pending' &&
            entry.id.startsWith('debt-plan:') &&
            rows.any(
              (row) =>
                  entry.recurringRuleId == row.ruleId &&
                  entry.plannedDueDate != null &&
                  _day(entry.plannedDueDate!) == row.contractualDueDate,
            ))
          entry.id,
    };
    return WeeklyDebtPlan._(
      request: request,
      inputFingerprint: _fingerprint(data, request, ignoredIds),
      rows: List.unmodifiable(rows),
      debts: List.unmodifiable(
        allPositions.where((p) => p.direction == DebtDirection.payable),
      ),
      receivables: List.unmodifiable(
        allPositions.where((p) => p.direction == DebtDirection.receivable),
      ),
      debtTotalsByCurrency: Map.unmodifiable(debtTotals),
      receivableTotalsByCurrency: Map.unmodifiable(receivableTotals),
      shortages: List.unmodifiable(deficits.values),
      needsConditions: List.unmodifiable(needs.toSet()),
      warnings: List.unmodifiable(warnings.toSet()),
      assumptions: List.unmodifiable(assumptions),
      initialBalanceMinor: initial,
      endingBalanceMinor: balance,
      usedBudgetMinor: used,
      previousRows: {
        for (final id in ignoredIds)
          id: data.entries.where((e) => e.id == id).firstOrNull == null
              ? null
              : _hash(data.entries.firstWhere((e) => e.id == id).toJson()),
      },
    );
  }
}
