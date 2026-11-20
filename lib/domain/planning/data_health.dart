import '../finance_engine.dart';
import '../models.dart';
import '../payee_summary.dart';
import 'income_planner.dart';

/// One account's standing: the ledger balance and when it was last checked
/// against the bank.
class AccountCheck {
  const AccountCheck(this.account, this.bookMinor, this.last);
  final Account account;
  final int bookMinor;
  final Reconciliation? last;

  /// Days since the last check (null — never checked).
  int? daysSince(DateTime now) =>
      last == null ? null : now.difference(last!.at).inDays;
}

/// Two operations that may be one: what matches.
class DuplicatePair {
  const DuplicatePair(this.a, this.b, this.reasons);
  final FinanceEntry a, b;
  final List<String> reasons;
}

/// A data problem and where to fix it.
class DataIssue {
  const DataIssue(this.kind, this.text, {this.entryId, this.accountId});

  /// stale · unconfirmed · uncategorized · duplicate · expected · difference
  final String kind;
  final String text;
  final String? entryId, accountId;
}

class DataHealthReport {
  const DataHealthReport({
    required this.accounts,
    required this.pending,
    required this.uncategorized,
    required this.duplicates,
    required this.expected,
    required this.issues,
    required this.limits,
  });
  final List<AccountCheck> accounts;
  final List<FinanceEntry> pending, uncategorized;
  final List<DuplicatePair> duplicates;

  /// Expected incomes in the forecast that are not received yet.
  final List<CashEvent> expected;
  final List<DataIssue> issues;

  /// What the forecast rests on and what it cannot know.
  final List<String> limits;
}

/// «Честная картина финансов» (Phase 8): what the balances and the forecast
/// rest on and what needs checking. It reports facts — when a balance was
/// last checked, what is unconfirmed, what may be a duplicate and why — and
/// never claims a cause (a missing expense) it cannot know, nor a percentage
/// of accuracy.
abstract final class DataHealth {
  static const staleDays = 14;

  static DataHealthReport check(FinanceData data, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final recs = [...data.extras.reconciliations]
      ..sort((a, b) => a.at.compareTo(b.at));
    final accounts = [
      for (final a in data.accounts.where((a) => !a.archived))
        AccountCheck(
          a,
          FinanceEngine.balance(a, data.entries),
          recs.where((r) => r.accountId == a.id).lastOrNull,
        ),
    ];
    final pending = data.entries.where((e) => e.status == 'pending').toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final uncategorized = data.entries
        .where(
          (e) =>
              e.status != 'cancelled' &&
              e.kind != EntryKind.transfer &&
              e.isOrdinary &&
              (e.categoryId == null ||
                  !data.categories.any((c) => c.id == e.categoryId)),
        )
        .toList();
    final duplicates = findDuplicates(data.entries);
    final plan = IncomePlanner.plan(data, now: clock);
    final expected = plan.events.where((e) => e.income).toList();
    final names = {for (final a in data.accounts) a.id: a.name};
    final issues = <DataIssue>[];
    for (final c in accounts) {
      final days = c.daysSince(clock);
      if (days == null) {
        issues.add(
          DataIssue(
            'stale',
            'Остаток счёта «${c.account.name}» ещё ни разу не сверялся.',
            accountId: c.account.id,
          ),
        );
      } else if (days >= staleDays) {
        issues.add(
          DataIssue(
            'stale',
            'Остаток счёта «${c.account.name}» не проверялся $days дн.',
            accountId: c.account.id,
          ),
        );
      }
      final last = c.last;
      if (last != null &&
          last.differenceMinor != 0 &&
          last.adjustmentEntryId == null) {
        issues.add(
          DataIssue(
            'difference',
            '«${c.account.name}»: при сверке ${_d(last.at)} в банке было на '
                '${_m(last.differenceMinor.abs())} ${last.differenceMinor > 0 ? 'больше' : 'меньше'}, '
                'чем в учёте. Причина не известна — проверьте операции.',
            accountId: c.account.id,
          ),
        );
      }
    }
    for (final e in pending) {
      issues.add(
        DataIssue(
          'unconfirmed',
          'Не подтверждено: ${e.payee.isEmpty ? 'операция' : e.payee} '
              '${_m(e.amountMinor)} на ${_d(e.date)}.',
          entryId: e.id,
        ),
      );
    }
    for (final e in uncategorized.take(20)) {
      issues.add(
        DataIssue(
          'uncategorized',
          'Без категории: ${e.payee.isEmpty ? 'операция' : e.payee} ${_m(e.amountMinor)}, ${_d(e.date)}.',
          entryId: e.id,
        ),
      );
    }
    for (final p in duplicates.take(20)) {
      issues.add(
        DataIssue(
          'duplicate',
          'Могут дублировать друг друга: ${p.a.payee.isEmpty ? 'операция' : p.a.payee} '
              '${_m(p.a.amountMinor)} — совпадают ${p.reasons.join(', ')}.',
          entryId: p.b.id,
        ),
      );
    }
    for (final e in expected) {
      issues.add(
        DataIssue(
          'expected',
          'В прогноз включён ожидаемый доход ${_m(e.amountMinor)} '
              '(«${e.name}», ${_d(e.date)}).',
          entryId: e.entryId,
        ),
      );
    }
    final limits = <String>[
      'Прогноз опирается на операции, внесённые в приложение. Траты, которых '
          'здесь нет, он не видит.',
      if (accounts.any((c) => (c.daysSince(clock) ?? 999) >= staleDays))
        'Остатки не всех счетов сверены с банком недавно.',
      if (expected.isNotEmpty)
        'Включены ожидаемые доходы на ${_m(expected.fold(0, (s, e) => s + e.amountMinor))} — они ещё не получены.',
      if (pending.isNotEmpty)
        '${pending.length} операц. не подтверждены и не влияют на остаток.',
      if (data.accounts.any((a) => a.excluded))
        'Счета, исключённые из итога (${data.accounts.where((a) => a.excluded).map((a) => names[a.id]).join(', ')}), в прогноз не входят.',
    ];
    return DataHealthReport(
      accounts: accounts,
      pending: pending,
      uncategorized: uncategorized,
      duplicates: duplicates,
      expected: expected,
      issues: issues,
      limits: limits,
    );
  }

  /// Pairs of operations that may be one, with what matches: account, sum
  /// and date within a day; the place too when both have one.
  static List<DuplicatePair> findDuplicates(List<FinanceEntry> entries) {
    final byKey = <String, List<FinanceEntry>>{};
    for (final e in entries) {
      if (e.status == 'cancelled' || e.kind == EntryKind.transfer) continue;
      (byKey['${e.accountId}|${e.kind.name}|${e.amountMinor}|${e.currency}'] ??=
              [])
          .add(e);
    }
    final out = <DuplicatePair>[];
    for (final list in byKey.values) {
      if (list.length < 2) continue;
      list.sort((a, b) => a.date.compareTo(b.date));
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i], b = list[j];
          if (b.date.difference(a.date).inHours > 24) break;
          final pa = PayeeSummary.key(a.payee), pb = PayeeSummary.key(b.payee);
          if (pa.isNotEmpty && pb.isNotEmpty && pa != pb) continue;
          out.add(
            DuplicatePair(a, b, [
              'счёт',
              'сумма',
              a.date.day == b.date.day ? 'дата' : 'даты в пределах суток',
              if (pa.isNotEmpty && pa == pb) 'получатель',
            ]),
          );
        }
      }
    }
    return out;
  }

  /// A new reconciliation of [accountId]: the ledger balance now against
  /// [actualMinor]. Nothing is changed; an adjustment is a separate choice.
  static Reconciliation reconcile(
    FinanceData data, {
    required String id,
    required String accountId,
    required int actualMinor,
    DateTime? now,
    String note = '',
  }) {
    final account = data.accounts.firstWhere((a) => a.id == accountId);
    return Reconciliation(
      id: id,
      accountId: accountId,
      at: now ?? DateTime.now(),
      bookMinor: FinanceEngine.balance(account, data.entries),
      actualMinor: actualMinor,
      note: note,
    );
  }

  /// The explicit correction for [r]: an operation marked as an adjustment
  /// that brings the ledger to the bank's figure (not income or spending).
  static FinanceEntry adjustment(
    Reconciliation r,
    FinanceData data, {
    required String id,
  }) {
    final account = data.accounts.firstWhere((a) => a.id == r.accountId);
    final diff = r.differenceMinor;
    return FinanceEntry(
      id: id,
      kind: diff > 0 ? EntryKind.income : EntryKind.expense,
      amountMinor: diff.abs(),
      currency: account.currency,
      accountId: account.id,
      date: r.at,
      payee: 'Корректировка остатка',
      note:
          'Сверка ${_d(r.at)}: в учёте ${_m(r.bookMinor)}, в банке ${_m(r.actualMinor)}',
      purpose: FinanceEntry.adjustment,
      recordedAt: r.at,
    );
  }

  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  static String _m(int v) {
    final s = (v.abs() ~/ 100).toString();
    final b = StringBuffer(v < 0 ? '−' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    final c = v.abs() % 100;
    return '$b${c == 0 ? '' : ',${c.toString().padLeft(2, '0')}'} ₽';
  }
}
