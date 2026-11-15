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
      Icons.blur_on_rounded,
      'Финора — сфера света',
      'Финора стала живой сферой света: переливается и светится ярче, когда слушает или отвечает, — без глаз, рта и эмоций. Мир Финоры, игры, гардероб и компаньоны убраны: в приложении остались только деньги. Приложение стало заметно легче.',
    ),
    (
      Icons.light_mode_rounded,
      'Спокойная светлая тема',
      'Светлая тема Finora стала спокойной: тёплый бумажный фон вместо оранжевых пятен, белые карточки и один карамельный акцент. Доходы и расходы читаются чётче, а надписи на чипах категорий больше не белые на светлом — их хорошо видно везде.',
    ),
    (
      Icons.photo_outlined,
      'Фото на карточках мечт',
      'В настройке мечты выберите фото и обрежьте его под карточку — оно станет её фоном на главной.',
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
          const Center(child: FinoraCharacter(size: 84)),
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
