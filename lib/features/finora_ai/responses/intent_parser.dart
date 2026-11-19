import '../models/ai_models.dart';

/// What the person asks Finora AI about (typed in the AI screen; the voice
/// assistant has its own parser and is not involved).
enum AiIntent {
  /// «Что ты умеешь?» — the list of capabilities.
  capabilities,
  whySpendingMore,
  compare,
  forecast,
  freeMoney,
  subscriptions,
  anomalies,
  budgetRisk,
  budgetAdvice,
  income,
  habits,
  goals,
  categorize,
  summary,

  /// How long savings would last.
  cushion,

  /// The stability index and its reasons.
  stability,

  /// Payments coming up (the cash-flow timeline).
  payments,

  /// «Сколько я потратил на продукты?» — one category's spending.
  categorySpend,
  unknown,
}

class ParsedQuery {
  const ParsedQuery(
    this.intent, {
    this.subject,
    this.period,
    this.previous = false,
    this.detailed = false,
  });
  final AiIntent intent;

  /// For [AiIntent.categorize]: the merchant or description to classify;
  /// for [AiIntent.categorySpend]: the category (its words, then its id).
  final String? subject;

  /// For [AiIntent.compare]: the period named («эту неделю с прошлой»).
  final PeriodUnit? period;

  /// The previous period («в прошлом месяце»), for [AiIntent.categorySpend].
  final bool previous;

  /// «Подробнее»: all the observations, not only the top ones.
  final bool detailed;
}

/// Keyword rules, most specific first. Deterministic and offline.
abstract final class IntentParser {
  static final _rules = <(AiIntent, RegExp)>[
    (
      AiIntent.capabilities,
      RegExp(
        r'что (ты )?(умеешь|можешь|знаешь)|твои возможности|чем (ты )?'
        r'(можешь )?помо|что (у тебя )?(можно )?спросить|как (с )?тобой '
        r'польз|^помощь$|^help$',
      ),
    ),
    (
      AiIntent.payments,
      RegExp(
        r'ближайш\S* (платеж|списан|оплат)|какие платежи (скоро|впереди|ждут)|'
        r'календар\S* платеж|когда (мне )?(платить|оплачивать)|'
        r'что (нужно|надо) (оплатить|заплатить)',
      ),
    ),
    (
      AiIntent.cushion,
      RegExp(r'подушк|на сколько (месяцев |времени )?хватит|финансов\S* запас'),
    ),
    (
      AiIntent.stability,
      RegExp(
        r'индекс|финансов\S* стабильн|стабильн\S* (у меня )?финанс|'
        r'насколько (я |у меня )?стабил|оцен\S* (мои |моих )?финанс',
      ),
    ),
    (
      AiIntent.whySpendingMore,
      RegExp(
        r'почему.*(больше|рост|выросл|много)|из-за чего|откуда (рост|столько)',
      ),
    ),
    (
      AiIntent.budgetAdvice,
      RegExp(r'(предлож|посоветуй|подбери|какой).*(бюджет|лимит)'),
    ),
    (AiIntent.budgetRisk, RegExp(r'бюджет|лимит|превыш|уложусь|уложиться')),
    (
      AiIntent.freeMoney,
      RegExp(
        r'остан|свободн|после обязательн|сколько (я )?(могу|можно) потратить',
      ),
    ),
    (
      AiIntent.forecast,
      RegExp(r'прогноз|сколько (я )?потрачу|до конца месяца|к концу месяца'),
    ),
    (AiIntent.subscriptions, RegExp(r'подписк|регулярн|повторя')),
    (
      AiIntent.anomalies,
      RegExp(r'крупн|необычн|аномал|большие трат|незапланир'),
    ),
    (AiIntent.income, RegExp(r'доход|зарплат|стабильн')),
    (AiIntent.goals, RegExp(r'мечт|цел[ьия]|накоп|отложить')),
    (
      AiIntent.habits,
      RegExp(r'привычк|куда уход|на что .*(трачу|уходит)|в какой день'),
    ),
    (
      AiIntent.compare,
      RegExp(
        r'сравни|прошл\S* (месяц|недел|квартал|год)|чем в прошлом|чем вчера',
      ),
    ),
    (
      AiIntent.summary,
      RegExp(r'итог|сводк|как (у меня )?дела|как месяц|summary|обзор'),
    ),
  ];

  static final _categorize = RegExp(
    r'(?:к какой категории|какая категория|категори[яю] (?:для|у))\s*(.*)$',
  );

  /// The period a comparison names; null means the month. (Word edges are
  /// spelled out: `\b` does not see Cyrillic letters.)
  static PeriodUnit? periodOf(String t) => RegExp(r'недел').hasMatch(t)
      ? PeriodUnit.week
      : RegExp(r'квартал').hasMatch(t)
      ? PeriodUnit.quarter
      : RegExp(r'(^|\s)год(а|у|ом)?($|[\s?.!,])').hasMatch(t)
      ? PeriodUnit.year
      : RegExp(r'сегодн|вчера|(^|\s)(день|дня|дне)($|[\s?.!,])').hasMatch(t)
      ? PeriodUnit.day
      : null;

  static final _categorySpend = RegExp(
    r'сколько (я |мы |у меня )?(потратил\S*|ушло|уходит|трачу|тратил\S*|потрачено) (на|в|за) (.+)$',
  );

  static ParsedQuery parse(String text) {
    final t = text.toLowerCase().replaceAll('ё', 'е').trim();
    final spend = _categorySpend.firstMatch(t);
    if (spend != null) {
      final rest = spend.group(4)!.replaceAll(RegExp(r'[?.!]+$'), '');
      return ParsedQuery(
        AiIntent.categorySpend,
        subject: rest,
        period: periodOf(rest),
        previous: RegExp(r'прошл').hasMatch(rest),
      );
    }
    final c = _categorize.firstMatch(t);
    if (c != null) {
      final subject = text
          .substring(text.length - c.group(1)!.length)
          .replaceAll(RegExp(r'^[\s:«"]+|[\s?»"]+$'), '');
      return ParsedQuery(
        AiIntent.categorize,
        subject: subject.isEmpty ? null : subject,
      );
    }
    for (final (intent, re) in _rules) {
      if (!re.hasMatch(t)) continue;
      return ParsedQuery(
        intent,
        period: intent == AiIntent.compare ? periodOf(t) : null,
      );
    }
    return const ParsedQuery(AiIntent.unknown);
  }
}
