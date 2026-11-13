import 'package:flutter/material.dart' hide InputDecoration, Text;

import '../domain/app_version.dart';
import 'controller.dart';
import 'haptics.dart';
import 'widgets/finora_orb.dart';
import 'l10n_widgets.dart';

/// «Что нового» (1.36): after an update Finora tells, once, what changed.
abstract final class WhatsNew {
  static const items = <(IconData, String, String)>[
    (
      Icons.auto_awesome_rounded,
      'Живой «Поток»',
      'Фишки меняются местами, лопаются с искрами и падают на место, каскады отмечаются надписью. Звёзды победы выскакивают по очереди под конфетти.',
    ),
    (
      Icons.grid_view_rounded,
      'Аккуратный «Поток»',
      'Новое игровое поле с жемчужной рамкой, компактные ходы и цели, небольшое окно усилителей. Все надписи в игре — фирменным шрифтом.',
    ),
    (
      Icons.checkroom_outlined,
      'Премиальный гардероб и колесо',
      'Гардероб стал витриной с подсветкой, колесо действий вокруг Финоры — стеклянным. Иконки в «Ещё» в одном цвете, Мир Финоры аккуратнее.',
    ),
    (
      Icons.photo_outlined,
      'Фото на карточках мечт',
      'В настройке мечты выберите фото и обрежьте его под карточку — оно станет её фоном на главной.',
    ),
    (
      Icons.bubble_chart_outlined,
      'Новая Финора и стекло',
      'Финора стала объёмным пузырём, карточки снова из жидкого стекла, а при запуске пишется слово Finora.',
    ),
    (
      Icons.document_scanner_outlined,
      'Скриншоты операций',
      'Экран одной операции с кешбэком или комиссией снова распознаётся как одна покупка — с получателем, датой и временем.',
    ),
    (
      Icons.auto_awesome_mosaic_outlined,
      'Спокойный дизайн в стиле Apple',
      'Ровный фон и карточки без рамок, новый шрифт Inter и крупный баланс на главной. '
          'Расходы показаны обычным цветом, нижняя панель и анимации стали тише.',
    ),
    (
      Icons.grid_view_rounded,
      'Новая графика «Потока»',
      'Террасная карта, финансовые фишки, препятствия, ракеты и сфера из вашего набора. '
          'Новые панели и окна подготовки, паузы, победы и окончания ходов.',
    ),
    (
      Icons.auto_awesome_outlined,
      'Усилители и звук',
      'Ограниченный стартовый запас: молоток, бомба, перемешивание и +5 ходов. '
          'Запас сохраняется. Музыка, звуки и вибрация настраиваются отдельно в паузе.',
    ),
    (
      Icons.cottage_outlined,
      'Дом на весь экран',
      'Мир Финоры стал цельной сценой: компактные счётчики, Финора и питомец в доме, '
          'жемчужная панель разделов. Образы, коллекции и обзор доступны через «Ещё» внутри дома.',
    ),
    (
      Icons.palette_outlined,
      'Читаемое оформление мира',
      'Исправлены тёмные поля и светлый текст на жемчужных карточках. '
          'Тема мира больше не зависит от выбранной финансовой темы. Прогресс сохранён.',
    ),
    (
      Icons.home_outlined,
      'Новый дом и сад',
      'Шесть фонов дома, новые иконки и шесть кадров растения из вашего набора. '
          'Выбранный фон, питомец, плащ и прогресс сохраняются.',
    ),
    (
      Icons.grid_on_outlined,
      'Finora — Поток',
      'Игра «3 в ряд» внутри Мира Финоры: 20 уровней, усилители, лёд и стопки чеков. '
          'Попытка сохраняется после каждого хода. Награда за уровень выдаётся один раз.',
    ),
    (
      Icons.cottage_outlined,
      'Мир Финоры',
      'Дом, декор, сохранённые образы и реакции питомца. '
          '«Ещё» → «Настройки» → «Финора» → «Мир Финоры». '
          'Основные финансовые экраны остались прежними.',
    ),
    (
      Icons.spa_outlined,
      'Сад и воспоминания',
      'Растения растут вместе с вашими мечтами. Коллекции объединяют '
          'существующий гардероб, а важные моменты сохраняются в альбоме.',
    ),
    (
      Icons.auto_awesome_outlined,
      'Искры и путешествия',
      'Косметические награды за полезные привычки и три небольшие игры. '
          'Искры не связаны с реальными деньгами. Прогресс работает без сети.',
    ),
    (
      Icons.checkroom_rounded,
      'Компаньоны и плащи',
      '13 новых компаньонов и 15 плащей в «Гардеробе Finora». '
          'Компаньон находится рядом, плащ — за Финорой. '
          'Можно надеть оба и снять каждый независимо.',
    ),
    (
      Icons.auto_awesome_rounded,
      'Новые карточки достижений',
      'У каждого из 54 достижений своя яркая картинка Финоры в высоком '
          'качестве.',
    ),
    (
      Icons.celebration_rounded,
      'Достижение — на весь экран',
      'Полученная награда выскакивает карточкой поверх экрана: с сиянием, '
          'репликой Финоры, а у редких — с конфетти. Несколько — по очереди.',
    ),
    (
      Icons.emoji_events_rounded,
      'Достижения',
      'Больше 50 наград за регулярный учёт, бюджет, накопления и мечты: '
          'редкости, уровни и секретные. «Ещё» → «Достижения».',
    ),
    (
      Icons.local_fire_department_rounded,
      'Серии и уровни',
      'Финора считает дни подряд с финансовыми делами и не ругает за '
          'пропуски. Очки за награды поднимают уровень — от «Новичка» до '
          '«Финансового гуру».',
    ),
    (
      Icons.dashboard_customize_rounded,
      'Карточка на главной',
      'Серия, сколько получено и что ближе всего — прямо на главном экране.',
    ),
    (
      Icons.palette_rounded,
      'Яркие виджеты',
      'Все виджеты — сочные, в цвет картинки Финоры. Новый «Финора-мини» 1×1.',
    ),
    (
      Icons.build_circle_outlined,
      'Исправления',
      'Убран виджет «Финора-стикер» 2×2; ночная картинка «Всё спокойно» '
          'вырезана ровно.',
    ),
    (
      Icons.swipe_left_rounded,
      'Плавные переходы',
      'Страницы въезжают сбоку и больше не накладываются друг на друга.',
    ),
    (
      Icons.local_fire_department_rounded,
      'Финора-напарник на рабочем столе',
      'Новый виджет: большая Финора с репликой и серией дней подряд. '
          'Радуется записям, напоминает, сердится, если серия вот-вот сгорит.',
    ),
    (
      Icons.shopping_basket_outlined,
      'Список покупок',
      'Отмечайте купленное в магазине, а потом одним нажатием запишите '
          'расход на всю сумму.',
    ),
  ];

  static bool _open = false;

  /// Shows the news once per version; true when it was shown.
  static Future<bool> check(BuildContext context) async {
    final c = FinanceScope.of(context);
    final p = c.data.preferences;
    final seen = p.seenVersion;
    if (_open || !p.onboarded || seen == null || seen == appVersion) {
      return false;
    }
    _open = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => const _Sheet(),
      );
      await c.mutate(
        (d) => d.copyWith(
          preferences: d.preferences.copyWith(seenVersion: appVersion),
        ),
      );
      return true;
    } finally {
      _open = false;
    }
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        key: const ValueKey('whats-new'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(
            child: FinoraCharacter(size: 84, moods: [FinoraMood.delight]),
          ),
          const SizedBox(height: 8),
          Text(
            'Что нового в $appVersion',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (icon, title, text) in WhatsNew.items)
                  ListTile(
                    leading: Icon(icon, color: theme.colorScheme.primary),
                    title: Text(title),
                    subtitle: Text(text),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
              key: const ValueKey('whats-new-ok'),
              onPressed: () {
                Haptics.success();
                Navigator.pop(context);
              },
              child: const Text('Отлично!'),
            ),
          ),
        ],
      ),
    );
  }
}
