import '../../../presentation/widgets/common.dart' show money;
import '../models/ai_models.dart';
import '../services/finora_ai_snapshot.dart';

/// Finora's words over facts the engines already computed. Templates only:
/// every number is taken as it is from an engine result, nothing is
/// recalculated or invented here. When an engine had too little data, the
/// answer says so plainly.
abstract final class ResponseLayer {
  static const notEnough =
      'У меня пока недостаточно данных, чтобы нормально сравнить расходы.';
  static const needHistory = 'Для прогноза нужно накопить больше истории.';
  static const unsureCategory = 'Я пока не могу уверенно определить категорию.';

  static String _m(FinoraAiSnapshot s, int minor) =>
      money(minor, s.ctx.currency);

  static String _pct(double p) => '${p.abs().round()}%';

  static String _cat(FinoraAiSnapshot s, String? id) =>
      '«${s.ctx.categoryName(id)}»';

  static const _weekdays = [
    '',
    'понедельник',
    'вторник',
    'среду',
    'четверг',
    'пятницу',
    'субботу',
    'воскресенье',
  ];

  /// One insight as a short sentence.
  static String insight(FinoraAiSnapshot s, Insight i) {
    switch (i.kind) {
      case InsightKind.notEnoughData:
        return 'Пока операций мало — добавьте ещё немного, и я начну '
            'находить закономерности.';
      case InsightKind.summary:
        final base = 'С начала месяца расходы — ${_m(s, i.amount!)}';
        if (i.percent == null) return '$base.';
        final more = i.percent! >= 0;
        final driver = i.categoryId == null || !more
            ? ''
            : ' Больше всего выросла категория ${_cat(s, i.categoryId)}.';
        return '$base: на ${_pct(i.percent!)} ${more ? 'больше' : 'меньше'}, '
            'чем за те же дни прошлого месяца.$driver';
      case InsightKind.forecast:
        return 'Если текущий темп сохранится, расходы за месяц составят '
            'около ${_m(s, i.amount!)}, а на счетах к концу месяца будет '
            'примерно ${_m(s, i.secondAmount!)}.';
      case InsightKind.freeMoney:
        final after =
            'После обязательных платежей у тебя останется '
            'примерно ${_m(s, i.amount!)}';
        if (i.secondAmount == null) return '$after.';
        return '$after, а с учётом обычных трат до конца месяца — около '
            '${_m(s, i.secondAmount!)}.';
      case InsightKind.budgetRisk:
        final r = i.risk!;
        final name = r.budget.categoryId == null
            ? '«${r.budget.name}»'
            : _cat(s, r.budget.categoryId);
        return 'Если текущий темп сохранится, бюджет $name будет превышен '
            'примерно на ${_m(s, r.overrun)} (вероятность ${_pct(r.probability * 100)}).';
      case InsightKind.growth:
        if (i.subject == 'usual') {
          return 'Ты тратишь на ${s.ctx.categoryName(i.categoryId).toLowerCase()} '
              'примерно на ${_m(s, i.amount!)} больше, чем обычно.';
        }
        final p = i.percent;
        return p == null
            ? 'В категории ${_cat(s, i.categoryId)} появились траты на '
                  '${_m(s, i.amount!)}, которых в прошлом месяце не было.'
            : 'В этом месяце траты в категории ${_cat(s, i.categoryId)} '
                  'выросли на ${_pct(p)} (+${_m(s, i.amount!)}).';
      case InsightKind.decrease:
        return 'Расходы в категории ${_cat(s, i.categoryId)} снизились '
            '${i.percent == null ? '' : 'на ${_pct(i.percent!)} '}'
            '(−${_m(s, i.amount!)}).';
      case InsightKind.subscription:
        final c = i.recurring!;
        final when = switch (c.cadence) {
          Cadence.weekly => 'примерно раз в неделю',
          Cadence.monthly => 'примерно раз в месяц',
          Cadence.yearly => 'примерно раз в год',
        };
        return 'Я заметила платёж ${_m(s, c.typicalAmount)} «${c.displayName}» '
            '$when. Возможно, это подписка.';
      case InsightKind.recurring:
        return 'Похоже, «${i.subject}» — регулярный платёж.';
      case InsightKind.anomaly:
        final a = i.anomaly!;
        final first = a.firstAtMerchant
            ? ' Похоже на незапланированную покупку.'
            : '';
        return 'Крупная трата: ${_m(s, a.entry.amountMinor)} '
            '${a.entry.payee.isEmpty ? '' : '«${a.entry.payee}» '}— примерно '
            'в ${a.ratio.toStringAsFixed(1).replaceAll('.', ',')} раза больше '
            'обычного для категории ${_cat(s, a.entry.categoryId)}.$first';
      case InsightKind.trend:
        final t = i.trend!;
        return t.trend == Trend.rising
            ? 'Последние три месяца расходы в категории ${_cat(s, t.categoryId)} '
                  'постепенно растут.'
            : 'Последние три месяца расходы в категории ${_cat(s, t.categoryId)} '
                  'постепенно снижаются.';
      case InsightKind.incomeStability:
        return switch (i.subject) {
          'stable' =>
            'Доходы стабильные: от месяца к месяцу почти не меняются.',
          'moderate' => 'Доходы немного колеблются от месяца к месяцу.',
          _ =>
            'Доходы заметно меняются от месяца к месяцу — стоит держать запас.',
        };
      case InsightKind.unusualMonth:
        final month = DateTime.parse(i.subject!);
        return 'Один из месяцев (${month.month.toString().padLeft(2, '0')}.${month.year}) '
            'был необычно затратным: ${_m(s, i.amount!)} при среднем '
            '${_m(s, i.secondAmount!)}.';
      case InsightKind.habit:
        final d = int.parse(i.subject!);
        return 'Больше всего ты тратишь в ${_weekdays[d]} — '
            '${_pct(i.percent!)} всех расходов.';
      case InsightKind.suggestion:
        return 'Для категории ${_cat(s, i.categoryId)} подойдёт бюджет около '
            '${_m(s, i.amount!)} в месяц — так ты обычно и тратишь.';
      case InsightKind.goal:
        return 'Чтобы успеть с мечтой «${i.subject}», откладывай около '
            '${_m(s, i.amount!)} в месяц.';
    }
  }

  /// A classification as a sentence.
  static String classification(
    FinoraAiSnapshot s,
    String merchant,
    ClassificationResult r,
  ) {
    final best = r.best;
    if (best == null) return unsureCategory;
    return 'Эту операцию я бы отнесла к категории ${_cat(s, best.categoryId)} '
        'с уверенностью ${_pct(best.confidence * 100)}.';
  }

  /// Why spending changed, from the month comparison.
  static String whySpendingMore(FinoraAiSnapshot s) {
    final c = s.comparison;
    if (c.insufficient != null) return notEnough;
    if (c.difference <= 0) {
      return 'В этом месяце ты тратишь не больше обычного: '
          '${_m(s, c.current)} против ${_m(s, c.previous)} за те же дни '
          'прошлого месяца.';
    }
    if (c.drivers.isEmpty) {
      return 'Расходы выше на ${_m(s, c.difference)}, но рост размазан по '
          'разным категориям.';
    }
    final names = c.drivers
        .take(2)
        .map((d) => s.ctx.categoryName(d.categoryId).toLowerCase());
    final first = c.drivers.first;
    return 'Основной рост расходов сейчас дают ${names.join(' и ')}. '
        'На ${s.ctx.categoryName(first.categoryId).toLowerCase()} ты потратил '
        'примерно на ${_m(s, first.difference)} больше, чем за те же дни '
        'прошлого месяца.';
  }

  static String forecast(FinoraAiSnapshot s) {
    final f = s.forecast;
    if (f.insufficient != null) return needHistory;
    return insight(
      s,
      Insight(
        kind: InsightKind.forecast,
        priority: 0,
        amount: f.projectedExpense,
        secondAmount: f.projectedBalance,
      ),
    );
  }

  static String freeMoney(FinoraAiSnapshot s) => insight(
    s,
    Insight(
      kind: InsightKind.freeMoney,
      priority: 0,
      amount: s.cashflow.afterMandatory,
      secondAmount: s.forecast.insufficient == null
          ? s.cashflow.afterAll
          : null,
    ),
  );
}
