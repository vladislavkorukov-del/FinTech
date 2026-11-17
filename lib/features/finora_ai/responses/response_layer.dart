import '../../../presentation/widgets/common.dart' show money;
import '../../../domain/models.dart' show EntryKind;
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
        final safe = r.safeDaily > 0
            ? ' Чтобы уложиться, тратить не больше ${_m(s, r.safeDaily)} в день.'
            : '';
        return 'Если текущий темп сохранится, бюджет $name будет превышен '
            'примерно на ${_m(s, r.overrun)} (вероятность ${_pct(r.probability * 100)}).$safe';
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
        final when = cadenceText(c.cadence);
        return 'Я заметила платёж ${_m(s, c.typicalAmount)} «${c.displayName}» '
            '$when. Возможно, это подписка.';
      case InsightKind.recurring:
        return 'Похоже, «${i.subject}» — регулярный платёж.';
      case InsightKind.anomaly:
        final a = i.anomaly!;
        final first = a.firstAtMerchant
            ? ' Похоже на незапланированную покупку.'
            : '';
        final times = a.ratio.toStringAsFixed(1).replaceAll('.', ',');
        final norm = a.basis == AnomalyBasis.merchant
            ? 'твоей обычной покупки здесь (${_m(s, a.typical)})'
            : 'обычного для категории ${_cat(s, a.entry.categoryId)}';
        return 'Крупная трата: ${_m(s, a.entry.amountMinor)} '
            '${a.entry.payee.isEmpty ? '' : '«${a.entry.payee}» '}— примерно '
            'в $times раза больше $norm.$first';
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
      case InsightKind.latePayment:
        return 'Обычно платёж «${i.subject}» (${_m(s, i.amount!)}) к этому '
            'времени уже проходил.';
      case InsightKind.frequency:
        return 'В этом месяце уже ${i.amount} трат — обычно к этому дню их '
            'около ${i.secondAmount}.';
      case InsightKind.goal:
        final g = s.goalForecasts
            .where((g) => g.goal.name == i.subject)
            .firstOrNull;
        if (g == null || g.monthlyNeed == null) {
          final when = g?.expectedDate;
          return when == null
              ? 'Мечта «${i.subject}» пока без регулярных пополнений.'
              : 'В текущем темпе (${_m(s, g!.monthlyPace)} в месяц) мечта '
                    '«${i.subject}» исполнится примерно к ${_monthYear(when)}.';
        }
        final need =
            'Чтобы успеть с мечтой «${i.subject}», откладывай около '
            '${_m(s, g.monthlyNeed!)} в месяц (~${_m(s, g.weeklyNeed!)} в '
            'неделю).';
        final d = g.deviation!;
        if (g.monthlyPace == 0) return need;
        return d >= 0
            ? '$need Сейчас ты откладываешь ${_m(s, g.monthlyPace)} — успеваешь.'
            : '$need Сейчас ${_m(s, g.monthlyPace)} в месяц — не хватает '
                  '${_m(s, -d)}; можно сдвинуть срок или увеличить взнос.';
      case InsightKind.priceChange:
        final more = i.amount! > i.secondAmount!;
        return 'Подписка «${i.subject}» стала ${more ? 'дороже' : 'дешевле'}: '
            '${_m(s, i.amount!)} вместо обычных ${_m(s, i.secondAmount!)}.';
      case InsightKind.cushion:
        return 'Накоплений на отдельных счетах — ${_m(s, i.amount!)}: это '
            'меньше месяца обычных трат (${_m(s, i.secondAmount!)}).';
    }
  }

  static const _months = [
    '',
    'январю',
    'февралю',
    'марту',
    'апрелю',
    'маю',
    'июню',
    'июлю',
    'августу',
    'сентябрю',
    'октябрю',
    'ноябрю',
    'декабрю',
  ];

  static String _monthYear(DateTime d) => '${_months[d.month]} ${d.year}';

  /// How often a regular payment repeats, in words.
  static String cadenceText(Cadence c) => switch (c) {
    Cadence.weekly => 'примерно раз в неделю',
    Cadence.biweekly => 'примерно раз в две недели',
    Cadence.monthly => 'примерно раз в месяц',
    Cadence.quarterly => 'примерно раз в квартал',
    Cadence.yearly => 'примерно раз в год',
  };

  /// A classification as a sentence.
  static String classification(
    FinoraAiSnapshot s,
    String merchant,
    ClassificationResult r,
  ) {
    final best = r.best;
    if (best == null) return unsureCategory;
    final why = explain(s, merchant, best);
    return 'Эту операцию я бы отнесла к категории ${_cat(s, best.categoryId)} '
        'с уверенностью ${_pct(best.confidence * 100)}.'
        '${why.isEmpty ? '' : ' $why'}';
  }

  /// Why a category was chosen, from its source and evidence.
  static String explain(FinoraAiSnapshot s, String merchant, CategoryScore b) {
    final cat = _cat(s, b.categoryId);
    final n = b.evidence;
    return switch (b.source) {
      ClassificationSource.memory =>
        'Ты сам${n > 1 ? ' $n ${_times(n)}' : ''} выбирал $cat для этого места.',
      ClassificationSource.exact => 'Так называется твоя категория.',
      ClassificationSource.history =>
        n > 1
            ? 'Последние $n покупок в этом месте были отнесены к $cat.'
            : 'Прошлая покупка здесь была в категории $cat.',
      ClassificationSource.catalog => 'Это известное место категории $cat.',
      ClassificationSource.model =>
        'Так подсказывает локальная модель по названию и сумме.',
      ClassificationSource.fallback || ClassificationSource.none => '',
    };
  }

  static String _times(int n) {
    final last = n % 10, lastTwo = n % 100;
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
      return 'раза';
    }
    return 'раз';
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

  /// Two periods compared, from [MonthComparisonEngine.comparePeriods]:
  /// spending, the categories behind the change, income and cash flow.
  static String periodComparison(FinoraAiSnapshot s, PeriodComparison c) {
    final (now, before) = switch (c.unit) {
      PeriodUnit.day => ('Сегодня', 'вчера'),
      PeriodUnit.week => ('На этой неделе', 'за те же дни прошлой недели'),
      PeriodUnit.quarter => (
        'В этом квартале',
        'за те же дни прошлого квартала',
      ),
      PeriodUnit.year => ('В этом году', 'за те же дни прошлого года'),
      _ => ('В этом месяце', 'за те же дни прошлого месяца'),
    };
    switch (c.insufficient) {
      case InsufficientData.noPreviousData:
        return 'Сравнить пока не с чем: $before операций нет.';
      case InsufficientData.tooFewEntries:
        return notEnough;
      case null:
        break;
    }
    final p = c.expensePercent;
    final more = c.expenseDifference >= 0;
    final lines = [
      p == null
          ? '$now расходы — ${_m(s, c.expense)}, а $before — '
                '${_m(s, c.previousExpense)}.'
          : '$now расходы — ${_m(s, c.expense)}: на ${_pct(p)} '
                '${more ? 'больше' : 'меньше'}, чем $before '
                '(${_m(s, c.previousExpense)}).',
    ];
    String names(List<CategoryDelta> list, String sign) => list
        .take(2)
        .map(
          (d) =>
              '${s.ctx.categoryName(d.categoryId).toLowerCase()} '
              '($sign${_m(s, d.difference.abs())})',
        )
        .join(', ');
    if (more && c.increases.isNotEmpty) {
      lines.add('Больше всего выросли: ${names(c.increases, '+')}.');
    } else if (!more && c.decreases.isNotEmpty) {
      lines.add('Меньше всего стало: ${names(c.decreases, '−')}.');
    }
    if (c.income > 0 || c.previousIncome > 0) {
      lines.add(
        'Доходы — ${_m(s, c.income)} против ${_m(s, c.previousIncome)}; '
        'разница доходов и расходов ${_signed(s, c.cashflow)} '
        '(было ${_signed(s, c.previousCashflow)}).',
      );
    }
    return lines.join(' ');
  }

  static String _signed(FinoraAiSnapshot s, int minor) =>
      '${minor < 0 ? '−' : '+'}${_m(s, minor.abs())}';

  /// Subscriptions' cost and changes, from [SubscriptionAnalytics].
  static String subscriptionSummary(FinoraAiSnapshot s) {
    final a = s.subscriptionStats;
    final lines = <String>[
      if (a.count > 0)
        'Подписки: ${a.count} шт., около ${_m(s, a.monthly)} в месяц — '
            '${_m(s, a.yearly)} в год.',
      for (final c in a.priceChanged.take(2))
        '«${c.displayName}» теперь ${_m(s, c.lastAmount)} вместо '
            '${_m(s, c.typicalAmount)}.',
      for (final c in a.added.take(2))
        'Новая: «${c.displayName}», ${_m(s, c.typicalAmount)} '
            '${cadenceText(c.cadence)}.',
      for (final c in a.stopped.take(2))
        '«${c.displayName}» больше не списывается — похоже, отключена.',
    ];
    return lines.join('\n');
  }

  /// How long the savings would last.
  static String cushion(FinoraAiSnapshot s) {
    final c = s.cushion;
    final months = c?.months;
    if (c == null || months == null) {
      return 'Накоплений на отдельных счетах (накопительный, вклад) я не вижу '
          '— или пока мало истории трат, чтобы посчитать.';
    }
    String m(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final mandatory = c.mandatoryMonths;
    return 'Накоплений ${_m(s, c.savings)}: при обычных тратах '
        '(${_m(s, c.monthlyExpenses)} в месяц) этого хватит примерно на '
        '${m(months)} мес.'
        '${mandatory == null ? '' : ' Только на обязательные платежи — на ${m(mandatory)} мес.'}';
  }

  /// The stability index with every reason.
  static String stability(FinoraAiSnapshot s) {
    final st = s.stability;
    if (st == null) {
      return 'Для индекса стабильности нужно хотя бы два полных месяца.';
    }
    final parts = [
      for (final f in st.factors)
        '• ${f.name}: ${f.points}/${f.max} — ${f.reason}',
    ];
    return 'Индекс стабильности Финоры — ${st.score} из ${st.max}. Это не '
        'кредитный рейтинг, а то, насколько ровно идут деньги:\n'
        '${parts.join('\n')}';
  }

  /// Payments coming up this period, the found ones with their likelihood.
  static String upcoming(FinoraAiSnapshot s) {
    final t = s.timeline;
    final ahead = t.events.where((e) => e.kind == EntryKind.expense).toList();
    if (ahead.isEmpty && t.late.isEmpty) {
      return 'До конца месяца регулярных платежей я не вижу.';
    }
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
    final lines = [
      for (final e in ahead.take(6))
        '${day(e.date)} — «${e.title}», ${_m(s, e.amount)}'
            '${e.detected ? ' (вероятно, ${_pct(e.confidence * 100)})' : ''}',
      for (final e in t.late.where((e) => e.detected).take(2))
        'Обычно «${e.title}» к этому времени уже проходил.',
    ];
    final low = t.lowest;
    final warn = low != null && low.$2 < 0
        ? '\nК ${day(low.$1)} на счетах может не хватить около '
              '${_m(s, -low.$2)}.'
        : '';
    return 'Ближайшие платежи:\n${lines.join('\n')}$warn';
  }
}
