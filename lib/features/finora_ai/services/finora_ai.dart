import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../../../domain/models.dart';
import '../classification/transaction_classifier.dart';
import '../inference/linear_model.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../personalization/feedback.dart';
import '../repositories/memory_repository.dart';
import '../responses/intent_parser.dart';
import '../responses/response_layer.dart';
import 'finora_ai_snapshot.dart';

/// A question answered: the text and the structured facts behind it (the UI
/// can show the facts even without the text).
class AiAnswer {
  const AiAnswer(this.query, this.text, {this.insights = const []});
  final ParsedQuery query;
  final String text;
  final List<Insight> insights;
}

/// Finora AI — the entry point. Facts first (engines), words second
/// (response layer). Works fully offline; without the model file it still
/// classifies by memory, history and the catalog.
class FinoraAi {
  FinoraAi({MemoryRepository? memory, this.model})
    : memoryRepository = memory ?? MemoryRepository();

  static final instance = FinoraAi();

  static const modelAsset = 'assets/ai/finora_classifier.json';

  final MemoryRepository memoryRepository;
  LinearModel? model;
  Future<void>? _ready;

  PersonalMemory get memory => memoryRepository.memory;

  /// Loads the memory and the model once.
  Future<void> ready() => _ready ??= _load();

  Future<void> _load() async {
    await memoryRepository.load();
    if (model != null) return;
    try {
      model = LinearModel.parse(await rootBundle.loadString(modelAsset));
    } catch (_) {
      // No model: the classifier falls back to memory, history, catalog.
      model = null;
    }
  }

  TransactionClassifier get classifier => TransactionClassifier(model: model);

  FinoraAiSnapshot snapshot(FinanceData data, {DateTime? now}) =>
      FinoraAiSnapshot.compute(data, memory: memory, now: now);

  ClassificationResult classify(
    FinanceData data, {
    required String merchant,
    String description = '',
    int amountMinor = 0,
    EntryKind kind = EntryKind.expense,
    DateTime? date,
  }) => classifier.classify(
    merchant: merchant,
    description: description,
    amountMinor: amountMinor,
    kind: kind,
    data: data,
    memory: memory,
    date: date,
  );

  /// Learns from a saved operation (called by the controller).
  void observeSave(FinanceEntry entry, {FinanceEntry? before}) {
    if (Feedback.observeSave(memory, entry, before: before)) {
      memoryRepository.saveSoon();
    }
  }

  void confirmSubscription(RecurringCandidate c) {
    Feedback.confirmSubscription(memory, c);
    memoryRepository.saveSoon();
  }

  void rejectSubscription(RecurringCandidate c) {
    Feedback.rejectSubscription(memory, c);
    memoryRepository.saveSoon();
  }

  void rejectBudget(String categoryId) {
    Feedback.rejectBudget(memory, categoryId);
    memoryRepository.saveSoon();
  }

  /// Answers a typed question from the facts of [s].
  AiAnswer answer(String question, FinoraAiSnapshot s) {
    final q = IntentParser.parse(question);
    List<Insight> of(InsightKind k) =>
        s.insights.where((i) => i.kind == k).toList();
    String join(List<Insight> list, String empty) => list.isEmpty
        ? empty
        : list.map((i) => ResponseLayer.insight(s, i)).join('\n');
    switch (q.intent) {
      case AiIntent.whySpendingMore:
      case AiIntent.compare:
        return AiAnswer(
          q,
          ResponseLayer.whySpendingMore(s),
          insights: [...of(InsightKind.growth), ...of(InsightKind.decrease)],
        );
      case AiIntent.forecast:
        return AiAnswer(
          q,
          ResponseLayer.forecast(s),
          insights: of(InsightKind.forecast),
        );
      case AiIntent.freeMoney:
        return AiAnswer(
          q,
          ResponseLayer.freeMoney(s),
          insights: of(InsightKind.freeMoney),
        );
      case AiIntent.subscriptions:
        final subs = of(InsightKind.subscription);
        return AiAnswer(
          q,
          join(
            subs,
            'Новых регулярных платежей, похожих на подписки, я не нашла.',
          ),
          insights: subs,
        );
      case AiIntent.anomalies:
        final list = of(InsightKind.anomaly);
        return AiAnswer(
          q,
          join(list, 'Необычно крупных трат в этом месяце я не вижу.'),
          insights: list,
        );
      case AiIntent.budgetRisk:
        final list = of(InsightKind.budgetRisk);
        return AiAnswer(
          q,
          join(
            list,
            s.ctx.data.budgets.isEmpty
                ? 'Бюджетов пока нет — могу предложить, исходя из твоих трат.'
                : 'Если темп сохранится, все бюджеты уложатся в лимиты.',
          ),
          insights: list,
        );
      case AiIntent.budgetAdvice:
        final list = of(InsightKind.suggestion);
        return AiAnswer(
          q,
          join(
            list,
            'Для совета по бюджету нужно хотя бы два полных месяца трат.',
          ),
          insights: list,
        );
      case AiIntent.income:
        final list = of(InsightKind.incomeStability);
        return AiAnswer(
          q,
          join(
            list,
            'Чтобы оценить доходы, нужно хотя бы три месяца с поступлениями.',
          ),
          insights: list,
        );
      case AiIntent.habits:
        final list = [...of(InsightKind.habit), ...of(InsightKind.trend)];
        return AiAnswer(
          q,
          join(
            list,
            'Устойчивых привычек пока не видно — нужно больше операций.',
          ),
          insights: list,
        );
      case AiIntent.goals:
        final list = of(InsightKind.goal);
        return AiAnswer(
          q,
          join(
            list,
            'Нет мечт со сроком — добавь срок, и я посчитаю, сколько откладывать.',
          ),
          insights: list,
        );
      case AiIntent.categorize:
        final subject = q.subject;
        if (subject == null) {
          return AiAnswer(q, 'Назови магазин или описание операции.');
        }
        final r = classify(s.ctx.data, merchant: subject);
        return AiAnswer(q, ResponseLayer.classification(s, subject, r));
      case AiIntent.summary:
        final top = s.insights.take(3).toList();
        return AiAnswer(q, join(top, ResponseLayer.notEnough), insights: top);
      case AiIntent.unknown:
        return AiAnswer(
          q,
          'Я могу рассказать, почему растут расходы, дать прогноз до конца '
          'месяца, посчитать свободный остаток, найти подписки и крупные '
          'траты или подсказать бюджет.',
        );
    }
  }
}
