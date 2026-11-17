/// What the person asks Finora AI about (typed in the AI screen; the voice
/// assistant has its own parser and is not involved).
enum AiIntent {
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
  unknown,
}

class ParsedQuery {
  const ParsedQuery(this.intent, {this.subject});
  final AiIntent intent;

  /// For [AiIntent.categorize]: the merchant or description to classify.
  final String? subject;
}

/// Keyword rules, most specific first. Deterministic and offline.
abstract final class IntentParser {
  static final _rules = <(AiIntent, RegExp)>[
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
      RegExp(r'остан|свободн|после обязательн|сколько (могу|можно) потратить'),
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
    (AiIntent.compare, RegExp(r'сравни|прошл\S* месяц|чем в прошлом')),
    (
      AiIntent.summary,
      RegExp(r'итог|сводк|как (у меня )?дела|как месяц|summary|обзор'),
    ),
  ];

  static final _categorize = RegExp(
    r'(?:к какой категории|какая категория|категори[яю] (?:для|у))\s*(.*)$',
  );

  static ParsedQuery parse(String text) {
    final t = text.toLowerCase().replaceAll('ё', 'е').trim();
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
      if (re.hasMatch(t)) return ParsedQuery(intent);
    }
    return const ParsedQuery(AiIntent.unknown);
  }
}
