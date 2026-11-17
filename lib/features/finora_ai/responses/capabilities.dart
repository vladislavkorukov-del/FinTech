import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/widgets.dart' show IconData;

/// What Finora AI can do, in one place: the chat answers «что ты умеешь?»
/// from this list, and Settings → «Finora AI» shows it in full with
/// examples to try. Only what the chat really handles today is listed —
/// app commands (open a screen, change the theme, add an entry) go through
/// voice and are described in «Голосовые команды».
class AiCapability {
  const AiCapability(this.title, this.icon, this.about, this.examples);
  final String title;
  final IconData icon;

  /// One line: what she does here.
  final String about;

  /// Questions to try, word for word.
  final List<String> examples;
}

abstract final class AiCapabilities {
  static const all = <AiCapability>[
    AiCapability(
      'Куда уходят деньги',
      CupertinoIcons.chart_pie,
      'Сравню с прошлым периодом и назову категории, которые дали рост.',
      [
        'Почему я трачу больше?',
        'Сравни этот месяц с прошлым',
        'Сравни эту неделю с прошлой',
        'Сравни этот год с прошлым',
      ],
    ),
    AiCapability(
      'Прогноз и свободные деньги',
      CupertinoIcons.graph_square,
      'Посчитаю расходы до конца месяца и сколько останется после '
          'обязательных платежей.',
      [
        'Сколько я потрачу до конца месяца?',
        'Сколько останется?',
        'Хватит ли денег после обязательных платежей?',
      ],
    ),
    AiCapability(
      'Подписки и регулярные платежи',
      CupertinoIcons.arrow_2_circlepath,
      'Найду повторяющиеся платежи и похожие на подписки — с недели до года.',
      ['Найди подписки', 'Какие платежи повторяются?'],
    ),
    AiCapability(
      'Необычные траты',
      CupertinoIcons.exclamationmark_circle,
      'Сравню с твоими же обычными покупками — без общих порогов.',
      ['Были крупные траты?', 'Были необычные траты?'],
    ),
    AiCapability(
      'Бюджеты',
      CupertinoIcons.gauge,
      'Скажу, какой бюджет под угрозой, и предложу лимит по твоей истории.',
      ['Уложусь в бюджеты?', 'Предложи бюджет'],
    ),
    AiCapability(
      'Доходы, привычки, мечты',
      CupertinoIcons.sparkles,
      'Оценю стабильность доходов, привычки трат и взнос, чтобы успеть '
          'с мечтой.',
      [
        'Доходы стабильные?',
        'Куда уходят деньги?',
        'Сколько откладывать на мечту?',
      ],
    ),
    AiCapability(
      'Подушка, стабильность, платежи',
      CupertinoIcons.shield,
      'Посчитаю, на сколько хватит накоплений, оценю стабильность финансов '
          'и покажу ближайшие платежи.',
      [
        'На сколько хватит подушки?',
        'Насколько стабильны мои финансы?',
        'Какие ближайшие платежи?',
      ],
    ),
    AiCapability(
      'Категории',
      CupertinoIcons.tag,
      'Подскажу категорию по названию магазина и объясню, почему.',
      ['К какой категории ВкусВилл?', 'Какая категория для Ozon?'],
    ),
    AiCapability(
      'Обзор',
      CupertinoIcons.doc_text,
      'Коротко о главном: три самых полезных наблюдения.',
      ['Как у меня дела?', 'Итоги месяца'],
    ),
  ];

  /// The chat's answer to «что ты умеешь?»: every area with one example.
  static String answer() {
    final lines = [for (final c in all) '• ${c.title} — «${c.examples.first}»'];
    return 'Я считаю всё по твоим операциям прямо на телефоне. Вот что можно '
        'спросить:\n${lines.join('\n')}\n\n'
        'Полный список с примерами — в Настройках → «Finora AI». '
        'Записать операцию, открыть экран или сменить тему можно голосом.';
  }
}
