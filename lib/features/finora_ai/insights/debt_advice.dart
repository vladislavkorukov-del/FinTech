import 'package:intl/intl.dart';

import '../../../domain/debt_strategy.dart';
import '../../../domain/models.dart';
import '../../../presentation/widgets/common.dart' show money;

/// Finora's answer to «как мне погасить долги?»: the debts, the money the
/// person's own operations leave free each month, and the plan that costs
/// least — all calculated by [DebtStrategies]; the words only report it.
abstract final class DebtAdvice {
  static final _question = RegExp(
    r'как.{0,30}(погас|закр|выплат|рассчита|избав|разобрат).{0,30}(долг|кредит|займ|рассроч)|'
    r'(долг|кредит|займ).{0,30}(как|когда|быстрее|стратеги|выгодн)|'
    r'когда.{0,20}(закро|погаш|расплач|рассчита|выплач)',
    caseSensitive: false,
  );

  /// The weekly payment schedule is a different request (an action).
  static final _schedule = RegExp(
    r'план|распредел|график|недел|запланир',
    caseSensitive: false,
  );

  static bool matches(String text) =>
      _question.hasMatch(text) && !_schedule.hasMatch(text);

  static String answer(FinanceData data, {String? currency, DateTime? now}) {
    final cur = currency ?? data.preferences.baseCurrency;
    final clock = now ?? DateTime.now();
    final debts = DebtStrategies.debtsOf(data, currency: cur, now: clock);
    if (debts.isEmpty) {
      return 'В приложении нет долгов в $cur. Добавьте кредит, рассрочку '
          'или долг человеку в разделе «Долги» — посчитаю, как закрыть их '
          'быстрее и дешевле.';
    }
    String m(int v) => money(v, cur);
    String month(int n) => DateFormat(
      'LLLL yyyy',
      'ru',
    ).format(DateTime(clock.year, clock.month + n));
    final owed = debts.fold<int>(0, (a, d) => a + d.balanceMinor);
    final minimums = debts.fold<int>(0, (a, d) => a + d.minimumMinor);
    final cap = DebtStrategies.capacity(data, currency: cur, now: clock);
    final extra = cap.suggestedExtraMinor;
    final lines = <String>[
      'Долги: ${m(owed)} (${debts.length}). Обязательные платежи — '
          '${m(minimums)} в месяц.',
    ];
    if (cap.months == 0) {
      lines.add(
        'Истории операций пока мало, чтобы понять, сколько свободно. '
        'Посчитала с одними обязательными платежами.',
      );
    } else if (cap.freeMinor <= 0) {
      lines.add(
        'По операциям за ${cap.months} мес. после расходов и платежей '
        'денег не остаётся (${m(cap.freeMinor)} в месяц). Начните с '
        'сокращения расходов или договоритесь о меньшем платеже.',
      );
    } else {
      lines.add(
        'Свободно в месяц по операциям за ${cap.months} мес.: '
        '≈ ${m(cap.freeMinor)}. Советую направлять сверх минимума '
        '${m(extra)} — половину, остальное оставьте запасом.',
      );
    }
    final plans = DebtStrategies.compare(debts, extra);
    final best = plans.first;
    final base = plans.last;
    final names = {for (final d in debts) d.id: d.name};
    if (!best.finished) {
      lines.add(
        'Такими платежами долги не закрываются: платёж меньше процентов '
        'или у долга нет платежа. Нужна сумма сверх минимума.',
      );
    } else {
      final first = names[best.order.first];
      final name = best.strategy == DebtStrategy.snowball
          ? 'Снежный ком'
          : 'Лавина';
      final why = best.strategy == DebtStrategy.snowball
          ? 'сначала самый маленький долг'
          : 'сначала самый дорогой по ставке';
      var text =
          '$name ($why: $first): без долгов к ${month(best.months)}, '
          'проценты ${m(best.totalInterestMinor)}.';
      if (base.finished) {
        final sooner = base.months - best.months;
        final saved = base.totalInterestMinor - best.totalInterestMinor;
        if (sooner > 0 || saved > 0) {
          text +=
              ' Это ${sooner > 0 ? 'на $sooner мес. раньше' : 'в тот же срок'}'
              '${saved > 0 ? ' и на ${m(saved)} дешевле' : ''}, чем одними '
              'минимальными платежами.';
        }
      }
      lines.add(text);
      final now = best.schedule.firstOrNull;
      if (now != null && now.payments.isNotEmpty) {
        lines.add(
          'В этом месяце: ${now.payments.entries.map((e) => '${names[e.key]} — ${m(e.value)}').join(', ')}.',
        );
      }
    }
    lines.add('Подробно и с выбором суммы — в разделе «Долги».');
    return lines.join('\n');
  }
}
