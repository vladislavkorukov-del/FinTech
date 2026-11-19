import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../l10n_widgets.dart';

/// «Как пользоваться долгами»: what to add, how payments are marked and how
/// Finora's plan is read — each with an example.
Future<void> showDebtsHelp(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .85,
    minChildSize: .4,
    maxChildSize: .95,
    builder: (context, scroll) => ListView(
      key: const ValueKey('debts-help'),
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
      children: const [
        _H('Как пользоваться долгами'),
        _P(
          'Здесь собраны все долги: что должны вы и что должны вам. Финора '
          'считает остаток, напоминает о платежах и подсказывает, как '
          'закрыть долги быстрее и с меньшей переплатой.',
        ),
        _H2('1. Добавьте долг — кнопка «+» вверху'),
        _Example(
          'Кредит',
          'Банк, кредитка, ипотека — всё, где есть проценты.',
          'Сбербанк · осталось 200 000 ₽ · 15 % · платёж 7 000 ₽ в месяц · '
              'следующий 5 декабря',
        ),
        _Example(
          'Рассрочка',
          'Без процентов, по графику.',
          'iPhone в рассрочку · 60 000 ₽ · по 5 000 ₽ в месяц',
        ),
        _Example(
          'Долг человеку',
          'Заняли у знакомого. Платёж — сколько готовы отдавать в месяц.',
          'Саше · 10 000 ₽ · по 2 000 ₽ в месяц',
        ),
        _Example(
          'Мне должны',
          'Дали в долг. Эти деньги не считаются вашими, пока их не вернут.',
          'Лёша · 5 000 ₽ · обещал по 1 000 ₽ в месяц',
        ),
        _H2('2. Отмечайте платежи'),
        _P(
          'Заплатили — откройте долг и нажмите «Оплатить досрочно» или '
          'подтвердите напоминание Финоры в день платежа. Остаток '
          'уменьшится сам. Запланированные платежи остаток не меняют, '
          'пока вы их не подтвердите. Реальных переводов приложение не '
          'делает.',
        ),
        _H2('3. Смотрите план Финоры'),
        _P(
          '«Свободно в месяц» — сколько остаётся по вашим операциям за '
          'последние месяцы после обычных расходов и обязательных платежей.',
        ),
        _Example(
          'Пример',
          null,
          'Доходы 100 000 ₽ − расходы 60 000 ₽ − платежи по долгам '
              '10 000 ₽ = свободно 30 000 ₽. Финора советует отдавать '
              'сверх минимума половину — 15 000 ₽, вторая половина — запас.',
        ),
        _P(
          'Ползунок задаёт, сколько вы отдаёте сверх минимальных платежей. '
          'Дата «Без долгов к …» и переплата пересчитываются сразу.',
        ),
        _H2('4. Выберите стратегию'),
        _Example(
          'Лавина',
          'Лишние деньги — в долг с самой высокой ставкой. Переплата меньше '
              'всего.',
          'Кредитка 60 000 ₽ под 30 % и кредит 200 000 ₽ под 15 %: сначала '
              'закрываем кредитку, потом весь платёж идёт в кредит.',
        ),
        _Example(
          'Снежный ком',
          'Лишние деньги — в самый маленький долг. Первый долг закроется '
              'быстрее — это мотивирует.',
          'Сначала 10 000 ₽ Саше, потом кредитка, потом кредит.',
        ),
        _P(
          'Финора отмечает выгодную стратегию словами «Рекомендую». Под '
          'планом — сколько платить в этом месяце по каждому долгу.',
        ),
        _H2('5. Спросите Финору'),
        _P(
          'В Finora AI: «Как мне погасить долги?», «Когда я закрою '
          'кредит?». Для платежей по датам — «Недельный график платежей» '
          'внизу экрана.',
        ),
      ],
    ),
  ),
);

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.headlineSmall),
  );
}

class _H2 extends StatelessWidget {
  const _H2(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(height: 1.4)),
  );
}

class _Example extends StatelessWidget {
  const _Example(this.title, this.what, this.example);
  final String title;
  final String? what;
  final String example;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (what != null) ...[
                const SizedBox(height: 2),
                Text(what!, style: const TextStyle(height: 1.35)),
              ],
              const SizedBox(height: 6),
              Text(
                'Например: $example',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
