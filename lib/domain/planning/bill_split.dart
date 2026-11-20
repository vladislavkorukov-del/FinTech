import '../models.dart';
import '../payment_plan.dart';

/// Where one person of a split stands.
class ShareStatus {
  const ShareStatus(this.share, this.repaidMinor, this.repayments);
  final SplitShare share;
  final int repaidMinor;
  final List<FinanceEntry> repayments;

  /// Still owed (never below zero).
  int get leftMinor =>
      share.shareMinor > repaidMinor ? share.shareMinor - repaidMinor : 0;

  /// Paid back beyond the share — shown, not lost.
  int get overpaidMinor =>
      repaidMinor > share.shareMinor ? repaidMinor - share.shareMinor : 0;
}

/// A split in numbers: money out of the account, the person's own spending,
/// what others owe and have returned.
class SplitStatus {
  const SplitStatus(this.split, this.entry, this.shares);
  final BillSplit split;
  final FinanceEntry entry;
  final List<ShareStatus> shares;

  /// Paid from the account.
  int get outflowMinor => entry.amountMinor;

  /// The person's own spending.
  int get personalMinor => split.ownShareMinor;
  int get initiallyOwedMinor => split.othersMinor;
  int get returnedMinor => shares.fold(0, (s, x) => s + x.repaidMinor);
  int get stillOwedMinor => shares.fold(0, (s, x) => s + x.leftMinor);
  int get overpaidMinor => shares.fold(0, (s, x) => s + x.overpaidMinor);
}

/// «Я заплатил за всех» (Phase 8). Each other person's part becomes a
/// «Мне должны» debt of the existing debt system; a repayment is money
/// coming back to an account, marked as a debt returned — it raises the
/// balance but is not earned income. Kopecks left by rounding stay with the
/// person who paid, so nobody owes a kopeck more than their part.
abstract final class BillSplits {
  /// [total] split equally between the payer and [others] people: the
  /// payer's part, then each other's.
  static (int, List<int>) equal(int total, int others) {
    final n = others + 1;
    final base = total ~/ n;
    return (total - base * others, List.filled(others, base));
  }

  /// [total] split by [weights] (the payer's first), largest remainders
  /// rounding the parts; leftovers go to the payer.
  static (int, List<int>) byShares(int total, List<int> weights) {
    final sum = weights.fold<int>(0, (a, b) => a + b);
    if (sum <= 0 || weights.length < 2) {
      throw const FormatException('Укажите доли участников');
    }
    final parts = [for (final w in weights) total * w ~/ sum];
    final left = total - parts.fold<int>(0, (a, b) => a + b);
    parts[0] += left;
    return (parts.first, parts.sublist(1));
  }

  /// Checks parts given in kopecks: they must add up to [total].
  static void checkAmounts(int total, int own, List<int> others) {
    if (own < 0 || others.any((v) => v <= 0)) {
      throw const FormatException('Доли должны быть положительными');
    }
    if (own + others.fold(0, (a, b) => a + b) != total) {
      throw const FormatException('Сумма долей не равна сумме операции');
    }
  }

  /// [data] with [entry] split: own part [own], [names] owing [parts].
  static FinanceData create(
    FinanceData data, {
    required FinanceEntry entry,
    required int own,
    required List<String> names,
    required List<int> parts,
    required String Function() newId,
    String method = 'equal',
    DateTime? now,
  }) {
    if (entry.kind != EntryKind.expense) {
      throw const FormatException('Разделить можно только расход');
    }
    if (data.extras.splits.any((s) => s.entryId == entry.id)) {
      throw const FormatException('Эта операция уже разделена');
    }
    if (names.length != parts.length || names.isEmpty) {
      throw const FormatException('Добавьте участников');
    }
    if (names.any((n) => n.trim().isEmpty)) {
      throw const FormatException('Укажите имя каждого участника');
    }
    checkAmounts(entry.amountMinor, own, parts);
    final clock = now ?? DateTime.now();
    final rules = <RecurringRule>[];
    final shares = <SplitShare>[];
    for (var i = 0; i < names.length; i++) {
      final rule = RecurringRule(
        id: newId(),
        name:
            '${names[i].trim()} · ${entry.payee.isEmpty ? 'общий счёт' : entry.payee}',
        accountId: entry.accountId,
        currency: entry.currency,
        kind: EntryKind.income,
        amountMinor: parts[i],
        totalMinor: parts[i],
        frequency: 'monthly',
        nextDate: DateTime(clock.year, clock.month, clock.day + 14),
      );
      rules.add(rule);
      shares.add(
        SplitShare(
          name: names[i].trim(),
          shareMinor: parts[i],
          ruleId: rule.id,
        ),
      );
    }
    final split = BillSplit(
      id: newId(),
      entryId: entry.id,
      ownShareMinor: own,
      shares: shares,
      createdAt: clock,
      method: method,
    );
    return data.copyWith(
      recurring: [...data.recurring, ...rules],
      extras: data.extras.copyWith(splits: [...data.extras.splits, split]),
    );
  }

  static SplitStatus? status(FinanceData data, BillSplit split) {
    final entry = data.entries.where((e) => e.id == split.entryId).firstOrNull;
    if (entry == null) return null;
    return SplitStatus(split, entry, [
      for (final s in split.shares)
        () {
          final rule = data.recurring
              .where((r) => r.id == s.ruleId)
              .firstOrNull;
          final paid = rule == null
              ? <FinanceEntry>[]
              : data.entries
                    .where(
                      (e) =>
                          e.kind == EntryKind.income &&
                          PaymentPlan.belongs(e, rule),
                    )
                    .toList();
          return ShareStatus(
            s,
            paid.fold(0, (a, e) => a + e.amountMinor),
            paid..sort((a, b) => a.date.compareTo(b.date)),
          );
        }(),
    ]);
  }

  /// [data] with a repayment of [amount] by the person of [share], to
  /// [accountId] (any account). More than is owed is accepted and shown as
  /// an overpayment.
  static FinanceData repay(
    FinanceData data, {
    required SplitShare share,
    required int amount,
    required String accountId,
    required DateTime date,
    required String uniqueSuffix,
  }) {
    if (amount <= 0) throw const FormatException('Сумма возврата больше нуля');
    final account = data.accounts.where((a) => a.id == accountId).firstOrNull;
    final rule = data.recurring.where((r) => r.id == share.ruleId).firstOrNull;
    if (account == null || rule == null) {
      throw const FormatException('Счёт или долг не найден');
    }
    if (account.currency != rule.currency) {
      throw const FormatException('Валюта счёта не совпадает с валютой долга');
    }
    final entry = FinanceEntry(
      // The id ties it to the debt (PaymentPlan counts it as paid).
      id: 'recurring:${rule.id}:$uniqueSuffix',
      kind: EntryKind.income,
      amountMinor: amount,
      currency: account.currency,
      accountId: account.id,
      date: date,
      payee: '${share.name}: возврат',
      purpose: FinanceEntry.reimbursement,
    );
    return data.copyWith(entries: [...data.entries, entry]);
  }

  /// [data] without the repayment [entryId] (cancelled).
  static FinanceData cancelRepayment(FinanceData data, String entryId) => data
      .copyWith(entries: data.entries.where((e) => e.id != entryId).toList());

  /// [data] with the split's parts changed: [own] and [parts] by person
  /// (same order as the shares; a part of 0 removes a person who has not
  /// paid anything back).
  static FinanceData edit(
    FinanceData data, {
    required BillSplit split,
    required int own,
    required List<int> parts,
  }) {
    final status = BillSplits.status(data, split);
    if (status == null) throw const FormatException('Операция не найдена');
    final kept = <SplitShare>[], keptParts = <int>[];
    final removedRules = <String>{};
    for (var i = 0; i < split.shares.length; i++) {
      if (parts[i] == 0) {
        if (status.shares[i].repaidMinor > 0) {
          throw FormatException(
            '${split.shares[i].name} уже вернул(а) деньги — его долю нельзя убрать',
          );
        }
        removedRules.add(split.shares[i].ruleId);
      } else {
        kept.add(split.shares[i]);
        keptParts.add(parts[i]);
      }
    }
    checkAmounts(status.entry.amountMinor, own, keptParts);
    final byRule = {
      for (var i = 0; i < kept.length; i++) kept[i].ruleId: keptParts[i],
    };
    return data.copyWith(
      recurring: [
        for (final r in data.recurring)
          if (removedRules.contains(r.id))
            ...[]
          else if (byRule.containsKey(r.id))
            r.copyWith(amountMinor: byRule[r.id], totalMinor: byRule[r.id])
          else
            r,
      ],
      extras: data.extras.copyWith(
        splits: [
          for (final s in data.extras.splits)
            if (s.id == split.id)
              BillSplit(
                id: s.id,
                entryId: s.entryId,
                ownShareMinor: own,
                shares: [
                  for (var i = 0; i < kept.length; i++)
                    SplitShare(
                      name: kept[i].name,
                      shareMinor: keptParts[i],
                      ruleId: kept[i].ruleId,
                    ),
                ],
                createdAt: s.createdAt,
                method: 'amount',
              )
            else
              s,
        ],
      ),
    );
  }
}
