import '../../../domain/models.dart';
import '../../../domain/payee_summary.dart';
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
///    merchant (personal_memory);
/// 2. an exact rule — the payee is the name of one of the person's own
///    categories («Такси» → «Такси») (exact_rule);
/// 3. history — what this merchant was filed under before
///    (statistical_rule);
/// 4. the store and service catalog — Пятёрочка → «Продукты» (the existing
///    [ReceiptParser.suggestCategory] rules) (merchant_rule);
/// 5. the local model — text, amount and date features (ml_model);
/// 6. a fallback — the person's most used category of the kind, weak, only
///    so that three choices can be shown (fallback).
///
/// Scores from several sources are merged per category; below
/// [minConfidence] the answer is «not sure» rather than a guess. Merchants
/// are matched by their canonical key, so «PYATEROCHKA #123» learns from
/// «Пятёрочка».
class TransactionClassifier {
  const TransactionClassifier({
    this.model,
    this.minConfidence = AiConfig.minConfidence,
  });

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
    void offer(
      String? id,
      double confidence,
      ClassificationSource source, {
      int evidence = 0,
    }) {
      if (id == null || !active.contains(id) || confidence <= 0) return;
      final old = scores[id];
      if (old == null) {
        scores[id] = CategoryScore(id, confidence, source, evidence: evidence);
      } else {
        // Two sources agreeing raise each other (noisy-or), the more
        // trusted source is kept as the reason.
        final merged = 1 - (1 - old.confidence) * (1 - confidence);
        final keepOld = old.source.index <= source.index;
        scores[id] = CategoryScore(
          id,
          merged.clamp(0, .99),
          keepOld ? old.source : source,
          evidence: keepOld ? old.evidence : evidence,
        );
      }
    }

    // 1. Memory (an older memory may hold the name's plain key).
    final remembered =
        memory?.categoryFor(key) ??
        memory?.categoryFor(PayeeSummary.key(merchant));
    if (remembered != null) {
      offer(
        remembered.categoryId,
        remembered.confidence,
        ClassificationSource.memory,
        evidence: remembered.weight,
      );
    }
    // 2. Exact rule: the payee is one of the person's category names.
    final plain = PayeeSummary.key(merchant);
    if (plain.isNotEmpty) {
      for (final c in data.categories) {
        if (active.contains(c.id) && PayeeSummary.key(c.name) == plain) {
          offer(c.id, .9, ClassificationSource.exact);
        }
      }
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
            evidence: c.value,
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
    // 6. Fallback: the most used categories of the kind, weakly — only to
    // fill the three choices, never enough to be applied.
    if (scores.length < 3) {
      final counts = <String, int>{};
      for (final e in data.entries) {
        if (e.kind == kind && e.categoryId != null) {
          counts[e.categoryId!] = (counts[e.categoryId!] ?? 0) + 1;
        }
      }
      final frequent = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final f in frequent) {
        if (scores.length >= 3) break;
        if (scores.containsKey(f.key)) continue;
        offer(f.key, .2, ClassificationSource.fallback, evidence: f.value);
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
