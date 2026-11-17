import '../../../domain/models.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';

/// How the person's actions teach Finora: every saved operation with a
/// merchant confirms its category, an edited category is a correction, and
/// answers to suggestions are remembered (confirmed or rejected).
abstract final class Feedback {
  /// An operation was saved; [before] is its previous version when edited.
  static bool observeSave(
    PersonalMemory memory,
    FinanceEntry entry, {
    FinanceEntry? before,
  }) {
    if (entry.kind == EntryKind.transfer || entry.categoryId == null) {
      return false;
    }
    final key = AiContext.merchantKey(entry.payee);
    if (key.isEmpty) return false;
    final previous = before?.categoryId;
    // An unchanged re-save adds nothing.
    if (before != null &&
        previous == entry.categoryId &&
        AiContext.merchantKey(before.payee) == key) {
      return false;
    }
    memory.observe(key, entry.categoryId!, previous: previous, at: entry.date);
    return true;
  }

  static void confirmSubscription(PersonalMemory m, RecurringCandidate c) {
    m.confirmedSubscriptions.add(c.merchantKey);
    m.confirmedRecurring.add(c.merchantKey);
    m.unreject('subscription:${c.merchantKey}');
  }

  /// «Это не подписка»: hidden until three more payments arrive.
  static void rejectSubscription(PersonalMemory m, RecurringCandidate c) =>
      m.reject('subscription:${c.merchantKey}', evidence: c.occurrences);

  static void rejectBudget(PersonalMemory m, String categoryId) =>
      m.reject('budget:$categoryId');
}
