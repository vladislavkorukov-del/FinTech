import '../../../domain/debt_strategy.dart';
import '../../../domain/finance_engine.dart';
import '../../../domain/models.dart';
import '../../../presentation/widgets/common.dart' show money;
import '../conversation/conversation_context.dart' show ConversationContext;

/// «Что если…» (Phase 7): the effect of a change, counted from the person's
/// own operations, goals and debts. Nothing is changed in the ledger.
///
/// - «что если сократить кафе на 20 %» / «тратить на такси на 3000 меньше»
/// - «что если откладывать 5000 в месяц»
/// - «что если досрочно внести 50 000 в кредит»
/// - «что если доход вырастет на 10 000»
abstract final class WhatIf {
  static final _ask = RegExp(
    r'что (будет )?если|а если|если я буду|если бы',
    caseSensitive: false,
  );

  static bool matches(String text) => _ask.hasMatch(text);

  /// The answer, or null when the change is not one Finora can count.
  static String? answer(FinanceData data, String text, {DateTime? now}) {
    if (!matches(text)) return null;
    final clock = now ?? DateTime.now();
    final t = text.toLowerCase().replaceAll('ё', 'е');
    final cur = data.preferences.baseCurrency;
    String m(int v) => money(v, cur);
    final percent = RegExp(r'(\d+(?:[.,]\d+)?)\s*(%|процент)').firstMatch(t);
    final sum = _amount(t);

    // Cut a category.
    if (RegExp(r'сократ|меньше трат|урез|экономить|отказат').hasMatch(t)) {
      final id = ConversationContext.categoryIn(t, data);
      final category = data.categories.where((c) => c.id == id).firstOrNull;
      final monthly = _monthlySpend(data, id, clock);
      if (monthly == 0) {
        return category == null
            ? 'Назовите категорию: «что если сократить кафе на 20 %».'
            : 'На «${category.name}» за последние три месяца трат не было.';
      }
      final cut = percent != null
          ? (monthly *
                    double.parse(percent.group(1)!.replaceAll(',', '.')) /
                    100)
                .round()
          : (sum ?? monthly ~/ 5).clamp(0, monthly);
      final lines = [
        '${category == null ? 'Все расходы' : '«${category.name}»'}: сейчас в среднем ${m(monthly)} в месяц.',
        'Если тратить на ${m(cut)} меньше — за год останется ${m(cut * 12)}.',
        ..._effect(data, cut, clock),
      ];
      return lines.join('\n');
    }

    // Pay a debt early.
    if (RegExp(r'досрочн|погас|внест|закрыть.*(долг|кредит)').hasMatch(t) &&
        sum != null) {
      final debts = DebtStrategies.debtsOf(data, currency: cur, now: clock);
      if (debts.isEmpty) return 'Долгов в $cur в приложении нет.';
      final target = [...debts]
        ..sort((a, b) => b.annualRate.compareTo(a.annualRate));
      final d = target.first;
      final before = DebtStrategies.simulate(debts, strategy: null);
      final lump = sum.clamp(0, d.balanceMinor);
      final after = DebtStrategies.simulate([
        for (final x in debts)
          x.id == d.id
              ? DebtItem(
                  id: x.id,
                  name: x.name,
                  balanceMinor: x.balanceMinor - lump,
                  annualRate: x.annualRate,
                  minimumMinor: x.minimumMinor,
                )
              : x,
      ], strategy: null);
      final lines = [
        'Если внести ${m(lump)} в «${d.name}»${d.annualRate > 0 ? ' (${d.annualRate.toStringAsFixed(1)} %)' : ''}:',
        if (before.finished && after.finished) ...[
          'переплата меньше на ${m(before.totalInterestMinor - after.totalInterestMinor)},',
          'долги закроются на ${before.months - after.months} мес. раньше.',
        ] else
          'остаток станет ${m(d.balanceMinor - lump)}.',
        'Подушку на непредвиденное лучше не трогать.',
      ];
      return lines.join('\n');
    }

    // Save every month.
    if (RegExp(r'отклад|копить|сберег|в копилку').hasMatch(t) && sum != null) {
      return [
        'Если откладывать ${m(sum)} в месяц: за полгода — ${m(sum * 6)}, '
            'за год — ${m(sum * 12)}.',
        ..._goals(data, sum),
      ].join('\n');
    }

    // Income changes.
    if (RegExp(r'доход|зарплат|заработ').hasMatch(t) && sum != null) {
      final down = RegExp(r'упад|снизит|уменьш|меньше|потеря').hasMatch(t);
      final cap = DebtStrategies.capacity(data, currency: cur, now: clock);
      final free = cap.freeMinor + (down ? -sum : sum);
      return [
        'Сейчас свободно в месяц ≈ ${m(cap.freeMinor)}.',
        'Если доход ${down ? 'уменьшится' : 'вырастет'} на ${m(sum)} — '
            'будет ${free >= 0 ? '≈ ${m(free)}' : 'не хватать ${m(-free)}'}.',
        if (!down) ..._effect(data, sum, clock),
      ].join('\n');
    }
    return 'Могу посчитать: «что если сократить кафе на 20 %», «что если '
        'откладывать 5000 в месяц», «что если досрочно внести 50 000 в '
        'кредит», «что если доход вырастет на 10 000».';
  }

  /// What [monthlyMinor] more a month would do to goals and debts.
  static List<String> _effect(
    FinanceData data,
    int monthlyMinor,
    DateTime now,
  ) {
    final out = <String>[..._goals(data, monthlyMinor)];
    final cur = data.preferences.baseCurrency;
    final debts = DebtStrategies.debtsOf(data, currency: cur, now: now);
    if (debts.isNotEmpty) {
      final base = DebtStrategies.simulate(debts);
      final more = DebtStrategies.simulate(debts, extraMinor: monthlyMinor);
      if (base.finished && more.finished && base.months > more.months) {
        out.add(
          'Направить в долги — закроете на ${base.months - more.months} мес. '
          'раньше и сэкономите ${money(base.totalInterestMinor - more.totalInterestMinor, cur)}.',
        );
      }
    }
    return out;
  }

  static List<String> _goals(FinanceData data, int monthlyMinor) {
    final cur = data.preferences.baseCurrency;
    int saved(Goal g) => FinanceEngine.goalSaved(g, data.entries);
    final goals = data.goals
        .where((g) => g.currency == cur && g.targetMinor > saved(g))
        .toList();
    if (goals.isEmpty || monthlyMinor <= 0) return const [];
    final g = goals.first;
    final left = g.targetMinor - saved(g);
    final months = (left + monthlyMinor - 1) ~/ monthlyMinor;
    return [
      'Мечта «${g.name}» (осталось ${money(left, cur)}) — за $months мес.',
    ];
  }

  /// Average monthly spending of category [id] (all when null) over the
  /// last three full months.
  static int _monthlySpend(FinanceData data, String? id, DateTime now) {
    final cur = data.preferences.baseCurrency;
    final start = DateTime(now.year, now.month - 3);
    final end = DateTime(now.year, now.month);
    var sum = 0;
    for (final e in data.entries) {
      if (e.kind != EntryKind.expense ||
          e.status != 'posted' ||
          e.currency != cur ||
          (id != null && e.categoryId != id) ||
          e.date.isBefore(start) ||
          !e.date.isBefore(end)) {
        continue;
      }
      sum += e.amountMinor;
    }
    return (sum / 3).round().clamp(0, FinanceEngine.maxMinor);
  }

  /// The first sum in [t] in kopecks («5000», «50 000», «10 тыс», «3к»).
  static int? _amount(String t) {
    final m = RegExp(
      r'(\d[\d\s]*(?:[.,]\d+)?)\s*(тыс\S*|к(?![а-я]))?(?!\s*(%|процент))',
    ).firstMatch(t);
    if (m == null) return null;
    final raw = m.group(1)!.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
    final v = double.tryParse(raw);
    if (v == null || v <= 0) return null;
    return (v * (m.group(2) != null ? 1000 : 1) * 100).round();
  }
}
