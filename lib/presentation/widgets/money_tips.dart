import '../i18n.dart';
import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../controller.dart';
import 'common.dart';
import 'finora_orb.dart';
import 'grouped_list.dart';
import '../l10n_widgets.dart';

/// Money basics from Finora (1.28): one short, practical tip a day on the
/// main screen. «Ещё совет» shows the next; swipe left (with a question)
/// or Settings → «Советы по финансам» hides the card.
class MoneyTipsCard extends StatefulWidget {
  const MoneyTipsCard({super.key});

  static const tips = <(String, String)>[
    (
      'Правило 50/30/20',
      '50% дохода — на обязательное, 30% — на желания, 20% — на сбережения '
          'и погашение долгов.',
    ),
    (
      'Подушка безопасности',
      'Держите запас на 3–6 месяцев обязательных расходов на отдельном '
          'счёте с быстрым доступом.',
    ),
    (
      'Сначала заплатите себе',
      'Откладывайте часть зарплаты в день её поступления, а не то, что '
          'останется в конце месяца.',
    ),
    (
      'Кредитка без процентов',
      'Кредитная карта выгодна, только если гасить весь долг в льготный '
          'период.',
    ),
    (
      'Какой долг гасить первым',
      'Досрочно гасите долг с самой высокой ставкой — так переплата '
          'уменьшается быстрее всего.',
    ),
    (
      'Сложный процент',
      '10 000 ₽ под 10% годовых с капитализацией за 10 лет вырастают '
          'примерно до 26 000 ₽. Время работает на вас.',
    ),
    (
      'Ревизия подписок',
      'Раз в месяц просматривайте подписки: забытые сервисы незаметно '
          'съедают бюджет.',
    ),
    (
      'Правило 24 часов',
      'Перед незапланированной покупкой дороже 5 000 ₽ подождите сутки — '
          'часто желание проходит.',
    ),
    (
      'Страховка вкладов',
      'Вклады и счета в банках РФ застрахованы АСВ до 1,4 млн ₽ на '
          'человека в одном банке.',
    ),
    (
      'Инфляция',
      'Деньги «под подушкой» дешевеют. Храните запас хотя бы на '
          'накопительном счёте или вкладе.',
    ),
    (
      'Конкретная цель',
      '«Машина за 2 млн к 2028 году» копится легче, чем просто «на '
          'машину». Добавьте мечту — Финора посчитает.',
    ),
    (
      'Налоговый вычет',
      'За лечение, обучение, ипотеку и ИИС можно вернуть 13% расходов в '
          'пределах лимитов.',
    ),
    (
      'Не всё в одном месте',
      'Распределяйте сбережения между разными инструментами и банками — '
          'так меньше риск.',
    ),
    (
      'Мелочи за год',
      'Кофе и такси каждый день за год складываются в крупную сумму. '
          'Посмотрите их в аналитике.',
    ),
    (
      'Записывайте сразу',
      'Через неделю половина мелких трат забудется — скажите Финоре сразу '
          'после покупки.',
    ),
    (
      'Лимиты на главное',
      'Поставьте бюджет на 2–3 самые большие категории — этого часто '
          'достаточно для порядка.',
    ),
    (
      'Коды из СМС',
      'Никому не сообщайте коды из СМС: настоящий банк их никогда не '
          'спрашивает.',
    ),
    (
      'Полная стоимость кредита',
      'Сравнивайте кредиты по ПСК — полной стоимости, а не только по '
          'ставке.',
    ),
    (
      'Тарифы раз в год',
      'Пересматривайте тарифы связи, интернета и страховок — часто есть '
          'дешевле.',
    ),
    (
      'Доход растёт — расходы нет',
      'При повышении зарплаты направьте хотя бы половину прибавки в '
          'сбережения.',
    ),
  ];

  @override
  State<MoneyTipsCard> createState() => _MoneyTipsCardState();
}

class _MoneyTipsCardState extends State<MoneyTipsCard> {
  late int _i =
      DateTime.now().difference(DateTime(DateTime.now().year)).inDays %
      MoneyTipsCard.tips.length;

  @override
  Widget build(BuildContext context) {
    final c = FinanceScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (title, text) = MoneyTipsCard.tips[_i];
    return SwipeToDelete(
      key: const ValueKey('money-tips'),
      margin: EdgeInsets.zero,
      title: 'Скрыть советы?',
      message:
          'Финора перестанет показывать советы на главной. Вернуть их '
          'можно в настройках: «Советы по финансам».',
      onDelete: () => c.preferences(c.data.preferences.copyWith(tips: false)),
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 4),
                  child: FinoraMark(size: 40, mood: FinoraMood.idea),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Column(
                      key: ValueKey(_i),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('ФИНАНСОВАЯ ГРАМОТНОСТЬ'),
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: .6,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('money-tips-next'),
                onPressed: () =>
                    setState(() => _i = (_i + 1) % MoneyTipsCard.tips.length),
                icon: const Icon(Icons.lightbulb_outline_rounded, size: 17),
                label: Text(tr('Ещё совет')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
