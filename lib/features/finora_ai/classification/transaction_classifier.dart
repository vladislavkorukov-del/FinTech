import '../../../domain/models.dart';
import '../../../domain/receipt_parser.dart';
import '../inference/features.dart';
import '../inference/linear_model.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../services/ai_context.dart';
import 'category_mapper.dart';

/// Picks the category of an operation, hybrid and in order of trust:
///
/// 1. personal memory — what the person chose or corrected for this
///    merchant;
/// 2. history — what this merchant was filed under before;
/// 3. the store and service catalog — Пятёрочка → «Продукты» (the existing
///    [ReceiptParser.suggestCategory] rules);
/// 4. the local model — text, amount and date features.
///
/// Scores from several sources are merged per category; below
/// [minConfidence] the answer is «not sure» rather than a guess.
class TransactionClassifier {
  const TransactionClassifier({this.model, this.minConfidence = .45});

  final LinearModel? model;
  final double minConfidence;

  ClassificationResult classify({
    required String merchant,
    String description = '',
    required int amountMinor,
    required EntryKind kind,
    required FinanceData data,
    PersonalMemory? memory,
    String accountType = '',
    DateTime? date,
  }) {
    if (kind == EntryKind.transfer) {
      return const ClassificationResult(
        top: [],
        insufficient: Insufficient(InsufficientReason.lowConfidence),
      );
    }
    final active = {
      for (final c in data.categories.where(
        (c) => c.kind == kind && !c.archived,
      ))
        c.id,
    };
    final key = AiContext.merchantKey(merchant);
    final scores = <String, CategoryScore>{};
    void offer(String? id, double confidence, ClassificationSource source) {
      if (id == null || !active.contains(id) || confidence <= 0) return;
      final old = scores[id];
      if (old == null) {
        scores[id] = CategoryScore(id, confidence, source);
      } else {
        // Two sources agreeing raise each other (noisy-or), the more
        // trusted source is kept as the reason.
        final merged = 1 - (1 - old.confidence) * (1 - confidence);
        scores[id] = CategoryScore(
          id,
          merged.clamp(0, .99),
          old.source.index <= source.index ? old.source : source,
        );
      }
    }

    // 1. Memory.
    final remembered = memory?.categoryFor(key);
    if (remembered != null) {
      offer(
        remembered.categoryId,
        remembered.confidence,
        ClassificationSource.memory,
      );
    }
    // 2. History: the share of this merchant's past operations per category.
    if (key.isNotEmpty) {
      final past = data.entries
          .where(
            (e) =>
                e.kind == kind &&
                e.status == 'posted' &&
                e.categoryId != null &&
                AiContext.merchantKey(e.payee) == key,
          )
          .toList();
      if (past.isNotEmpty) {
        final counts = <String, int>{};
        for (final e in past) {
          counts[e.categoryId!] = (counts[e.categoryId!] ?? 0) + 1;
        }
        for (final c in counts.entries) {
          final share = c.value / past.length;
          final strength = 1 - 1 / (1 + past.length);
          offer(
            c.key,
            (.5 + .45 * strength) * share,
            ClassificationSource.history,
          );
        }
      }
    }
    // 3. Catalog rules (the existing receipt/voice categorisation).
    if (merchant.trim().isNotEmpty) {
      final hinted = ReceiptParser.suggestCategory(
        payee: merchant,
        text: description,
        kind: kind,
        categories: data.categories,
      );
      offer(hinted, .82, ClassificationSource.catalog);
    }
    // 4. The model.
    final m = model;
    if (m != null && merchant.trim().isNotEmpty) {
      final predictions = m.predict(
        TransactionInput(
          merchant: merchant,
          description: description,
          amountMinor: amountMinor,
          kind: kind == EntryKind.income ? 'income' : 'expense',
          accountType: accountType,
          date: date ?? DateTime.now(),
        ),
        k: 5,
      );
      for (final (cls, p) in predictions) {
        if (CategoryMapper.kindOf(cls) != kind) continue;
        offer(
          CategoryMapper.categoryFor(cls, data.categories),
          p * .9,
          ClassificationSource.model,
        );
      }
    }
    final ranked = scores.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final top = ranked.take(3).toList();
    return ClassificationResult(
      top: top,
      modelVersion: m?.version,
      insufficient: top.isEmpty || top.first.confidence < minConfidence
          ? const Insufficient(InsufficientReason.lowConfidence)
          : null,
    );
  }
}
