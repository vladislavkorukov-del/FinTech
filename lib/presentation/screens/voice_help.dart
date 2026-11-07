import 'package:flutter/material.dart';

import '../widgets/finora_orb.dart';
import '../widgets/grouped_list.dart';

/// What Finora understands (1.33): every kind of voice command with
/// examples. Opened from Settings → Финора → «Голосовые команды» and
/// mentioned in the tour.
class VoiceHelpScreen extends StatelessWidget {
  const VoiceHelpScreen({super.key});

  static const groups = <(String, IconData, Color, List<String>)>[
    (
      'Записать трату или доход',
      Icons.edit_note_rounded,
      TileColors.green,
      [
        'Пятёрочка 450 рублей',
        'Кофе 300 вчера',
        'Т2 695 рублей',
        'Такси 1 300 рублей 20 копеек',
        'Зарплата 90 тысяч',
        'Чат ГПТ 2000',
      ],
    ),
    (
      'Показать операции',
      Icons.receipt_long_rounded,
      TileColors.blue,
      [
        'Покажи расходы за июнь',
        'Покажи доход за год',
        'Расходы за прошлый месяц',
        'Сколько я потратил на кафе в мае',
        'Покажи расходы по Тинькофф',
        'Доходы за последние 3 месяца',
      ],
    ),
    (
      'Подписки и обязательные платежи',
      Icons.event_repeat_rounded,
      TileColors.purple,
      [
        'Подписка Т2 695 рублей в месяц',
        'Подписка Яндекс Плюс 399 в месяц',
        'Обязательный платёж кредит 15 000 25 числа',
        'Ипотека 32 000 каждый месяц 5 числа',
        'Обязательный платёж аренда 40 тысяч 1 числа',
        'Зарплата 90 тысяч каждый месяц 10 числа',
      ],
    ),
    (
      'Мечты, счета, бюджеты, категории',
      Icons.auto_awesome_rounded,
      TileColors.orange,
      [
        'Хочу машину за 2 миллиона к 2028 году',
        'Коплю на айфон 120 тысяч до декабря',
        'Добавь карту Сбер с балансом 15 тысяч',
        'Бюджет на продукты 20 тысяч',
        'Добавь категорию Спорт',
      ],
    ),
    (
      'Открыть экран',
      Icons.open_in_new_rounded,
      TileColors.teal,
      [
        'Открой настройки',
        'Открой счета · мечты · бюджеты · календарь',
        'Покажи аналитику',
        'Покажи подписки',
        'На главную',
      ],
    ),
    (
      'Тема оформления',
      Icons.palette_rounded,
      TileColors.pink,
      [
        'Поменяй тему на зелёную',
        'Сделай тёмную тему',
        'Тема как в системе',
        'Тема Сансет',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Голосовые команды')),
      body: ListView(
        key: const ValueKey('voice-help'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              const FinoraMark(size: 56, mood: FinoraMood.happy),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Нажмите на Финору внизу и скажите — как здесь. Суммы можно '
                  'словами или цифрами, «тысяч», «миллиона», «рублей» и '
                  '«копеек» она понимает.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final (title, icon, color, examples) in groups)
            GroupedSection(
              title: title,
              children: [
                for (final e in examples)
                  GroupedRow(icon: icon, color: color, title: '«$e»'),
              ],
            ),
          const GroupedSection(
            title: 'Как позвать Финору',
            footer:
                'Когда приложение закрыто, Финора не слушает — только после '
                'нажатия или жеста.',
            children: [
              GroupedRow(
                icon: Icons.touch_app_rounded,
                color: TileColors.blue,
                title: 'Нажмите на кругляш внизу',
                subtitle: 'Удержание — ручной ввод',
              ),
              GroupedRow(
                icon: Icons.record_voice_over_rounded,
                color: TileColors.teal,
                title: 'Скажите «Финора»',
                subtitle: 'Пока приложение открыто — включите в настройках',
              ),
              GroupedRow(
                icon: Icons.power_settings_new_rounded,
                color: TileColors.indigo,
                title: 'Удерживайте кнопку питания',
                subtitle: 'Если Финора выбрана помощником телефона',
              ),
              GroupedRow(
                icon: Icons.widgets_rounded,
                color: TileColors.purple,
                title: 'Плитка «Финора» в шторке или виджет',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
