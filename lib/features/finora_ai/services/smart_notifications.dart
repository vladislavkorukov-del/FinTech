import '../../../domain/models.dart';
import '../../../presentation/widgets/common.dart' show money;
import '../memory/personal_memory.dart';
import 'finora_ai_snapshot.dart';

/// One smart notification Finora might send.
class SmartNotice {
  const SmartNotice(this.key, this.title, this.body, this.priority);

  /// Stable for deduplication: the same fact is never sent twice.
  final String key;
  final String title, body;
  final int priority;
}

/// Smart notifications from the engines' facts, most important first:
/// money may run short before the end of the month, an unusual expense,
/// a regular payment that usually has happened by now, a subscription
/// that got dearer. The notification service sends at most one a day, and
/// never the same fact twice — not spam.
abstract final class SmartNotifications {
  static List<SmartNotice> candidates(
    FinanceData data, {
    DateTime? now,
    PersonalMemory? memory,
  }) {
    final ai = data.preferences.ai;
    if (!ai.enabled || !ai.smartNotifications) return const [];
    final s = FinoraAiSnapshot.compute(data, memory: memory, now: now);
    String m(int minor) => money(minor, s.ctx.currency);
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    final out = <SmartNotice>[];
    final low = s.timeline.lowest;
    if (low != null && low.$2 < 0) {
      out.add(
        SmartNotice(
          'smart:low:${s.ctx.periodStart.toIso8601String().substring(0, 10)}',
          'Может не хватить денег',
          'К ${day(low.$1)} на счетах может не хватить около ${m(-low.$2)} '
              'с учётом обязательных платежей.',
          90,
        ),
      );
    }
    final today = s.ctx.now;
    for (final a in s.anomalies) {
      if (today.difference(a.entry.date).inDays > 2) continue;
      out.add(
        SmartNotice(
          'smart:anomaly:${a.entry.id}',
          'Необычно крупная трата',
          '${m(a.entry.amountMinor)}${a.entry.payee.isEmpty ? '' : ' «${a.entry.payee}»'} '
              '— примерно в ${a.ratio.toStringAsFixed(1).replaceAll('.', ',')} '
              'раза больше обычного.',
          70,
        ),
      );
      break;
    }
    for (final e in s.timeline.late.where((e) => e.detected).take(1)) {
      out.add(
        SmartNotice(
          'smart:late:${e.title}:${s.ctx.periodStart.month}',
          'Платёж ещё не прошёл',
          'Обычно «${e.title}» (${m(e.amount)}) к этому времени уже '
              'проходил.',
          50,
        ),
      );
    }
    for (final c in s.subscriptionStats.priceChanged.take(1)) {
      out.add(
        SmartNotice(
          'smart:price:${c.merchantKey}:${c.lastAmount}',
          'Подписка изменилась',
          '«${c.displayName}» теперь ${m(c.lastAmount)} вместо '
              '${m(c.typicalAmount)}.',
          40,
        ),
      );
    }
    out.sort((a, b) => b.priority.compareTo(a.priority));
    return out;
  }

  /// The one notice to send now: the most important unseen one, and none
  /// if one was already sent today.
  static SmartNotice? pick(
    List<SmartNotice> candidates,
    Set<String> seen,
    DateTime now,
  ) {
    final todayKey = 'smart:day:${now.toIso8601String().substring(0, 10)}';
    if (seen.contains(todayKey)) return null;
    for (final c in candidates) {
      if (!seen.contains(c.key)) return c;
    }
    return null;
  }

  static String dayKey(DateTime now) =>
      'smart:day:${now.toIso8601String().substring(0, 10)}';
}
