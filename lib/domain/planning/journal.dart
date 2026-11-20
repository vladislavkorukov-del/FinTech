import 'dart:convert';

import '../models.dart';

/// What changed between two states of the ledger, as journal events for the
/// time machine, and the time each new or changed operation became known.
abstract final class Journal {
  /// [after] with [FinanceEntry.recordedAt] set to [now] on every operation
  /// that is new or changed since [before].
  static FinanceData stamp(
    FinanceData before,
    FinanceData after,
    DateTime now,
  ) {
    final old = {for (final e in before.entries) e.id: e};
    var changed = false;
    final entries = [
      for (final e in after.entries)
        if (_same(old[e.id], e))
          e
        else
          () {
            changed = true;
            return e.copyWith(recordedAt: now);
          }(),
    ];
    return changed ? after.copyWith(entries: entries) : after;
  }

  static bool _same(FinanceEntry? a, FinanceEntry b) {
    if (a == null) return false;
    // Unchanged operations keep the same object: no work for 100 000 rows.
    if (identical(a, b)) return true;
    final x = a.toJson()..remove('recordedAt');
    final y = b.toJson()..remove('recordedAt');
    return jsonEncode(x) == jsonEncode(y);
  }

  /// The journal events for the change [before] → [after].
  static List<HistoryEvent> diff(
    FinanceData before,
    FinanceData after,
    DateTime now,
  ) {
    final out = <HistoryEvent>[];
    var n = 0;
    void add(String kind, Map<String, Object?> payload) => out.add(
      HistoryEvent(
        id: '${now.microsecondsSinceEpoch}-${n++}',
        at: now,
        kind: kind,
        payload: payload,
      ),
    );
    void compare<T>(
      String kind,
      List<T> a,
      List<T> b,
      String Function(T) id,
      Map<String, Object?> Function(T) json, {
      Set<String> ignore = const {},
    }) {
      final left = {for (final x in a) id(x): x};
      final right = {for (final x in b) id(x): x};
      String key(T x) =>
          jsonEncode(json(x)..removeWhere((k, _) => ignore.contains(k)));
      for (final e in right.entries) {
        final was = left[e.key];
        if (identical(was, e.value)) continue;
        if (was == null) {
          add(kind, {'action': 'add', 'id': e.key, 'after': json(e.value)});
        } else if (key(was) != key(e.value)) {
          add(kind, {
            'action': 'edit',
            'id': e.key,
            'before': json(was),
            'after': json(e.value),
          });
        }
      }
      for (final e in left.entries) {
        if (!right.containsKey(e.key)) {
          add(kind, {'action': 'delete', 'id': e.key, 'before': json(e.value)});
        }
      }
    }

    compare<FinanceEntry>(
      'entry',
      before.entries,
      after.entries,
      (e) => e.id,
      (e) => e.toJson()..remove('attachmentPath'),
      ignore: {'recordedAt'},
    );
    compare<Goal>(
      'goal',
      before.goals,
      after.goals,
      (g) => g.id,
      (g) => g.toJson(),
    );
    compare<Budget>(
      'budget',
      before.budgets,
      after.budgets,
      (b) => b.id,
      (b) => b.toJson(),
    );
    compare<RecurringRule>(
      'rule',
      before.recurring,
      after.recurring,
      (r) => r.id,
      (r) => r.toJson(),
    );
    compare<Account>(
      'account',
      before.accounts,
      after.accounts,
      (a) => a.id,
      (a) => a.toJson(),
    );
    final fa = jsonEncode(before.extras.goalFunding.toJson());
    final fb = jsonEncode(after.extras.goalFunding.toJson());
    if (fa != fb) {
      add('goalFunding', {
        'before': before.extras.goalFunding.toJson(),
        'after': after.extras.goalFunding.toJson(),
      });
    }
    final ra = {for (final r in before.extras.reconciliations) r.id};
    for (final r in after.extras.reconciliations) {
      if (!ra.contains(r.id)) add('reconciliation', r.toJson());
    }
    return out;
  }
}
