import '../../../domain/models.dart';
import '../models/ai_models.dart';
import '../responses/intent_parser.dart';

/// What the conversation is about (Phase 6): the last question Finora
/// answered, so that a short follow-up is understood —
///
/// - «Сравни с прошлым месяцем» → «а за неделю?» — the same comparison
///   for a week;
/// - «Сколько я потратил на продукты?» → «а на такси?» — the same question
///   for another category;
/// - «Какой прогноз?» → «а почему?» — why spending grew;
/// - «Итоги месяца» → «подробнее» — all observations, not only the top.
///
/// Only the person's own last question is remembered, for ten minutes;
/// nothing is stored on disk.
class ConversationContext {
  ParsedQuery? _last;
  DateTime? _at;

  static const ttl = Duration(minutes: 10);

  ParsedQuery? get last => _last;

  void forget() {
    _last = null;
    _at = null;
  }

  static final _followUp = RegExp(
    r'^(а|и|ну|тогда|еще|ещё|а если|а что|а как|а сколько)(\s|$|[?,.!])',
  );
  static final _more = RegExp(
    r'^(подробнее|подробно|детальнее|еще|ещё|а еще|а ещё|расскажи подробнее|покажи все|покажи всё)[?.!]*$',
  );
  static final _why = RegExp(r'^(а )?почему[?.!]*$|^(а )?из-за чего[?.!]*$');

  /// [parsed] adjusted by the conversation so far; remembers the result.
  ParsedQuery resolve(
    String text,
    ParsedQuery parsed,
    FinanceData data, {
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final t = text.toLowerCase().replaceAll('ё', 'е').trim();
    final last = _at != null && clock.difference(_at!) <= ttl ? _last : null;
    final previous = RegExp(r'прошл').hasMatch(t);
    // The category's words become its id.
    if (parsed.intent == AiIntent.categorySpend && parsed.subject != null) {
      parsed = ParsedQuery(
        AiIntent.categorySpend,
        subject: categoryIn(parsed.subject!, data),
        period: parsed.period,
        previous: parsed.previous,
      );
    }
    var result = parsed;
    // «а в прошлом месяце?», «а на такси в прошлом месяце?» after a
    // category question: still about the category, not a comparison.
    final aboutCategory =
        last?.intent == AiIntent.categorySpend || categoryIn(t, data) != null;
    if (last != null &&
        parsed.intent == AiIntent.compare &&
        _followUp.hasMatch(t) &&
        !t.contains('сравн') &&
        aboutCategory) {
      result = ParsedQuery(
        AiIntent.categorySpend,
        subject:
            categoryIn(t, data) ??
            (last.intent == AiIntent.categorySpend ? last.subject : null),
        period: IntentParser.periodOf(t),
        previous: previous,
      );
    } else if (parsed.intent == AiIntent.unknown && last != null) {
      final category = categoryIn(t, data);
      final period = IntentParser.periodOf(t);
      if (_why.hasMatch(t)) {
        result = const ParsedQuery(AiIntent.whySpendingMore);
      } else if (_more.hasMatch(t)) {
        result = ParsedQuery(
          last.intent,
          period: last.period,
          subject: last.subject,
          previous: last.previous,
          detailed: true,
        );
      } else if (category != null &&
          (last.intent == AiIntent.categorySpend || _followUp.hasMatch(t))) {
        result = ParsedQuery(
          AiIntent.categorySpend,
          subject: category,
          period: period ?? last.period,
          previous: previous || (period == null && last.previous),
        );
      } else if (period != null &&
          (_followUp.hasMatch(t) || t.split(' ').length <= 4)) {
        result = switch (last.intent) {
          AiIntent.categorySpend => ParsedQuery(
            AiIntent.categorySpend,
            subject: last.subject,
            period: period,
            previous: previous,
          ),
          _ => ParsedQuery(AiIntent.compare, period: period),
        };
      }
    } else if (parsed.intent == AiIntent.categorySpend &&
        parsed.subject == null &&
        last?.intent == AiIntent.categorySpend) {
      result = ParsedQuery(
        AiIntent.categorySpend,
        subject: last!.subject,
        period: parsed.period ?? last.period,
        previous: parsed.previous,
      );
    }
    if (result.intent != AiIntent.unknown) {
      _last = result;
      _at = clock;
    }
    return result;
  }

  /// The id of the category named in [t] («на продукты», «такси»): by the
  /// category's name or the first five letters of a word of it.
  static String? categoryIn(String t, FinanceData data) {
    String norm(String s) => s.toLowerCase().replaceAll('ё', 'е');
    final words = norm(t)
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.length >= 4)
        .toList();
    for (final c in data.categories.where((c) => !c.archived)) {
      final name = norm(c.name);
      if (norm(t).contains(name)) return c.id;
      for (final part in name.split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))) {
        if (part.length < 4) continue;
        final stem = part.substring(0, part.length < 5 ? part.length : 5);
        if (words.any((w) => w.startsWith(stem))) return c.id;
      }
    }
    return null;
  }
}

/// The period of a category question as dates: this month (by the
/// person's month start), this week, today, this quarter or year.
(DateTime, DateTime, String) periodRange(
  PeriodUnit? unit,
  DateTime now,
  int monthStart,
  int weekStart,
) {
  final day = DateTime(now.year, now.month, now.day);
  switch (unit) {
    case PeriodUnit.day:
      return (day, day.add(const Duration(days: 1)), 'сегодня');
    case PeriodUnit.week:
      final start = day.subtract(Duration(days: (day.weekday - weekStart) % 7));
      return (start, start.add(const Duration(days: 7)), 'на этой неделе');
    case PeriodUnit.quarter:
      final q = (now.month - 1) ~/ 3;
      return (
        DateTime(now.year, q * 3 + 1),
        DateTime(now.year, q * 3 + 4),
        'в этом квартале',
      );
    case PeriodUnit.year:
      return (DateTime(now.year), DateTime(now.year + 1), 'в этом году');
    default:
      var start = DateTime(now.year, now.month, monthStart);
      if (start.isAfter(day)) {
        start = DateTime(now.year, now.month - 1, monthStart);
      }
      return (
        start,
        DateTime(start.year, start.month + 1, monthStart),
        'в этом месяце',
      );
  }
}
