import 'package:flutter/material.dart';

import '../domain/app_version.dart';
import 'controller.dart';
import 'haptics.dart';
import 'widgets/finora_orb.dart';

/// «Что нового» (1.36): after an update Finora tells, once, what changed.
abstract final class WhatsNew {
  static const items = <(IconData, String, String)>[
    (
      Icons.event_repeat_rounded,
      'Кредиты и рассрочки',
      'Впишите полную сумму — Финора покажет, сколько осталось, и график '
          '«платёж 7 из 12». Просроченные — красным и с напоминаниями.',
    ),
    (
      Icons.swipe_right_rounded,
      'Свайп вправо — оплачено досрочно',
      'В платежах и подписках. Финора спросит сумму и запишет расход.',
    ),
    (
      Icons.edit_note_rounded,
      'Сумма подписки поменялась?',
      'При подтверждении оплаты сумму можно исправить и запомнить.',
    ),
    (
      Icons.drag_indicator_rounded,
      'Свой порядок платежей',
      'Удерживайте карточку и перетаскивайте.',
    ),
    (
      Icons.space_bar_rounded,
      'Суммы с пробелами',
      '1 250 000 читается сразу — разряды разделяются при вводе.',
    ),
    (
      Icons.face_retouching_natural_rounded,
      'Аватар и Финора в цвет темы',
      'Настройки → профиль. Цвет Финоры — в разделе «Финора».',
    ),
    (
      Icons.widgets_outlined,
      'Виджет с характером',
      'Финора на виджете радуется записям, напоминает днём и сердится, '
          'если вы забыли о расходах.',
    ),
    (
      Icons.record_voice_over_rounded,
      'Голос и импорт точнее',
      '«пятнадцатого числа» понимается; «Финора» не срабатывает от '
          'похожих слов; переводы между своими счетами при импорте — не траты.',
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
