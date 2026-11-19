import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import '../../../domain/models.dart';
import '../classification/transaction_classifier.dart';
import '../inference/linear_model.dart';
import '../conversation/conversation_context.dart';
import '../insights/debt_advice.dart';
import '../responses/category_spend.dart';
import '../memory/personal_memory.dart';
import '../models/ai_models.dart';
import '../personalization/feedback.dart';
import '../personalization/payee_aliases.dart';
import '../repositories/memory_repository.dart';
import '../responses/capabilities.dart';
import '../responses/intent_parser.dart';
import '../responses/response_layer.dart';
import 'ai_context.dart';
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

  /// The memory is loaded (the app starts loading it at launch).
  bool get loaded => _loaded;
  bool _loaded = false;

  Future<void> _load() async {
    await memoryRepository.load();
    _loaded = true;
    if (model != null) return;
    try {
      final source = await rootBundle.loadString(modelAsset);
      try {
        // The 300 KB model is decoded off the UI thread.
        model = await LinearModel.parseInBackground(source);
      } on UnsupportedError {
        // No isolates on this platform: decode here.
        model = LinearModel.parse(source);
      }
    } catch (_) {
      // No model, or one this app cannot read (an unknown file schema or
      // feature version): the classifier falls back to memory, history and
      // the catalog.
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
    merchant: resolvePayee(data, merchant),
    description: description,
    amountMinor: amountMinor,
    kind: kind,
    data: data,
    // Without personalization the person's memory is not used.
    memory: data.preferences.ai.personalization ? memory : null,
    date: date,
  );

  /// «Сбросить персонализацию»: forgets what Finora learned — merchant
  /// choices, corrections, answers to suggestions, snoozes. The person's
  /// operations are not touched.
  Future<void> resetPersonalization() => memoryRepository.replace(
    PersonalMemory(
      preferences: memory.preferences,
      scenarios: List.of(memory.scenarios),
    ),
  );

  /// Restores the memory saved in a backup (see [memoryForBackup]).
  Future<void> restoreMemory(Map<String, dynamic> json) =>
      memoryRepository.replace(PersonalMemory.fromJson(json));

  /// The memory as it goes into a full backup.
  Map<String, dynamic> memoryForBackup() => memory.toJson();

  /// [payee] written in full when the person taught Finora a short name
  /// for it («Кб» → «Красное&Белое»); otherwise [payee] itself. Not used
  /// with personalization turned off.
  String resolvePayee(FinanceData data, String payee) {
    if (!data.preferences.ai.personalization) return payee;
    return PayeeAliases.resolve(memory, payee) ?? payee;
  }

  /// Remembers that [short] means [full]; returns the stored full name or
  /// null when there was nothing to learn.
  String? learnAlias(String short, String full) {
    final name = PayeeAliases.learn(memory, short, full);
    if (name != null) memoryRepository.saveSoon();
    return name;
  }

  void forgetAlias(String short) {
    if (PayeeAliases.forget(memory, short)) memoryRepository.saveSoon();
  }

  /// The category the person's own memory gives the place [payee] (after
  /// its short name is resolved): only a strong, settled choice, never a
  /// guess of the model.
  String? rememberedCategory(FinanceData data, String payee, EntryKind kind) {
    if (!data.preferences.ai.personalization) return null;
    final key = AiContext.merchantKey(resolvePayee(data, payee));
    if (key.isEmpty) return null;
    final vote = memory.categoryFor(key);
    if (vote == null || vote.confidence < .8) return null;
    final category = data.categories
        .where((c) => c.id == vote.categoryId && !c.archived && c.kind == kind)
        .firstOrNull;
    return category?.id;
  }

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

  /// «Не учитывать этот месяц в прогнозах» — an unusual month (a move, a
  /// repair) stops weighing on the everyday pace.
  void excludeMonth(String month) {
    memory.excludedMonths.add(month);
    memory.reject('unusual:$month');
    memoryRepository.saveSoon();
  }

  /// «Учитывать как обычный» — the question is not asked again.
  void keepMonth(String month) {
    memory.reject('unusual:$month');
    memoryRepository.saveSoon();
  }

  void rejectBudget(String categoryId) {
    Feedback.rejectBudget(memory, categoryId);
    memoryRepository.saveSoon();
  }

  /// Answers a typed question from the facts of [s].
  /// The conversation so far (Phase 6): short follow-ups are understood.
  final conversation = ConversationContext();

  AiAnswer answer(String question, FinoraAiSnapshot s) {
    final q = conversation.resolve(
      question,
      IntentParser.parse(question),
      s.ctx.data,
      now: s.ctx.now,
    );
    // «Как мне погасить долги?» — the payoff plan from the person's data.
    if (DebtAdvice.matches(question)) {
      return AiAnswer(
        q,
        DebtAdvice.answer(s.ctx.data, currency: s.ctx.currency, now: s.ctx.now),
      );
    }
    List<Insight> of(InsightKind k) =>
        s.insights.where((i) => i.kind == k).toList();
    String join(List<Insight> list, String empty) => list.isEmpty
        ? empty
        : list.map((i) => ResponseLayer.insight(s, i)).join('\n');
    switch (q.intent) {
      case AiIntent.capabilities:
        return AiAnswer(q, AiCapabilities.answer());
      case AiIntent.compare:
        return AiAnswer(
          q,
          ResponseLayer.periodComparison(
            s,
            s.compare(q.period ?? PeriodUnit.month),
          ),
          insights: [...of(InsightKind.growth), ...of(InsightKind.decrease)],
        );
      case AiIntent.whySpendingMore:
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
        final summary = ResponseLayer.subscriptionSummary(s);
        final found = join(subs, '');
        final text = [summary, found].where((t) => t.isNotEmpty).join('\n');
        return AiAnswer(
          q,
          text.isEmpty
              ? 'Подписок и похожих на них регулярных платежей я не нашла.'
              : text,
          insights: subs,
        );
      case AiIntent.cushion:
        return AiAnswer(q, ResponseLayer.cushion(s));
      case AiIntent.stability:
        return AiAnswer(q, ResponseLayer.stability(s));
      case AiIntent.payments:
        return AiAnswer(q, ResponseLayer.upcoming(s));
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
      case AiIntent.categorySpend:
        return AiAnswer(
          q,
          CategorySpend.answer(
            s.ctx.data,
            categoryId: q.subject,
            period: q.period,
            previous: q.previous,
            now: s.ctx.now,
          ),
        );
      case AiIntent.summary:
        // The month in one line, then the most useful observations
        // («Подробнее»: up to eight).
        final top = <Insight>{
          ...of(InsightKind.summary).take(1),
          ...s.top,
          if (q.detailed) ...s.insights,
        }.take(q.detailed ? 8 : 3).toList();
        return AiAnswer(q, join(top, ResponseLayer.notEnough), insights: top);
      case AiIntent.unknown:
        return AiAnswer(
          q,
          'Такого я пока не умею. Спроси «что ты умеешь?» — покажу, с чем '
          'могу помочь.',
        );
    }
  }
}
