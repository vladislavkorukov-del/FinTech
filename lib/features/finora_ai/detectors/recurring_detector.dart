import 'dart:math' as math;

import '../../../domain/models.dart';
import '../../../domain/service_catalog.dart';
import '../../../domain/service_recognizer.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// Finds payments that repeat at a steady rhythm — weekly, monthly, yearly —
/// from the operations alone, and marks the ones that look like
/// subscriptions (a known service, or a steady monthly amount).
///
/// A merchant needs at least three payments, and most gaps between them must
/// be close to the typical gap. Suggestions the person rejected stay hidden
/// until a new payment arrives after the rejection.
abstract final class RecurringDetector {
  static List<RecurringCandidate> detect(
    AiContext ctx, {
    PersonalMemory? memory,
  }) {
    final groups = <String, List<FinanceEntry>>{};
    final since = DateTime(ctx.now.year - 1, ctx.now.month - 1, ctx.now.day);
    for (final e in ctx.expenses) {
      if (e.date.isBefore(since)) continue;
      final key = AiContext.merchantKey(e.payee);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(e);
    }
    final out = <RecurringCandidate>[];
    for (final g in groups.entries) {
      final list = g.value..sort((a, b) => a.date.compareTo(b.date));
      if (list.length < 3) continue;
      final gaps = [
        for (var i = 1; i < list.length; i++)
          list[i].date.difference(list[i - 1].date).inDays.toDouble(),
      ].where((d) => d > 0).toList();
      if (gaps.length < 2) continue;
      final typical = median(gaps);
      final cadence = typical >= 5 && typical <= 9
          ? Cadence.weekly
          : typical >= 25 && typical <= 36
          ? Cadence.monthly
          : typical >= 340 && typical <= 390
          ? Cadence.yearly
          : null;
      if (cadence == null) continue;
      final regular =
          gaps.where((d) => (d - typical).abs() <= typical * .25).length /
          gaps.length;
      if (regular < .6) continue;
      final amounts = [for (final e in list) e.amountMinor.toDouble()];
      final mid = median(amounts);
      final mean = amounts.reduce((a, b) => a + b) / amounts.length;
      final sd = math.sqrt(
        amounts.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) /
            amounts.length,
      );
      final cv = mean == 0 ? 1.0 : sd / mean;
      final last = list.last;
      final name = last.payee.trim();
      final service =
          ServiceCatalog.byId(last.serviceId) ?? ServiceRecognizer.find(name);
      final knownService =
          service != null &&
          !service.id.startsWith('store_') &&
          service.group != 'banks';
      final subscription =
          knownService || (cadence == Cadence.monthly && cv < .08);
      final tracked = ctx.data.recurring.any(
        (r) =>
            AiContext.merchantKey(r.name) == g.key ||
            (r.serviceId != null && r.serviceId == service?.id),
      );
      // A rejection holds until there are new grounds (more payments).
      if (memory != null &&
          memory.stillRejected('recurring:${g.key}', list.length)) {
        continue;
      }
      final confidence =
          (regular * .6 +
                  (1 - cv.clamp(0, 1)) * .25 +
                  math.min(list.length, 8) / 8 * .15)
              .clamp(0.0, .99);
      final step = switch (cadence) {
        Cadence.weekly => const Duration(days: 7),
        Cadence.monthly => Duration(days: typical.round()),
        Cadence.yearly => Duration(days: typical.round()),
      };
      final next = cadence == Cadence.monthly
          ? DateTime(last.date.year, last.date.month + 1, last.date.day)
          : last.date.add(step);
      out.add(
        RecurringCandidate(
          merchantKey: g.key,
          displayName: name,
          cadence: cadence,
          typicalAmount: mid.round(),
          occurrences: list.length,
          lastDate: last.date,
          nextExpected: next,
          confidence: confidence.toDouble(),
          subscriptionLikely: subscription,
          tracked: tracked,
          categoryId: last.categoryId,
          serviceId: knownService ? service.id : null,
        ),
      );
    }
    out.sort((a, b) => b.typicalAmount.compareTo(a.typicalAmount));
    return out;
  }

  /// Possible subscriptions not yet tracked, not confirmed and not rejected.
  static List<RecurringCandidate> subscriptions(
    AiContext ctx, {
    PersonalMemory? memory,
  }) => [
    for (final c in detect(ctx, memory: memory))
      if (c.subscriptionLikely &&
          !c.tracked &&
          !(memory?.stillRejected(
                'subscription:${c.merchantKey}',
                c.occurrences,
              ) ??
              false) &&
          !(memory?.confirmedSubscriptions.contains(c.merchantKey) ?? false))
        c,
  ];
}
